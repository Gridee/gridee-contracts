// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract PropertyRegistry is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum InvalidParameterMessage {
        EmptyString,
        ZeroValue,
        NothingToUpdate
    }

    struct Property {
        uint8 flatCount;
        string location;
        bool isActive;
        uint40 createdAt;
    }

    mapping(bytes32 => Property) public properties;
    mapping(bytes32 => address) public propertyToLandlord;
    mapping(address => mapping(uint256 => bytes32)) private landlordToPropertyCodes;
    mapping(address => uint256) public landlordPropertyCount;

    event PropertyRegistered(
        address indexed operator,
        address indexed landlord,
        bytes32 code,
        uint256 flatCount
    );
    event PropertyDeactivated(address indexed admin, bytes32 code, address landlord);
    event PropertyFlatCountUpdated(bytes32 code, uint8 oldFlatCount, uint8 newFlatCount);
    event PropertyLocationUpdated(bytes32 code, string oldLocation, string newLocation);

    error DuplicatePropertyCode(address sender, bytes32 code);
    error InvalidParameter(string parameter, InvalidParameterMessage message);
    error PropertyNotFound(bytes32 code);
    error PropertyInactive(bytes32 code);
    error ZeroAddress(address value);

    constructor(address deployer, address initialOperator) {
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, initialOperator);
    }

    function registerProperty(
        bytes32 code,
        address landlordWallet,
        uint8 flatCount,
        string calldata location
    ) external onlyRole(OPERATOR_ROLE) {
        if (code == bytes32(0)) {
            revert InvalidParameter("code", InvalidParameterMessage.EmptyString);
        }
        if (landlordWallet == address(0)) {
            revert ZeroAddress(landlordWallet);
        }
        if (flatCount == 0) {
            revert InvalidParameter("flatCount", InvalidParameterMessage.ZeroValue);
        }
        if (bytes(location).length == 0) {
            revert InvalidParameter("location", InvalidParameterMessage.EmptyString);
        }
        if (propertyToLandlord[code] != address(0)) {
            revert DuplicatePropertyCode(msg.sender, code);
        }

        Property memory newProperty = Property({
            flatCount: flatCount,
            location: location,
            isActive: true,
            createdAt: uint40(block.timestamp)
        });

        properties[code] = newProperty;
        propertyToLandlord[code] = landlordWallet;

        uint256 index = landlordPropertyCount[landlordWallet];
        landlordToPropertyCodes[landlordWallet][index] = code;
        landlordPropertyCount[landlordWallet] = index + 1;

        emit PropertyRegistered(msg.sender, landlordWallet, code, flatCount);
    }

    function updateProperty(
        bytes32 code,
        uint8 newFlatCount,
        string calldata newLocation
    ) external onlyRole(OPERATOR_ROLE) {
        if (!propertyExists(code)) {
            revert PropertyNotFound(code);
        }

        Property storage property = properties[code];

        if (!property.isActive) {
            revert PropertyInactive(code);
        }

        bool flatCountEmpty = newFlatCount == 0;
        bool locationEmpty = bytes(newLocation).length == 0;

        if (flatCountEmpty && locationEmpty) {
            revert InvalidParameter("update", InvalidParameterMessage.NothingToUpdate);
        }

        if (!flatCountEmpty) {
            uint8 oldFlatCount = property.flatCount;
            property.flatCount = newFlatCount;
            emit PropertyFlatCountUpdated(code, oldFlatCount, newFlatCount);
        }

        if (!locationEmpty) {
            string memory oldLocation = property.location;
            property.location = newLocation;
            emit PropertyLocationUpdated(code, oldLocation, newLocation);
        }
    }

    function getProperty(bytes32 code) external view returns (Property memory) {
        if (!propertyExists(code)) {
            revert PropertyNotFound(code);
        }

        address landlord = propertyToLandlord[code];
        bool isLandlord = landlord == msg.sender;
        bool isOperator = hasRole(OPERATOR_ROLE, msg.sender);

        if (!isLandlord && !isOperator) {
            revert UnauthorizedAccess(msg.sender);
        }

        return properties[code];
    }

    function deactivateProperty(bytes32 code) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!propertyExists(code)) {
            revert PropertyNotFound(code);
        }

        properties[code].isActive = false;

        emit PropertyDeactivated(msg.sender, code, propertyToLandlord[code]);
    }

    function getPropertiesByLandlord(address landlordWallet) external view returns (Property[] memory) {
        uint256 count = landlordPropertyCount[landlordWallet];
        Property[] memory result = new Property[](count);

        for (uint256 i = 0; i < count; i++) {
            bytes32 code = landlordToPropertyCodes[landlordWallet][i];
            result[i] = properties[code];
        }

        return result;
    }

    function getPropertyCodesByLandlord(address landlordWallet) external view returns (bytes32[] memory) {
        uint256 count = landlordPropertyCount[landlordWallet];
        bytes32[] memory result = new bytes32[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = landlordToPropertyCodes[landlordWallet][i];
        }

        return result;
    }

    function propertyExists(bytes32 code) internal view returns (bool) {
        return propertyToLandlord[code] != address(0);
    }

    error UnauthorizedAccess(address sender);
}
