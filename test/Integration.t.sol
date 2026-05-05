// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {PropertyRegistry} from "../src/PropertyRegistry.sol";
import {EnergyLedger} from "../src/EnergyLedger.sol";
import {RevenueDistributor} from "../src/RevenueDistributor.sol";

contract IntegrationTest is Test {
    GrideeToken public token;
    WalletFactory public walletFactory;
    PropertyRegistry public propertyRegistry;
    EnergyLedger public energyLedger;
    RevenueDistributor public revenueDistributor;

    address deployer = address(1);
    address operator = address(2);
    address landlord = address(3);
    address tenant = address(4);
    address platformWallet = address(5);
    address opsWallet = address(6);
    address admin = address(7);

    bytes32 landlordPhoneHash = keccak256(abi.encodePacked("+2348000000001"));
    bytes32 tenantPhoneHash = keccak256(abi.encodePacked("+2348000000002"));
    bytes32 propertyCode = keccak256(abi.encodePacked("GRD-LAG-0042"));

    function setUp() public {
        vm.startPrank(deployer);
        token = new GrideeToken(deployer);
        walletFactory = new WalletFactory(deployer, operator);
        propertyRegistry = new PropertyRegistry(deployer, operator);
        energyLedger = new EnergyLedger(deployer, operator, address(token));
        revenueDistributor =
            new RevenueDistributor(deployer, operator, address(token), platformWallet, opsWallet, 1800, 900);

        token.grantRole(token.OPERATOR_ROLE(), address(energyLedger));
        token.grantRole(token.OPERATOR_ROLE(), address(revenueDistributor));
        token.grantRole(token.OPERATOR_ROLE(), operator);

        token.grantRole(token.DEFAULT_ADMIN_ROLE(), admin);
        walletFactory.grantRole(walletFactory.DEFAULT_ADMIN_ROLE(), admin);
        propertyRegistry.grantRole(propertyRegistry.DEFAULT_ADMIN_ROLE(), admin);
        energyLedger.grantRole(energyLedger.DEFAULT_ADMIN_ROLE(), admin);
        revenueDistributor.grantRole(revenueDistributor.DEFAULT_ADMIN_ROLE(), admin);

        token.renounceRole(token.DEFAULT_ADMIN_ROLE(), deployer);
        walletFactory.renounceRole(walletFactory.DEFAULT_ADMIN_ROLE(), deployer);
        propertyRegistry.renounceRole(propertyRegistry.DEFAULT_ADMIN_ROLE(), deployer);
        energyLedger.renounceRole(energyLedger.DEFAULT_ADMIN_ROLE(), deployer);
        revenueDistributor.renounceRole(revenueDistributor.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopPrank();
    }

    function testFullFlow() public {
        vm.startPrank(operator);

        walletFactory.registerLandlord(landlordPhoneHash, landlord);
        walletFactory.registerTenant(tenantPhoneHash, tenant, propertyCode);

        propertyRegistry.registerProperty(propertyCode, landlord, 10, "Surulere, Lagos");

        uint256 mintAmount = 1000 * 1e18;
        energyLedger.mintTokens(tenant, mintAmount);

        assertEq(token.balanceOf(tenant), mintAmount);

        token.mint(address(revenueDistributor), mintAmount);

        revenueDistributor.distributeRevenue(propertyCode, landlord, mintAmount);

        uint256 landlordShare = (mintAmount * 1800) / 10_000;
        uint256 platformShare = (mintAmount * 900) / 10_000;
        uint256 opsShare = mintAmount - landlordShare - platformShare;

        assertEq(revenueDistributor.pendingWithdrawals(landlord), landlordShare);
        assertEq(token.balanceOf(platformWallet), platformShare);
        assertEq(token.balanceOf(opsWallet), opsShare);

        vm.stopPrank();

        vm.prank(landlord);
        revenueDistributor.withdraw();

        assertEq(token.balanceOf(landlord), landlordShare);
        assertEq(revenueDistributor.pendingWithdrawals(landlord), 0);

        uint256 deductAmount = 500 * 1e18;
        vm.prank(operator);
        energyLedger.deductTokens(tenant, deductAmount);

        assertEq(token.balanceOf(tenant), mintAmount - deductAmount);
    }

    function testCutOffPreventsMinting() public {
        vm.startPrank(operator);
        energyLedger.mintTokens(tenant, 100 * 1e18);
        vm.stopPrank();

        vm.prank(admin);
        energyLedger.setCutOff(tenant, true);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("TenantCutOff(address)", tenant));
        energyLedger.mintTokens(tenant, 100 * 1e18);
    }

    function testPauseStopsOperations() public {
        vm.prank(admin);
        energyLedger.pause();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        energyLedger.mintTokens(tenant, 100 * 1e18);

        vm.prank(admin);
        energyLedger.unpause();

        vm.prank(operator);
        energyLedger.mintTokens(tenant, 100 * 1e18);

        assertEq(token.balanceOf(tenant), 100 * 1e18);
    }

    function testDeductInsufficientBalance() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance(address,uint256,uint256)", tenant, 0, 100 * 1e18));
        energyLedger.deductTokens(tenant, 100 * 1e18);
    }

    function testWithdrawWithNoPending() public {
        vm.prank(landlord);
        vm.expectRevert("NoPendingWithdrawals()");
        revenueDistributor.withdraw();
    }
}
