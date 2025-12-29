// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./utils/SafeMath.sol";
import "./utils/SafeMathInt.sol";
import "./utils/Ownable.sol";

contract rtUSQ is IERC20, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    uint256 internal constant INFINITE_ALLOWANCE = ~uint256(0);

    string private _name;
    string private _symbol;

    uint256 _totalSupply;
    uint256 _totalShares;

    uint8 constant _decimals = 18;

    uint256 public lastEpoch = 0;

    mapping(address => uint256) private shares;

    mapping(address => mapping(address => uint256)) private allowances;

    address public monetaryPolicy;
    address public rtUSQVaulat;

    modifier onlyMonetaryPolicy() {
        require(msg.sender == monetaryPolicy || msg.sender == owner(), "permissions error");
        _;
    }

    modifier onlyVaulat() {
        require(msg.sender == rtUSQVaulat, "permissions error");
        _;
    }

    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

    event SharesBurnt(
        address indexed account,
        uint256 preRebaseTokenAmount,
        uint256 postRebaseTokenAmount,
        uint256 sharesAmount
    );
    event LogRebase(uint256 indexed epoch, int256 amount, uint256 totalSupply);

    event LogMonetaryPolicyUpdated(address monetaryPolicy);

    constructor(string memory name_, string memory symbol_) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
    }

    function initialize(address _rtUSQVaulat) external onlyOwner {
        require(_rtUSQVaulat != address(0), "Cannot be zero address");
        require(rtUSQVaulat == address(0), "Initialized");
        rtUSQVaulat = _rtUSQVaulat;
    }

    function setMonetaryPolicy(address _monetaryPolicy) external onlyOwner {
        monetaryPolicy = _monetaryPolicy;
        emit LogMonetaryPolicyUpdated(_monetaryPolicy);
    }

    function mintTo(address to, uint256 _amount) public onlyVaulat {
        _mint(to, _amount);
    }

    function burnFrom(address from, uint256 _amount) public onlyVaulat {
        _burn(from, _amount);
    }

    function rebase(int256 _amount) public onlyMonetaryPolicy returns (uint256) {
        if (_amount == 0) {
            lastEpoch += 1;
            emit LogRebase(lastEpoch, _amount, _totalSupply);
            return _totalSupply;
        }
        if (_amount < 0) {
            _totalSupply = _totalSupply.sub(uint256(_amount.abs()));
        } else {
            _totalSupply = _totalSupply.add(uint256(_amount));
        }
        lastEpoch += 1;
        emit LogRebase(lastEpoch, _amount, _totalSupply);
        return _totalSupply;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return getRShares(_sharesOf(_account));
    }

    function getTotalShares() external view returns (uint256) {
        return _getTotalShares();
    }

    function sharesOf(address _account) external view returns (uint256) {
        return _sharesOf(_account);
    }

    function getSharesByRt(uint256 _rAmount) public view returns (uint256) {
        return _rAmount.mul(_getTotalShares()).div(totalSupply());
    }

    function getRShares(uint256 _sharesAmount) public view returns (uint256) {
        return _sharesAmount.mul(totalSupply()).div(_getTotalShares());
    }

    function _getTotalShares() internal view returns (uint256) {
        return _totalShares;
    }

    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    function transfer(address _recipient, uint256 _amount) public virtual override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function burn(uint256 _amount) public virtual returns (bool) {
        _burn(msg.sender, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) public view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) public override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public virtual returns (bool) {
        _approve(msg.sender, _spender, allowances[msg.sender][_spender].add(_addedValue));
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][_spender];
        require(currentAllowance >= _subtractedValue, "ALLOWANCE_BELOW_ZERO");
        _approve(msg.sender, _spender, currentAllowance.sub(_subtractedValue));
        return true;
    }

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256) {
        _transferShares(msg.sender, _recipient, _sharesAmount);
        uint256 tokensAmount = getRShares(_sharesAmount);
        _emitTransferEvents(msg.sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount) external returns (uint256) {
        uint256 tokensAmount = getRShares(_sharesAmount);
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        _emitTransferEvents(_sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) internal virtual {
        uint256 _sharesToTransfer = getSharesByRt(_amount);

        _transferShares(_sender, _recipient, _sharesToTransfer);
        _emitTransferEvents(_sender, _recipient, _amount, _sharesToTransfer);
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal virtual {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDR");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDR");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal virtual {
        uint256 currentAllowance = allowances[_owner][_spender];
        if (currentAllowance != INFINITE_ALLOWANCE) {
            require(currentAllowance >= _amount, "ALLOWANCE_EXCEEDED");
            _approve(_owner, _spender, currentAllowance - _amount);
        }
    }

    function _transferShares(address _sender, address _recipient, uint256 _sharesAmount) internal {
        require(_sender != address(0), "TRANSFER_FROM_ZERO_ADDR");
        require(_recipient != address(0), "TRANSFER_TO_ZERO_ADDR");
        require(_recipient != address(this), "TRANSFER_TO_STETH_CONTRACT");

        uint256 currentSenderShares = _sharesOf(_sender);
        require(_sharesAmount <= currentSenderShares, "BALANCE_EXCEEDED");

        shares[_sender] = currentSenderShares.sub(_sharesAmount);
        shares[_recipient] = shares[_recipient].add(_sharesAmount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        uint256 _sharesAmount = _totalSupply == 0 ? amount : getSharesByRt(amount);

        shares[account] = shares[account].add(_sharesAmount);

        _totalShares = _getTotalShares().add(_sharesAmount);

        _totalSupply = _totalSupply.add(amount);

        emit Transfer(address(0), account, amount);
    }

    function _mintShares(address _recipient, uint256 _sharesAmount) internal returns (uint256 newTotalShares) {
        require(_recipient != address(0), "MINT_TO_ZERO_ADDR");
        newTotalShares = _getTotalShares().add(_sharesAmount);
        _totalShares = newTotalShares;
        shares[_recipient] = shares[_recipient].add(_sharesAmount);
        return newTotalShares;
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = balanceOf(account);
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        uint256 _sharesAmount = getSharesByRt(amount);
        shares[account] = shares[account].sub(_sharesAmount);
        _totalShares = _getTotalShares().sub(_sharesAmount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _burnShares(address _account, uint256 _sharesAmount) internal returns (uint256 newTotalShares) {
        require(_account != address(0), "BURN_FROM_ZERO_ADDR");

        uint256 accountShares = shares[_account];
        require(_sharesAmount <= accountShares, "BALANCE_EXCEEDED");

        uint256 preRebaseTokenAmount = getRShares(_sharesAmount);

        newTotalShares = _getTotalShares().sub(_sharesAmount);

        _totalShares = newTotalShares;
        shares[_account] = accountShares.sub(_sharesAmount);

        uint256 postRebaseTokenAmount = getRShares(_sharesAmount);

        emit SharesBurnt(_account, preRebaseTokenAmount, postRebaseTokenAmount, _sharesAmount);
    }

    function _emitTransferEvents(address _from, address _to, uint256 _tokenAmount, uint256 _sharesAmount) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }

    function _emitTransferAfterMintingShares(address _to, uint256 _sharesAmount) internal {
        _emitTransferEvents(address(0), _to, getRShares(_sharesAmount), _sharesAmount);
    }
}
