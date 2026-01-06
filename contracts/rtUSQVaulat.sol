// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/ISwapRouter02.sol";

import "./utils/PathParser.sol";
import "./utils/TransferHelper.sol";
import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";
import "./interface/IRtUSQ.sol";

contract rtUSQVaulat is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    ISwapRouter02 public immutable router;

    address public immutable rtUSQ;
    address public tokenUsd;
    mapping(address => bool) public supportTokens;
    mapping(address => uint256) public userAsset;

    bool public investEnabled = true;
    bool public redeemEnabled = false;
    bool public withdrawEnabled = true;

    address public assetManager;
    address public admin;

    uint256 public maxSupply;
    uint256 public totalSubscribed;

    modifier onlyAssetManager() {
        require(msg.sender == assetManager, "permissions error");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "permissions error");
        _;
    }

    modifier notSupportToken(address token) {
        if (!supportTokens[token]) revert InvalidToken();
        _;
    }

    event Invest(
        address indexed user,
        address indexed token,
        uint256 indexed amt
    );
    event Redeem(address indexed user, uint256 indexed amt);
    event Withdraw(
        address indexed user,
        address indexed token,
        uint256 indexed amt
    );
    error InvalidToken();
    error NotWithdrawable();
    error NotInvestable();
    error NotRedeemable();
    error NoWithdrawableAssets();

    event Refund(address token, address to);
    event UpdateAdmin(address old, address newAddress);
    event UpdateAssetManager(address old, address newAddress);
    event UpdateSupportToken(address token, bool support);
    event UpdateMaxSupply(uint256 indexed max, uint256 indexed subscribed);

    constructor(
        address _rtUSQ,
        address _router,
        address _usdt1,
        address _usdt,
        address _admin,
        address _assetManger
    ) Ownable(msg.sender) {
        require(_rtUSQ != address(0), "Cannot be zero address");
        require(_assetManger != address(0), "Cannot be zero address");
        require(_admin != address(0), "Cannot be zero address");
        require(_usdt != address(0), "Cannot be zero address");
        rtUSQ = _rtUSQ;
        tokenUsd = _usdt;
        supportTokens[_usdt1] = true;
        supportTokens[_usdt] = true;
        admin = _admin;
        assetManager = _assetManger;
        router = ISwapRouter02(_router);
    }

    function getState() public view returns (bool, bool, bool) {
        return (investEnabled, redeemEnabled, withdrawEnabled);
    }

    function invest(
        address token,
        uint256 _amount,
        uint256 amountOutMin,
        bytes calldata path
    ) public notSupportToken(token) nonReentrant {
        if (!investEnabled || redeemEnabled) {
            revert NotInvestable();
        }
        if (totalSubscribed >= maxSupply) {
            revert NotInvestable();
        }
        if (token == tokenUsd) {
            IERC20(token).safeTransferFrom(_msgSender(), assetManager, _amount);
            IRtUSQ(rtUSQ).mintTo(_msgSender(), _amount);
            totalSubscribed += _amount;
            emit Invest(_msgSender(), token, _amount);
        } else {
            _checkPath(path);
            IERC20(token).safeTransferFrom(
                _msgSender(),
                address(this),
                _amount
            );
            TransferHelper.safeApprove(token, address(router), _amount);
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: path,
                    recipient: assetManager,
                    amountIn: _amount,
                    amountOutMinimum: amountOutMin
                });

            uint256 amountOut = router.exactInput(params);
            if (amountOut > 0) {
                IRtUSQ(rtUSQ).mintTo(_msgSender(), amountOut);
                totalSubscribed += amountOut;
            }
            emit Invest(_msgSender(), token, amountOut);
        }
    }

    function redeem(uint256 _amount) public nonReentrant {
        if (!redeemEnabled) {
            revert NotRedeemable();
        }
        IRtUSQ(rtUSQ).burnFrom(_msgSender(), _amount);
        userAsset[_msgSender()] += _amount;
        emit Redeem(_msgSender(), _amount);
    }

    function withdraw(
        address token,
        uint256 amountOutMin,
        bytes calldata path
    ) public notSupportToken(token) nonReentrant {
        if (!withdrawEnabled || redeemEnabled) {
            revert NotWithdrawable();
        }
        address _user = _msgSender();
        uint256 amt = userAsset[_user];
        if (amt > 0) {
            userAsset[_user] = 0;
            if (token == tokenUsd) {
                IERC20(token).transfer(_user, amt);
                emit Withdraw(_user, token, amt);
            } else {
                address outputToken = PathParser.getLastToken(path);
                if (outputToken != token) {
                    revert InvalidToken();
                }
                TransferHelper.safeApprove(tokenUsd, address(router), amt);
                IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                    .ExactInputParams({
                        path: path,
                        recipient: _user,
                        amountIn: amt,
                        amountOutMinimum: amountOutMin
                    });
                router.exactInput(params);
                emit Withdraw(_user, token, amt);
            }
        } else {
            revert NoWithdrawableAssets();
        }
    }

    function refundToken(address token, address to) external onlyAssetManager {
        require(to != address(0), "Cannot be zero address");
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: address(this).balance}(
                ""
            );
            if (!success) {
                revert();
            }
        } else {
            uint256 bal = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransfer(to, bal);
        }
        emit Refund(token, to);
    }

    function setInvestEnabled(bool _enabled) external onlyAdmin {
        investEnabled = _enabled;
    }
    function setRedeemEnabled(bool _enabled) external onlyAdmin {
        redeemEnabled = _enabled;
    }
    function setWithdrawEnabled(bool _enabled) external onlyAdmin {
        withdrawEnabled = _enabled;
    }

    function setMaxSupply(
        uint256 _max,
        uint256 _subscribed
    ) external onlyAdmin {
        maxSupply = _max;
        totalSubscribed = _subscribed;
        emit UpdateMaxSupply(_max, _subscribed);
    }

    function setUsdToken(address _token) external onlyOwner {
        tokenUsd = _token;
    }

    function updateSupportToken(
        address _token,
        bool _support
    ) external onlyOwner {
        supportTokens[_token] = _support;
        emit UpdateSupportToken(_token, _support);
    }

    function setAdmin(address admin_) external onlyOwner {
        require(admin_ != address(0), "Cannot be zero address");
        address prev = admin;
        admin = admin_;
        emit UpdateAdmin(prev, admin_);
    }

    function setAssetManager(address assetManager_) external onlyOwner {
        require(assetManager_ != address(0), "Cannot be zero address");
        address prev = assetManager;
        assetManager = assetManager_;
        emit UpdateAssetManager(prev, assetManager_);
    }

    function _checkPath(bytes calldata path) internal view {
        address outputToken = PathParser.getLastToken(path);
        if (outputToken != tokenUsd) {
            revert InvalidToken();
        }
    }
}
