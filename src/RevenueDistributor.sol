// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract RevenueDistributor is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    using SafeERC20 for IERC20;

    IERC20 public token;
    address public platformWallet;
    address public opsWallet;
    uint16 public landlordShareBPS;
    uint16 public platformShareBPS;

    mapping(address => uint256) public pendingWithdrawals;

    event RevenueDistributed(
        bytes32 propertyCode,
        address landlord,
        uint256 totalAmount,
        uint256 landlordShare,
        uint256 platformShare,
        uint256 opsShare
    );
    event SharesUpdated(uint256 landlordShareBPS, uint256 platformShareBPS);
    event WithdrawalClaimed(address indexed landlord, uint256 amount);
    event WalletsUpdated(address platformWallet, address opsWallet);

    error ZeroAddress(address value);
    error ZeroAmount();
    error InvalidShares(uint256 landlordBPS, uint256 platformBPS);
    error NoPendingWithdrawals();
    error TransferFailed();
    error NotPropertyLandlord(address wallet, bytes32 propertyCode);

    constructor(
        address deployer,
        address initialOperator,
        address tokenAddress,
        address platformWalletAddress,
        address opsWalletAddress,
        uint256 initialLandlordShareBPS,
        uint256 initialPlatformShareBPS
    ) {
        if (tokenAddress == address(0)) revert ZeroAddress(tokenAddress);
        if (platformWalletAddress == address(0)) revert ZeroAddress(platformWalletAddress);
        if (opsWalletAddress == address(0)) revert ZeroAddress(opsWalletAddress);
        if (initialLandlordShareBPS + initialPlatformShareBPS > 10_000) {
            revert InvalidShares(initialLandlordShareBPS, initialPlatformShareBPS);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, initialOperator);

        token = IERC20(tokenAddress);
        platformWallet = platformWalletAddress;
        opsWallet = opsWalletAddress;
        landlordShareBPS = uint16(initialLandlordShareBPS);
        platformShareBPS = uint16(initialPlatformShareBPS);
    }

    function distributeRevenue(bytes32 propertyCode, address landlordWallet, uint256 totalAmount)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
    {
        if (landlordWallet == address(0)) revert ZeroAddress(landlordWallet);
        if (totalAmount == 0) revert ZeroAmount();

        uint256 landlordShare = (totalAmount * landlordShareBPS) / 10_000;
        uint256 platformShare = (totalAmount * platformShareBPS) / 10_000;
        uint256 opsShare = totalAmount - landlordShare - platformShare;

        pendingWithdrawals[landlordWallet] += landlordShare;

        if (platformShare > 0) {
            token.safeTransfer(platformWallet, platformShare);
        }
        if (opsShare > 0) {
            token.safeTransfer(opsWallet, opsShare);
        }

        emit RevenueDistributed(propertyCode, landlordWallet, totalAmount, landlordShare, platformShare, opsShare);
    }

    function withdraw() external nonReentrant whenNotPaused {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoPendingWithdrawals();

        pendingWithdrawals[msg.sender] = 0;

        token.safeTransfer(msg.sender, amount);

        emit WithdrawalClaimed(msg.sender, amount);
    }

    function updateShares(uint256 newLandlordBPS, uint256 newPlatformBPS) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newLandlordBPS + newPlatformBPS > 10_000) {
            revert InvalidShares(newLandlordBPS, newPlatformBPS);
        }

        landlordShareBPS = uint16(newLandlordBPS);
        platformShareBPS = uint16(newPlatformBPS);

        emit SharesUpdated(newLandlordBPS, newPlatformBPS);
    }

    function updateWallets(address newPlatformWallet, address newOpsWallet) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newPlatformWallet == address(0)) revert ZeroAddress(newPlatformWallet);
        if (newOpsWallet == address(0)) revert ZeroAddress(newOpsWallet);

        platformWallet = newPlatformWallet;
        opsWallet = newOpsWallet;

        emit WalletsUpdated(newPlatformWallet, newOpsWallet);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
