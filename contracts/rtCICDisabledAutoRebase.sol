// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

/// @dev Keeps inherited rtERC20 totalSupply accounting stable until the real
///      auto-rebase contract is configured after holder distribution.
contract RtCICDisabledAutoRebase {
    function rebaseAmount() external pure returns (uint256) {
        return 0;
    }
}
