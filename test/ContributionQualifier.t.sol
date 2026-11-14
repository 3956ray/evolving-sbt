// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { EvolvingSBT } from "../src/EvolvingSBT.sol";
import { IEvolvingSBT } from "../src/interfaces/IEvolvingSBT.sol";
import { ClaimRevocationRegistry } from "../src/ClaimRevocationRegistry.sol";
import { ContributionQualifier } from "../src/ContributionQualifier.sol";

contract ContributionQualifierTest is Test {
    event ClaimRevoked(uint256 indexed tokenId, bytes32 indexed claimId, bytes32 indexed revocationKey);

    uint256 internal constant ISSUER_KEY = 0xB0B;
    uint256 internal constant CONTROLLER_KEY = 0xCA11;
    bytes32 internal constant NS = keccak256("community.contributions");
    EvolvingSBT internal sbt;
    ClaimRevocationRegistry internal registry;
    ContributionQualifier internal qualifier;
    address internal issuer;
    address internal controller;
    address internal holder = address(0xA11CE);
    uint256 internal token;
    bytes32 internal policy;

    function setUp() public {
        vm.warp(1_000_000);
        issuer = vm.addr(ISSUER_KEY);
        controller = vm.addr(CONTROLLER_KEY);
        sbt = new EvolvingSBT(address(this));
        policy = sbt.registerNamespace(NS, issuer, controller, "ipfs://contributions");
        registry = new ClaimRevocationRegistry(sbt, NS, issuer, controller);
        qualifier = new ContributionQualifier(sbt, NS, policy, registry);
        vm.prank(holder);
        token = sbt.mint();
        EvolvingSBT.Record memory empty;
        _advance(EvolvingSBT.Operation.Initialize, empty, IEvolvingSBT.NamespaceStatus.Active, 0);
    }

    function _record(uint256 id) internal view returns (EvolvingSBT.Record memory) {
        return EvolvingSBT.Record(
            keccak256(abi.encode("claim", id)),
            keccak256(abi.encode("experience", id)),
            holder,
            keccak256(abi.encode("contribution", id)),
            0,
            bytes32(0)
        );
    }

    function _advance(
        EvolvingSBT.Operation op,
        EvolvingSBT.Record memory record,
        IEvolvingSBT.NamespaceStatus status,
        uint64 expiry
    ) internal {
        IEvolvingSBT.StateHead memory head = sbt.stateOf(token, NS);
        (, IEvolvingSBT.PolicyStatus memory controls) = sbt.policyOf(NS, policy);
        EvolvingSBT.Evidence memory decoded = EvolvingSBT.Evidence(op, record);
        bytes memory evidence = abi.encode(decoded);
        IEvolvingSBT.Transition memory change = IEvolvingSBT.Transition({
            tokenId: token,
            namespace: NS,
            expectedRevision: head.revision,
            expectedStateHash: sbt.hashState(head),
            sourcePolicyEpoch: head.revision == 0 ? 0 : controls.epoch,
            targetPolicyEpoch: controls.epoch,
            nextState: sbt.previewTransition(token, NS, decoded, status, expiry),
            operationsCommitment: keccak256(evidence),
            deadline: uint64(block.timestamp + 1 hours)
        });
        uint256 key = op == EvolvingSBT.Operation.Append || op == EvolvingSBT.Operation.Correct
            ? ISSUER_KEY
            : CONTROLLER_KEY;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, sbt.transitionDigest(change));
        bytes memory auth = abi.encode(EvolvingSBT.Authorization(abi.encodePacked(r, s, v), bytes("")));
        vm.prank(holder);
        sbt.applyTransition(change, evidence, auth);
    }

    function _append(uint256 id) internal {
        IEvolvingSBT.StateHead memory head = sbt.stateOf(token, NS);
        _advance(EvolvingSBT.Operation.Append, _record(id), head.status, head.validUntil);
    }

    function _two() internal {
        _append(1);
        _append(2);
    }

    function _qualifies() internal view returns (bool) {
        return qualifier.qualifies(token, [uint256(0), 1]);
    }

    function _revoke(uint256 id) internal {
        bytes32 claim = _record(id).claimId;
        vm.prank(issuer);
        registry.revoke(token, claim);
    }

    function testQualificationRevocationImmediatelyInvalidatesUnchangedSBT() public {
        _two();
        assertTrue(_qualifies());
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        _revoke(1);
        assertFalse(_qualifies());
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
        assertTrue(sbt.isUsable(token, NS));
        (, bool active) = sbt.recordAt(token, NS, 0);
        assertTrue(active);
        assertEq(sbt.recordCount(token, NS), 2);
    }

    function testQualificationRejectsInsufficientDuplicateAndInvalidIndices() public {
        assertFalse(_qualifies());
        _append(1);
        assertFalse(_qualifies());
        assertFalse(qualifier.qualifies(token, [uint256(0), 0]));
        _append(2);
        assertTrue(qualifier.qualifies(token, [uint256(1), 0]));
        assertFalse(qualifier.qualifies(token, [uint256(0), type(uint256).max]));
    }

    function testQualificationOnlyIssuerRevokesAndRevocationIsIdempotent() public {
        _two();
        bytes32 claim = _record(1).claimId;
        vm.prank(holder);
        vm.expectRevert(ClaimRevocationRegistry.NotIssuer.selector);
        registry.revoke(token, claim);
        vm.prank(controller);
        vm.expectRevert(ClaimRevocationRegistry.NotIssuer.selector);
        registry.revoke(token, claim);
        assertTrue(_qualifies());
        _revoke(1);
        vm.recordLogs();
        _revoke(1);
        assertEq(vm.getRecordedLogs().length, 0);
        assertFalse(_qualifies());
    }

    function testQualificationRejectsZeroClaim() public {
        vm.prank(issuer);
        vm.expectRevert(ClaimRevocationRegistry.InvalidClaim.selector);
        registry.revoke(token, bytes32(0));
    }

    function testQualificationRejectsWrongIssuerControllerAndPolicyBindings() public {
        vm.expectRevert(ClaimRevocationRegistry.InvalidBinding.selector);
        new ClaimRevocationRegistry(sbt, NS, holder, controller);
        vm.expectRevert(ClaimRevocationRegistry.InvalidBinding.selector);
        new ClaimRevocationRegistry(sbt, NS, issuer, holder);
        vm.expectRevert(ContributionQualifier.InvalidBinding.selector);
        new ContributionQualifier(sbt, NS, bytes32(uint256(1)), registry);
        vm.expectRevert(ContributionQualifier.InvalidBinding.selector);
        new ContributionQualifier(sbt, keccak256("wrong"), policy, registry);
    }

    function testQualificationWrongRegistryCannotReplacePinnedRegistry() public {
        _two();
        ClaimRevocationRegistry otherRegistry = new ClaimRevocationRegistry(sbt, NS, issuer, controller);
        _revoke(1);
        assertFalse(otherRegistry.isRevoked(token, _record(1).claimId));
        assertEq(address(qualifier.registry()), address(registry));
        assertFalse(_qualifies());
        bytes32 otherNS = keccak256("other");
        sbt.registerNamespace(otherNS, issuer, controller, "ipfs://other");
        ClaimRevocationRegistry wrongScope = new ClaimRevocationRegistry(sbt, otherNS, issuer, controller);
        vm.expectRevert(ContributionQualifier.InvalidBinding.selector);
        new ContributionQualifier(sbt, NS, policy, wrongScope);
        EvolvingSBT other = new EvolvingSBT(address(this));
        bytes32 otherPolicy = other.registerNamespace(NS, issuer, controller, "ipfs://other-contract");
        vm.expectRevert(ContributionQualifier.InvalidBinding.selector);
        new ContributionQualifier(other, NS, otherPolicy, registry);
    }

    function testQualificationRevocationScopedToTokenAndClaim() public {
        _two();
        bytes32 claim = _record(1).claimId;
        vm.prank(issuer);
        registry.revoke(token + 1, claim);
        assertTrue(_qualifies());
        _revoke(3);
        assertTrue(_qualifies());
        assertNotEq(registry.revocationKey(token, claim), registry.revocationKey(token + 1, claim));
    }

    function testQualificationPreRevocationSurvivesAdmission() public {
        _revoke(1);
        _two();
        assertFalse(_qualifies());
    }

    function testQualificationRevocationEventAndDomainRemainStable() public {
        _two();
        bytes32 claim = _record(1).claimId;
        bytes32 expected = keccak256(abi.encode(block.chainid, address(sbt), NS, policy, token, claim));
        assertEq(registry.revocationKey(token, claim), expected);
        vm.expectEmit(true, true, true, true, address(registry));
        emit ClaimRevoked(token, claim, expected);
        _revoke(1);
        vm.chainId(block.chainid + 1);
        assertEq(registry.revocationKey(token, claim), expected);
        assertFalse(_qualifies());
    }

    function testQualificationRecordExpiryInclusiveBoundary() public {
        EvolvingSBT.Record memory record = _record(1);
        record.validUntil = uint64(block.timestamp + 10);
        _advance(EvolvingSBT.Operation.Append, record, IEvolvingSBT.NamespaceStatus.Active, 0);
        _append(2);
        vm.warp(record.validUntil);
        assertTrue(_qualifies());
        vm.warp(uint256(record.validUntil) + 1);
        assertFalse(_qualifies());
        assertTrue(sbt.isUsable(token, NS));
    }

    function testQualificationNamespaceExpiry() public {
        vm.prank(holder);
        token = sbt.mint();
        EvolvingSBT.Record memory empty;
        uint64 expiry = uint64(block.timestamp + 10);
        _advance(EvolvingSBT.Operation.Initialize, empty, IEvolvingSBT.NamespaceStatus.Active, expiry);
        _two();
        vm.warp(expiry);
        assertTrue(_qualifies());
        vm.warp(uint256(expiry) + 1);
        assertFalse(_qualifies());
    }

    function testQualificationUpdatesPausedStillAllowsIndependentRevocation() public {
        _two();
        vm.prank(controller);
        sbt.setPolicyControls(NS, false, true);
        assertTrue(_qualifies());
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        _revoke(1);
        assertFalse(_qualifies());
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
    }

    function testQualificationFullHistoryStillAllowsIndependentRevocation() public {
        for (uint256 i = 1; i <= 32; i++) {
            _append(i);
        }
        assertTrue(_qualifies());
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        _revoke(1);
        assertFalse(_qualifies());
        assertTrue(qualifier.qualifies(token, [uint256(1), 2]));
        assertEq(sbt.recordCount(token, NS), 32);
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
    }

    function testQualificationUseControlsSuspensionAndTerminalRevocation() public {
        _two();
        vm.prank(controller);
        sbt.setPolicyControls(NS, true, false);
        assertFalse(_qualifies());
        vm.prank(controller);
        sbt.setPolicyControls(NS, true, true);
        EvolvingSBT.Record memory empty;
        _advance(EvolvingSBT.Operation.Suspend, empty, IEvolvingSBT.NamespaceStatus.Suspended, 0);
        assertFalse(_qualifies());
        _advance(EvolvingSBT.Operation.Resume, empty, IEvolvingSBT.NamespaceStatus.Active, 0);
        assertTrue(_qualifies());
        _advance(EvolvingSBT.Operation.Revoke, empty, IEvolvingSBT.NamespaceStatus.Revoked, 0);
        assertFalse(_qualifies());
    }

    function testQualificationCorrectionsDoNotCountAsAnotherExperience() public {
        _two();
        _revoke(1);
        EvolvingSBT.Record memory corrected = _record(3);
        corrected.experienceId = _record(1).experienceId;
        corrected.replaces = _record(1).claimId;
        _advance(EvolvingSBT.Operation.Correct, corrected, IEvolvingSBT.NamespaceStatus.Active, 0);
        assertFalse(_qualifies());
        assertFalse(qualifier.qualifies(token, [uint256(0), 2]));
        assertTrue(qualifier.qualifies(token, [uint256(1), 2]));
        assertTrue(registry.isRevoked(token, _record(1).claimId));
        _revoke(3);
        assertFalse(qualifier.qualifies(token, [uint256(1), 2]));
    }

    function testQualificationBurnedAbsentAndUninitializedCredentialsFail() public {
        _two();
        assertFalse(qualifier.qualifies(token + 1, [uint256(0), 1]));
        vm.prank(holder);
        uint256 fresh = sbt.mint();
        assertFalse(qualifier.qualifies(fresh, [uint256(0), 1]));
        vm.prank(holder);
        sbt.burn(token);
        assertFalse(_qualifies());
    }

    function testFuzzQualificationRevocationDoesNotDependOnHolderUpdate(uint8 selected) public {
        _two();
        selected = uint8(bound(selected, 1, 2));
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        assertTrue(_qualifies());
        _revoke(selected);
        assertFalse(_qualifies());
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
    }
}
