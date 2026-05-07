// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {EnergyLedger} from "../src/EnergyLedger.sol";
import {MockUSDC} from "./MockUSDC.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract EnergyLedgerTest is Test {
    GrideeToken public grideeToken;
    EnergyLedger public ledger;
    MockUSDC public usdc;
    address public deployer;
    address public operator;
    address public admin;
    address public randomUser;
    address public tenant1;
    address public tenant2;
    address public landlord;
    address public platformWallet;
    address public opsWallet;

    uint256 public constant PRICE_PER_GRD = 10_000;
    uint256 public constant LANDLORD_SHARE_BPS = 1800;
    uint256 public constant PLATFORM_SHARE_BPS = 900;
    uint256 public constant DEDUCT_AMOUNT = 30 ether;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant OPERATOR_ROLE = 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929;

    function setUp() public {
        deployer = address(1);
        operator = address(2);
        admin = address(3);
        randomUser = address(4);
        tenant1 = address(5);
        tenant2 = address(6);
        landlord = address(7);
        platformWallet = address(8);
        opsWallet = address(9);

        usdc = new MockUSDC();
        vm.prank(deployer);
        grideeToken = new GrideeToken(
            deployer, address(usdc), platformWallet, opsWallet, PRICE_PER_GRD, LANDLORD_SHARE_BPS, PLATFORM_SHARE_BPS
        );
        vm.prank(deployer);
        ledger = new EnergyLedger(deployer, operator, address(grideeToken));

        vm.startPrank(deployer);
        grideeToken.grantRole(grideeToken.BURNER_ROLE(), address(ledger));
        grideeToken.grantRole(grideeToken.DEFAULT_ADMIN_ROLE(), admin);
        ledger.grantRole(DEFAULT_ADMIN_ROLE, admin);
        vm.stopPrank();
    }

    function _purchaseTokens(address tenant, uint256 usdcAmount) internal {
        usdc.mint(tenant, usdcAmount);
        vm.prank(tenant);
        usdc.approve(address(grideeToken), usdcAmount);
        vm.prank(tenant);
        grideeToken.depositUSDC(usdcAmount);
        vm.prank(tenant);
        grideeToken.purchaseTokens(usdcAmount, landlord);
    }

    function test_DeductTokens() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        vm.prank(operator);
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);

        uint256 initialGRD = (100 * 1e6 * 1e18) / PRICE_PER_GRD;
        assertEq(grideeToken.balanceOf(tenant1), initialGRD - DEDUCT_AMOUNT);
        assertEq(ledger.getBalance(tenant1), initialGRD - DEDUCT_AMOUNT);
    }

    function test_DeductTokens_FullBalance() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        uint256 balance = grideeToken.balanceOf(tenant1);

        vm.prank(operator);
        ledger.deductTokens(tenant1, balance);

        assertEq(grideeToken.balanceOf(tenant1), 0);
    }

    function test_DeductTokens_RevertsIfTenantIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.ZeroAddress.selector, address(0)));
        ledger.deductTokens(address(0), DEDUCT_AMOUNT);
    }

    function test_DeductTokens_RevertsIfAmountIsZero() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.ZeroAmount.selector));
        ledger.deductTokens(tenant1, 0);
    }

    function test_DeductTokens_RevertsIfInsufficientBalance() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        uint256 balance = grideeToken.balanceOf(tenant1);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(EnergyLedger.InsufficientBalance.selector, tenant1, balance, balance + 1)
        );
        ledger.deductTokens(tenant1, balance + 1);
    }

    function test_DeductTokens_RevertsIfNoBalance() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.InsufficientBalance.selector, tenant1, 0, DEDUCT_AMOUNT));
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);
    }

    function test_DeductTokens_RevertsIfNotOperator() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, OPERATOR_ROLE)
        );
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);
    }

    function test_DeductTokens_RevertsIfCutOff() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        vm.prank(admin);
        ledger.setCutOff(tenant1, true);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.TenantCutOff.selector, tenant1));
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);
    }

    function test_GetBalance_ReturnsZeroForNewTenant() public view {
        assertEq(ledger.getBalance(tenant1), 0);
    }

    function test_GetBalance_ReturnsCorrectBalanceAfterPurchase() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        uint256 expectedGRD = (100 * 1e6 * 1e18) / PRICE_PER_GRD;
        assertEq(ledger.getBalance(tenant1), expectedGRD);
    }

    function test_GetBalance_ReturnsCorrectBalanceAfterDeduct() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        uint256 initialGRD = grideeToken.balanceOf(tenant1);

        vm.prank(operator);
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);

        assertEq(ledger.getBalance(tenant1), initialGRD - DEDUCT_AMOUNT);
    }

    function test_SetCutOff_Enable() public {
        vm.prank(admin);
        ledger.setCutOff(tenant1, true);

        assertTrue(ledger.isCutOff(tenant1));
    }

    function test_SetCutOff_Disable() public {
        vm.prank(admin);
        ledger.setCutOff(tenant1, true);

        vm.prank(admin);
        ledger.setCutOff(tenant1, false);

        assertFalse(ledger.isCutOff(tenant1));
    }

    function test_SetCutOff_RevertsIfTenantIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.ZeroAddress.selector, address(0)));
        ledger.setCutOff(address(0), true);
    }

    function test_SetCutOff_RevertsIfNotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, DEFAULT_ADMIN_ROLE
            )
        );
        ledger.setCutOff(tenant1, true);
    }

    function test_IsCutOff_DefaultsFalse() public view {
        assertFalse(ledger.isCutOff(tenant1));
    }

    function test_PauseStopsDeductions() public {
        _purchaseTokens(tenant1, 100 * 1e6);

        vm.prank(admin);
        ledger.pause();

        vm.prank(operator);
        vm.expectRevert();
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);

        vm.prank(admin);
        ledger.unpause();

        vm.prank(operator);
        ledger.deductTokens(tenant1, DEDUCT_AMOUNT);
    }

    function test_PauseOnlyByAdmin() public {
        vm.prank(operator);
        vm.expectRevert();
        ledger.pause();
    }

    function test_DeployerHasAdminAndOperatorRoles() public view {
        assertTrue(ledger.hasRole(ledger.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(ledger.hasRole(ledger.OPERATOR_ROLE(), deployer));
    }

    function test_EnergyLedgerHasBurnerRoleOnToken() public view {
        assertTrue(grideeToken.hasRole(grideeToken.BURNER_ROLE(), address(ledger)));
    }
}
