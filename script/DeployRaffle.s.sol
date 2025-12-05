//SPDX-License-Identifier: MIT


pragma solidity ^0.8.2;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";  
import {CreateSubscription} from "./Interactions.s.sol";

contract DeployRaffle is Script{

    function deployContract() public returns(Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        //if local mocks are deployed, on sepolia, sepolia config are deployued
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        if (networkConfig.subscriptionId == 0) {
            console.log("Creating subscription on chainid:", block.chainid);
            // create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (networkConfig.subscriptionId, networkConfig.vrfCoordinator) = createSubscription.createSubscription(networkConfig.vrfCoordinator);
            console.log("Subscription created with id:", networkConfig.subscriptionId);
        }

        //Start the broadcast
        vm.startBroadcast();
        Raffle raffle = new Raffle(networkConfig.entranceFee, networkConfig.interval, networkConfig.vrfCoordinator, 
                                    networkConfig.keyHash, networkConfig.subscriptionId);
        vm.stopBroadcast();
        return (raffle, helperConfig);
    }
   

    function run() external {
    }

}