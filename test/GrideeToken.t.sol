// SPDX-License-Identifier: UNLICENSED
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
}
