// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGrideeToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}

contract EnergyLedger is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    IGrideeToken public token;
    mapping(address => bool) public isCutOff;

    event TokensMinted(address indexed tenant, uint256 amount);
    event TokensDeducted(address indexed tenant, uint256 amount);
    event CutOffUpdated(address indexed admin, address tenant, bool status);

    error ZeroAddress(address value);
    error ZeroAmount();
    error InsufficientBalance(address tenant, uint256 balance, uint256 requested);

    constructor(address deployer, address initialOperator, address tokenAddress) {
        if (tokenAddress == address(0)) {
            revert ZeroAddress(tokenAddress);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, initialOperator);

        token = IGrideeToken(tokenAddress);
    }

    function mintTokens(address tenantWallet, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (tenantWallet == address(0)) {
            revert ZeroAddress(tenantWallet);
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        token.mint(tenantWallet, amount);

        emit TokensMinted(tenantWallet, amount);
    }

    function deductTokens(address tenantWallet, uint256 amount) external onlyRole(OPERATOR_ROLE) {
        if (tenantWallet == address(0)) {
            revert ZeroAddress(tenantWallet);
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 balance = token.balanceOf(tenantWallet);
        if (amount > balance) {
            revert InsufficientBalance(tenantWallet, balance, amount);
        }

        token.burn(tenantWallet, amount);

        emit TokensDeducted(tenantWallet, amount);
    }

    function getBalance(address tenantWallet) external view returns (uint256) {
        return token.balanceOf(tenantWallet);
    }

    function setCutOff(address tenantWallet, bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tenantWallet == address(0)) {
            revert ZeroAddress(tenantWallet);
        }

        isCutOff[tenantWallet] = status;

        emit CutOffUpdated(msg.sender, tenantWallet, status);
    }
}
