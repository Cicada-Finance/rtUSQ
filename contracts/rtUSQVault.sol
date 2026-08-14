// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IRtUSQ } from "./interface/IRtUSQ.sol";
import { Ownable } from "./utils/Ownable.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

contract rtUSQVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    address public immutable rtUSQ;
    address public tokenUsd;
    mapping(address => uint256) public userAsset;

    bool public investEnabled = false;
    bool public redeemEnabled = false;
    bool public withdrawEnabled = false;

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

    event Invest(address indexed user, address indexed token, uint256 indexed amt);
    event Redeem(address indexed user, uint256 indexed amt);
    event Withdraw(address indexed user, address indexed token, uint256 indexed amt);
    error NotWithdrawable();
    error NotInvestable();
    error NotRedeemable();
    error NoWithdrawableAssets();

    event Refund(address token, address to);
    event UpdateAdmin(address old, address newAddress);
    event UpdateAssetManager(address old, address newAddress);
    event UpdateMaxSupply(uint256 indexed max, uint256 indexed subscribed);
    event UpdateUsdToken(address old, address newAddress);

    constructor(address _rtUSQ, address _usdt, address _admin, address _assetManger) Ownable(msg.sender) {
        require(_rtUSQ != address(0), "Cannot be zero address");
        require(_assetManger != address(0), "Cannot be zero address");
        require(_admin != address(0), "Cannot be zero address");
        require(_usdt != address(0), "Cannot be zero address");
        rtUSQ = _rtUSQ;
        tokenUsd = _usdt;
        admin = _admin;
        assetManager = _assetManger;
        maxSupply = 1000000 * 1e18;
    }

    function getState() public view returns (bool, bool, bool) {
        return (investEnabled, redeemEnabled, withdrawEnabled);
    }

    function invest(uint256 _amount) public nonReentrant {
        if (!investEnabled || redeemEnabled) {
            revert NotInvestable();
        }
        if (totalSubscribed >= maxSupply) {
            revert NotInvestable();
        }
        IERC20(tokenUsd).safeTransferFrom(_msgSender(), assetManager, _amount);
        IRtUSQ(rtUSQ).mintTo(_msgSender(), _amount);
        totalSubscribed += _amount;
        emit Invest(_msgSender(), tokenUsd, _amount);
    }

    function redeem(uint256 _amount) public nonReentrant {
        if (!redeemEnabled) {
            revert NotRedeemable();
        }
        IRtUSQ(rtUSQ).burnFrom(_msgSender(), _amount);
        userAsset[_msgSender()] += _amount;
        emit Redeem(_msgSender(), _amount);
    }

    function withdraw() public nonReentrant {
        if (!withdrawEnabled || redeemEnabled) {
            revert NotWithdrawable();
        }
        address _user = _msgSender();
        uint256 amt = userAsset[_user];
        if (amt > 0) {
            userAsset[_user] = 0;
            IERC20(tokenUsd).safeTransfer(_user, amt);
            emit Withdraw(_user, tokenUsd, amt);
        } else {
            revert NoWithdrawableAssets();
        }
    }

    function refundToken(address token, address to) external onlyAssetManager {
        require(to != address(0), "Cannot be zero address");
        if (token == address(0)) {
            (bool success, ) = payable(to).call{ value: address(this).balance }("");
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

    function setMaxSupply(uint256 _max, uint256 _subscribed) external onlyAdmin {
        maxSupply = _max;
        totalSubscribed = _subscribed;
        emit UpdateMaxSupply(_max, _subscribed);
    }

    function setUsdToken(address _token) external onlyOwner {
        address prev = tokenUsd;
        tokenUsd = _token;
        emit UpdateUsdToken(prev, _token);
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
}
