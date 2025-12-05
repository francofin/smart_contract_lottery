//SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import {Script, console, console2} from "forge-std/Script.sol";
import {HelperConfig, CodeConstants} from "./HelperConfig.s.sol";
import {Raffle} from "../src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

contract CreateSubscription is Script {


    function createSubscription(address vrfCoordinator) public returns (uint256, address) {
        console2.log("Creating subscription on chainid:", block.chainid);
        vm.startBroadcast();
        uint256 subId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        console2.log("Subscription created with id:", subId);
        return (subId, vrfCoordinator);
    }

    function createSubscriptionUsingConfig() public returns (uint256, address){
        HelperConfig helperConfig = new HelperConfig();
        //if local mocks are deployed, on sepolia, sepolia config are deployued
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        (uint256 subId, ) = createSubscription(vrfCoordinator);
        return (subId, vrfCoordinator);
    }

    function run() public {
        createSubscriptionUsingConfig();
    } 

}


contract FundSubscription is Script, CodeConstants {

    uint256 constant FUND_AMOUNT = 3 ether;

    function fundSubscription(uint256 subId, uint256 amount, address vrfCoordinator, address linkToken) public {

        console2.log("Funding subscription on chainid:", block.chainid);
        console2.log("Funding subscription with id:", subId);
        
        if (block.chainid == LOCAL_CHAIN_ID) {
            // For local testing with mocks
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subId, amount);
            vm.stopBroadcast();
        } else {
            // For testnets/mainnet, use LINK token to fund subscription
            // Assuming LinkToken has a transferAndCall function
            // This is a placeholder; actual implementation may vary
            // LinkToken(linkToken).transferAndCall(vrfCoordinator, amount, abi.encode(subId));
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(vrfCoordinator, amount, abi.encode(subId));
            vm.stopBroadcast();
        }
        
        
        console2.log("Subscription funded with:", amount);
    }


    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        //if local mocks are deployed, on sepolia, sepolia config are deployued
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        address vrfCoordinator = networkConfig.vrfCoordinator;
        uint256 subId = networkConfig.subscriptionId;
        address linkToken = networkConfig.linkTokenAddress;

        console2.log("Funding subscription on chainid:", block.chainid);
        fundSubscription(subId, FUND_AMOUNT, vrfCoordinator, linkToken);
        console2.log("Subscription funded with:", FUND_AMOUNT);
    }



    function run() public {
        fundSubscriptionUsingConfig();
    }
}