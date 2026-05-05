// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {GrideeToken} from "../src/GrideeToken.sol";

contract GrideeTokenTest is Test {
    GrideeToken public grideeToken;
    address public deployer = makeAddr("deployer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        grideeToken = new GrideeToken(deployer);
    }

    function test_MintTokens() public {
        vm.prank(deployer);
        grideeToken.mint(alice, 1 ether);
        assertEq(grideeToken.balanceOf(alice), 1 ether);
    }

    function test_BurnTokens() public {
        vm.startPrank(deployer);
        grideeToken.mint(alice, 1 ether);
        grideeToken.burn(alice, 1 ether);
        assertEq(grideeToken.balanceOf(alice), 0);
        vm.stopPrank();
    }

    function test_RevertIfNotOperator() public {
        vm.prank(deployer);
        grideeToken.mint(alice, 1 ether);

        vm.prank(alice);
        vm.expectRevert();
        grideeToken.burn(alice, 1 ether);
    }

    function test_BalanceOf() public {
        vm.prank(deployer);
        grideeToken.mint(alice, 500 ether);
        assertEq(grideeToken.balanceOf(alice), 500 ether);
        assertEq(grideeToken.balanceOf(bob), 0);
    }

    function test_TotalSupply() public {
        vm.startPrank(deployer);
        grideeToken.mint(alice, 300 ether);
        grideeToken.mint(bob, 200 ether);
        assertEq(grideeToken.totalSupply(), 500 ether);
        vm.stopPrank();
    }

    function test_Transfer() public {
        vm.prank(deployer);
        grideeToken.mint(alice, 100 ether);

        vm.prank(alice);
        grideeToken.transfer(bob, 40 ether);

        assertEq(grideeToken.balanceOf(alice), 60 ether);
        assertEq(grideeToken.balanceOf(bob), 40 ether);
    }

    function test_TransferInsufficientBalance() public {
        vm.prank(deployer);
        grideeToken.mint(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert();
        grideeToken.transfer(bob, 20 ether);
    }

    function test_ApproveAndTransferFrom() public {
        vm.prank(deployer);
        grideeToken.mint(alice, 100 ether);

        vm.prank(alice);
        grideeToken.approve(bob, 50 ether);

        assertEq(grideeToken.allowance(alice, bob), 50 ether);

        vm.prank(bob);
        grideeToken.transferFrom(alice, bob, 30 ether);

        assertEq(grideeToken.balanceOf(bob), 30 ether);
        assertEq(grideeToken.allowance(alice, bob), 20 ether);
    }

    function test_PauseAndUnpause() public {
        vm.prank(deployer);
        grideeToken.pause();

        vm.prank(deployer);
        vm.expectRevert();
        grideeToken.mint(alice, 1 ether);

        vm.prank(deployer);
        grideeToken.unpause();

        vm.prank(deployer);
        grideeToken.mint(alice, 1 ether);

        assertEq(grideeToken.balanceOf(alice), 1 ether);
    }

    function test_PauseOnlyByAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        grideeToken.pause();
    }

    function test_NameAndSymbol() public {
        assertEq(grideeToken.name(), "Gridee Token");
        assertEq(grideeToken.symbol(), "GRD");
    }
}
