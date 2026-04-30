// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract WalletFactoryTest is Test {
    WalletFactory public walletFactory;
    address public deployer = makeAddr("deployer");
    address public operator = makeAddr("operator");
    address public randomUser = makeAddr("randomUser");
    address public wallet1 = makeAddr("wallet1");
    address public wallet2 = makeAddr("wallet2");
    bytes32 public phoneHash1 = keccak256(abi.encodePacked("+2348012345678"));
    bytes32 public phoneHash2 = keccak256(abi.encodePacked("+2348098765432"));
    bytes32 public propertyCode = keccak256(abi.encodePacked("GRD-LAG-0045"));

    function setUp() public {
        walletFactory = new WalletFactory(deployer, operator);
    }

    // ==================== REGISTER LANDLORD ====================

    function test_RegisterLandlord() public {
        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit WalletFactory.LandlordRegistered(operator, phoneHash1, wallet1);
        walletFactory.registerLandlord(phoneHash1, wallet1);

        assertEq(walletFactory.landlordWallets(phoneHash1), wallet1);
        assertEq(walletFactory.getLandlordWallet(phoneHash1), wallet1);
        assertTrue(walletFactory.isWalletRegistered(wallet1));
    }

    function test_RegisterLandlord_RevertsIfWalletIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.ZeroAddress.selector, address(0)));
        walletFactory.registerLandlord(phoneHash1, address(0));
    }

    function test_RegisterLandlord_RevertsIfWalletAlreadyRegistered() public {
        vm.prank(operator);
        walletFactory.registerLandlord(phoneHash1, wallet1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.WalletAlreadyRegistered.selector, wallet1));
        walletFactory.registerLandlord(phoneHash2, wallet1);
    }

    function test_RegisterLandlord_RevertsIfLandlordAlreadyRegistered() public {
        vm.prank(operator);
        walletFactory.registerLandlord(phoneHash1, wallet1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.LandlordAlreadyRegistered.selector, phoneHash1));
        walletFactory.registerLandlord(phoneHash1, wallet2);
    }

    function test_RegisterLandlord_RevertsIfNotOperator() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929
            )
        );
        walletFactory.registerLandlord(phoneHash1, wallet1);
    }

    // ==================== REGISTER TENANT ====================

    function test_RegisterTenant() public {
        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit WalletFactory.TenantRegistered(operator, phoneHash1, wallet1, propertyCode);
        walletFactory.registerTenant(phoneHash1, wallet1, propertyCode);

        assertEq(walletFactory.tenantWallets(phoneHash1), wallet1);
        assertEq(walletFactory.getTenantWallet(phoneHash1), wallet1);
        assertEq(walletFactory.tenantProperty(phoneHash1), propertyCode);
        assertEq(walletFactory.getTenantProperty(phoneHash1), propertyCode);
        assertTrue(walletFactory.isWalletRegistered(wallet1));
    }

    function test_RegisterTenant_RevertsIfWalletIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.ZeroAddress.selector, address(0)));
        walletFactory.registerTenant(phoneHash1, address(0), propertyCode);
    }

    function test_RegisterTenant_RevertsIfWalletAlreadyRegistered() public {
        vm.prank(operator);
        walletFactory.registerLandlord(phoneHash1, wallet1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.WalletAlreadyRegistered.selector, wallet1));
        walletFactory.registerTenant(phoneHash2, wallet1, propertyCode);
    }

    function test_RegisterTenant_RevertsIfTenantAlreadyRegistered() public {
        vm.prank(operator);
        walletFactory.registerTenant(phoneHash1, wallet1, propertyCode);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.TenantAlreadyRegistered.selector, phoneHash1));
        walletFactory.registerTenant(phoneHash1, wallet2, propertyCode);
    }

    function test_RegisterTenant_RevertsIfPropertyCodeIsEmpty() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.EmptyPropertyCode.selector, bytes32(0)));
        walletFactory.registerTenant(phoneHash1, wallet1, bytes32(0));
    }

    function test_RegisterTenant_RevertsIfNotOperator() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929
            )
        );
        walletFactory.registerTenant(phoneHash1, wallet1, propertyCode);
    }

    // ==================== VIEW FUNCTIONS ====================

    function test_GetLandlordWallet_ReturnsZeroForUnregistered() public view {
        assertEq(walletFactory.getLandlordWallet(phoneHash1), address(0));
    }

    function test_GetTenantWallet_ReturnsZeroForUnregistered() public view {
        assertEq(walletFactory.getTenantWallet(phoneHash1), address(0));
    }

    function test_GetTenantProperty_ReturnsZeroForUnregistered() public view {
        assertEq(walletFactory.getTenantProperty(phoneHash1), bytes32(0));
    }

    function test_IsWalletRegistered_ReturnsFalseForUnregistered() public view {
        assertFalse(walletFactory.isWalletRegistered(wallet1));
    }

    function test_IsWalletRegistered_ReturnsTrueForRegistered() public {
        vm.prank(operator);
        walletFactory.registerLandlord(phoneHash1, wallet1);
        assertTrue(walletFactory.isWalletRegistered(wallet1));
    }

    // ==================== CROSS-TYPE WALLET REUSE ====================

    function test_CannotReuseLandlordWalletForTenant() public {
        vm.prank(operator);
        walletFactory.registerLandlord(phoneHash1, wallet1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.WalletAlreadyRegistered.selector, wallet1));
        walletFactory.registerTenant(phoneHash2, wallet1, propertyCode);
    }

    function test_CannotReuseTenantWalletForLandlord() public {
        vm.prank(operator);
        walletFactory.registerTenant(phoneHash1, wallet1, propertyCode);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.WalletAlreadyRegistered.selector, wallet1));
        walletFactory.registerLandlord(phoneHash2, wallet1);
    }

    // ==================== ROLE MANAGEMENT ====================

    function test_DeployerHasAdminAndOperatorRoles() public view {
        assertTrue(walletFactory.hasRole(walletFactory.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(walletFactory.hasRole(walletFactory.OPERATOR_ROLE(), deployer));
    }
}
