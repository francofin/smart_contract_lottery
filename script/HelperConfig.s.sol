//SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import {Raffle} from "../src/Raffle.sol";
import {Script, console} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 4000e8;

    uint256 constant FUND_AMOUNT = 1000 ether;

    /*//////////////////////////////////////////////////////////////
                               CHAIN IDS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;
    uint256 public constant LOCAL_CHAIN_ID = 31337;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public constant ARBITRUM_ONE_CHAIN_ID = 42161;
    uint256 public constant ARBITRUM_SEPOLIA_CHAIN_ID = 421613;
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84531;
    uint256 public constant BASE_MAINNET_CHAIN_ID = 8453;  

    address public constant VRF_COORDINATOR_SEPOLIA = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 public constant KEY_HASH_SEPOLIA = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; // 500 gwei
    address public constant SEPOLIA_LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789;

    address public constant VRF_COORDINATOR_MAINNET = 0xD7f86b4b8Cae7D942340FF628F82735b7a20893a;
    bytes32 public constant KEY_HASH_MAINNET =0x3fd2fec10d06ee8f65e7f2e95f5c56511359ece3f33960ad8a866ae24a8ff10b; // 450 gwei
    address public constant MAINNET_LINK_TOKEN = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    address public constant VRF_COORDINATOR_BASE_SEPOLIA = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    bytes32 public constant KEY_HASH_BASE_SEPOLIA = 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71; // 100 gwei 
    address public constant BASE_SEPOLIA_LINK_TOKEN = 0xE4aB69C077896252FAFBD49EFD26B5D171A32410;

    uint256 public constant ENTRACE_FEE = 0.01 ether;
    uint256 public constant INTERVAL = 30; //30 seconds to test
    // uint256 public constant INTERVAL = 300; //5 minutes

    //VRF Mock Values
    uint96 public constant MOCK_BASE_FEE = 0.25 ether; // 0.25 LINK
    uint96 public constant MOCK_GAS_PRICE_LINK = 1e9; // 0.000000001 LINK per gas
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 7e15; // 0.007 ETH per LINK

}

contract HelperConfig is Script, CodeConstants{
    error HelperConfig__InvalidChainId(uint256 chainId);

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        address linkTokenAddress;
        address account;
    }

     NetworkConfig public localNetworkConfig;
     mapping(uint256 chainId => NetworkConfig config) public networkConfigs;


    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getSepoliaEthConfig();
        networkConfigs[MAINNET_CHAIN_ID] = getMainnetEthConfig();
        networkConfigs[BASE_SEPOLIA_CHAIN_ID] = getBaseSepoliaEthConfig();
        }


     function getConfigByChainId(uint256 chainId) public returns(NetworkConfig memory){
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == LOCAL_CHAIN_ID){
            //Deploy Mocks, Return Mock Address
            return getOrCreateAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId(chainId);
        }
     }

     function getConfig() public returns(NetworkConfig memory){
        return getConfigByChainId(block.chainid);
     }

    //script can automatically create sub scription id after deployment
     function getSepoliaEthConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entranceFee: ENTRACE_FEE,
            interval: INTERVAL,
            vrfCoordinator: VRF_COORDINATOR_SEPOLIA,
            keyHash: KEY_HASH_SEPOLIA,
            subscriptionId: 36519466797660437088822149621106901780034305463039990526112483595192675524722, // to be filled in after deployment
            linkTokenAddress: SEPOLIA_LINK_TOKEN,
            account: 0xFbE6240fA92DA1a8d969fd4518e56Bfe475594e0
        }); 
     }

     function getBaseSepoliaEthConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entranceFee: ENTRACE_FEE,
            interval: INTERVAL,
            vrfCoordinator: VRF_COORDINATOR_BASE_SEPOLIA,
            keyHash: KEY_HASH_BASE_SEPOLIA,
            subscriptionId: 0, // to be filled in after deployment
            linkTokenAddress: BASE_SEPOLIA_LINK_TOKEN,
            account: 0xFbE6240fA92DA1a8d969fd4518e56Bfe475594e0
        }); 
     }

     function getMainnetEthConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entranceFee: ENTRACE_FEE,
            interval: INTERVAL,
            vrfCoordinator: VRF_COORDINATOR_MAINNET,
            keyHash: KEY_HASH_MAINNET,
            subscriptionId: 0, // to be filled in after deployment
            linkTokenAddress: MAINNET_LINK_TOKEN,
            account: 0xFbE6240fA92DA1a8d969fd4518e56Bfe475594e0 
        }); 
     }


     function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory){
        if(localNetworkConfig.vrfCoordinator != address(0)){
            return localNetworkConfig;
        }
        //Deploy Mocks, Return Mock Address
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock vrfCoordinatorV2_5Mock = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE, // base fee, amount of Link to pay
            MOCK_GAS_PRICE_LINK, // gas price link
            MOCK_WEI_PER_UNIT_LINK // eth per link
        );
        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        localNetworkConfig =  NetworkConfig({
            entranceFee: ENTRACE_FEE,
            interval: INTERVAL,
            vrfCoordinator: address(vrfCoordinatorV2_5Mock),
            keyHash: KEY_HASH_SEPOLIA,
            subscriptionId: 0, // to be filled in after deployment
            linkTokenAddress: address(linkToken), // Link token not needed for mocks,
            account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 //Base/.sol default address
        });

        return localNetworkConfig;


    }

}