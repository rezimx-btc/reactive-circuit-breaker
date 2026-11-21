// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title ISystemContract (minimal, hand-written from the official docs)
/// @notice Only the functions this breaker uses, with signatures copied from
///         dev.reactive.network/reactive-contracts:
///         subscribe(uint256,address,uint256,uint256,uint256,uint256) and
///         requestCallbackV_1_0(CallbackConfiguration_V_1_0).
///         The full library was deliberately NOT imported (see README).
interface ISystemContractMinimal {
    struct CallbackConfiguration_V_1_0 {
        uint256 chainId; // destination network
        address recipient; // target contract on the destination chain
        uint64 gasLimit; // execution gas limit
        bytes payload; // ABI-encoded function call
    }

    function subscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;

    function unsubscribe(
        uint256 chain_id,
        address _contract,
        uint256 topic_0,
        uint256 topic_1,
        uint256 topic_2,
        uint256 topic_3
    ) external;

    function requestCallbackV_1_0(
        CallbackConfiguration_V_1_0 memory config
    ) external;

    function debt(address _contract) external view returns (uint256);
}

/// @title CircuitBreaker — reactive contract on Reactive Lasna.
/// @notice Subscribes to Vault.Withdrawal events on Base Sepolia (84532).
///         Tracks withdrawal volume in a ROLLING TIME WINDOW measured with
///         `block.timestamp` (Lasna ~1s blocks), NOT block counts — Base
///         Sepolia makes ~200ms blocks, so a block-count window would be
///         meaningless across chains. Note: LogRecord carries no origin
///         timestamp, so the window uses the Lasna block timestamp at the
///         moment react() runs (~1s after the origin event).
///         When window volume >= threshold, react() requests a callback
///         that pauses the vault, and emits BurstFlagged for the AI agent.
/// @dev Follows the official "Reactive Contracts" pattern
///      (dev.reactive.network/reactive-contracts): SYSTEM at
///      0x8888888888888888888888888888888888888888, react() guarded by
///      msg.sender == SYSTEM, REACTIVE_IGNORE wildcard
///      0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad
///      (dev.reactive.network/legacy/subscriptions), callback via
///      requestCallbackV_1_0 with the first payload argument reserved as
///      address(0) for the proxy to overwrite with this contract's address.
///      subscribe() is a separate owner call (not the constructor): the
///      constructor-time subscribe precompile reverts under forge script
///      simulation, so deploy-then-subscribe is the deployable shape.
contract CircuitBreaker {
    // ---- Reactive Network constants (official docs) ----
    address public constant SYSTEM =
        0x8888888888888888888888888888888888888888;
    uint256 public constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;
    uint256 public constant ORIGIN_CHAIN_ID = 84532; // Base Sepolia
    uint256 public constant DEST_CHAIN_ID = 84532; // Base Sepolia (pause vault)
    // keccak256("Withdrawal(address,uint256)") — verified with cast.
    bytes32 public constant WITHDRAWAL_TOPIC0 =
        0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65;
    // Reactive enforces a minimum callback gas limit of 100,000.
    uint64 public constant CALLBACK_GAS_LIMIT = 300_000;
    uint256 public constant MAX_OBSERVATIONS = 64;

    ISystemContractMinimal public constant SYSTEM_CONTRACT =
        ISystemContractMinimal(SYSTEM);

    address public immutable owner;

    // ---- config ----
    address public vault; // Vault on Base Sepolia (origin + callback target)
    uint256 public windowSeconds; // rolling window, seconds (default 60)
    uint256 public threshold; // window volume that trips the breaker (wei)

    // ---- rolling-window state ----
    struct Observation {
        uint256 timestamp;
        uint256 amount;
    }
    Observation[64] public observations;
    uint256 public obsCount; // observations stored (<= 64)
    uint256 public obsHead; // next write index (ring buffer)

    // ---- burst state ----
    bool public flagged; // true from trip until the flag is cleared
    uint256 public burstCount;
    uint256 public lastBurstId;
    uint256 public lastBurstVolume;
    uint256 public lastBurstAt;

    // ---- events ----
    event BurstFlagged(
        uint256 indexed burstId,
        address indexed lastUser,
        uint256 lastAmount,
        uint256 windowVolume,
        uint256 timestamp
    );
    event Subscribed(address indexed vault);
    event Unsubscribed(address indexed vault);
    event ThresholdSet(uint256 threshold);
    event WindowSet(uint256 windowSeconds);
    event VaultSet(address indexed vault);
    event FlagCleared(uint256 indexed burstId);

    error NotOwner();
    error NotSystem();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param vault_ Vault contract on Base Sepolia.
    /// @param windowSeconds_ Rolling window in seconds.
    /// @param threshold_ Window volume (wei) that trips the breaker.
    constructor(
        address vault_,
        uint256 windowSeconds_,
        uint256 threshold_
    ) payable {
        if (vault_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        vault = vault_;
        windowSeconds = windowSeconds_;
        threshold = threshold_;
    }

    receive() external payable {}

    // ---- subscription management (owner) ----
    function subscribe() external onlyOwner {
        SYSTEM_CONTRACT.subscribe(
            ORIGIN_CHAIN_ID,
            vault,
            uint256(WITHDRAWAL_TOPIC0),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        emit Subscribed(vault);
    }

    function unsubscribe() external onlyOwner {
        SYSTEM_CONTRACT.unsubscribe(
            ORIGIN_CHAIN_ID,
            vault,
            uint256(WITHDRAWAL_TOPIC0),
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        emit Unsubscribed(vault);
    }

    // ---- config setters (owner) ----
    function setThreshold(uint256 threshold_) external onlyOwner {
        threshold = threshold_;
        emit ThresholdSet(threshold_);
    }

    function setWindow(uint256 windowSeconds_) external onlyOwner {
        windowSeconds = windowSeconds_;
        emit WindowSet(windowSeconds_);
    }

    function setVault(address vault_) external onlyOwner {
        if (vault_ == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultSet(vault_);
    }

    /// @notice Clear the trip latch (after the AI verdict resolved the
    ///         burst). Owner-only; the agent runs with the deployer key.
    function clearFlag() external onlyOwner {
        flagged = false;
        emit FlagCleared(lastBurstId);
    }

    // ---- LogRecord, as documented on dev.reactive.network ----
    struct LogRecord {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        bytes data;
        uint256 blockNumber;
        uint256 opCode;
        uint256 blockHash;
        uint256 txHash;
        uint256 logIndex;
    }

    /// @notice Entry point called by the system contract for each matching
    ///         log. Non-matching logs fall through silently (reverting as a
    ///         filter is a documented mistake: still billed, still logged).
    function react(LogRecord memory log_) external {
        if (msg.sender != SYSTEM) revert NotSystem();
        if (log_.topic0 != uint256(WITHDRAWAL_TOPIC0)) return;
        // Withdrawal(address indexed user, uint256 amount) is a LOG2:
        // topic1 = user, data = abi.encode(amount).
        if (log_.opCode != 2) return;
        uint256 amount = abi.decode(log_.data, (uint256));
        address user = address(uint160(log_.topic1));

        _record(block.timestamp, amount);
        uint256 volume = _windowVolume(block.timestamp);

        if (volume >= threshold && !flagged) {
            flagged = true;
            burstCount += 1;
            lastBurstId = burstCount;
            lastBurstVolume = volume;
            lastBurstAt = block.timestamp;
            emit BurstFlagged(burstCount, user, amount, volume, block.timestamp);
            _requestPause(burstCount);
        } else if (volume < threshold && flagged) {
            // Window slid past the burst with no new trip: re-arm.
            flagged = false;
        }
    }

    /// @notice Volume of observations inside the rolling window ending now.
    function windowVolumeNow() external view returns (uint256) {
        return _windowVolume(block.timestamp);
    }

    function _record(uint256 timestamp_, uint256 amount_) internal {
        observations[obsHead] = Observation({
            timestamp: timestamp_,
            amount: amount_
        });
        obsHead = (obsHead + 1) % MAX_OBSERVATIONS;
        if (obsCount < MAX_OBSERVATIONS) obsCount += 1;
    }

    function _windowVolume(uint256 now_) internal view returns (uint256) {
        uint256 cutoff = now_ >= windowSeconds
            ? now_ - windowSeconds
            : 0;
        uint256 sum = 0;
        for (uint256 i = 0; i < obsCount; i++) {
            Observation memory o = observations[i];
            if (o.timestamp >= cutoff) sum += o.amount;
        }
        return sum;
    }

    function _requestPause(uint256 burstId_) internal {
        // First payload argument MUST be address(0): the proxy overwrites
        // its first 160 bits with this contract's address.
        bytes memory payload = abi.encodeWithSignature(
            "pauseViaCallback(address,uint256)",
            address(0),
            burstId_
        );
        SYSTEM_CONTRACT.requestCallbackV_1_0(
            ISystemContractMinimal.CallbackConfiguration_V_1_0({
                chainId: DEST_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    // ---- Minimal payer surface (IPayer) for the system contract ----
    // Reactive tx fees draw on reserves funded via SYSTEM.depositTo(address);
    // if reserves run out the system contract calls pay() to settle from
    // this contract's own balance.
    function pay(uint256 amount) external {
        if (msg.sender != SYSTEM) revert NotSystem();
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "pay failed");
    }

    /// @notice Settle outstanding system-contract debt from own balance.
    function coverDebt() external {
        uint256 amount = SYSTEM_CONTRACT.debt(address(this));
        if (amount > 0) {
            (bool ok, ) = payable(SYSTEM).call{value: amount}("");
            require(ok, "coverDebt failed");
        }
    }
}
