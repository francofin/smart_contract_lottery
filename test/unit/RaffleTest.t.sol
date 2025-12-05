// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract RaffleTest is Test {
    Raffle public raffle;


    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash;
    uint256 subscriptionId;
    
    uint256 constant ENTRANCE_FEE = 0.1 ether;
    address public USER = makeAddr("user");
    address public PLAYER = makeAddr("player");
    address public PLAYERTWO = makeAddr("player2");
    address public PLAYERTHREE = makeAddr("player3");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    HelperConfig public helperConfig;

    event RaffleEntered(address indexed player, uint256 amount);
    event WinnerPicked(address indexed winner, uint256 amountWon);


    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.deployContract();
        vm.deal(USER, STARTING_PLAYER_BALANCE);
        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
        vm.deal(PLAYERTWO, STARTING_PLAYER_BALANCE);
        vm.deal(PLAYERTHREE, STARTING_PLAYER_BALANCE);

        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();
        entranceFee = networkConfig.entranceFee;
        interval = networkConfig.interval;
        vrfCoordinator = networkConfig.vrfCoordinator;
        keyHash = networkConfig.keyHash;
        subscriptionId = networkConfig.subscriptionId;
    }

    function testRaffleInitialState() public view {
        Raffle.RaffleState initRaffleState = raffle.getRaffleState();
        console.log("Initial Raffle State:", uint256(initRaffleState));
        assertEq(uint256(initRaffleState), 0); 
    }

    function testEntranceFeeIsSetCorrectly() public view {
        uint256 fee = raffle.getEntranceFee();
        console.log("Entrance Fee:", fee);
        assertEq(fee, entranceFee);
    }

    function testStartTimeIsLessThanOrEqualToBlockTimestamp() public view {
        uint256 startTime = raffle.getRaffleStartTime();
        console.log("Raffle Start Time:", startTime);
        console.log("Interval:", interval);
        assertLe(startTime, block.timestamp);
    }

    function testRaffleRevertsWhenNotEnoughEthIsSent() public {
        vm.prank(USER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthEntered.selector);
        raffle.enterRaffle{value: 0.005 ether}();
    }

    function testPlayerIsAddedOnEnterRaffle() public {
        vm.prank(USER);
        raffle.enterRaffle{value: entranceFee*5}();
        (address playerAddress, uint256 amountEntered) = raffle.getPlayer(0);
        uint256 totalFunds = raffle.getTotalFunds();
        console.log("Total Funds in Raffle:", totalFunds);
        console.log("Player Address:", playerAddress);
        console.log("Amount Entered:", amountEntered);
        assertEq(playerAddress, USER);
    }

    function testEnteringRaffleEmitsEvent() public {
        vm.prank(USER);
        //the booleans correspond to indexed parameters in the event
        vm.expectEmit(true, false, false, false, address(raffle));
        emit Raffle.RaffleEntered(USER, entranceFee*2);
        raffle.enterRaffle{value: entranceFee*2}();
    }

    function testPlayersCannotEnterWhenRaffleIsCalculating() public {
        vm.prank(USER);
        raffle.enterRaffle{value: entranceFee*5}();

        vm.prank(PLAYERTHREE);
        raffle.enterRaffle{value: entranceFee*5}();

        //fast forward time, warp sets the block.timestamp to the new time
        vm.warp(block.timestamp + interval + 1);
        //roll, changes the block number 
        vm.roll(block.number + 1);

        //pretend to be chainlink keeper
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }
}
