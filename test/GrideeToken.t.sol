// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract GrideeTokenTest is Test {
    GrideeToken public grideeToken;
    MockUSDC public usdc;
    address public deployer;
    address public admin;
    address public operator;
    address public tenant;
    address public landlord;
    address public platformWallet;
    address public opsWallet;
    address public energyLedger;

    uint256 constant PRICE_PER_GRD = 10_000;
    uint256 constant LANDLORD_SHARE_BPS = 1800;
    uint256 constant PLATFORM_SHARE_BPS = 900;

    function setUp() public {
        deployer = address(1);
        admin = address(2);
        operator = address(3);
        tenant = address(4);
        landlord = address(5);
        platformWallet = address(6);
        opsWallet = address(7);
        energyLedger = address(8);

        usdc = new MockUSDC();
        vm.prank(deployer);
        grideeToken = new GrideeToken(
            deployer, address(usdc), platformWallet, opsWallet, PRICE_PER_GRD, LANDLORD_SHARE_BPS, PLATFORM_SHARE_BPS
        );

        vm.startPrank(deployer);
        grideeToken.grantRole(grideeToken.DEFAULT_ADMIN_ROLE(), admin);
        grideeToken.grantRole(grideeToken.BURNER_ROLE(), energyLedger);
        grideeToken.setEnergyLedger(energyLedger);
        grideeToken.renounceRole(grideeToken.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopPrank();
    }

    function test_DepositUSDC() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        assertEq(grideeToken.tenantUSDCBalance(tenant), usdcAmount);
        assertEq(usdc.balanceOf(address(grideeToken)), usdcAmount);
    }

    function test_DepositUSDC_ZeroAmount() public {
        vm.prank(tenant);
        vm.expectRevert(GrideeToken.ZeroAmount.selector);
        grideeToken.depositUSDC(0);
    }

    function test_DepositUSDC_InsufficientApproval() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount - 1);

        vm.prank(tenant);
        vm.expectRevert();
        grideeToken.depositUSDC(usdcAmount);
    }

    function test_PurchaseTokens_FromVault() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);

        uint256 expectedGRD = (usdcAmount * 1e18) / PRICE_PER_GRD;
        assertEq(grideeToken.balanceOf(tenant), expectedGRD);
        assertEq(grideeToken.tenantUSDCBalance(tenant), 0);
    }

    function test_PurchaseTokensRevenueSplit() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);

        uint256 landlordShare = (usdcAmount * LANDLORD_SHARE_BPS) / 10_000;
        uint256 platformShare = (usdcAmount * PLATFORM_SHARE_BPS) / 10_000;
        uint256 opsShare = usdcAmount - landlordShare - platformShare;

        assertEq(usdc.balanceOf(landlord), landlordShare);
        assertEq(usdc.balanceOf(platformWallet), platformShare);
        assertEq(usdc.balanceOf(opsWallet), opsShare);
        assertEq(usdc.balanceOf(address(grideeToken)), 0);
    }

    function test_PurchaseTokensEmitsEvent() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        uint256 expectedGRD = (usdcAmount * 1e18) / PRICE_PER_GRD;
        uint256 landlordShare = (usdcAmount * LANDLORD_SHARE_BPS) / 10_000;
        uint256 platformShare = (usdcAmount * PLATFORM_SHARE_BPS) / 10_000;
        uint256 opsShare = usdcAmount - landlordShare - platformShare;

        vm.prank(tenant);
        vm.expectEmit(true, true, false, true);
        emit GrideeToken.TokensPurchased(tenant, landlord, usdcAmount, expectedGRD, landlordShare, platformShare, opsShare);
        grideeToken.purchaseTokens(usdcAmount, landlord);
    }

    function test_RevertIfPurchaseZeroAmount() public {
        vm.prank(tenant);
        vm.expectRevert(GrideeToken.ZeroAmount.selector);
        grideeToken.purchaseTokens(0, landlord);
    }

    function test_RevertIfPurchaseZeroLandlord() public {
        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(GrideeToken.ZeroAddress.selector, address(0)));
        grideeToken.purchaseTokens(1e6, address(0));
    }

    function test_RevertIfPriceNotSet() public {
        vm.prank(admin);
        grideeToken.setPrice(0);

        vm.prank(tenant);
        vm.expectRevert(GrideeToken.PriceNotSet.selector);
        grideeToken.purchaseTokens(1e6, landlord);
    }

    function test_RevertIfInsufficientUSDCBalance() public {
        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(GrideeToken.InsufficientUSDCBalance.selector, 0, 1e6));
        grideeToken.purchaseTokens(1e6, landlord);
    }

    function test_PartialPurchase() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        uint256 buyAmount = 50 * 1e6;
        vm.prank(tenant);
        grideeToken.purchaseTokens(buyAmount, landlord);

        assertEq(grideeToken.tenantUSDCBalance(tenant), 50 * 1e6);
    }

    function test_MultipleDeposits() public {
        uint256 usdcAmount = 50 * 1e6;
        usdc.mint(tenant, usdcAmount * 2);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        assertEq(grideeToken.tenantUSDCBalance(tenant), usdcAmount * 2);
    }

    function test_BurnByBurnerRole() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);

        uint256 balance = grideeToken.balanceOf(tenant);
        uint256 burnAmount = 50 * 1e18;

        vm.prank(energyLedger);
        grideeToken.burn(tenant, burnAmount);

        assertEq(grideeToken.balanceOf(tenant), balance - burnAmount);
    }

    function test_RevertIfBurnNotBurnerRole() public {
        vm.prank(tenant);
        vm.expectRevert();
        grideeToken.burn(tenant, 1e18);
    }

    function test_SetPrice() public {
        uint256 newPrice = 20_000;

        vm.prank(admin);
        grideeToken.setPrice(newPrice);

        assertEq(grideeToken.pricePerGRD(), newPrice);
    }

    function test_RevertIfSetPriceNotAdmin() public {
        vm.prank(operator);
        vm.expectRevert();
        grideeToken.setPrice(20_000);
    }

    function test_UpdateShares() public {
        vm.prank(admin);
        grideeToken.updateShares(2000, 1000);

        assertEq(grideeToken.landlordShareBPS(), 2000);
        assertEq(grideeToken.platformShareBPS(), 1000);
    }

    function test_RevertIfUpdateSharesInvalid() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(GrideeToken.InvalidShares.selector, 6000, 5000));
        grideeToken.updateShares(6000, 5000);
    }

    function test_RevertIfUpdateSharesNotAdmin() public {
        vm.prank(operator);
        vm.expectRevert();
        grideeToken.updateShares(2000, 1000);
    }

    function test_UpdateWallets() public {
        address newPlatform = address(10);
        address newOps = address(11);

        vm.prank(admin);
        grideeToken.updateWallets(newPlatform, newOps);

        assertEq(grideeToken.platformWallet(), newPlatform);
        assertEq(grideeToken.opsWallet(), newOps);
    }

    function test_RevertIfUpdateWalletsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(GrideeToken.ZeroAddress.selector, address(0)));
        grideeToken.updateWallets(address(0), address(11));
    }

    function test_SetEnergyLedger() public {
        address newLedger = address(12);

        vm.prank(admin);
        grideeToken.setEnergyLedger(newLedger);

        assertEq(grideeToken.energyLedger(), newLedger);
    }

    function test_TransferNotAllowed() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);

        vm.prank(tenant);
        vm.expectRevert(GrideeToken.TransferNotAllowed.selector);
        grideeToken.transfer(address(13), 10 * 1e18);
    }

    function test_TransferToEnergyLedgerAllowed() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);

        vm.prank(tenant);
        grideeToken.transfer(energyLedger, 10 * 1e18);

        assertEq(grideeToken.balanceOf(energyLedger), 10 * 1e18);
    }

    function test_PauseAndUnpause() public {
        vm.prank(admin);
        grideeToken.pause();

        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        vm.expectRevert();
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(admin);
        grideeToken.unpause();

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        assertEq(grideeToken.tenantUSDCBalance(tenant), usdcAmount);
    }

    function test_PauseOnlyByAdmin() public {
        vm.prank(operator);
        vm.expectRevert();
        grideeToken.pause();
    }

    function test_NameAndSymbol() public view {
        assertEq(grideeToken.name(), "Gridee Token");
        assertEq(grideeToken.symbol(), "GRD");
    }

    function test_PriceCalculation() public {
        vm.prank(admin);
        grideeToken.setPrice(5_000);

        uint256 usdcAmount = 50 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);

        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);

        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);

        uint256 expectedGRD = (usdcAmount * 1e18) / 5_000;
        assertEq(grideeToken.balanceOf(tenant), expectedGRD);
    }
}
