// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "./utils/Ownable.sol";
import { SafeMath } from "./utils/SafeMath.sol";
import { SafeMathInt } from "./utils/SafeMathInt.sol";

contract rtUSQ is IERC20, Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    uint256 internal constant INFINITE_ALLOWANCE = ~uint256(0);
    uint256 public constant GENESIS_BLOCK = 115730532;
    bytes32 public constant GENESIS_BLOCK_HASH =
        0x8624a3b60bb32ec1a5cae28ee64f37c1d131bb5d744aa1bdbf7ca5991ecf5e00;
    uint256 public constant GENESIS_TOTAL_SUPPLY = 1506830395981790900318539;
    uint256 public constant GENESIS_TOTAL_SHARES = 1424277497480449271384736;

    string private _name;
    string private _symbol;

    uint256 _totalSupply;
    uint256 _totalShares;

    uint8 constant _decimals = 18;

    uint256 public lastEpoch = 0;

    mapping(address => uint256) private shares;

    mapping(address => mapping(address => uint256)) private allowances;

    address public monetaryPolicy;
    address public rtUSQVault;
    address public immutable GENESIS_DEVELOPER;

    modifier onlyMonetaryPolicy() {
        require(msg.sender == monetaryPolicy || msg.sender == owner(), "permissions error");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == rtUSQVault, "permissions error");
        _;
    }

    event TransferShares(address indexed from, address indexed to, uint256 sharesValue);

    event LogRebase(uint256 indexed epoch, int256 amount, uint256 totalSupply);

    event LogMonetaryPolicyUpdated(address monetaryPolicy);

    event GenesisMinted(
        address indexed developer,
        uint256 indexed snapshotBlock,
        bytes32 snapshotBlockHash,
        uint256 tokenAmount,
        uint256 sharesAmount
    );

    constructor(string memory name_, string memory symbol_) Ownable(msg.sender) {
        _name = name_;
        _symbol = symbol_;
        GENESIS_DEVELOPER = msg.sender;
        _totalSupply = GENESIS_TOTAL_SUPPLY;
        _totalShares = GENESIS_TOTAL_SHARES;
        shares[msg.sender] = GENESIS_TOTAL_SHARES;

        emit Transfer(address(0), msg.sender, GENESIS_TOTAL_SUPPLY);
        emit TransferShares(address(0), msg.sender, GENESIS_TOTAL_SHARES);
        emit GenesisMinted(
            msg.sender,
            GENESIS_BLOCK,
            GENESIS_BLOCK_HASH,
            GENESIS_TOTAL_SUPPLY,
            GENESIS_TOTAL_SHARES
        );
    }

    function initialize(address _rtUSQVault) external onlyOwner {
        require(_rtUSQVault != address(0), "Cannot be zero address");
        require(rtUSQVault == address(0), "Initialized");
        rtUSQVault = _rtUSQVault;
    }

    function setMonetaryPolicy(address _monetaryPolicy) external onlyOwner {
        monetaryPolicy = _monetaryPolicy;
        emit LogMonetaryPolicyUpdated(_monetaryPolicy);
    }

    function mintTo(address to, uint256 _amount) public onlyVault {
        _mint(to, _amount);
    }

    function burnFrom(address from, uint256 _amount) public onlyVault {
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
        if (_totalSupply == 0 || _totalShares == 0) {
            return 0;
        }

        return getRShares(_sharesOf(_account));
    }

    function getTotalShares() external view returns (uint256) {
        return _getTotalShares();
    }

    function sharesOf(address _account) external view returns (uint256) {
        return _sharesOf(_account);
    }

    function getSharesByRt(uint256 _rAmount) public view returns (uint256) {
        if (_rAmount == 0) {
            return 0;
        }

        if (_totalSupply == 0 || _totalShares == 0) {
            return _rAmount;
        }

        return _rAmount.mul(_getTotalShares()).div(totalSupply());
    }

    function getRShares(uint256 _sharesAmount) public view returns (uint256) {
        if (_sharesAmount == 0 || _totalSupply == 0 || _totalShares == 0) {
            return 0;
        }

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
        require(_sharesAmount == 0 || tokensAmount > 0, "AMOUNT_TOO_SMALL");
        _emitTransferEvents(msg.sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount) external returns (uint256) {
        uint256 tokensAmount = getRShares(_sharesAmount);
        require(_sharesAmount == 0 || tokensAmount > 0, "AMOUNT_TOO_SMALL");
        _spendAllowance(_sender, msg.sender, tokensAmount);
        _transferShares(_sender, _recipient, _sharesAmount);
        _emitTransferEvents(_sender, _recipient, tokensAmount, _sharesAmount);
        return tokensAmount;
    }

    function _transfer(address _sender, address _recipient, uint256 _amount) internal virtual {
        uint256 senderBalance = balanceOf(_sender);
        uint256 _sharesToTransfer = _amount > 0 && _amount == senderBalance
            ? _sharesOf(_sender)
            : getSharesByRt(_amount);
        require(_amount == 0 || _sharesToTransfer > 0, "AMOUNT_TOO_SMALL");

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
        require(amount == 0 || _sharesAmount > 0, "AMOUNT_TOO_SMALL");

        shares[account] = shares[account].add(_sharesAmount);

        _totalShares = _getTotalShares().add(_sharesAmount);

        _totalSupply = _totalSupply.add(amount);

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = balanceOf(account);
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        uint256 _sharesAmount = amount > 0 && amount == accountBalance ? _sharesOf(account) : getSharesByRt(amount);
        require(amount == 0 || _sharesAmount > 0, "AMOUNT_TOO_SMALL");
        shares[account] = shares[account].sub(_sharesAmount);
        _totalShares = _getTotalShares().sub(_sharesAmount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _emitTransferEvents(address _from, address _to, uint256 _tokenAmount, uint256 _sharesAmount) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }
}
