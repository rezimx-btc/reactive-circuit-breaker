// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {CircuitBreaker} from "../src/CircuitBreaker.sol";

/// @notice Mock of the Reactive system contract, etched at the real SYSTEM
///         address 0x8888...8888 so CircuitBreaker.react() auth passes in
///         tests. Records subscribe + callback requests for assertions.
contract MockSystem {
    struct CallbackReq {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    uint256 public subscribeCalls;
    uint256 public unsubscribeCalls;
    CallbackReq[] public callbacks;

    function subscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {
        subscribeCalls += 1;
    }

    function unsubscribe(
        uint256,
        address,
        uint256,
        uint256,
        uint256,
        uint256
    ) external {
        unsubscribeCalls += 1;
    }

    function requestCallbackV_1_0(
        CircuitBreakerCallbackConfig memory config
    ) external {
        callbacks.push(
            CallbackReq({
                chainId: config.chainId,
                recipient: config.recipient,
                gasLimit: config.gasLimit,
                payload: config.payload
            })
        );
    }

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function callbackCount() external view returns (uint256) {
        return callbacks.length;
    }
}

// Same layout as ISystemContractMinimal.CallbackConfiguration_V_1_0 so the
// mock can receive the struct (ABI-identical).
struct CircuitBreakerCallbackConfig {
    uint256 chainId;
    address recipient;
    uint64 gasLimit;
    bytes payload;
}

contract CircuitBreakerTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address constant VAULT = address(0x000000000000000000000000000000000000a007);
    uint256 constant WINDOW = 60;
    uint256 constant THRESHOLD = 1 ether;

    // Local copy so _log() makes no external call (an external call would
    // consume the vm.prank(SYSTEM) meant for react()).
    bytes32 constant TOPIC0 =
        0x7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65;

    CircuitBreaker breaker;
    MockSystem mock;

    function setUp() public {
        // Etch the mock's code at the real SYSTEM address, then talk to the
        // mock THROUGH that address (its storage lives there after etch).
        MockSystem template = new MockSystem();
        vm.etch(SYSTEM, address(template).code);
        mock = MockSystem(SYSTEM);
        breaker = new CircuitBreaker(VAULT, WINDOW, THRESHOLD);
    }

    function _log(address user, uint256 amount) internal view returns (CircuitBreaker.LogRecord memory) {
        return CircuitBreaker.LogRecord({
            chainId: 84532,
            contractAddress: VAULT,
            topic0: uint256(TOPIC0),
            topic1: uint256(uint160(user)),
            topic2: 0,
            topic3: 0,
            data: abi.encode(amount),
            blockNumber: 1,
            opCode: 2,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function testTopic0MatchesEventSignature() public view {
        assertEq(
            breaker.WITHDRAWAL_TOPIC0(),
            keccak256("Withdrawal(address,uint256)")
        );
    }

    function testReactRejectsNonSystemCaller() public {
        vm.expectRevert(CircuitBreaker.NotSystem.selector);
        breaker.react(_log(address(0x1), 1 ether));
    }

    function testBelowThresholdDoesNotFlag() public {
        vm.warp(1_000_000);
        vm.prank(SYSTEM);
        breaker.react(_log(address(0x1), 0.4 ether));
        assertFalse(breaker.flagged());
        assertEq(breaker.burstCount(), 0);
        assertEq(mock.callbackCount(), 0); // no callback requested
    }

    function testBurstTripsBreakerAndRequestsPauseCallback() public {
        vm.warp(1_000_000);
        address attacker = address(0xA77A);
        vm.prank(SYSTEM);
        breaker.react(_log(attacker, 0.6 ether));
        vm.prank(SYSTEM);
        breaker.react(_log(attacker, 0.6 ether)); // window sum 1.2 >= 1.0

        assertTrue(breaker.flagged());
        assertEq(breaker.burstCount(), 1);
        assertEq(breaker.lastBurstVolume(), 1.2 ether);

        // Exactly one callback, to the vault on Base Sepolia, calling
        // pauseViaCallback(address, burstId=1).
        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) = mock.callbacks(0);
        assertEq(chainId, 84532);
        assertEq(recipient, VAULT);
        assertGe(gasLimit, 100_000);
        (address arg0, uint256 burstId) = abi.decode(
            _payloadArgs(payload),
            (address, uint256)
        );
        assertEq(arg0, address(0)); // placeholder the proxy overwrites
        assertEq(burstId, 1);
    }

    function testNoDoubleFlagWhileLatched() public {
        vm.warp(1_000_000);
        vm.prank(SYSTEM);
        breaker.react(_log(address(0x1), 1.5 ether));
        assertEq(breaker.burstCount(), 1);
        vm.prank(SYSTEM);
        breaker.react(_log(address(0x1), 0.5 ether));
        assertEq(breaker.burstCount(), 1); // still latched, no 2nd callback
    }

    function testWindowIsTimeBasedNotBlockBased() public {
        // Two withdrawals 61s apart (same block-number regime in the test)
        // must NOT sum: the window is 60s of timestamps.
        vm.warp(1_000_000);
        vm.prank(SYSTEM);
        breaker.react(_log(address(0x1), 0.9 ether));
        vm.warp(1_000_000 + 61);
        vm.prank(SYSTEM);
        breaker.react(_log(address(0x1), 0.9 ether));
        assertFalse(breaker.flagged());
        assertEq(breaker.windowVolumeNow(), 0.9 ether);
    }

    function testNonWithdrawalTopicIgnored() public {
        vm.warp(1_000_000);
        CircuitBreaker.LogRecord memory l = _log(address(0x1), 5 ether);
        l.topic0 = uint256(keccak256("Deposit(address,uint256)"));
        vm.prank(SYSTEM);
        breaker.react(l);
        assertFalse(breaker.flagged());
        assertEq(breaker.burstCount(), 0);
    }

    function testSubscribeCallsSystem() public {
        breaker.subscribe();
        assertEq(mock.subscribeCalls(), 1);
        breaker.unsubscribe();
        assertEq(mock.unsubscribeCalls(), 1);
    }

    function testClearFlagRearms() public {
        vm.warp(1_000_000);
        vm.prank(SYSTEM);
        breaker.react(_log(address(0x1), 2 ether));
        assertTrue(breaker.flagged());
        breaker.clearFlag();
        assertFalse(breaker.flagged());
    }

    /// @dev Strip the 4-byte selector from abi.encodeWithSignature payload.
    function _payloadArgs(bytes memory payload) internal pure returns (bytes memory) {
        bytes memory args = new bytes(payload.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = payload[i + 4];
        }
        return args;
    }
}
