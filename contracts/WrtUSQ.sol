// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

interface IRtUSQShares is IERC20 {
    function sharesOf(address account) external view returns (uint256);

    function transferSharesFrom(address sender, address recipient, uint256 sharesAmount) external returns (uint256);
}

contract WrappedRtUSQ is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    error GenesisDeveloperOnly();
    error MigrationAlreadyInitialized();
    error NativeTransferFailed();
    error NonEmptyVault();
    error UnexpectedGenesisShares();
    error ZeroAddress();

    uint256 public constant GENESIS_BLOCK = 115730532;
    bytes32 public constant GENESIS_BLOCK_HASH = 0x8624a3b60bb32ec1a5cae28ee64f37c1d131bb5d744aa1bdbf7ca5991ecf5e00;
    uint256 public constant GENESIS_TOTAL_SUPPLY = 472817435057562679109599;
    uint256 public constant GENESIS_TOTAL_ASSETS = 491355694115188876511399;
    uint256 public constant GENESIS_ASSET_SHARES = 464436382656835717518787;

    address public immutable GENESIS_DEVELOPER;
    bool public migrationInitialized;

    event TokenRescued(address indexed token, address indexed to, uint256 amount);
    event GenesisMinted(
        address indexed developer,
        uint256 indexed snapshotBlock,
        bytes32 snapshotBlockHash,
        uint256 assetAmount,
        uint256 assetShares,
        uint256 wrappedShares
    );

    constructor(
        address rtUsqToken,
        string memory name_,
        string memory symbol_
    ) ERC4626(IERC20(rtUsqToken)) ERC20(name_, symbol_) Ownable() {
        GENESIS_DEVELOPER = msg.sender;
    }

    /// @notice Atomically restores the old wrapper backing and mints its snapshot supply to the developer.
    /// @dev The developer must approve enough rtUSQ for the current value of GENESIS_ASSET_SHARES.
    function initializeMigration() external onlyOwner {
        if (msg.sender != GENESIS_DEVELOPER) revert GenesisDeveloperOnly();
        if (migrationInitialized) revert MigrationAlreadyInitialized();

        IRtUSQShares rtUsq = IRtUSQShares(asset());
        uint256 sharesBefore = rtUsq.sharesOf(address(this));
        if (totalSupply() != 0 || sharesBefore != 0) revert NonEmptyVault();

        migrationInitialized = true;
        rtUsq.transferSharesFrom(msg.sender, address(this), GENESIS_ASSET_SHARES);

        uint256 sharesAfter = rtUsq.sharesOf(address(this));
        if (sharesAfter != sharesBefore + GENESIS_ASSET_SHARES) revert UnexpectedGenesisShares();
        uint256 receivedAssets = totalAssets();

        _mint(msg.sender, GENESIS_TOTAL_SUPPLY);
        emit Deposit(msg.sender, msg.sender, receivedAssets, GENESIS_TOTAL_SUPPLY);
        emit GenesisMinted(
            msg.sender,
            GENESIS_BLOCK,
            GENESIS_BLOCK_HASH,
            receivedAssets,
            GENESIS_ASSET_SHARES,
            GENESIS_TOTAL_SUPPLY
        );
    }

    function rescueToken(address token, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 transferredAmount;
        if (token == address(0)) {
            transferredAmount = address(this).balance;
            (bool success, ) = payable(to).call{ value: address(this).balance }("");
            if (!success) revert NativeTransferFailed();
        } else {
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            transferredAmount = tokenBalance;
            IERC20(token).safeTransfer(to, tokenBalance);
        }
        emit TokenRescued(token, to, transferredAmount);
    }
}
