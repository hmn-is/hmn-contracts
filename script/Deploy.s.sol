// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/HmnManager.sol";
import "../src/HmnManagerImplMainV1.sol";
import "../src/HmnMain.sol";
import "../src/interfaces/IWorldID.sol";

contract Deploy is Script {
    // Add constants for initialization
    uint256 constant DEVICE_TIMEOUT = 365 days;
    uint256 constant ORB_TIMEOUT = 30 days;
    uint256 constant MIN_RECOVERY_SAFETY_PERIOD = 7 days;
    uint256 constant MOVE_OUT_TIME = 24 hours;
    uint256 constant TRANSFER_PROTECTION_MODE = 5;
    uint256 constant REQUIRED_VERIFICATION_LEVEL_FOR_TRANSFER = 0; // Device verification
    uint256 constant UNTRUST_FEE = 101; // Block transfer
    uint256 constant ON_CHAIN_VERIFICATION_LEVEL = 1; // WorldID Group ID 1
    bool constant ALLOW_ACCOUNT_REUSE = false;

    function run() external returns (address, address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying from:", deployer);
        console.log("Deploying HMN manager and token");

        // Deploy implementation
        beginBroadcast();
        
        // Create initialization call
        bytes memory initializeCall = abi.encodeWithSignature(
            "initialize(address,address,uint256,string,string,uint256,uint256,uint256,uint256,bool,uint256,uint256)",
            vm.envAddress("ADMIN_ADDRESS"),
            IWorldID(vm.envAddress("WORLD_ID_ROUTER")),
            ON_CHAIN_VERIFICATION_LEVEL,
            vm.envString("NEXT_PUBLIC_APP_ID"),
            vm.envString("NEXT_PUBLIC_ACTION"),
            ORB_TIMEOUT,
            DEVICE_TIMEOUT,
            MIN_RECOVERY_SAFETY_PERIOD,
            MOVE_OUT_TIME,
            ALLOW_ACCOUNT_REUSE,
            TRANSFER_PROTECTION_MODE,
            REQUIRED_VERIFICATION_LEVEL_FOR_TRANSFER
        );

        HmnManagerImplMainV1 impl = new HmnManagerImplMainV1();

        // Deploy proxy with implementation and initialization
        HmnManager manager = new HmnManager(address(impl), initializeCall);
        console.log("Manager Proxy:", address(manager));
        // console.log("Manager Implementation:", manager.implementation2());

        // Deploy the HMN token
        HmnMain hmn = new HmnMain(
            IHmnManagerMain(address(manager)),
            IL1CustomGateway(address(0)),
            IL2GatewayRouter(address(0))
        );

        console.log("HMN Token:", address(hmn));
        HmnManagerImplMainV1(address(manager)).setHmnAddress(address(hmn));
        HmnManagerImplMainV1(address(manager)).setUntrustFee(101);

        vm.stopBroadcast();

        return (address(manager), address(hmn));
    }

    function beginBroadcast() internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
    }
}