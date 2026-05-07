// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract GrideeToken is ERC20, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    IERC20 public usdc;
    address public platformWallet;
    address public opsWallet;
    uint16 public landlordShareBPS;
    uint16 public platformShareBPS;
    uint256 public pricePerGRD;
    address public energyLedger;

    mapping(address => uint256) public tenantUSDCBalance;

    event USDCDeposited(address indexed tenant, uint256 amount);
    event TokensPurchased(
        address indexed tenant,
        address indexed landlord,
        uint256 usdcAmount,
        uint256 grdAmount,
        uint256 landlordShare,
        uint256 platformShare,
        uint256 opsShare
    );
    event PriceUpdated(uint256 newPricePerGRD);
    event SharesUpdated(uint256 landlordShareBPS, uint256 platformShareBPS);
    event WalletsUpdated(address platformWallet, address opsWallet);
    event EnergyLedgerUpdated(address energyLedger);

    error ZeroAddress(address value);
    error ZeroAmount();
    error InvalidShares(uint256 landlordBPS, uint256 platformBPS);
    error TransferNotAllowed();
    error PriceNotSet();
    error InsufficientUSDCBalance(uint256 balance, uint256 requested);

    constructor(
        address deployer,
        address usdcAddress,
        address platformWalletAddress,
        address opsWalletAddress,
        uint256 initialPricePerGRD,
        uint256 initialLandlordShareBPS,
        uint256 initialPlatformShareBPS
    ) ERC20("Gridee Token", "GRD") {
        if (usdcAddress == address(0)) revert ZeroAddress(usdcAddress);
        if (platformWalletAddress == address(0)) revert ZeroAddress(platformWalletAddress);
        if (opsWalletAddress == address(0)) revert ZeroAddress(opsWalletAddress);
        if (initialLandlordShareBPS + initialPlatformShareBPS > 10_000) {
            revert InvalidShares(initialLandlordShareBPS, initialPlatformShareBPS);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);

        usdc = IERC20(usdcAddress);
        platformWallet = platformWalletAddress;
        opsWallet = opsWalletAddress;
        pricePerGRD = initialPricePerGRD;
        landlordShareBPS = uint16(initialLandlordShareBPS);
        platformShareBPS = uint16(initialPlatformShareBPS);
    }

    function depositUSDC(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        usdc.safeTransferFrom(msg.sender, address(this), amount);
        tenantUSDCBalance[msg.sender] += amount;

        emit USDCDeposited(msg.sender, amount);
    }

    function purchaseTokens(uint256 usdcAmount, address landlord) external nonReentrant whenNotPaused {
        if (landlord == address(0)) revert ZeroAddress(landlord);
        if (usdcAmount == 0) revert ZeroAmount();
        if (pricePerGRD == 0) revert PriceNotSet();
        if (tenantUSDCBalance[msg.sender] < usdcAmount) {
            revert InsufficientUSDCBalance(tenantUSDCBalance[msg.sender], usdcAmount);
        }

        tenantUSDCBalance[msg.sender] -= usdcAmount;

        uint256 grdAmount = (usdcAmount * 1e18) / pricePerGRD;

        uint256 landlordShare = (usdcAmount * landlordShareBPS) / 10_000;
        uint256 platformShare = (usdcAmount * platformShareBPS) / 10_000;
        uint256 opsShare = usdcAmount - landlordShare - platformShare;

        if (landlordShare > 0) {
            usdc.safeTransfer(landlord, landlordShare);
        }
        if (platformShare > 0) {
            usdc.safeTransfer(platformWallet, platformShare);
        }
        if (opsShare > 0) {
            usdc.safeTransfer(opsWallet, opsShare);
        }

        _mint(msg.sender, grdAmount);

        emit TokensPurchased(msg.sender, landlord, usdcAmount, grdAmount, landlordShare, platformShare, opsShare);
    }

    function burn(address account, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    function setPrice(uint256 newPricePerGRD) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pricePerGRD = newPricePerGRD;
        emit PriceUpdated(newPricePerGRD);
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

    function setEnergyLedger(address newEnergyLedger) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newEnergyLedger == address(0)) revert ZeroAddress(newEnergyLedger);
        energyLedger = newEnergyLedger;
        emit EnergyLedgerUpdated(newEnergyLedger);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && to != energyLedger) {
            revert TransferNotAllowed();
        }
        super._update(from, to, value);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
