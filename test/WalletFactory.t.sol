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
    uint256 public userId1 = 1;
    uint256 public userId2 = 2;

    function setUp() public {
        walletFactory = new WalletFactory(deployer, operator);
    }

    function test_AssignWallet() public {
        vm.prank(operator);
        vm.expectEmit(true, false, false, true);
        emit WalletFactory.WalletAssigned(operator, userId1, wallet1);
        walletFactory.assignWallet(userId1, wallet1);

        assertEq(walletFactory.wallets(userId1), wallet1);
        assertEq(walletFactory.getWallet(userId1), wallet1);
        assertEq(walletFactory.walletToUserId(wallet1), userId1);
    }

    function test_AssignWallet_MultipleUsers() public {
        vm.prank(operator);
        walletFactory.assignWallet(userId1, wallet1);
        vm.prank(operator);
        walletFactory.assignWallet(userId2, wallet2);

        assertEq(walletFactory.wallets(userId1), wallet1);
        assertEq(walletFactory.wallets(userId2), wallet2);
        assertEq(walletFactory.walletToUserId(wallet1), userId1);
        assertEq(walletFactory.walletToUserId(wallet2), userId2);
    }

    function test_AssignWallet_RevertsIfWalletIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.ZeroAddress.selector, address(0)));
        walletFactory.assignWallet(userId1, address(0));
    }

    function test_AssignWallet_RevertsIfWalletAlreadyAssigned() public {
        vm.prank(operator);
        walletFactory.assignWallet(userId1, wallet1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.WalletAlreadyAssigned.selector, userId1));
        walletFactory.assignWallet(userId1, wallet2);
    }

    function test_AssignWallet_RevertsIfWalletReuse() public {
        vm.prank(operator);
        walletFactory.assignWallet(userId1, wallet1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(WalletFactory.WalletReuseNotAllowed.selector, wallet1));
        walletFactory.assignWallet(userId2, wallet1);
    }

    function test_AssignWallet_RevertsIfNotOperator() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929
            )
        );
        walletFactory.assignWallet(userId1, wallet1);
    }

    function test_GetWallet_ReturnsZeroForUnassignedUser() public view {
        assertEq(walletFactory.getWallet(userId1), address(0));
    }

    function test_GetWallet_ReturnsAssignedWallet() public {
        vm.prank(operator);
        walletFactory.assignWallet(userId1, wallet1);

        assertEq(walletFactory.getWallet(userId1), wallet1);
    }

    function test_WalletExists_ReturnsFalseForUnassignedUser() public view {
        assertFalse(walletFactory.walletExists(userId1));
    }

    function test_WalletExists_ReturnsTrueForAssignedUser() public {
        vm.prank(operator);
        walletFactory.assignWallet(userId1, wallet1);

        assertTrue(walletFactory.walletExists(userId1));
    }

    function test_DeployerHasAdminAndOperatorRoles() public view {
        assertTrue(walletFactory.hasRole(walletFactory.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(walletFactory.hasRole(walletFactory.OPERATOR_ROLE(), deployer));
    }
}
