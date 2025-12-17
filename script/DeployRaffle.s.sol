//SPDX-License-Identifier: MIT


pragma solidity ^0.8.2;

import {Script, console} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";  
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script, CodeConstants {

    function run() public returns(Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        //if local mocks are deployed, on sepolia, sepolia config are deployued
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        if (networkConfig.subscriptionId == 0) {
            console.log("Creating subscription on chainid:", block.chainid);
            // create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (networkConfig.subscriptionId, networkConfig.vrfCoordinator) = createSubscription.createSubscription(networkConfig.vrfCoordinator, networkConfig.account);
            console.log("Subscription created with id:", networkConfig.subscriptionId);

            //Fund Subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(networkConfig.subscriptionId, FUND_AMOUNT, networkConfig.vrfCoordinator, networkConfig.linkTokenAddress, networkConfig.account);
        }
        //Start the broadcast
        vm.startBroadcast(networkConfig.account);
        Raffle raffle = new Raffle(networkConfig.entranceFee, networkConfig.interval, networkConfig.vrfCoordinator, 
                                    networkConfig.keyHash, networkConfig.subscriptionId);
        vm.stopBroadcast();

        //add consumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(networkConfig.subscriptionId, networkConfig.vrfCoordinator, address(raffle), networkConfig.account);

        return (raffle, helperConfig);
    }

}