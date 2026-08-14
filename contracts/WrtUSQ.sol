// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract WrappedRtUSQ is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    event TokenRescued(address indexed token, address indexed to, uint256 amount);

    constructor(
        address rtUsqToken,
        string memory name_,
        string memory symbol_
    ) ERC4626(IERC20(rtUsqToken)) ERC20(name_, symbol_) Ownable() {}

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
}
