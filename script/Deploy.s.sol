// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {GrideeToken} from "../src/GrideeToken.sol";
import {WalletFactory} from "../src/WalletFactory.sol";
import {PropertyRegistry} from "../src/PropertyRegistry.sol";
import {EnergyLedger} from "../src/EnergyLedger.sol";
import {RevenueDistributor} from "../src/RevenueDistributor.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address platformWallet = vm.envAddress("PLATFORM_WALLET");
        address opsWallet = vm.envAddress("OPS_WALLET");

        uint256 landlordShareBPS = vm.envUint("LANDLORD_SHARE_BPS");
        uint256 platformShareBPS = vm.envUint("PLATFORM_SHARE_BPS");

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying GrideeToken...");
        GrideeToken token = new GrideeToken(deployer);
        console.log("GrideeToken deployed:", address(token));

        console.log("Deploying WalletFactory...");
        WalletFactory walletFactory = new WalletFactory(deployer, operator);
        console.log("WalletFactory deployed:", address(walletFactory));

        console.log("Deploying PropertyRegistry...");
        PropertyRegistry propertyRegistry = new PropertyRegistry(deployer, operator);
        console.log("PropertyRegistry deployed:", address(propertyRegistry));

        console.log("Deploying EnergyLedger...");
        EnergyLedger energyLedger = new EnergyLedger(deployer, operator, address(token));
        console.log("EnergyLedger deployed:", address(energyLedger));

        console.log("Deploying RevenueDistributor...");
        RevenueDistributor revenueDistributor = new RevenueDistributor(
            deployer,
            operator,
            address(token),
            platformWallet,
            opsWallet,
            landlordShareBPS,
            platformShareBPS
        );
        console.log("RevenueDistributor deployed:", address(revenueDistributor));

        console.log("\nGranting OPERATOR_ROLE to EnergyLedger on GrideeToken...");
        token.grantRole(token.OPERATOR_ROLE(), address(energyLedger));

        console.log("Granting OPERATOR_ROLE to RevenueDistributor on GrideeToken...");
        token.grantRole(token.OPERATOR_ROLE(), address(revenueDistributor));

        vm.stopBroadcast();

        console.log("\n========== DEPLOYMENT COMPLETE ==========");
        console.log("GRIDEETOKEN:", address(token));
        console.log("WALLETFACTORY:", address(walletFactory));
        console.log("PROPERTYREGISTRY:", address(propertyRegistry));
        console.log("ENERGYLEDGER:", address(energyLedger));
        console.log("REVENUEDISTRIBUTOR:", address(revenueDistributor));
        console.log("==========================================");
    }
}
