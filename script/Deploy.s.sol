// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/HmnManager.sol";
import "../src/HmnManagerImplMainLogicV1.sol";
import "../src/HmnMain.sol";
import "../src/interfaces/IWorldID.sol";
import "../src/HmnSafe.sol";
import "../src/HmnSafeImplV1.sol";

contract Deploy is Script {
    // Add constants for initialization
    uint256 constant DEVICE_TIMEOUT = 365 days;
    uint256 constant ORB_TIMEOUT = 30 days;
    uint256 constant MIN_RECOVERY_SAFETY_PERIOD = 7 days;
    uint256 constant MOVE_OUT_TIME = 24 hours;
    uint256 constant TRANSFER_PROTECTION_MODE = 5;
    uint256 constant REQUIRED_VERIFICATION_LEVEL_FOR_TRANSFER = 0; // Device verification
    uint256 constant MAX_FEE_BPS = 101; // Block transfer
    uint256 constant ON_CHAIN_VERIFICATION_LEVEL = 1; // WorldID Group ID 1
    bool constant ALLOW_ACCOUNT_REUSE = false;
    // Delays are intially low to allow for flexibility during initial testing period,
    // but will be changed to 30 days after the contracts are deemed stable.
    uint256 constant MANAGER_UPGRADE_DELAY = 7 days;
    uint256 constant REWARD_SAFE_DELAY = 7 days;
    uint256 constant COMMUNITY_SAFE_DELAY = 7 days;
    uint256 constant TEAM_SAFE_DELAY = 7 days;
    uint256 constant LIQUIDITY_SAFE_DELAY = 1 days;

    function run() external returns (address, address, address, address, address) {
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console.log("Deploying from:", deployer);
        console.log("Deploying HMN manager and token");
        console.log("NEXT_PUBLIC_WORLD_APP_ID", vm.envString("NEXT_PUBLIC_WORLD_APP_ID"));
        console.log("NEXT_PUBLIC_WORLD_ACTION_HMN", vm.envString("NEXT_PUBLIC_WORLD_ACTION_HMN"));
        console.log("WORLD_ID_ROUTER", vm.envString("WORLD_ID_ROUTER"));
        

        // Deploy implementation
        beginBroadcast();

        // These are kept outside of initilize to meet max contract size requirements
        if (0 != ORB_TIMEOUT && ORB_TIMEOUT < 10 minutes) revert("InvalidOrbTimeout");
        if (0 != DEVICE_TIMEOUT && DEVICE_TIMEOUT < 10 minutes) revert("InvalidDeviceTimeout");
        
        // Create initialization call for manager
        bytes memory initializeCall = abi.encodeWithSignature(
            "initialize(address,address,uint256,string,string,uint256,uint256,uint256,uint256,bool,uint256,uint256,uint256)",
            vm.envAddress("ADMIN_ADDRESS"),
            IWorldID(vm.envAddress("WORLD_ID_ROUTER")),
            ON_CHAIN_VERIFICATION_LEVEL,
            vm.envString("NEXT_PUBLIC_WORLD_APP_ID"),
            vm.envString("NEXT_PUBLIC_WORLD_ACTION_HMN"),
            ORB_TIMEOUT,
            DEVICE_TIMEOUT,
            MIN_RECOVERY_SAFETY_PERIOD,
            MOVE_OUT_TIME,
            ALLOW_ACCOUNT_REUSE,
            TRANSFER_PROTECTION_MODE,
            REQUIRED_VERIFICATION_LEVEL_FOR_TRANSFER,
            MANAGER_UPGRADE_DELAY
        );

        HmnManagerImplMainLogicV1 impl = new HmnManagerImplMainLogicV1();

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
        HmnManagerImplMainLogicV1(address(manager)).setHmnAddress(address(hmn));
        HmnManagerImplMainLogicV1(address(manager)).setUnverifiedFee(101);

        // Deploy HmnSafe implementations
        HmnSafeImplV1 safeImpl = new HmnSafeImplV1();
        
        // Create initialization calls for safes with different delays
        bytes memory rewardSafeInitCall = abi.encodeWithSignature(
            "initialize(uint256)",
            REWARD_SAFE_DELAY
        );

       bytes memory communitySafeInitCall = abi.encodeWithSignature(
            "initialize(uint256)",
            COMMUNITY_SAFE_DELAY
        );

        bytes memory teamSafeInitCall = abi.encodeWithSignature(
            "initialize(uint256)",
            TEAM_SAFE_DELAY
        );

        bytes memory liquiditySafeInitCall = abi.encodeWithSignature(
            "initialize(uint256)",
            LIQUIDITY_SAFE_DELAY
        );

        // Deploy reward safe
        HmnSafe rewardSafe = new HmnSafe(address(safeImpl), rewardSafeInitCall);
        console.log("Reward Safe Proxy:", address(rewardSafe));

        // Deploy community safe
        HmnSafe communitySafe = new HmnSafe(address(safeImpl), communitySafeInitCall);
        console.log("Community Safe Proxy:", address(communitySafe));

        // Deploy team safe
        HmnSafe teamSafe = new HmnSafe(address(safeImpl), teamSafeInitCall);
        console.log("Team Safe Proxy:", address(teamSafe));

        // Deploy liquidity safe
        HmnSafe liquiditySafe = new HmnSafe(address(safeImpl), liquiditySafeInitCall);
        console.log("Liquidity Safe Proxy:", address(liquiditySafe));

        // Whitelist the safe contracts
        HmnManagerImplMainLogicV1(address(manager)).adjustContractWhitelist(address(rewardSafe), deployer);
        console.log("Whitelisted Reward Safe");
        HmnManagerImplMainLogicV1(address(manager)).adjustContractWhitelist(address(communitySafe), deployer);
        console.log("Whitelisted Community Safe");
        HmnManagerImplMainLogicV1(address(manager)).adjustContractWhitelist(address(teamSafe), deployer);
        console.log("Whitelisted Team Safe");
        HmnManagerImplMainLogicV1(address(manager)).adjustContractWhitelist(address(liquiditySafe), deployer);
        console.log("Whitelisted Liquidity Safe");

        // Get deployer's token balance
        uint256 deployerBalance = hmn.balanceOf(deployer);
        console.log("Deployer balance:", deployerBalance);
        
        // Transfer tokens to safes
        uint256 rewardAmount = (deployerBalance * 50) / 100;
        hmn.transfer(address(rewardSafe), rewardAmount);
        console.log("Transferred to Reward Safe:", rewardAmount);

        uint256 communityAmount = (deployerBalance * 10) / 100;
        hmn.transfer(address(communitySafe), communityAmount);
        console.log("Transferred to Community Safe:", communityAmount);

        uint256 teamAmount = (deployerBalance * 10) / 100;
        hmn.transfer(address(teamSafe), teamAmount);
        console.log("Transferred to Team Safe:", teamAmount);

        // Note: Liquidity safe will hold liquidity tokens after manual pool creation
        console.log("Initial supply held by deployer:", hmn.balanceOf(deployer));

        vm.stopBroadcast();

        return (
            address(manager), 
            address(hmn), 
            address(rewardSafe), 
            address(communitySafe), 
            address(teamSafe)
        );
    }

    function beginBroadcast() internal {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
    }
}