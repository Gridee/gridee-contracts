// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract WalletFactory is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(bytes32 => address) public landlordWallets;
    mapping(bytes32 => address) public tenantWallets;
    mapping(bytes32 => bytes32) public tenantProperty;
    mapping(address => bool) private walletRegistered;

    event LandlordRegistered(address indexed operator, bytes32 phoneHash, address wallet);
    event TenantRegistered(address indexed operator, bytes32 phoneHash, address wallet, bytes32 propertyCode);

    error WalletAlreadyRegistered(address wallet);
    error LandlordAlreadyRegistered(bytes32 phoneHash);
    error TenantAlreadyRegistered(bytes32 phoneHash);
    error ZeroAddress(address value);
    error EmptyPropertyCode(bytes32 propertyCode);

    constructor(address deployer, address initialOperator) {
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, initialOperator);
    }

    function registerLandlord(bytes32 phoneHash, address wallet) external onlyRole(OPERATOR_ROLE) {
        if (wallet == address(0)) {
            revert ZeroAddress(wallet);
        }
        if (walletRegistered[wallet]) {
            revert WalletAlreadyRegistered(wallet);
        }
        if (landlordWallets[phoneHash] != address(0)) {
            revert LandlordAlreadyRegistered(phoneHash);
        }

        landlordWallets[phoneHash] = wallet;
        walletRegistered[wallet] = true;

        emit LandlordRegistered(msg.sender, phoneHash, wallet);
    }

    function registerTenant(
        bytes32 phoneHash,
        address wallet,
        bytes32 propertyCode
    ) external onlyRole(OPERATOR_ROLE) {
        if (wallet == address(0)) {
            revert ZeroAddress(wallet);
        }
        if (walletRegistered[wallet]) {
            revert WalletAlreadyRegistered(wallet);
        }
        if (tenantWallets[phoneHash] != address(0)) {
            revert TenantAlreadyRegistered(phoneHash);
        }
        if (propertyCode == bytes32(0)) {
            revert EmptyPropertyCode(propertyCode);
        }

        tenantWallets[phoneHash] = wallet;
        tenantProperty[phoneHash] = propertyCode;
        walletRegistered[wallet] = true;

        emit TenantRegistered(msg.sender, phoneHash, wallet, propertyCode);
    }

    function getLandlordWallet(bytes32 phoneHash) external view returns (address) {
        return landlordWallets[phoneHash];
    }

    function getTenantWallet(bytes32 phoneHash) external view returns (address) {
        return tenantWallets[phoneHash];
    }

    function getTenantProperty(bytes32 phoneHash) external view returns (bytes32) {
        return tenantProperty[phoneHash];
    }

    function isWalletRegistered(address wallet) external view returns (bool) {
        return walletRegistered[wallet];
    }
}
