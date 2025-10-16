// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title WeightedGovernance
 * @notice A minimal weighted voting governance contract (no imports, no constructor, no input fields).
 * @dev - No constructor: call initialize() once after deployment to set owner.
 *      - Members acquire voting weight by sending ETH to buyVotingPower() (1 wei = 1 weight).
 *      - Only one active proposal at a time (simplifies parameter-free functions).
 *      - Voting duration is fixed (ROUND_DURATION). Votes are weighted by the voter's weight at vote time.
 *      - Each address may vote once per proposal. Votes are immutable for that proposal.
 *      - Quorum is evaluated against totalVotingWeight at execution time.
 *
 * WARNING: This is an educational/demo contract. Do NOT use in production without security review.
 */

contract WeightedGovernance {
    // --- Roles & settings ---
    address public owner;
    uint256 public totalVotingWeight;        // Sum of all weights held by members
    uint256 public constant ROUND_DURATION = 7 days;  // voting period duration
    uint256 public constant QUORUM_PERCENT = 20;      // 20% quorum required

    // --- Member state ---
    mapping(address => uint256) public weightOf;     // current voting weight for each address

    // --- Proposal structure ---
    struct Proposal {
        uint256 id;
        address proposer;
        uint256 startTime;
        uint256 endTime;
        uint256 yesWeight;
        uint256 noWeight;
        bool executed;
        bool exists;
        string metadataCID; // optional: off-chain metadata pointer (set by proposer via event)
    }

    Proposal public activeProposal;   // only one active proposal at a time
    uint256 public proposalCount;

    // Tracks whether an address has voted in a given proposal id
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    // Records weight used when an address voted (so rebalancing weights later doesn't retroactively change past votes)
    mapping(uint256 => mapping(address => uint256)) public weightUsedInVote;

    // --- Events ---
    event Initialized(address indexed owner);
    event VotingPowerPurchased(address indexed buyer, uint256 amount, uint256 newWeight);
    event ProposalCreated(uint256 indexed id, address indexed proposer, uint256 startTime, uint256 endTime);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weightUsed);
    event ProposalExecuted(uint256 indexed proposalId, bool passed, uint256 yesWeight, uint256 noWeight);
    event ProposalCancelled(uint256 indexed proposalId);
    event WeightWithdrawn(address indexed user, uint256 amount);

    // --- Initialization (no constructor) ---
    function initialize() external {
        require(owner == address(0), "Already initialized");
        owner = msg.sender;
        proposalCount = 0;
        emit Initialized(owner);
    }

    // --- Membership / Voting Weight Management ---

    /**
     * Buy voting weight. 1 wei = 1 weight.
     * No input fields — send ETH with the call.
     */
    function buyVotingPower() external payable {
        require(msg.value > 0, "Send ETH to buy weight");
        weightOf[msg.sender] += msg.value;
        totalVotingWeight += msg.value;
        emit VotingPowerPurchased(msg.sender, msg.value, weightOf[msg.sender]);
    }

    /**
     * Withdraw (burn) voting weight by withdrawing ETH back to caller.
     * This lets members reduce their weight. Withdraws are limited by current available (not already used votes).
     * Note: weight used in previous votes is not returned; weightOf reflects current available weight.
     */
    function withdrawWeight() external {
        uint256 available = weightOf[msg.sender];
        require(available > 0, "No weight to withdraw");
        // simple immediate withdraw: set to zero and transfer ETH back
        weightOf[msg.sender] = 0;
        totalVotingWeight -= available;
        (bool sent, ) = payable(msg.sender).call{value: available}("");
        require(sent, "Withdraw failed");
        emit WeightWithdrawn(msg.sender, available);
    }

    // --- Proposal lifecycle ---

    /**
     * Create a new proposal (no parameters). Only allowed when no active proposal is running.
     * Proposal metadata should be stored off-chain (IPFS/CID) — the proposer is expected to post metadata
     * off-chain and reference it in a transaction log. To keep functions parameter-free we still emit an event
     * so clients can attach metadata in a subsequent transaction or indexer.
     *
     * The proposer should call createProposal() and then (off-chain) publish the proposal details (title, description),
     * referencing the emitted proposal id if needed.
     */
    function createProposal() external {
        require(owner != address(0), "Not initialized");
        require(!activeProposal.exists || block.timestamp >= activeProposal.endTime, "Active proposal in progress");

        uint256 id = ++proposalCount;
        uint256 start = block.timestamp;
        uint256 end = block.timestamp + ROUND_DURATION;

        activeProposal = Proposal({
            id: id,
            proposer: msg.sender,
            startTime: start,
            endTime: end,
            yesWeight: 0,
            noWeight: 0,
            executed: false,
            exists: true,
            metadataCID: "" // optional; off-chain metadata recommended
        });

        emit ProposalCreated(id, msg.sender, start, end);
    }

    /**
     * Optionally the proposer can emit metadata for the active proposal using this function.
     * It takes no input fields, but reads bytes from calldata: the caller may include a short CID
     * encoded into calldata when calling this zero-arg function. To keep the interface simple
     * and avoid typed parameters, we allow the proposer to call setProposalMetadataWithCalldata()
     * by placing an ASCII IPFS CID inside calldata payload. NOTE: Not all wallets allow manual calldata.
     *
     * Practical clients will typically rely on off-chain coordination (e.g., GitHub/IPFS) linked to the ProposalCreated event.
     */
    function setProposalMetadataWithCalldata() external {
        require(activeProposal.exists, "No active proposal");
        require(msg.sender == activeProposal.proposer, "Only proposer");
        // Read calldata after function selector (first 4 bytes)
        // calldata size minus 4 may be zero; only set metadata if calldata contains bytes
        uint256 dataSize = msg.data.length;
        if (dataSize > 4) {
            // extract bytes [4..end)
            bytes memory payload = new bytes(dataSize - 4);
            for (uint256 i = 4; i < dataSize; i++) {
                payload[i - 4] = msg.data[i];
            }
            // store as string (may be binary but intended as ASCII CID)
            activeProposal.metadataCID = string(payload);
        }
        // if no calldata provided, leaves metadataCID unchanged
    }

    /**
     * Cancel the active proposal. Only the proposer or owner can cancel, and only while the proposal is active.
     */
    function cancelProposal() external {
        require(activeProposal.exists, "No active proposal");
        require(msg.sender == activeProposal.proposer || msg.sender == owner, "Only proposer or owner");
        require(!activeProposal.executed, "Already executed");
        delete activeProposal;
        emit ProposalCancelled(activeProposal.id);
    }

    // --- Voting (no input fields) ---

    /**
     * Vote YES on the active proposal. Uses voter's current available weight and records that weight used.
     * Each address can vote once per proposal.
     */
    function voteYes() external {
        _vote(true);
    }

    /**
     * Vote NO on the active proposal. Uses voter's current available weight and records that weight used.
     */
    function voteNo() external {
        _vote(false);
    }

    // Internal vote handler
    function _vote(bool support) internal {
        require(activeProposal.exists, "No active proposal");
        require(block.timestamp >= activeProposal.startTime, "Voting not started");
        require(block.timestamp < activeProposal.endTime, "Voting period ended");
        require(!hasVoted[activeProposal.id][msg.sender], "Already voted");

        uint256 voterWeight = weightOf[msg.sender];
        require(voterWeight > 0, "No voting weight");

        // Record vote
        hasVoted[activeProposal.id][msg.sender] = true;
        weightUsedInVote[activeProposal.id][msg.sender] = voterWeight;

        if (support) {
            activeProposal.yesWeight += voterWeight;
        } else {
            activeProposal.noWeight += voterWeight;
        }

        emit Voted(activeProposal.id, msg.sender, support, voterWeight);
    }

    // --- Execution & Helpers ---

    /**
     * Execute the active proposal after voting period. Anyone can call executeProposal() once the round ends.
     * The proposal passes if:
     *   - (yesWeight + noWeight) >= quorum (QUORUM_PERCENT of totalVotingWeight at execution time)
     *   - yesWeight > noWeight
     *
     * Execution here simply emits an event indicating result. In more advanced systems, execution would
     * perform state changes (calls to other contracts) based on encoded instructions. Keeping it simple here.
     */
    function executeProposal() external {
        require(activeProposal.exists, "No active proposal");
        require(block.timestamp >= activeProposal.endTime, "Voting period not ended");
        require(!activeProposal.executed, "Already executed");

        uint256 yes = activeProposal.yesWeight;
        uint256 no = activeProposal.noWeight;
        uint256 turnout = yes + no;

        bool passed = false;
        // compute quorum threshold = ceil(totalVotingWeight * QUORUM_PERCENT / 100)
        uint256 quorumThreshold = (totalVotingWeight * QUORUM_PERCENT + 99) / 100;

        if (turnout >= quorumThreshold && yes > no) {
            passed = true;
        }

        activeProposal.executed = true;

        emit ProposalExecuted(activeProposal.id, passed, yes, no);

        // Clear active proposal so new proposals may be created
        delete activeProposal;
    }

    // --- Read helpers ---

    function getActiveProposalId() external view returns (uint256) {
        if (!activeProposal.exists) return 0;
        return activeProposal.id;
    }

    function getActiveProposalTimes() external view returns (uint256 start, uint256 end) {
        if (!activeProposal.exists) return (0, 0);
        return (activeProposal.startTime, activeProposal.endTime);
    }

    function getActiveProposalTally() external view returns (uint256 yes, uint256 no) {
        if (!activeProposal.exists) return (0, 0);
        return (activeProposal.yesWeight, activeProposal.noWeight);
    }

    function getActiveProposalMetadataCID() external view returns (string memory) {
        if (!activeProposal.exists) return "";
        return activeProposal.metadataCID;
    }

    function timeRemainingOnActive() external view returns (uint256) {
        if (!activeProposal.exists) return 0;
        if (block.timestamp >= activeProposal.endTime) return 0;
        return activeProposal.endTime - block.timestamp;
    }

    // --- Owner emergency functions ---

    /**
     * Owner-only emergency drain of contract ETH (not governance funds). Only callable if owner set.
     * This exists for safety in demo environments. Don't use in production governance without transparent rules.
     */
    function emergencyWithdrawAll() external {
        require(owner != address(0), "Not initialized");
        require(msg.sender == owner, "Only owner");
        uint256 bal = address(this).balance;
        require(bal > 0, "No balance");
        (bool sent, ) = payable(owner).call{value: bal}("");
        require(sent, "Withdraw failed");
    }

    // --- Fallback: accept ETH deposits (counts as buying weight only if buyVotingPower is used) ---
    receive() external payable {}
}
