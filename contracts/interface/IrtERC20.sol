// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IrtERC20 is IERC20 {
    function mintTo(address to, uint256 _amount) external;

    function burn(uint256 _amount) external;

    function decimals() external returns (uint8);

    function rebase(int256 _amount) external returns (uint256);
}
