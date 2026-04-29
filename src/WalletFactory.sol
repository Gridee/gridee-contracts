// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract WalletFactory is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(uint256 => address) public wallets;
    mapping(address => uint256) public walletToUserId;

    event WalletAssigned(address indexed operator, uint256 userId, address wallet);

    error WalletAlreadyAssigned(uint256 userId);
    error WalletReuseNotAllowed(address wallet);
    error ZeroAddress(address value);

    constructor(address deployer, address initialOperator) {
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, initialOperator);
    }

    function assignWallet(uint256 userId, address wallet) external onlyRole(OPERATOR_ROLE) {
        if (wallet == address(0)) {
            revert ZeroAddress(wallet);
        }
        if (wallets[userId] != address(0)) {
            revert WalletAlreadyAssigned(userId);
        }
        if (walletToUserId[wallet] != 0) {
            revert WalletReuseNotAllowed(wallet);
        }

        wallets[userId] = wallet;
        walletToUserId[wallet] = userId;

        emit WalletAssigned(msg.sender, userId, wallet);
    }

    function getWallet(uint256 userId) external view returns (address) {
        return wallets[userId];
    }

    function walletExists(uint256 userId) external view returns (bool) {
        return wallets[userId] != address(0);
    }
}
