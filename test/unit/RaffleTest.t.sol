// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../../test/mocks/LinkToken.sol";
import {CodeConstants} from "../../script/HelperConfig.s.sol";


contract RaffleTest is Test, CodeConstants {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 keyHash;
    uint256 subscriptionId;
    LinkToken link;
    uint256 totalPoolTests;
    
    uint256 constant ENTRANCE_FEE = 0.1 ether;
    address public USER = makeAddr("user");
    address public PLAYER = makeAddr("player");
    address public PLAYERTWO = makeAddr("player2");
    address public PLAYERTHREE = makeAddr("player3");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;
    uint256 public constant LINK_BALANCE = 100 ether;
    

    event RaffleEntered(address indexed player, uint256 amount);
    event WinnerPicked(address indexed winner, uint256 amountWon);


    function setUp() external {
        DeployRaffle deployRaffle = new DeployRaffle();
        (raffle, helperConfig) = deployRaffle.run();
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

        link = LinkToken(networkConfig.linkTokenAddress);

        // vm.startPrank(msg.sender);
        // if (block.chainid == LOCAL_CHAIN_ID) {
        //     link.mint(msg.sender, LINK_BALANCE);
        //     VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, LINK_BALANCE);
        // }
        // link.approve(vrfCoordinator, LINK_BALANCE);
        // vm.stopPrank();
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

    function testCheckUpkeepReturnsFalseIfNoPlayers() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);  
    }

    function testCheckUpkeepReturnsTrue() public {
        vm.prank(USER);
        raffle.enterRaffle{value: entranceFee}();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee*3}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        console.log("Block Timestamp:", block.timestamp);
        console.log("Raffle Start Time:", raffle.getRaffleStartTime());

        Raffle.RaffleState raffleState = raffle.getRaffleState();
        console.log("Raffle State:", uint256(raffleState));

        

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    //Perform upkeep tests

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(USER);
        raffle.enterRaffle{value: entranceFee}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");

    }

    function testPerformUpKeepRevertsIfCheckUpkeepIsFalse() public {

        uint256 currentBalance = raffle.getTotalFunds();
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        vm.expectRevert(abi.encodeWithSelector(
            Raffle.Raffle__UpKeepNotNeeded.selector,
            currentBalance,
            numPlayers,
            uint256(raffleState)
        ));
        raffle.performUpkeep("");
    }

    modifier raffleEntered() {
        vm.prank(USER);
        raffle.enterRaffle{value: entranceFee*5}();

        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered{

        //the booleans correspond to indexed parameters in the event
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // console.log("Number of logs:", entries);
    }

    //fulfillrandom words


    modifier skipFork() {
        if (block.chainid != LOCAL_CHAIN_ID) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsRaffleAndSendsMoney() public raffleEntered skipFork {
        totalPoolTests += entranceFee*5;
        uint256 startingBalance = USER.balance;
        console.log("Starting balance:", startingBalance);
        uint256 additionalEntrants = 3;
        for (uint256 i = 1; i <= additionalEntrants+1; i++) {
            address player = address(uint160(i)); //avoid collision with existing addresses
            hoax(player, STARTING_PLAYER_BALANCE);
            raffle.enterRaffle{value: entranceFee*i}();
            totalPoolTests += entranceFee*i;
        }

        uint256 currentTime = raffle.getRaffleStartTime();
        console.log("Raffle Real Total Pool:", raffle.getTotalFunds());
        console.log("Test Total Pool:", totalPoolTests);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestIdTopic = keccak256("RequestedRaffleWinner(uint256)");
        uint256 requestId;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == requestIdTopic) {
                requestId = uint256(entries[i].topics[1]);
                break;
            }
        }
        console.log("Request ID:", requestId);

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        address recentWinner = raffle.getRecentWinner();
        console.log("Recent Winner:", recentWinner);
        uint256 endingBalance = recentWinner.balance;
        console.log("Ending Balance of winner:", endingBalance);

        // assertEq(endingBalance, startingBalance + entranceFee);
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.CLOSED));
        assertEq(raffle.getNumberOfPlayers(), 0);
        assertEq(raffle.getTotalFunds(), 0);
    }
}
