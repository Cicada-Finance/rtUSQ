// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRtUSQ is IERC20 {
    function mintTo(address to, uint256 _amount) external;
    function burnFrom(address from, uint256 _amount) external;

    function burn(uint256 _amount) external;
    function decimals() external view returns (uint8);
}
