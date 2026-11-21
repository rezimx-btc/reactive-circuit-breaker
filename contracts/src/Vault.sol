// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Vault — demo vault for the Reactive Circuit-Breaker.
/// @notice Holds ETH deposits. Withdrawals emit `Withdrawal` events that the
///         reactive CircuitBreaker on Reactive Lasna subscribes to.
///         The vault is ALSO the callback recipient on Base Sepolia: the
///         Reactive Network delivers the pause callback through the Base
///         Sepolia callback proxy, which this contract authenticates by
///         (1) msg.sender == callback proxy and (2) the injected first
///         payload argument == the authorized CircuitBreaker address.
///         This mirrors the official "Callback Contracts" pattern
///         (dev.reactive.network/callback-contracts) without importing the
///         Reactive library: `pay(uint256)` / `receive()` implement the
///         minimal IPayer surface the proxy uses to settle callback fees,
///         and funding goes through the proxy's `depositTo(address)`.
/// @dev Chain: Base Sepolia (84532). Callback proxy (official docs,
///      dev.reactive.network/origins-and-destinations):
///      0x476F44b11F5C942c58f4c8E3d0300E5710743585
contract Vault {
    // ---- config (immutable after deploy, set via constructor) ----
    address public immutable CALLBACK_PROXY =
        0x476F44b11F5C942c58f4c8E3d0300E5710743585; // Base Sepolia proxy
    address public immutable owner;

    // ---- state ----
    address public circuitBreaker; // reactive contract on Lasna (set by owner)
    address public verdictOracle; // VerdictOracle on Base Sepolia (set by owner)
    mapping(address => uint256) public balances;
    bool public paused;

    // ---- events ----
    event Deposited(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event PausedByBreaker(address indexed reactive, uint256 indexed burstId);
    event PausedByOwner(address indexed owner);
    event Unpaused(address indexed by);
    event CircuitBreakerSet(address indexed breaker);
    event VerdictOracleSet(address indexed oracle);

    error NotOwner();
    error NotAuthorized();
    error Paused();
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address circuitBreaker_, address verdictOracle_) payable {
        owner = msg.sender;
        circuitBreaker = circuitBreaker_;
        verdictOracle = verdictOracle_;
    }

    // Plain ETH transfers count as deposits (same accounting as deposit()).
    receive() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Deposit ETH into the vault.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH. Blocked while paused. Emits the event the
    ///         reactive contract watches.
    function withdraw(uint256 amount) external {
        if (paused) revert Paused();
        if (balances[msg.sender] < amount) revert InsufficientBalance();
        balances[msg.sender] -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit Withdrawal(msg.sender, amount);
    }

    /// @notice Pause callback from Reactive Network. First payload argument
    ///         is overwritten by the proxy with the requesting reactive
    ///         contract's address (official callback pattern).
    /// @param reactive_ Injected by the proxy: the CircuitBreaker address.
    /// @param burstId_  Burst id assigned by the CircuitBreaker.
    function pauseViaCallback(address reactive_, uint256 burstId_) external {
        if (msg.sender != CALLBACK_PROXY) revert NotAuthorized();
        if (reactive_ != circuitBreaker) revert NotAuthorized();
        paused = true;
        emit PausedByBreaker(reactive_, burstId_);
    }

    /// @notice Unpause, callable only by the VerdictOracle (after a
    ///         LEGITIMATE verdict) or the owner.
    function unpauseByOracle() external {
        if (msg.sender != verdictOracle && msg.sender != owner)
            revert NotAuthorized();
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Owner pause/unpause (manual override / demo setup).
    function ownerPause() external onlyOwner {
        paused = true;
        emit PausedByOwner(msg.sender);
    }

    function ownerUnpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    /// @notice Wiring setters (owner only). The breaker address is set after
    ///         the Lasna deploy; the oracle after its Base Sepolia deploy.
    function setCircuitBreaker(address breaker_) external onlyOwner {
        if (breaker_ == address(0)) revert ZeroAddress();
        circuitBreaker = breaker_;
        emit CircuitBreakerSet(breaker_);
    }

    function setVerdictOracle(address oracle_) external onlyOwner {
        if (oracle_ == address(0)) revert ZeroAddress();
        verdictOracle = oracle_;
        emit VerdictOracleSet(oracle_);
    }

    // ---- Minimal payer surface (IPayer) for the callback proxy ----
    // The proxy charges callback execution to this contract: reserves are
    // funded via the proxy's depositTo(address); if reserves run out the
    // proxy calls pay() and this contract settles from its own balance.
    function pay(uint256 amount) external {
        if (msg.sender != CALLBACK_PROXY) revert NotAuthorized();
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Settle outstanding proxy debt from this contract's balance.
    function coverDebt() external {
        uint256 amount = IProxyDebt(CALLBACK_PROXY).debt(address(this));
        if (amount > 0) {
            (bool ok, ) = payable(CALLBACK_PROXY).call{value: amount}("");
            if (!ok) revert TransferFailed();
        }
    }
}

interface IProxyDebt {
    function debt(address _contract) external view returns (uint256);
}
