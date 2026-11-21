// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";

/// @notice Callback proxy stand-in: in production this is the Base Sepolia
///         proxy 0x476F44b11F5C942c58f4c8E3d0300E5710743585. The Vault
///         hardcodes that address, so tests deploy a MockProxy via etch at
///         the real proxy address.
contract MockProxy {
    function debt(address) external pure returns (uint256) {
        return 0;
    }
}

contract VaultTest is Test {
    address constant PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    address constant BREAKER = address(0xBEEF);
    address constant ORACLE = address(0x0BAD);

    Vault vault;
    address user = address(0xA11CE);

    function setUp() public {
        vm.etch(PROXY, address(new MockProxy()).code);
        vault = new Vault(BREAKER, ORACLE);
        vm.deal(user, 10 ether);
    }

    function testDepositAndWithdraw() public {
        vm.prank(user);
        vault.deposit{value: 3 ether}();
        assertEq(vault.balances(user), 3 ether);

        vm.prank(user);
        vm.expectEmit(true, false, false, true, address(vault));
        emit Vault.Withdrawal(user, 1 ether);
        vault.withdraw(1 ether);
        assertEq(vault.balances(user), 2 ether);
        assertEq(user.balance, 10 ether - 3 ether + 1 ether);
    }

    function testWithdrawRevertsWhenInsufficient() public {
        vm.prank(user);
        vault.deposit{value: 1 ether}();
        vm.prank(user);
        vm.expectRevert(Vault.InsufficientBalance.selector);
        vault.withdraw(2 ether);
    }

    function testPauseViaCallbackAuth() public {
        // Only the proxy may call it.
        vm.expectRevert(Vault.NotAuthorized.selector);
        vault.pauseViaCallback(BREAKER, 1);

        // Proxy calling with a wrong reactive address is rejected.
        vm.prank(PROXY);
        vm.expectRevert(Vault.NotAuthorized.selector);
        vault.pauseViaCallback(address(0x1234), 1);

        // Proxy + correct breaker pauses.
        vm.prank(PROXY);
        vault.pauseViaCallback(BREAKER, 7);
        assertTrue(vault.paused());

        // Withdrawals revert while paused.
        vm.prank(user);
        vault.deposit{value: 1 ether}();
        vm.prank(user);
        vm.expectRevert(Vault.Paused.selector);
        vault.withdraw(0.1 ether);
    }

    function testUnpauseByOracleAndOwner() public {
        vault.ownerPause();
        assertTrue(vault.paused());

        // Random caller cannot unpause.
        vm.prank(user);
        vm.expectRevert(Vault.NotAuthorized.selector);
        vault.unpauseByOracle();

        // Oracle can.
        vm.prank(ORACLE);
        vault.unpauseByOracle();
        assertFalse(vault.paused());
    }

    function testReceiveCountsAsDeposit() public {
        vm.prank(user);
        (bool ok, ) = payable(address(vault)).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(vault.balances(user), 0.5 ether);
    }
}
