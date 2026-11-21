// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IVaultUnpause {
    function unpauseByOracle() external;
}

/// @title VerdictOracle — on-chain store for AI verdicts (Base Sepolia).
/// @notice The off-chain AI agent posts one verdict per burst:
///         LEGITIMATE (burst looks like genuine user activity) or
///         ATTACK_LIKE (burst looks like a drain attempt), plus a one-line
///         reason. A LEGITIMATE verdict automatically unpauses the vault;
///         ATTACK_LIKE leaves it paused for manual review.
///         The verdict itself is written by the agent; the contract only
///         enforces one-verdict-per-burst and the agent role — it never
///         invents a classification.
contract VerdictOracle {
    enum Verdict {
        NONE,
        LEGITIMATE,
        ATTACK_LIKE
    }

    struct StoredVerdict {
        Verdict verdict;
        string reason;
        uint256 timestamp;
        address agent;
    }

    address public immutable owner;
    address public vault;
    address public agent;

    mapping(uint256 => StoredVerdict) public verdicts;

    event VerdictPosted(
        uint256 indexed burstId,
        Verdict verdict,
        string reason,
        address indexed agent
    );
    event AgentSet(address indexed agent);
    event VaultSet(address indexed vault);

    error NotOwner();
    error NotAgent();
    error InvalidVerdict();
    error AlreadyVerdicted();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgent() {
        if (msg.sender != agent) revert NotAgent();
        _;
    }

    constructor(address vault_, address agent_) {
        owner = msg.sender;
        vault = vault_;
        agent = agent_;
    }

    /// @notice Post the AI verdict for a burst. One verdict per burst.
    /// @param burstId_ Burst id emitted by CircuitBreaker.BurstFlagged.
    /// @param verdict_ LEGITIMATE or ATTACK_LIKE (NONE is rejected).
    /// @param reason_ One-line human-readable reason (e.g. model output).
    function submitVerdict(
        uint256 burstId_,
        Verdict verdict_,
        string calldata reason_
    ) external onlyAgent {
        if (verdict_ == Verdict.NONE) revert InvalidVerdict();
        if (verdicts[burstId_].verdict != Verdict.NONE)
            revert AlreadyVerdicted();
        verdicts[burstId_] = StoredVerdict({
            verdict: verdict_,
            reason: reason_,
            timestamp: block.timestamp,
            agent: msg.sender
        });
        emit VerdictPosted(burstId_, verdict_, reason_, msg.sender);
        if (verdict_ == Verdict.LEGITIMATE) {
            IVaultUnpause(vault).unpauseByOracle();
        }
    }

    function setAgent(address agent_) external onlyOwner {
        if (agent_ == address(0)) revert ZeroAddress();
        agent = agent_;
        emit AgentSet(agent_);
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultSet(vault_);
    }
}
