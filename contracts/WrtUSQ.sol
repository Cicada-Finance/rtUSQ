// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/ISwapRouter02.sol";
import "./utils/PathParser.sol";

contract WrappedRtUSQ is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public rtUSQ;
    IERC20 public usdt;
    ISwapRouter02 public immutable router;

    event RtUsqPurchased(address indexed buyer, uint256 usdtAmount, uint256 rtUsqReceived);
    event RtUsqSold(address indexed seller, uint256 rtUsqAmount, uint256 usdtReceived);
    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    constructor(
        address rtUsqToken,
        address usdtToken,
        string memory name_,
        string memory symbol_,
        address routerAddress
    ) ERC4626(IERC20(rtUsqToken)) ERC20(name_, symbol_) Ownable() {
        router = ISwapRouter02(routerAddress);
        rtUSQ = IERC20(rtUsqToken);
        usdt = IERC20(usdtToken);
    }

    function rescueToken(address token, address to) external onlyOwner {
        require(to != address(0), "Cannot be zero address");
        uint256 transferredAmount;
        if (token == address(0)) {
            transferredAmount = address(this).balance;
            (bool success, ) = payable(to).call{ value: address(this).balance }("");
            if (!success) {
                revert();
            }
        } else {
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            transferredAmount = tokenBalance;
            IERC20(token).safeTransfer(to, tokenBalance);
        }
        emit TokenRescued(token, to, transferredAmount);
    }

    function buyRtUsq(
        uint256 usdtAmount,
        uint256 minRtUsqOut,
        address recipient,
        bytes calldata path
    ) external nonReentrant returns (uint256 rtUsqReceived) {
        usdt.safeTransferFrom(msg.sender, address(this), usdtAmount);
        usdt.forceApprove(address(router), usdtAmount);

        _validateSwapPath(address(this), path);
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            amountIn: usdtAmount,
            amountOutMinimum: 1
        });

        uint256 wrappedSharesReceived = router.exactInput(params);

        uint256 expectedRtUsq = convertToAssets(wrappedSharesReceived);
        require(expectedRtUsq >= minRtUsqOut, "Slippage: Too little rtUSQ received after conversion");

        rtUsqReceived = expectedRtUsq;
        _withdraw(address(this), recipient, address(this), rtUsqReceived, wrappedSharesReceived);

        require(rtUsqReceived >= minRtUsqOut, "Slippage: Final rtUSQ amount too low");

        emit RtUsqPurchased(msg.sender, usdtAmount, rtUsqReceived);
    }

    function sellRtUsq(
        uint256 rtUsqAmount,
        uint256 minUsdtOut,
        address recipient,
        bytes calldata path
    ) external nonReentrant returns (uint256 usdtReceived) {
        rtUSQ.safeTransferFrom(msg.sender, address(this), rtUsqAmount);
        uint256 wrappedSharesMinted = previewDeposit(rtUsqAmount);
        _mint(address(this), wrappedSharesMinted);
        emit Deposit(address(this), address(this), rtUsqAmount, wrappedSharesMinted);
        IERC20(address(this)).forceApprove(address(router), wrappedSharesMinted);
        _validateSwapPath(address(usdt), path);
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: recipient,
            amountIn: wrappedSharesMinted,
            amountOutMinimum: 1
        });

        usdtReceived = router.exactInput(params);

        require(usdtReceived >= minUsdtOut, "Slippage: Too little USDT received");

        emit RtUsqSold(msg.sender, rtUsqAmount, usdtReceived);
    }

    function _validateSwapPath(address expectedOutputToken, bytes calldata path) internal pure {
        address actualOutputToken = PathParser.getLastToken(path);
        require(actualOutputToken == expectedOutputToken, "Invalid path: output token does not match expected token");
    }
}
