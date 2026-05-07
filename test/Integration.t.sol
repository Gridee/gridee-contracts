// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {PropertyRegistry} from "../src/PropertyRegistry.sol";
import {EnergyLedger} from "../src/EnergyLedger.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract IntegrationTest is Test {
    GrideeToken public token;
    PropertyRegistry public propertyRegistry;
    EnergyLedger public energyLedger;
    MockUSDC public usdc;

    address deployer = address(1);
    address operator = address(2);
    address landlord = address(3);
    address tenant = address(4);
    address platformWallet = address(5);
    address opsWallet = address(6);
    address admin = address(7);

    bytes32 propertyCode = keccak256(abi.encodePacked("GRD-LAG-0042"));

    uint256 constant PRICE_PER_GRD = 10_000;
    uint256 constant LANDLORD_SHARE_BPS = 1800;
    uint256 constant PLATFORM_SHARE_BPS = 900;

    function setUp() public {
        vm.startPrank(deployer);

        usdc = new MockUSDC();
        token = new GrideeToken(
            deployer, address(usdc), platformWallet, opsWallet, PRICE_PER_GRD, LANDLORD_SHARE_BPS, PLATFORM_SHARE_BPS
        );
        propertyRegistry = new PropertyRegistry(deployer, operator);
        energyLedger = new EnergyLedger(deployer, operator, address(token));

        token.grantRole(token.BURNER_ROLE(), address(energyLedger));
        token.grantRole(token.OPERATOR_ROLE(), operator);

        token.grantRole(token.DEFAULT_ADMIN_ROLE(), admin);
        propertyRegistry.grantRole(propertyRegistry.DEFAULT_ADMIN_ROLE(), admin);
        energyLedger.grantRole(energyLedger.DEFAULT_ADMIN_ROLE(), admin);

        token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);
        propertyRegistry.renounceRole(propertyRegistry.DEFAULT_ADMIN_ROLE(), deployer);
        energyLedger.renounceRole(energyLedger.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopPrank();
    }

    function testFullFlow() public {
        vm.startPrank(operator);
        propertyRegistry.registerProperty(propertyCode, landlord, 10, "Surulere, Lagos");
        propertyRegistry.registerTenant(propertyCode, tenant);
        vm.stopPrank();

        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(token), usdcAmount);

        vm.prank(tenant);
        token.depositUSDC(usdcAmount);

        vm.prank(tenant);
        token.purchaseTokens(usdcAmount, landlord);

        uint256 expectedGRD = (usdcAmount * 1e18) / PRICE_PER_GRD;
        assertEq(token.balanceOf(tenant), expectedGRD);
        assertEq(token.tenantUSDCBalance(tenant), 0);

        uint256 landlordShare = (usdcAmount * LANDLORD_SHARE_BPS) / 10_000;
        uint256 platformShare = (usdcAmount * PLATFORM_SHARE_BPS) / 10_000;
        uint256 opsShare = usdcAmount - landlordShare - platformShare;

        assertEq(usdc.balanceOf(landlord), landlordShare);
        assertEq(usdc.balanceOf(platformWallet), platformShare);
        assertEq(usdc.balanceOf(opsWallet), opsShare);
        assertEq(usdc.balanceOf(address(token)), 0);

        uint256 deductAmount = 500 * 1e18;
        vm.prank(operator);
        energyLedger.deductTokens(tenant, deductAmount);

        assertEq(token.balanceOf(tenant), expectedGRD - deductAmount);
    }

    function testCutOffPreventsDeduction() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(token), usdcAmount);

        vm.prank(tenant);
        token.depositUSDC(usdcAmount);

        vm.prank(tenant);
        token.purchaseTokens(usdcAmount, landlord);

        vm.prank(admin);
        energyLedger.setCutOff(tenant, true);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("TenantCutOff(address)", tenant));
        energyLedger.deductTokens(tenant, 100 * 1e18);
    }

    function testPauseStopsOperations() public {
        vm.prank(admin);
        energyLedger.pause();

        vm.prank(operator);
        vm.expectRevert();
        energyLedger.deductTokens(tenant, 100 * 1e18);

        vm.prank(admin);
        energyLedger.unpause();

        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(token), usdcAmount);

        vm.prank(tenant);
        token.depositUSDC(usdcAmount);

        vm.prank(tenant);
        token.purchaseTokens(usdcAmount, landlord);

        uint256 expectedGRD = (usdcAmount * 1e18) / PRICE_PER_GRD;
        assertEq(token.balanceOf(tenant), expectedGRD);
    }

    function testDeductInsufficientBalance() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.InsufficientBalance.selector, tenant, 0, 100 * 1e18));
        energyLedger.deductTokens(tenant, 100 * 1e18);
    }

    function testTenantCannotTransferTokens() public {
        uint256 usdcAmount = 100 * 1e6;
        usdc.mint(tenant, usdcAmount);

        vm.prank(tenant);
        usdc.approve(address(token), usdcAmount);

        vm.prank(tenant);
        token.depositUSDC(usdcAmount);

        vm.prank(tenant);
        token.purchaseTokens(usdcAmount, landlord);

        vm.prank(tenant);
        vm.expectRevert(GrideeToken.TransferNotAllowed.selector);
        token.transfer(landlord, 10 * 1e18);
    }

    function testMultiplePurchasesAccumulateBalance() public {
        uint256 usdcAmount = 50 * 1e6;
        usdc.mint(tenant, usdcAmount * 2);

        vm.prank(tenant);
        usdc.approve(address(token), usdcAmount);

        vm.prank(tenant);
        token.depositUSDC(usdcAmount);

        vm.prank(tenant);
        token.purchaseTokens(usdcAmount, landlord);

        uint256 firstGRD = (usdcAmount * 1e18) / PRICE_PER_GRD;
        assertEq(token.balanceOf(tenant), firstGRD);

        vm.prank(tenant);
        usdc.approve(address(token), usdcAmount);

        vm.prank(tenant);
        token.depositUSDC(usdcAmount);

        vm.prank(tenant);
        token.purchaseTokens(usdcAmount, landlord);

        assertEq(token.balanceOf(tenant), firstGRD * 2);
    }

    function testPropertyRegistryIntegration() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(propertyCode, landlord, 10, "Surulere, Lagos");

        vm.prank(landlord);
        PropertyRegistry.Property memory prop = propertyRegistry.getProperty(propertyCode);

        assertTrue(prop.isActive);
        assertEq(prop.flatCount, 10);
        assertEq(prop.location, "Surulere, Lagos");
        assertTrue(prop.createdAt > 0);
        assertEq(propertyRegistry.propertyToLandlord(propertyCode), landlord);
    }

    function testTenantCapacityEnforcement() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(propertyCode, landlord, 2, "Surulere, Lagos");

        address tenant1 = address(10);
        address tenant2 = address(11);
        address tenant3 = address(12);

        vm.prank(operator);
        propertyRegistry.registerTenant(propertyCode, tenant1);

        vm.prank(operator);
        propertyRegistry.registerTenant(propertyCode, tenant2);

        assertEq(propertyRegistry.getAvailableFlats(propertyCode), 0);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.PropertyAtCapacity.selector, propertyCode, 2));
        propertyRegistry.registerTenant(propertyCode, tenant3);
    }

    function testTenantDeregistrationFreesCapacity() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(propertyCode, landlord, 1, "Surulere, Lagos");

        address tenant1 = address(10);

        vm.prank(operator);
        propertyRegistry.registerTenant(propertyCode, tenant1);

        assertEq(propertyRegistry.getAvailableFlats(propertyCode), 0);

        vm.prank(operator);
        propertyRegistry.deregisterTenant(propertyCode, tenant1);

        assertEq(propertyRegistry.getAvailableFlats(propertyCode), 1);

        address tenant2 = address(11);
        vm.prank(operator);
        propertyRegistry.registerTenant(propertyCode, tenant2);

        assertEq(propertyRegistry.getAvailableFlats(propertyCode), 0);
    }

    function testTenantToPropertyMapping() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(propertyCode, landlord, 10, "Surulere, Lagos");

        vm.prank(operator);
        propertyRegistry.registerTenant(propertyCode, tenant);

        assertEq(propertyRegistry.getTenantProperty(tenant), propertyCode);

        vm.prank(operator);
        propertyRegistry.deregisterTenant(propertyCode, tenant);

        assertEq(propertyRegistry.getTenantProperty(tenant), bytes32(0));
    }
}
