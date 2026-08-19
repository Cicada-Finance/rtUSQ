// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import { rtERC20 } from "./rtERC20.sol";
import { RtCICDisabledAutoRebase } from "./rtCICDisabledAutoRebase.sol";

/// @notice rtCIC restored to the final block before the incident.
/// @dev The deployer receives all historical shares and distributes sharesRaw off-contract.
contract rtCIC is rtERC20 {
    uint256 public constant GENESIS_BLOCK = 115730532;
    bytes32 public constant GENESIS_BLOCK_HASH = 0x8624a3b60bb32ec1a5cae28ee64f37c1d131bb5d744aa1bdbf7ca5991ecf5e00;
    uint256 public constant GENESIS_TOTAL_SUPPLY = 1969996648338013568589757077;
    uint256 public constant GENESIS_TOTAL_SHARES = 990439290065931252525811831;

    address public immutable GENESIS_DEVELOPER;
    address public immutable GENESIS_AUTO_REBASE;

    event GenesisMinted(
        address indexed developer,
        uint256 indexed snapshotBlock,
        bytes32 snapshotBlockHash,
        uint256 tokenAmount,
        uint256 sharesAmount
    );

    constructor() rtERC20("rtCIC", "rtCIC", address(new RtCICDisabledAutoRebase())) {
        GENESIS_DEVELOPER = msg.sender;
        GENESIS_AUTO_REBASE = rtAutoRebase;
        _totalSupply = GENESIS_TOTAL_SUPPLY;
        _mintShares(msg.sender, GENESIS_TOTAL_SHARES);

        emit Transfer(address(0), msg.sender, GENESIS_TOTAL_SUPPLY);
        emit TransferShares(address(0), msg.sender, GENESIS_TOTAL_SHARES);
        emit GenesisMinted(msg.sender, GENESIS_BLOCK, GENESIS_BLOCK_HASH, GENESIS_TOTAL_SUPPLY, GENESIS_TOTAL_SHARES);
    }
}
