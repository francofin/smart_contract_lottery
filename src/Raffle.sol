// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

/**
 * @title Raffle Contract
 * @author Francois Jack
 * @notice This contract allows users to enter a raffle and a chainlink VRF which implements randomness picks a winner.
 * @dev Relies on Chainlink VRF for randomness
 */

import {PriceConverter} from "./PriceConverter.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console2} from "forge-std/console2.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__NotEnoughEthEntered();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);
    event RequestedRaffleWinner(uint256 indexed requestId);

    using PriceConverter for uint256;

    // Your subscription ID.
    // address public constant I_VRF_COORDINATOR = 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D;
    // VRF Coordinator V2 Testnet address, contract we interact with to
    //request random numbers or answers
    // bytes32 public constant KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; //This is the gas lane Chainlink VRF requires, max gas price for a request in wei.

    
    uint256 private immutable I_SUBSCRIPTION_ID; //id for funding request, set up in data.chainlink
    //@dev The duration of the raffle in seconds
    uint256 public immutable I_INTERVAL;
    //@dev The gas lane key hash value, which is the maximum gas price you are willing to pay for a request in wei
    bytes32 private immutable I_KEY_HASH;
    //@dev Entrance fee for a single raffle ticket
    uint256 private immutable I_ENTRANCE_FEE;

    AggregatorV3Interface private s_priceFeed;
    address private s_recentWinner;
    address payable[] private s_players;
    uint256 public s_totalPool;
    mapping(address player => uint256 amountEntered) private s_amountsByAddress;

    //says when the raffle starts
    uint256 private s_raffleStart;

    // Depends on the number of requested values that you want sent to the
    // fulfillRandomWords() function. Storing each word costs about 20,000 gas,
    // so 40,000 is a safe default for this example contract. Test and adjust
    // this limit based on the network that you select, the size of the request,
    // and the processing of the callback request in the fulfillRandomWords()
    // function.
    uint32 public constant CALLBACK_GAS_LIMIT = 500000; // when the node responds it calls fulfill random words

    // The default is 3, but you can set this higher., how many confirmations the nodes wait before responding.
    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    // For this example, retrieve 1 random value in one request.
    // Cannot exceed VRFCoordinatorV2_5.MAX_NUM_WORDS.
    uint32 public constant NUMWORDS = 1;

    enum RaffleState {
        OPEN,
        CALCULATING,
        CLOSED
    }

    RaffleState public s_raffleState;

    event RaffleEntered(address indexed player, uint256 amount);
    event WinnerPicked(address indexed winner, uint256 amountWon);
    event CurrentRaffleState(RaffleState currentState);

    //vrfcoordinator contract is the one we interact with to request the random numbers

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 iKeyHash,
        uint256 subscriptionId
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        I_ENTRANCE_FEE = entranceFee;
        I_INTERVAL = interval;
        I_KEY_HASH = iKeyHash;
        I_SUBSCRIPTION_ID = subscriptionId;
        s_raffleStart = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function _notEnoughEthToEnter() internal view {
        if (msg.value < I_ENTRANCE_FEE) revert Raffle__NotEnoughEthEntered();
    }

    function _enoughTimeHasPassed() internal view {
        if (block.timestamp - s_raffleStart < I_INTERVAL) revert Raffle__NotEnoughTimePassed();
    }

    modifier enoughEthToEnter() {
        _notEnoughEthToEnter();
        _;
    }

    modifier enoughTimePassed() {
        _enoughTimeHasPassed();
        _;
    }

    function enterRaffle() public payable enoughEthToEnter {
        // Logic to enter the raffle
        //only allow people to enter if winner is not being picked.
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }   
        uint256 numberOfTickets = msg.value / I_ENTRANCE_FEE;
        s_amountsByAddress[payable(msg.sender)] += numberOfTickets;
        s_players.push(payable(msg.sender));
        s_totalPool += msg.value;

        //events make migrations easier to track
        //makes front end indexing easier

        emit RaffleEntered(msg.sender, msg.value);
    }

//when should we pick a winner
/**
 * @dev This is the chainlink function the nodes call to see if the lottery is ready to have a winner picked SHould be true for upkeep needed to be true
 * 1. Time Interval has passed bteween raffle runs
 * 2. At least one player has entered the raffle
 * 3. The contract has ETH
 * 4. The raffle is in an "open" state
 * 5. Subscription has LINK.
 * @return upkeepNeeded 
 * @return 
 */

// giving a named param in the return makes it so we dont have to name it in the function body and call the return statement explicitly. 
    function checkUpkeep(bytes memory /* checkData */) public view returns(bool upkeepNeeded, bytes memory /* performData */) {
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool timePassed = ((block.timestamp - s_raffleStart) >= I_INTERVAL);
        bool hasPlayers = s_players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
        return (upkeepNeeded, "");
    }   

    function performUpkeep(bytes calldata /* checkData */) external {

        //This essentially picks the winner
        // Logic to pick a winner using Chainlink VRF
        //If enough time has passed we need to get a random number using chainlink's VRF
        //Chainlink VRF gives the random number in a second tx it sends.

        //To pick a random winner, make request to VRFV2PlusClient contract, 
        //pickwinner sends the request for the random word and then the contract will call fllfillrandomworkds and pick the winner

        //Put raffle in picking state
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }
        s_raffleState = RaffleState.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: I_KEY_HASH,
            subId: I_SUBSCRIPTION_ID,
            requestConfirmations: REQUEST_CONFIRMATIONS,
            callbackGasLimit: CALLBACK_GAS_LIMIT,
            numWords: NUMWORDS,
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request); //passed into fulfillrandom words
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal override {

        // lets say there are ten players and the randome number returned is 12. if we do 10 % 12 we get 2 back. Thus index 2 can be random winner. 
        //Randomwords is index 0, but we only request 1 word back. so would be 0
        address payable[] memory m_players = s_players;
        uint256 numPlayers = m_players.length;
        uint256 indexOfWinner = (randomWords[0] % numPlayers);
        address payable recentWinner = m_players[indexOfWinner];
        s_recentWinner = recentWinner;
        console2.log("The recent winner is:", recentWinner);
        console2.log("The prize amount is:", address(this).balance);
        console2.log("TotalPool:", s_totalPool);    

        emit WinnerPicked(recentWinner, address(this).balance);
        (bool sent, ) = recentWinner.call{value: address(this).balance}("");
        if (!sent) {
            revert Raffle__TransferFailed();
        }
        
        for (uint256 i = 0; i < numPlayers; i++) {
            address player = m_players[i];
            s_amountsByAddress[player] = 0;
        }
        s_players = new address payable[](0);
        s_totalPool = 0;
        s_raffleStart = block.timestamp;
        
        s_raffleState = RaffleState.CLOSED;
        emit CurrentRaffleState(s_raffleState);
    }

    //Default receive and fallback funding functions to enter the raffle

    receive() external payable {
        enterRaffle();
    }

    fallback() external payable {
        enterRaffle();
    }

    // Getter Functions

    function getEntranceFee() external view returns (uint256) {
        return I_ENTRANCE_FEE;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getNumberOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getPlayer(uint256 index) external view returns (address, uint256) {
        return (s_players[index], s_amountsByAddress[s_players[index]]);
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getRaffleStartTime() external view returns (uint256) {
        return s_raffleStart;
    }

    function getTotalFunds() external view returns (uint256) {
        return s_totalPool;
    }
}
