// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {VerdictOracle} from "../src/VerdictOracle.sol";

/// @notice Minimal vault stand-in recording unpauseByOracle calls.
contract MockVault {
    uint256 public unpauseCalls;
    address public lastCaller;

    function unpauseByOracle() external {
        unpauseCalls += 1;
        lastCaller = msg.sender;
    }
}

contract VerdictOracleTest is Test {
    VerdictOracle oracle;
    MockVault vault;
    address agent = address(0xA6E77);
    address stranger = address(0x7A9E);

    function setUp() public {
        vault = new MockVault();
        oracle = new VerdictOracle(address(vault), agent);
    }

    function testLegitimateVerdictUnpausesVault() public {
        vm.prank(agent);
        oracle.submitVerdict(1, VerdictOracle.Verdict.LEGITIMATE, "2 known users, prior history");
        assertEq(vault.unpauseCalls(), 1);
        (VerdictOracle.Verdict v, string memory reason, , address a) = oracle.verdicts(1);
        assertEq(uint256(v), uint256(VerdictOracle.Verdict.LEGITIMATE));
        assertEq(reason, "2 known users, prior history");
        assertEq(a, agent);
    }

    function testAttackVerdictKeepsVaultPaused() public {
        vm.prank(agent);
        oracle.submitVerdict(2, VerdictOracle.Verdict.ATTACK_LIKE, "1 fresh address, full drain in 3s");
        assertEq(vault.unpauseCalls(), 0);
        (VerdictOracle.Verdict v, , , ) = oracle.verdicts(2);
        assertEq(uint256(v), uint256(VerdictOracle.Verdict.ATTACK_LIKE));
    }

    function testOnlyAgentCanSubmit() public {
        vm.prank(stranger);
        vm.expectRevert(VerdictOracle.NotAgent.selector);
        oracle.submitVerdict(1, VerdictOracle.Verdict.LEGITIMATE, "x");
    }

    function testOneVerdictPerBurst() public {
        vm.prank(agent);
        oracle.submitVerdict(3, VerdictOracle.Verdict.LEGITIMATE, "first");
        vm.prank(agent);
        vm.expectRevert(VerdictOracle.AlreadyVerdicted.selector);
        oracle.submitVerdict(3, VerdictOracle.Verdict.ATTACK_LIKE, "second");
    }

    function testNoneVerdictRejected() public {
        vm.prank(agent);
        vm.expectRevert(VerdictOracle.InvalidVerdict.selector);
        oracle.submitVerdict(4, VerdictOracle.Verdict.NONE, "none");
    }
}
