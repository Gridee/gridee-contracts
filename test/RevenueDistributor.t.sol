// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {RevenueDistributor} from "../src/RevenueDistributor.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract RevenueDistributorTest is Test {
    GrideeToken public grideeToken;
    RevenueDistributor public revenueDistributor;
    address public deployer = makeAddr("deployer");
    address public operator = makeAddr("operator");
    address public admin = makeAddr("admin");
    address public randomUser = makeAddr("randomUser");
    address public landlord1 = makeAddr("landlord1");
    address public landlord2 = makeAddr("landlord2");
    address public platformWallet = makeAddr("platformWallet");
    address public opsWallet = makeAddr("opsWallet");
    bytes32 public propertyCode1 = keccak256(abi.encodePacked("GRD-LAG-0045"));
    bytes32 public propertyCode2 = keccak256(abi.encodePacked("GRD-NYC-0001"));

    uint256 public constant LANDLORD_BPS = 1800;
    uint256 public constant PLATFORM_BPS = 900;
    uint256 public constant TOTAL_AMOUNT = 100 ether;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant OPERATOR_ROLE = 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929;

    function setUp() public {
        grideeToken = new GrideeToken(deployer);
        revenueDistributor = new RevenueDistributor(
            deployer,
            operator,
            address(grideeToken),
            platformWallet,
            opsWallet,
            LANDLORD_BPS,
            PLATFORM_BPS
        );

        vm.startPrank(deployer);
        grideeToken.grantRole(OPERATOR_ROLE, address(revenueDistributor));
        revenueDistributor.grantRole(DEFAULT_ADMIN_ROLE, admin);
        grideeToken.mint(address(revenueDistributor), 10_000 ether);
        vm.stopPrank();
    }

    // ==================== DISTRIBUTE REVENUE ====================

    function test_DistributeRevenue() public {
        uint256 landlordShare = (TOTAL_AMOUNT * LANDLORD_BPS) / 10_000;
        uint256 platformShare = (TOTAL_AMOUNT * PLATFORM_BPS) / 10_000;
        uint256 opsShare = TOTAL_AMOUNT - landlordShare - platformShare;

        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);

        assertEq(revenueDistributor.pendingWithdrawals(landlord1), landlordShare);
        assertEq(grideeToken.balanceOf(platformWallet), platformShare);
        assertEq(grideeToken.balanceOf(opsWallet), opsShare);
    }

    function test_DistributeRevenue_MultipleDistributions() public {
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);

        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode2, landlord1, 50 ether);

        uint256 expectedPending = ((TOTAL_AMOUNT + 50 ether) * LANDLORD_BPS) / 10_000;
        assertEq(revenueDistributor.pendingWithdrawals(landlord1), expectedPending);
    }

    function test_DistributeRevenue_DifferentLandlords() public {
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode2, landlord2, 50 ether);

        uint256 landlord1Share = (TOTAL_AMOUNT * LANDLORD_BPS) / 10_000;
        uint256 landlord2Share = (50 ether * LANDLORD_BPS) / 10_000;

        assertEq(revenueDistributor.pendingWithdrawals(landlord1), landlord1Share);
        assertEq(revenueDistributor.pendingWithdrawals(landlord2), landlord2Share);
    }

    function test_DistributeRevenue_RevertsIfLandlordIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueDistributor.ZeroAddress.selector, address(0))
        );
        revenueDistributor.distributeRevenue(propertyCode1, address(0), TOTAL_AMOUNT);
    }

    function test_DistributeRevenue_RevertsIfAmountIsZero() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(RevenueDistributor.ZeroAmount.selector));
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, 0);
    }

    function test_DistributeRevenue_RevertsIfNotOperator() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                OPERATOR_ROLE
            )
        );
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);
    }

    // ==================== WITHDRAW ====================

    function test_Withdraw() public {
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);

        uint256 expectedShare = (TOTAL_AMOUNT * LANDLORD_BPS) / 10_000;

        vm.prank(landlord1);
        revenueDistributor.withdraw();

        assertEq(revenueDistributor.pendingWithdrawals(landlord1), 0);
        assertEq(grideeToken.balanceOf(landlord1), expectedShare);
    }

    function test_Withdraw_MultipleWithdrawals() public {
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode2, landlord1, 50 ether);

        uint256 totalPending = ((TOTAL_AMOUNT + 50 ether) * LANDLORD_BPS) / 10_000;

        vm.prank(landlord1);
        revenueDistributor.withdraw();

        assertEq(revenueDistributor.pendingWithdrawals(landlord1), 0);
        assertEq(grideeToken.balanceOf(landlord1), totalPending);
    }

    function test_Withdraw_RevertsIfNoPendingWithdrawals() public {
        vm.prank(landlord1);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueDistributor.NoPendingWithdrawals.selector)
        );
        revenueDistributor.withdraw();
    }

    // ==================== UPDATE SHARES ====================

    function test_UpdateShares() public {
        vm.prank(admin);
        revenueDistributor.updateShares(2000, 1000);

        assertEq(revenueDistributor.landlordShareBPS(), 2000);
        assertEq(revenueDistributor.platformShareBPS(), 1000);
    }

    function test_UpdateShares_AffectsFutureDistributions() public {
        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode1, landlord1, TOTAL_AMOUNT);

        vm.prank(admin);
        revenueDistributor.updateShares(2000, 1000);

        vm.prank(operator);
        revenueDistributor.distributeRevenue(propertyCode2, landlord1, TOTAL_AMOUNT);

        uint256 firstShare = (TOTAL_AMOUNT * LANDLORD_BPS) / 10_000;
        uint256 secondShare = (TOTAL_AMOUNT * 2000) / 10_000;

        assertEq(revenueDistributor.pendingWithdrawals(landlord1), firstShare + secondShare);
    }

    function test_UpdateShares_RevertsIfSharesExceed10000() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueDistributor.InvalidShares.selector, 6000, 5000)
        );
        revenueDistributor.updateShares(6000, 5000);
    }

    function test_UpdateShares_RevertsIfExactly10000() public {
        vm.prank(admin);
        revenueDistributor.updateShares(9000, 1000);
        assertEq(revenueDistributor.landlordShareBPS(), 9000);
        assertEq(revenueDistributor.platformShareBPS(), 1000);
    }

    function test_UpdateShares_RevertsIfNotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                operator,
                DEFAULT_ADMIN_ROLE
            )
        );
        revenueDistributor.updateShares(2000, 1000);
    }

    // ==================== UPDATE WALLETS ====================

    function test_UpdateWallets() public {
        address newPlatform = makeAddr("newPlatform");
        address newOps = makeAddr("newOps");

        vm.prank(admin);
        revenueDistributor.updateWallets(newPlatform, newOps);

        assertEq(revenueDistributor.platformWallet(), newPlatform);
        assertEq(revenueDistributor.opsWallet(), newOps);
    }

    function test_UpdateWallets_RevertsIfPlatformIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueDistributor.ZeroAddress.selector, address(0))
        );
        revenueDistributor.updateWallets(address(0), opsWallet);
    }

    function test_UpdateWallets_RevertsIfOpsIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(RevenueDistributor.ZeroAddress.selector, address(0))
        );
        revenueDistributor.updateWallets(platformWallet, address(0));
    }

    function test_UpdateWallets_RevertsIfNotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                operator,
                DEFAULT_ADMIN_ROLE
            )
        );
        revenueDistributor.updateWallets(makeAddr("newPlatform"), makeAddr("newOps"));
    }

    // ==================== ROLE MANAGEMENT ====================

    function test_DeployerHasAdminAndOperatorRoles() public view {
        assertTrue(revenueDistributor.hasRole(revenueDistributor.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(revenueDistributor.hasRole(revenueDistributor.OPERATOR_ROLE(), deployer));
    }

    function test_GrideeTokenGrantedOperatorRoleToRevenueDistributor() public view {
        assertTrue(grideeToken.hasRole(OPERATOR_ROLE, address(revenueDistributor)));
    }
}
