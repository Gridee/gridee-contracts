// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {EnergyLedger, IGrideeToken} from "../src/EnergyLedger.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract EnergyLedgerTest is Test {
    GrideeToken public grideeToken;
    EnergyLedger public energyLedger;
    address public deployer = makeAddr("deployer");
    address public operator = makeAddr("operator");
    address public admin = makeAddr("admin");
    address public randomUser = makeAddr("randomUser");
    address public tenant1 = makeAddr("tenant1");
    address public tenant2 = makeAddr("tenant2");
    uint256 public constant MINT_AMOUNT = 100 ether;
    uint256 public constant DEDUCT_AMOUNT = 30 ether;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant OPERATOR_ROLE = 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929;

    function setUp() public {
        grideeToken = new GrideeToken(deployer);
        energyLedger = new EnergyLedger(deployer, operator, address(grideeToken));

        vm.prank(deployer);
        grideeToken.grantRole(OPERATOR_ROLE, address(energyLedger));

        vm.prank(deployer);
        energyLedger.grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ==================== MINT TOKENS ====================

    function test_MintTokens() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);

        assertEq(grideeToken.balanceOf(tenant1), MINT_AMOUNT);
        assertEq(energyLedger.getBalance(tenant1), MINT_AMOUNT);
    }

    function test_MintTokens_MultipleTenants() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);
        vm.prank(operator);
        energyLedger.mintTokens(tenant2, 50 ether);

        assertEq(grideeToken.balanceOf(tenant1), MINT_AMOUNT);
        assertEq(grideeToken.balanceOf(tenant2), 50 ether);
    }

    function test_MintTokens_RevertsIfTenantIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(EnergyLedger.ZeroAddress.selector, address(0))
        );
        energyLedger.mintTokens(address(0), MINT_AMOUNT);
    }

    function test_MintTokens_RevertsIfAmountIsZero() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.ZeroAmount.selector));
        energyLedger.mintTokens(tenant1, 0);
    }

    function test_MintTokens_RevertsIfNotOperator() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                OPERATOR_ROLE
            )
        );
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);
    }

    // ==================== DEDUCT TOKENS ====================

    function test_DeductTokens() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);

        vm.prank(operator);
        energyLedger.deductTokens(tenant1, DEDUCT_AMOUNT);

        assertEq(grideeToken.balanceOf(tenant1), MINT_AMOUNT - DEDUCT_AMOUNT);
        assertEq(energyLedger.getBalance(tenant1), MINT_AMOUNT - DEDUCT_AMOUNT);
    }

    function test_DeductTokens_FullBalance() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);

        vm.prank(operator);
        energyLedger.deductTokens(tenant1, MINT_AMOUNT);

        assertEq(grideeToken.balanceOf(tenant1), 0);
    }

    function test_DeductTokens_RevertsIfTenantIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(EnergyLedger.ZeroAddress.selector, address(0))
        );
        energyLedger.deductTokens(address(0), DEDUCT_AMOUNT);
    }

    function test_DeductTokens_RevertsIfAmountIsZero() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(EnergyLedger.ZeroAmount.selector));
        energyLedger.deductTokens(tenant1, 0);
    }

    function test_DeductTokens_RevertsIfInsufficientBalance() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyLedger.InsufficientBalance.selector,
                tenant1,
                MINT_AMOUNT,
                MINT_AMOUNT + 1
            )
        );
        energyLedger.deductTokens(tenant1, MINT_AMOUNT + 1);
    }

    function test_DeductTokens_RevertsIfNoBalance() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnergyLedger.InsufficientBalance.selector,
                tenant1,
                0,
                DEDUCT_AMOUNT
            )
        );
        energyLedger.deductTokens(tenant1, DEDUCT_AMOUNT);
    }

    function test_DeductTokens_RevertsIfNotOperator() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                randomUser,
                OPERATOR_ROLE
            )
        );
        energyLedger.deductTokens(tenant1, DEDUCT_AMOUNT);
    }

    // ==================== GET BALANCE ====================

    function test_GetBalance_ReturnsZeroForUnmintedTenant() public view {
        assertEq(energyLedger.getBalance(tenant1), 0);
    }

    function test_GetBalance_ReturnsCorrectBalanceAfterMint() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);
        assertEq(energyLedger.getBalance(tenant1), MINT_AMOUNT);
    }

    function test_GetBalance_ReturnsCorrectBalanceAfterDeduct() public {
        vm.prank(operator);
        energyLedger.mintTokens(tenant1, MINT_AMOUNT);
        vm.prank(operator);
        energyLedger.deductTokens(tenant1, DEDUCT_AMOUNT);
        assertEq(energyLedger.getBalance(tenant1), MINT_AMOUNT - DEDUCT_AMOUNT);
    }

    // ==================== CUT-OFF ====================

    function test_SetCutOff_Enable() public {
        vm.prank(admin);
        energyLedger.setCutOff(tenant1, true);

        assertTrue(energyLedger.isCutOff(tenant1));
    }

    function test_SetCutOff_Disable() public {
        vm.prank(admin);
        energyLedger.setCutOff(tenant1, true);

        vm.prank(admin);
        energyLedger.setCutOff(tenant1, false);

        assertFalse(energyLedger.isCutOff(tenant1));
    }

    function test_SetCutOff_RevertsIfTenantIsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(EnergyLedger.ZeroAddress.selector, address(0))
        );
        energyLedger.setCutOff(address(0), true);
    }

    function test_SetCutOff_RevertsIfNotAdmin() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                operator,
                DEFAULT_ADMIN_ROLE
            )
        );
        energyLedger.setCutOff(tenant1, true);
    }

    function test_IsCutOff_DefaultsFalse() public view {
        assertFalse(energyLedger.isCutOff(tenant1));
    }

    // ==================== ROLE MANAGEMENT ====================

    function test_DeployerHasAdminAndOperatorRoles() public view {
        assertTrue(energyLedger.hasRole(energyLedger.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(energyLedger.hasRole(energyLedger.OPERATOR_ROLE(), deployer));
    }

    function test_GrideeTokenGrantedOperatorRoleToEnergyLedger() public view {
        assertTrue(grideeToken.hasRole(OPERATOR_ROLE, address(energyLedger)));
    }
}
