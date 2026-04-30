// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {PropertyRegistry} from "../src/PropertyRegistry.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract PropertyRegistryTest is Test {
    PropertyRegistry public propertyRegistry;
    address public deployer = makeAddr("deployer");
    address public operator = makeAddr("operator");
    address public admin = makeAddr("admin");
    address public landlord1 = makeAddr("landlord1");
    address public landlord2 = makeAddr("landlord2");
    address public randomUser = makeAddr("randomUser");
    bytes32 public constant PROPERTY_CODE1 = keccak256(abi.encodePacked("GRD-LAG-0045"));
    bytes32 public constant PROPERTY_CODE2 = keccak256(abi.encodePacked("GRD-LAG-0046"));
    bytes32 public constant PROPERTY_CODE3 = keccak256(abi.encodePacked("GRD-NYC-0001"));
    bytes32 public constant NONEXISTENT_CODE = keccak256(abi.encodePacked("NONEXISTENT"));
    bytes32 public constant NOPE_CODE = keccak256(abi.encodePacked("NOPE"));

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant OPERATOR_ROLE = 0x97667070c54ef182b0f5858b034beac1b6f3089aa2d3188bb1e8929f4fa9b929;

    function setUp() public {
        propertyRegistry = new PropertyRegistry(deployer, operator);
        vm.prank(deployer);
        propertyRegistry.grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function _getProperty(bytes32 code) internal view returns (PropertyRegistry.Property memory) {
        (uint8 flatCount, string memory location, bool isActive, uint40 createdAt) = propertyRegistry.properties(code);
        return PropertyRegistry.Property(flatCount, location, isActive, createdAt);
    }

    // ==================== REGISTER PROPERTY ====================

    function test_RegisterProperty() public {
        vm.prank(operator);
        vm.expectEmit(true, true, false, true);
        emit PropertyRegistry.PropertyRegistered(operator, landlord1, PROPERTY_CODE1, 10);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        assertEq(propertyRegistry.propertyToLandlord(PROPERTY_CODE1), landlord1);
        assertEq(propertyRegistry.landlordPropertyCount(landlord1), 1);

        PropertyRegistry.Property memory prop = _getProperty(PROPERTY_CODE1);
        assertEq(prop.flatCount, 10);
        assertEq(prop.location, "Ikoyi");
        assertTrue(prop.isActive);
        assertTrue(prop.createdAt > 0);
    }

    function test_RegisterProperty_MultiplePropertiesForSameLandlord() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE2, landlord1, 5, "Victoria Island");

        assertEq(propertyRegistry.landlordPropertyCount(landlord1), 2);

        bytes32[] memory codes = propertyRegistry.getPropertyCodesByLandlord(landlord1);
        assertEq(codes[0], PROPERTY_CODE1);
        assertEq(codes[1], PROPERTY_CODE2);
    }

    function test_RegisterProperty_RevertsIfCodeIsEmpty() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PropertyRegistry.InvalidParameter.selector, "code", PropertyRegistry.InvalidParameterMessage.EmptyString
            )
        );
        propertyRegistry.registerProperty(bytes32(0), landlord1, 10, "Ikoyi");
    }

    function test_RegisterProperty_RevertsIfLandlordIsZeroAddress() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.ZeroAddress.selector, address(0)));
        propertyRegistry.registerProperty(PROPERTY_CODE1, address(0), 10, "Ikoyi");
    }

    function test_RegisterProperty_RevertsIfFlatCountIsZero() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PropertyRegistry.InvalidParameter.selector,
                "flatCount",
                PropertyRegistry.InvalidParameterMessage.ZeroValue
            )
        );
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 0, "Ikoyi");
    }

    function test_RegisterProperty_RevertsIfLocationIsEmpty() public {
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PropertyRegistry.InvalidParameter.selector,
                "location",
                PropertyRegistry.InvalidParameterMessage.EmptyString
            )
        );
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "");
    }

    function test_RegisterProperty_RevertsIfCodeExists() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(PropertyRegistry.DuplicatePropertyCode.selector, operator, PROPERTY_CODE1)
        );
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord2, 5, "VI");
    }

    function test_RegisterProperty_RevertsIfNotOperator() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, OPERATOR_ROLE)
        );
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");
    }

    // ==================== UPDATE PROPERTY ====================

    function test_UpdateProperty_BothFields() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit PropertyRegistry.PropertyFlatCountUpdated(PROPERTY_CODE1, 10, 20);
        vm.expectEmit(false, false, false, true);
        emit PropertyRegistry.PropertyLocationUpdated(PROPERTY_CODE1, "Ikoyi", "Victoria Island");
        propertyRegistry.updateProperty(PROPERTY_CODE1, 20, "Victoria Island");

        PropertyRegistry.Property memory prop = _getProperty(PROPERTY_CODE1);
        assertEq(prop.flatCount, 20);
        assertEq(prop.location, "Victoria Island");
    }

    function test_UpdateProperty_FlatCountOnly() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit PropertyRegistry.PropertyFlatCountUpdated(PROPERTY_CODE1, 10, 15);
        propertyRegistry.updateProperty(PROPERTY_CODE1, 15, "");

        PropertyRegistry.Property memory prop = _getProperty(PROPERTY_CODE1);
        assertEq(prop.flatCount, 15);
        assertEq(prop.location, "Ikoyi");
    }

    function test_UpdateProperty_LocationOnly() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(operator);
        vm.expectEmit(false, false, false, true);
        emit PropertyRegistry.PropertyLocationUpdated(PROPERTY_CODE1, "Ikoyi", "Lekki");
        propertyRegistry.updateProperty(PROPERTY_CODE1, 0, "Lekki");

        PropertyRegistry.Property memory prop = _getProperty(PROPERTY_CODE1);
        assertEq(prop.flatCount, 10);
        assertEq(prop.location, "Lekki");
    }

    function test_UpdateProperty_RevertsIfPropertyNotFound() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.PropertyNotFound.selector, NONEXISTENT_CODE));
        propertyRegistry.updateProperty(NONEXISTENT_CODE, 10, "Ikoyi");
    }

    function test_UpdateProperty_RevertsIfPropertyInactive() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(admin);
        propertyRegistry.deactivateProperty(PROPERTY_CODE1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.PropertyInactive.selector, PROPERTY_CODE1));
        propertyRegistry.updateProperty(PROPERTY_CODE1, 15, "VI");
    }

    function test_UpdateProperty_RevertsIfNothingToUpdate() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PropertyRegistry.InvalidParameter.selector,
                "update",
                PropertyRegistry.InvalidParameterMessage.NothingToUpdate
            )
        );
        propertyRegistry.updateProperty(PROPERTY_CODE1, 0, "");
    }

    function test_UpdateProperty_RevertsIfNotOperator() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, randomUser, OPERATOR_ROLE)
        );
        propertyRegistry.updateProperty(PROPERTY_CODE1, 15, "VI");
    }

    // ==================== GET PROPERTY ====================

    function test_GetProperty_AsLandlord() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(landlord1);
        PropertyRegistry.Property memory prop = propertyRegistry.getProperty(PROPERTY_CODE1);
        assertEq(prop.flatCount, 10);
        assertEq(prop.location, "Ikoyi");
        assertTrue(prop.isActive);
    }

    function test_GetProperty_AsOperator() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(operator);
        PropertyRegistry.Property memory prop = propertyRegistry.getProperty(PROPERTY_CODE1);
        assertEq(prop.flatCount, 10);
        assertEq(prop.location, "Ikoyi");
    }

    function test_GetProperty_RevertsIfUnauthorized() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.UnauthorizedAccess.selector, randomUser));
        propertyRegistry.getProperty(PROPERTY_CODE1);
    }

    function test_GetProperty_RevertsIfNotFound() public {
        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.PropertyNotFound.selector, NOPE_CODE));
        propertyRegistry.getProperty(NOPE_CODE);
    }

    // ==================== DEACTIVATE PROPERTY ====================

    function test_DeactivateProperty() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit PropertyRegistry.PropertyDeactivated(admin, PROPERTY_CODE1, landlord1);
        propertyRegistry.deactivateProperty(PROPERTY_CODE1);

        PropertyRegistry.Property memory prop = _getProperty(PROPERTY_CODE1);
        assertFalse(prop.isActive);
    }

    function test_DeactivateProperty_RevertsIfNotFound() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(PropertyRegistry.PropertyNotFound.selector, NOPE_CODE));
        propertyRegistry.deactivateProperty(NOPE_CODE);
    }

    function test_DeactivateProperty_RevertsIfNotAdmin() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");

        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, operator, DEFAULT_ADMIN_ROLE
            )
        );
        propertyRegistry.deactivateProperty(PROPERTY_CODE1);
    }

    // ==================== ADMIN VIEW FUNCTIONS ====================

    function test_GetPropertiesByLandlord() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE2, landlord1, 5, "VI");
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE3, landlord2, 20, "Manhattan");

        PropertyRegistry.Property[] memory props = propertyRegistry.getPropertiesByLandlord(landlord1);
        assertEq(props.length, 2);
        assertEq(props[0].flatCount, 10);
        assertEq(props[0].location, "Ikoyi");
        assertEq(props[1].flatCount, 5);
        assertEq(props[1].location, "VI");

        PropertyRegistry.Property[] memory props2 = propertyRegistry.getPropertiesByLandlord(landlord2);
        assertEq(props2.length, 1);
        assertEq(props2[0].flatCount, 20);
        assertEq(props2[0].location, "Manhattan");
    }

    function test_GetPropertiesByLandlord_Empty() public view {
        PropertyRegistry.Property[] memory props = propertyRegistry.getPropertiesByLandlord(randomUser);
        assertEq(props.length, 0);
    }

    function test_GetPropertyCodesByLandlord() public {
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE1, landlord1, 10, "Ikoyi");
        vm.prank(operator);
        propertyRegistry.registerProperty(PROPERTY_CODE2, landlord1, 5, "VI");

        bytes32[] memory codes = propertyRegistry.getPropertyCodesByLandlord(landlord1);
        assertEq(codes.length, 2);
        assertEq(codes[0], PROPERTY_CODE1);
        assertEq(codes[1], PROPERTY_CODE2);
    }

    function test_GetPropertyCodesByLandlord_Empty() public view {
        bytes32[] memory codes = propertyRegistry.getPropertyCodesByLandlord(randomUser);
        assertEq(codes.length, 0);
    }

    // ==================== ROLE MANAGEMENT ====================

    function test_DeployerHasAdminAndOperatorRoles() public view {
        assertTrue(propertyRegistry.hasRole(propertyRegistry.DEFAULT_ADMIN_ROLE(), deployer));
        assertTrue(propertyRegistry.hasRole(propertyRegistry.OPERATOR_ROLE(), deployer));
    }

    function test_GrantOperatorRole() public {
        vm.prank(deployer);
        propertyRegistry.grantRole(OPERATOR_ROLE, landlord2);
        assertTrue(propertyRegistry.hasRole(OPERATOR_ROLE, landlord2));
    }

    function test_RevokeOperatorRole() public {
        vm.prank(deployer);
        propertyRegistry.revokeRole(OPERATOR_ROLE, operator);
        assertFalse(propertyRegistry.hasRole(OPERATOR_ROLE, operator));
    }
}
