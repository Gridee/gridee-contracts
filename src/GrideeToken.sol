// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract GrideeToken is ERC20, AccessControl, Pausable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address deployer) ERC20("Gridee Token", "GRD") {
        _grantRole(DEFAULT_ADMIN_ROLE, deployer);
        _grantRole(OPERATOR_ROLE, deployer);
    }

    function mint(address to, uint256 amount) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) external onlyRole(OPERATOR_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
