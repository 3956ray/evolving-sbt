// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Test } from "forge-std/Test.sol";
import { EvolvingSBT } from "../src/EvolvingSBT.sol";
import { IEvolvingSBT } from "../src/interfaces/IEvolvingSBT.sol";
import { Mock1271Wallet, ReentrantMintReceiver } from "./helpers/TestWallets.sol";

contract EvolvingSBTTest is Test {
    EvolvingSBT internal sbt;
    uint256 internal constant HOLDER_KEY = 0xA11CE;
    uint256 internal constant ISSUER_KEY = 0xB0B;
    uint256 internal constant CONTROLLER_KEY = 0xCA11;
    uint256 internal constant ISSUER_B_KEY = 0xB0B2;
    uint256 internal constant CONTROLLER_B_KEY = 0xCA112;
    bytes32 internal constant NS = keccak256("community.contributions");
    bytes32 internal constant NS_B = keccak256("education.qualifications");
    address internal holder;
    address internal issuer;
    address internal controller;
    address internal relayer = address(0xBEEF);
    uint256 internal token;
    bytes32 internal policy;
    bytes32 internal policyB;

    function setUp() public {
        vm.warp(1_000_000);
        holder = vm.addr(HOLDER_KEY);
        issuer = vm.addr(ISSUER_KEY);
        controller = vm.addr(CONTROLLER_KEY);
        sbt = new EvolvingSBT(address(this));
        policy = sbt.registerNamespace(NS, issuer, controller, "ipfs://community-profile-v1");
        policyB = sbt.registerNamespace(
            NS_B, vm.addr(ISSUER_B_KEY), vm.addr(CONTROLLER_B_KEY), "ipfs://qualification-profile-v1"
        );
        vm.prank(holder);
        token = sbt.mint();
    }

    function _sig(bytes32 digest, uint256 key) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _lifecycle(EvolvingSBT.Operation op) internal pure returns (EvolvingSBT.Evidence memory e) {
        e.operation = op;
    }

    function _record(uint256 id) internal view returns (EvolvingSBT.Record memory r) {
        r.claimId = keccak256(abi.encode("claim", id));
        r.experienceId = keccak256(abi.encode("experience", id));
        r.subject = holder;
        r.contentHash = keccak256(abi.encode("content", id));
    }

    function _appendEvidence(uint256 id) internal view returns (EvolvingSBT.Evidence memory e) {
        e.operation = EvolvingSBT.Operation.Append;
        e.record = _record(id);
    }

    function _change(
        EvolvingSBT target,
        uint256 tokenId,
        bytes32 ns,
        bytes32 policyId,
        EvolvingSBT.Evidence memory e,
        IEvolvingSBT.NamespaceStatus status,
        uint64 validUntil
    ) internal view returns (IEvolvingSBT.Transition memory c, bytes memory evidence) {
        IEvolvingSBT.StateHead memory head = target.stateOf(tokenId, ns);
        (, IEvolvingSBT.PolicyStatus memory controls) = target.policyOf(ns, policyId);
        evidence = abi.encode(e);
        c = IEvolvingSBT.Transition({
            tokenId: tokenId,
            namespace: ns,
            expectedRevision: head.revision,
            expectedStateHash: target.hashState(head),
            sourcePolicyEpoch: head.revision == 0 ? 0 : controls.epoch,
            targetPolicyEpoch: controls.epoch,
            nextState: target.previewTransition(tokenId, ns, e, status, validUntil),
            operationsCommitment: keccak256(evidence),
            deadline: uint64(block.timestamp + 1 hours)
        });
    }

    function _change(EvolvingSBT.Evidence memory e, IEvolvingSBT.NamespaceStatus status, uint64 expiry)
        internal
        view
        returns (IEvolvingSBT.Transition memory c, bytes memory evidence)
    {
        return _change(sbt, token, NS, policy, e, status, expiry);
    }

    function _auth(IEvolvingSBT.Transition memory c, uint256 authorityKey, bool consent)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = sbt.transitionDigest(c);
        return abi.encode(
            EvolvingSBT.Authorization({
                authoritySignature: _sig(digest, authorityKey),
                holderSignature: consent ? _sig(digest, HOLDER_KEY) : bytes("")
            })
        );
    }

    function _submit(IEvolvingSBT.Transition memory c, bytes memory evidence, uint256 key)
        internal
        returns (uint64)
    {
        bytes memory authorization = _auth(c, key, c.expectedRevision == 0);
        vm.prank(relayer);
        return sbt.applyTransition(c, evidence, authorization);
    }

    function _initialize() internal {
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0);
        _submit(c, e, CONTROLLER_KEY);
    }

    function _append(uint256 id) internal {
        IEvolvingSBT.StateHead memory h = sbt.stateOf(token, NS);
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(id), h.status, h.validUntil);
        _submit(c, e, ISSUER_KEY);
    }

    function _setStatus(EvolvingSBT.Operation operation, IEvolvingSBT.NamespaceStatus status) internal {
        IEvolvingSBT.StateHead memory h = sbt.stateOf(token, NS);
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(operation), status, h.validUntil);
        _submit(c, e, CONTROLLER_KEY);
    }

    function testSupportsERC721ERC165ERC5192AndCandidateInterface() public view {
        assertTrue(sbt.supportsInterface(0x80ac58cd));
        assertTrue(sbt.supportsInterface(0x01ffc9a7));
        assertTrue(sbt.supportsInterface(0xb45a3c0e));
        assertTrue(sbt.supportsInterface(type(IEvolvingSBT).interfaceId));
        assertFalse(sbt.supportsInterface(0xffffffff));
        assertTrue(sbt.locked(token));
        assertEq(sbt.ownerOf(token), holder);
    }

    function testAllTransferEntryPointsRejectIncludingSelfTransfer() public {
        vm.startPrank(holder);
        vm.expectRevert(EvolvingSBT.Soulbound.selector);
        sbt.transferFrom(holder, relayer, token);
        vm.expectRevert(EvolvingSBT.Soulbound.selector);
        sbt.safeTransferFrom(holder, relayer, token);
        vm.expectRevert(EvolvingSBT.Soulbound.selector);
        sbt.safeTransferFrom(holder, relayer, token, "payload");
        vm.expectRevert(EvolvingSBT.Soulbound.selector);
        sbt.transferFrom(holder, holder, token);
        vm.stopPrank();
        assertEq(sbt.ownerOf(token), holder);
    }

    function testMintIsSelfConsentAndBurnedIdentifierNeverReused() public {
        vm.prank(holder);
        sbt.burn(token);
        vm.expectRevert();
        sbt.locked(token);
        vm.expectRevert();
        sbt.stateOf(token, NS);
        vm.prank(holder);
        uint256 next = sbt.mint();
        assertGt(next, token);
        assertEq(sbt.ownerOf(next), holder);
        vm.expectRevert();
        sbt.ownerOf(token);
    }

    function testOnlyHolderCanBurn() public {
        vm.prank(relayer);
        vm.expectRevert(EvolvingSBT.NotHolder.selector);
        sbt.burn(token);
        assertEq(sbt.ownerOf(token), holder);
    }

    function testERC721ApprovalsCannotTransferOrBurnSoulboundToken() public {
        vm.prank(holder);
        sbt.approve(relayer, token);
        vm.startPrank(relayer);
        vm.expectRevert(EvolvingSBT.Soulbound.selector);
        sbt.transferFrom(holder, relayer, token);
        vm.expectRevert(EvolvingSBT.NotHolder.selector);
        sbt.burn(token);
        vm.stopPrank();
        vm.prank(holder);
        sbt.setApprovalForAll(relayer, true);
        vm.startPrank(relayer);
        vm.expectRevert(EvolvingSBT.Soulbound.selector);
        sbt.safeTransferFrom(holder, relayer, token);
        vm.expectRevert(EvolvingSBT.NotHolder.selector);
        sbt.burn(token);
        vm.stopPrank();
        assertEq(sbt.ownerOf(token), holder);
        assertTrue(sbt.locked(token));
    }

    function testUnknownNamespaceAndPolicyReject() public {
        vm.expectRevert(EvolvingSBT.UnknownPolicy.selector);
        sbt.stateOf(token, keccak256("unknown"));
        vm.expectRevert(EvolvingSBT.UnknownPolicy.selector);
        sbt.policyOf(NS, bytes32(uint256(9)));
    }

    function testNamespaceRegistrationIsImmutableAndAdminOnly() public {
        vm.prank(holder);
        vm.expectRevert();
        sbt.registerNamespace(keccak256("new"), issuer, controller, "uri");
        vm.expectRevert();
        sbt.registerNamespace(NS, issuer, controller, "changed");
        (IEvolvingSBT.PolicyDefinition memory definition,) = sbt.policyOf(NS, policy);
        assertEq(definition.specificationURI, "ipfs://community-profile-v1");
    }

    function testRelayedInitializeRequiresBothAuthorityAndHolderConsent() public {
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory noConsent = _auth(c, CONTROLLER_KEY, false);
        vm.prank(relayer);
        vm.expectRevert(EvolvingSBT.HolderConsentRequired.selector);
        sbt.applyTransition(c, e, noConsent);
        assertEq(sbt.stateOf(token, NS).revision, 0);
        assertEq(_submit(c, e, CONTROLLER_KEY), 1);
        assertEq(uint8(sbt.stateOf(token, NS).status), uint8(IEvolvingSBT.NamespaceStatus.Active));
    }

    function testHolderCanDirectlyConsentToAuthorizedInitialization() public {
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, CONTROLLER_KEY, false);
        vm.prank(holder);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, NS).revision, 1);
    }

    function testIssuerCannotInitializeWithoutControllerAuthority() public {
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, true);
        vm.prank(holder);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
    }

    function testAppendChangesHeadAndAdvancesExactlyOneRevision() public {
        _initialize();
        bytes32 oldRoot = sbt.stateOf(token, NS).stateRoot;
        _append(1);
        IEvolvingSBT.StateHead memory afterAppend = sbt.stateOf(token, NS);
        assertEq(afterAppend.revision, 2);
        assertNotEq(afterAppend.stateRoot, oldRoot);
        assertEq(afterAppend.policyId, policy);
        assertEq(afterAppend.validUntil, 0);
    }

    function testControllerCannotIssueExperiences() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, CONTROLLER_KEY, false);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, NS).revision, 1);
    }

    function testArbitraryRootRejectedEvenWhenIssuerSignsIt() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        c.nextState.stateRoot = keccak256("invented-root");
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        vm.expectRevert(EvolvingSBT.InvalidNextState.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
        // A rejected update must not leave the experience in duplicate accounting.
        _append(1);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testEvidenceCannotBeReplacedUnderAnExistingAuthorization() public {
        _initialize();
        (IEvolvingSBT.Transition memory c,) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.BadOperationsCommitment.selector);
        sbt.applyTransition(c, abi.encode(_appendEvidence(2)), authorization);
        assertEq(sbt.stateOf(token, NS).revision, 1);
    }

    function testWrongSubjectRejectedEvenWithIssuerSignature() public {
        _initialize();
        EvolvingSBT.Evidence memory wrong = _appendEvidence(1);
        wrong.record.subject = relayer;
        // Preview itself validates subject attribution, before an invalid root can be built.
        vm.expectRevert(EvolvingSBT.WrongSubject.selector);
        sbt.previewTransition(token, NS, wrong, IEvolvingSBT.NamespaceStatus.Active, 0);
    }

    function testDuplicateExperienceCannotBeCreditedWithNewClaimId() public {
        _initialize();
        _append(1);
        EvolvingSBT.Evidence memory duplicate = _appendEvidence(2);
        duplicate.record.experienceId = _record(1).experienceId;
        vm.expectRevert(EvolvingSBT.DuplicateExperience.selector);
        sbt.previewTransition(token, NS, duplicate, IEvolvingSBT.NamespaceStatus.Active, 0);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testDuplicateClaimIdRejectedEvenWithNewExperience() public {
        _initialize();
        _append(1);
        EvolvingSBT.Evidence memory duplicate = _appendEvidence(2);
        duplicate.record.claimId = _record(1).claimId;
        vm.expectRevert(EvolvingSBT.DuplicateClaim.selector);
        sbt.previewTransition(token, NS, duplicate, IEvolvingSBT.NamespaceStatus.Active, 0);
    }

    function testCorrectionMustRetainExperienceIdentity() public {
        _initialize();
        _append(1);
        EvolvingSBT.Evidence memory correction = _appendEvidence(2);
        correction.operation = EvolvingSBT.Operation.Correct;
        correction.record.replaces = _record(1).claimId;
        vm.expectRevert(EvolvingSBT.InvalidCorrection.selector);
        sbt.previewTransition(token, NS, correction, IEvolvingSBT.NamespaceStatus.Active, 0);
    }

    function testCorrectionAppendsReplacementAndOldClaimCannotBeCorrectedAgain() public {
        _initialize();
        _append(1);
        EvolvingSBT.Evidence memory correction = _appendEvidence(2);
        correction.operation = EvolvingSBT.Operation.Correct;
        correction.record.experienceId = _record(1).experienceId;
        correction.record.replaces = _record(1).claimId;
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(correction, IEvolvingSBT.NamespaceStatus.Active, 0);
        _submit(c, e, ISSUER_KEY);
        assertEq(sbt.stateOf(token, NS).revision, 3);
        assertEq(sbt.recordCount(token, NS), 2);
        (EvolvingSBT.Record memory original, bool originalActive) = sbt.recordAt(token, NS, 0);
        (EvolvingSBT.Record memory replacement, bool replacementActive) = sbt.recordAt(token, NS, 1);
        assertEq(keccak256(abi.encode(original)), keccak256(abi.encode(_record(1))));
        assertFalse(originalActive);
        assertTrue(replacementActive);
        assertEq(replacement.replaces, original.claimId);
        assertEq(replacement.experienceId, original.experienceId);
        assertTrue(sbt.isCredited(token, NS, original.experienceId));
        correction.record.claimId = keccak256("third-claim");
        vm.expectRevert(EvolvingSBT.InvalidCorrection.selector);
        sbt.previewTransition(token, NS, correction, IEvolvingSBT.NamespaceStatus.Active, 0);
        EvolvingSBT.Evidence memory duplicate = _appendEvidence(3);
        duplicate.record.experienceId = _record(1).experienceId;
        vm.expectRevert(EvolvingSBT.DuplicateExperience.selector);
        sbt.previewTransition(token, NS, duplicate, IEvolvingSBT.NamespaceStatus.Active, 0);
    }

    function testOnlyOneCompetingUpdateCanUseSamePredecessor() public {
        _initialize();
        (IEvolvingSBT.Transition memory first, bytes memory firstEvidence) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        (IEvolvingSBT.Transition memory second, bytes memory secondEvidence) =
            _change(_appendEvidence(2), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory secondAuth = _auth(second, ISSUER_KEY, false);
        _submit(first, firstEvidence, ISSUER_KEY);
        vm.expectRevert(EvolvingSBT.WrongPredecessor.selector);
        sbt.applyTransition(second, secondEvidence, secondAuth);
        _append(2);
        assertEq(sbt.stateOf(token, NS).revision, 3);
    }

    function testExactSameSignedUpdateCannotBeReplayed() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        sbt.applyTransition(c, e, authorization);
        vm.expectRevert(EvolvingSBT.WrongPredecessor.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testWrongPredecessorHashRejectedEvenWithCorrectRevisionAndSignature() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        c.expectedStateHash = keccak256("wrong-predecessor");
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.WrongPredecessor.selector);
        sbt.applyTransition(c, e, authorization);
    }

    function testExpiredAndZeroDeadlinesReject() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        c.deadline = uint64(block.timestamp - 1);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.DeadlineExpired.selector);
        sbt.applyTransition(c, e, authorization);
        c.deadline = 0;
        authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.DeadlineExpired.selector);
        sbt.applyTransition(c, e, authorization);
    }

    function testDeadlineInclusiveBoundarySucceeds() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        c.deadline = uint64(block.timestamp);
        _submit(c, e, ISSUER_KEY);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testPauseResumeDoesNotReactivatePendingAuthorization() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.prank(controller);
        sbt.setPolicyControls(NS, false, true);
        vm.expectRevert(EvolvingSBT.UpdatesDisabled.selector);
        sbt.applyTransition(c, e, authorization);
        vm.prank(controller);
        sbt.setPolicyControls(NS, true, true);
        (, IEvolvingSBT.PolicyStatus memory p) = sbt.policyOf(NS, policy);
        assertEq(p.epoch, 3);
        vm.expectRevert(EvolvingSBT.EpochMismatch.selector);
        sbt.applyTransition(c, e, authorization);
        _append(1);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testUseControlsAreIndependentFromUpdateControls() public {
        _initialize();
        assertTrue(sbt.isUsable(token, NS));
        vm.prank(controller);
        sbt.setPolicyControls(NS, true, false);
        (, IEvolvingSBT.PolicyStatus memory p) = sbt.policyOf(NS, policy);
        assertTrue(p.updatesEnabled);
        assertFalse(p.usesEnabled);
        assertFalse(sbt.isUsable(token, NS));
        _append(1);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testPolicyControlsRequireNamespaceController() public {
        vm.prank(issuer);
        vm.expectRevert(EvolvingSBT.NotController.selector);
        sbt.setPolicyControls(NS, false, false);
        vm.prank(vm.addr(CONTROLLER_B_KEY));
        vm.expectRevert(EvolvingSBT.NotController.selector);
        sbt.setPolicyControls(NS, false, false);
    }

    function testTwoNamespacesRemainIndependent() public {
        _initialize();
        _append(1);
        bytes32 preserved = sbt.hashState(sbt.stateOf(token, NS));
        (IEvolvingSBT.Transition memory c, bytes memory e) = _change(
            sbt,
            token,
            NS_B,
            policyB,
            _lifecycle(EvolvingSBT.Operation.Initialize),
            IEvolvingSBT.NamespaceStatus.Active,
            0
        );
        _submit(c, e, CONTROLLER_B_KEY);
        (c, e) =
            _change(sbt, token, NS_B, policyB, _appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory wrongAuthority = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, wrongAuthority);
        _submit(c, e, ISSUER_B_KEY);
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), preserved);
        assertEq(sbt.stateOf(token, NS_B).revision, 2);
    }

    function testIssuerCannotSuspendOrResume() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Suspend), IEvolvingSBT.NamespaceStatus.Suspended, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        _submit(c, e, CONTROLLER_KEY);
        (c, e) = _change(_lifecycle(EvolvingSBT.Operation.Resume), IEvolvingSBT.NamespaceStatus.Active, 0);
        authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        _submit(c, e, CONTROLLER_KEY);
        assertEq(sbt.stateOf(token, NS).revision, 3);
    }

    function testAppendCannotResumeOrExtendValidity() public {
        _initialize();
        _setStatus(EvolvingSBT.Operation.Suspend, IEvolvingSBT.NamespaceStatus.Suspended);
        vm.expectRevert(EvolvingSBT.InvalidOperation.selector);
        sbt.previewTransition(token, NS, _appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        _setStatus(EvolvingSBT.Operation.Resume, IEvolvingSBT.NamespaceStatus.Active);
        vm.expectRevert(EvolvingSBT.InvalidOperation.selector);
        sbt.previewTransition(
            token, NS, _appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, uint64(block.timestamp + 100)
        );
    }

    function testRevocationIsTerminalAndNamespaceCannotBeReset() public {
        _initialize();
        _setStatus(EvolvingSBT.Operation.Revoke, IEvolvingSBT.NamespaceStatus.Revoked);
        vm.expectRevert(EvolvingSBT.NamespaceTerminated.selector);
        sbt.previewTransition(
            token, NS, _lifecycle(EvolvingSBT.Operation.Resume), IEvolvingSBT.NamespaceStatus.Active, 0
        );
        vm.expectRevert(EvolvingSBT.NamespaceTerminated.selector);
        sbt.previewTransition(
            token, NS, _lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0
        );
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testUnsupportedPolicyMigrationRejected() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        c.nextState.policyId = policyB;
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.MigrationUnsupported.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, NS).policyId, policy);
    }

    function testChainDomainPreventsCrossChainReplay() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        uint256 originalChain = block.chainid;
        vm.chainId(originalChain + 1);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        vm.chainId(originalChain);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, NS).revision, 2);
    }

    function testContractDomainPreventsCrossDeploymentReplay() public {
        EvolvingSBT other = new EvolvingSBT(address(this));
        bytes32 otherPolicy = other.registerNamespace(NS, issuer, controller, "ipfs://community-profile-v1");
        vm.prank(holder);
        uint256 otherToken = other.mint();
        (IEvolvingSBT.Transition memory c, bytes memory e) = _change(
            other,
            otherToken,
            NS,
            otherPolicy,
            _lifecycle(EvolvingSBT.Operation.Initialize),
            IEvolvingSBT.NamespaceStatus.Active,
            0
        );
        // These signatures cover the exact target request but the wrong verifying contract.
        bytes memory wrongDomain = _auth(c, CONTROLLER_KEY, true);
        vm.prank(relayer);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        other.applyTransition(c, e, wrongDomain);
        bytes32 digest = other.transitionDigest(c);
        bytes memory correctDomain =
            abi.encode(EvolvingSBT.Authorization(_sig(digest, CONTROLLER_KEY), _sig(digest, HOLDER_KEY)));
        vm.prank(relayer);
        other.applyTransition(c, e, correctDomain);
        assertEq(other.stateOf(otherToken, NS).revision, 1);
    }

    function testSignatureBindsCredentialId() public {
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, CONTROLLER_KEY, true);
        vm.prank(holder);
        uint256 secondToken = sbt.mint();
        c.tokenId = secondToken;
        vm.prank(relayer);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(secondToken, NS).revision, 0);
    }

    function testSignatureBindsNamespaceEvenWithSameAuthorities() public {
        bytes32 twinNS = keccak256("same-authorities-different-namespace");
        bytes32 twinPolicy = sbt.registerNamespace(twinNS, issuer, controller, "ipfs://twin");
        (IEvolvingSBT.Transition memory c, bytes memory e) = _change(
            sbt,
            token,
            twinNS,
            twinPolicy,
            _lifecycle(EvolvingSBT.Operation.Initialize),
            IEvolvingSBT.NamespaceStatus.Active,
            0
        );
        IEvolvingSBT.Transition memory signatureRequest = c;
        signatureRequest.namespace = NS;
        bytes memory authorization = _auth(signatureRequest, CONTROLLER_KEY, true);
        c.namespace = twinNS;
        vm.prank(relayer);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, twinNS).revision, 0);
    }

    function testMalformedEvidenceAndAuthorizationRejectWithoutStateChange() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.expectRevert();
        sbt.applyTransition(c, hex"deadbeef", authorization);
        vm.expectRevert();
        sbt.applyTransition(c, e, hex"deadbeef");
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
    }

    function testFuzzWrongSignerCannotAppend(uint256 signerKey) public {
        signerKey = bound(signerKey, 1, type(uint128).max);
        vm.assume(signerKey != ISSUER_KEY);
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, signerKey, false);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, authorization);
        assertEq(sbt.stateOf(token, NS).revision, 1);
    }

    function testFuzzAppendSequencesAdvanceRevision(uint8 count) public {
        count = uint8(bound(count, 1, 8));
        _initialize();
        for (uint256 i = 1; i <= count; i++) {
            _append(i);
            assertEq(sbt.stateOf(token, NS).revision, i + 1);
            assertEq(sbt.stateOf(token, NS_B).revision, 0);
        }
    }

    function testTypedDataDigestHasIndependentReproducibleEncoding() public {
        (IEvolvingSBT.Transition memory c, bytes memory evidence) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes32 domain = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("EvolvingSBT"),
                keccak256("1"),
                block.chainid,
                address(sbt)
            )
        );
        bytes32 nextHash = keccak256(
            abi.encode(
                keccak256("StateUpdate(bytes32 stateRoot,bytes32 policyId,uint8 status,uint64 validUntil)"),
                c.nextState.stateRoot,
                c.nextState.policyId,
                uint8(c.nextState.status),
                c.nextState.validUntil
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Transition(uint256 tokenId,bytes32 namespace,uint64 expectedRevision,bytes32 expectedStateHash,uint64 sourcePolicyEpoch,uint64 targetPolicyEpoch,StateUpdate nextState,bytes32 operationsCommitment,uint64 deadline)StateUpdate(bytes32 stateRoot,bytes32 policyId,uint8 status,uint64 validUntil)"
                ),
                c.tokenId,
                c.namespace,
                c.expectedRevision,
                c.expectedStateHash,
                c.sourcePolicyEpoch,
                c.targetPolicyEpoch,
                nextHash,
                c.operationsCommitment,
                c.deadline
            )
        );
        bytes32 expected = keccak256(abi.encodePacked(hex"1901", domain, structHash));
        assertEq(sbt.transitionDigest(c), expected);
        bytes memory authorization = abi.encode(
            EvolvingSBT.Authorization(_sig(expected, CONTROLLER_KEY), _sig(expected, HOLDER_KEY))
        );
        vm.prank(relayer);
        sbt.applyTransition(c, evidence, authorization);
        assertEq(sbt.stateOf(token, NS).revision, 1);
    }

    function testStateRootsAndStateHashesHaveIndependentReproducibleEncoding() public {
        bytes32 profile = keccak256("evolving-sbt.signed-growth.v1");
        _initialize();
        bytes32 expectedRoot = keccak256(abi.encode(profile, bytes32(0), uint64(0), bytes32(0), bytes32(0)));
        assertEq(sbt.stateOf(token, NS).stateRoot, expectedRoot);
        EvolvingSBT.Record memory original = _record(1);
        _append(1);
        bytes32 recordsRoot = keccak256(abi.encode(bytes32(0), keccak256(abi.encode(original))));
        bytes32 statuses = keccak256(abi.encode(bytes32(0), original.claimId, true));
        bytes32 credited = keccak256(abi.encode(bytes32(0), original.experienceId));
        expectedRoot = keccak256(abi.encode(profile, recordsRoot, uint64(1), statuses, credited));
        assertEq(sbt.stateOf(token, NS).stateRoot, expectedRoot);

        EvolvingSBT.Evidence memory correction = _appendEvidence(2);
        correction.operation = EvolvingSBT.Operation.Correct;
        correction.record.replaces = original.claimId;
        correction.record.experienceId = original.experienceId;
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(correction, IEvolvingSBT.NamespaceStatus.Active, 0);
        _submit(c, e, ISSUER_KEY);
        recordsRoot = keccak256(abi.encode(recordsRoot, keccak256(abi.encode(correction.record))));
        statuses = keccak256(abi.encode(bytes32(0), original.claimId, false));
        statuses = keccak256(abi.encode(statuses, correction.record.claimId, true));
        expectedRoot = keccak256(abi.encode(profile, recordsRoot, uint64(2), statuses, credited));
        IEvolvingSBT.StateHead memory head = sbt.stateOf(token, NS);
        assertEq(head.stateRoot, expectedRoot);
        assertEq(
            sbt.hashState(head),
            keccak256(
                abi.encode(
                    uint64(3), expectedRoot, policy, uint8(IEvolvingSBT.NamespaceStatus.Active), uint64(0)
                )
            )
        );
    }

    function testRecordCapIncludesCorrectionsAndDoesNotPreventRevocation() public {
        _initialize();
        for (uint256 i = 1; i <= 31; i++) {
            _append(i);
        }
        EvolvingSBT.Evidence memory correction = _appendEvidence(32);
        correction.operation = EvolvingSBT.Operation.Correct;
        correction.record.replaces = _record(1).claimId;
        correction.record.experienceId = _record(1).experienceId;
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(correction, IEvolvingSBT.NamespaceStatus.Active, 0);
        _submit(c, e, ISSUER_KEY);
        assertEq(sbt.recordCount(token, NS), 32);
        vm.expectRevert(EvolvingSBT.RecordLimitReached.selector);
        sbt.previewTransition(token, NS, _appendEvidence(33), IEvolvingSBT.NamespaceStatus.Active, 0);
        correction.record.claimId = keccak256("correction-after-cap");
        correction.record.replaces = _record(2).claimId;
        correction.record.experienceId = _record(2).experienceId;
        vm.expectRevert(EvolvingSBT.RecordLimitReached.selector);
        sbt.previewTransition(token, NS, correction, IEvolvingSBT.NamespaceStatus.Active, 0);
        _setStatus(EvolvingSBT.Operation.Revoke, IEvolvingSBT.NamespaceStatus.Revoked);
        assertEq(sbt.stateOf(token, NS).revision, 34);
        assertFalse(sbt.isUsable(token, NS));
    }

    function testExpiryIsCheckedAtUseTimeAndOnlyControllerCanExtend() public {
        uint64 expiry = uint64(block.timestamp + 100);
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, expiry);
        _submit(c, e, CONTROLLER_KEY);
        vm.warp(expiry);
        assertTrue(sbt.isUsable(token, NS));
        vm.warp(uint256(expiry) + 1);
        assertFalse(sbt.isUsable(token, NS));
        (c, e) = _change(
            _lifecycle(EvolvingSBT.Operation.Extend), IEvolvingSBT.NamespaceStatus.Active, expiry + 100
        );
        bytes memory wrongAuthority = _auth(c, ISSUER_KEY, false);
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, wrongAuthority);
        _submit(c, e, CONTROLLER_KEY);
        assertTrue(sbt.isUsable(token, NS));
        assertEq(sbt.stateOf(token, NS).validUntil, expiry + 100);
        vm.expectRevert(EvolvingSBT.InvalidValidity.selector);
        sbt.previewTransition(
            token, NS, _lifecycle(EvolvingSBT.Operation.Extend), IEvolvingSBT.NamespaceStatus.Active, 0
        );
    }

    function testExpiryOfIndividualRecordDoesNotChangeNamespaceValidity() public {
        _initialize();
        EvolvingSBT.Evidence memory append = _appendEvidence(1);
        append.record.validUntil = uint64(block.timestamp + 20);
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(append, IEvolvingSBT.NamespaceStatus.Active, 0);
        _submit(c, e, ISSUER_KEY);
        vm.warp(block.timestamp + 21);
        assertTrue(sbt.isUsable(token, NS));
        (EvolvingSBT.Record memory record, bool active) = sbt.recordAt(token, NS, 0);
        assertTrue(active); // Active means not superseded; applications must check record expiry.
        assertGt(block.timestamp, record.validUntil);
        assertTrue(sbt.isCredited(token, NS, record.experienceId));
    }

    function testSuspendResumePreservesExperiencesAndDeduplication() public {
        _initialize();
        _append(1);
        bytes32 root = sbt.stateOf(token, NS).stateRoot;
        _setStatus(EvolvingSBT.Operation.Suspend, IEvolvingSBT.NamespaceStatus.Suspended);
        assertFalse(sbt.isUsable(token, NS));
        assertEq(sbt.stateOf(token, NS).stateRoot, root);
        _setStatus(EvolvingSBT.Operation.Resume, IEvolvingSBT.NamespaceStatus.Active);
        assertTrue(sbt.isUsable(token, NS));
        assertEq(sbt.stateOf(token, NS).stateRoot, root);
        assertEq(sbt.recordCount(token, NS), 1);
        EvolvingSBT.Evidence memory duplicate = _appendEvidence(2);
        duplicate.record.experienceId = _record(1).experienceId;
        vm.expectRevert(EvolvingSBT.DuplicateExperience.selector);
        sbt.previewTransition(token, NS, duplicate, IEvolvingSBT.NamespaceStatus.Active, 0);
    }

    function testRejectedCorrectionLeavesNoPartialSupersessionOrDedupChange() public {
        _initialize();
        _append(1);
        EvolvingSBT.Evidence memory correction = _appendEvidence(2);
        correction.operation = EvolvingSBT.Operation.Correct;
        correction.record.replaces = _record(1).claimId;
        correction.record.experienceId = _record(1).experienceId;
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(correction, IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory invalidAuth = _auth(c, CONTROLLER_KEY, false);
        bytes32 beforeHash = sbt.hashState(sbt.stateOf(token, NS));
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, invalidAuth);
        assertEq(sbt.hashState(sbt.stateOf(token, NS)), beforeHash);
        assertEq(sbt.recordCount(token, NS), 1);
        (, bool active) = sbt.recordAt(token, NS, 0);
        assertTrue(active);
        assertTrue(sbt.isCredited(token, NS, correction.record.experienceId));
        _submit(c, e, ISSUER_KEY);
        assertEq(sbt.recordCount(token, NS), 2);
    }

    function testPolicyNoOpDoesNotInvalidateAuthorizationButUseChangeDoes() public {
        _initialize();
        (IEvolvingSBT.Transition memory c, bytes memory e) =
            _change(_appendEvidence(1), IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory authorization = _auth(c, ISSUER_KEY, false);
        vm.prank(controller);
        sbt.setPolicyControls(NS, true, true);
        (, IEvolvingSBT.PolicyStatus memory controls) = sbt.policyOf(NS, policy);
        assertEq(controls.epoch, 1);
        sbt.applyTransition(c, e, authorization);
        (c, e) = _change(_appendEvidence(2), IEvolvingSBT.NamespaceStatus.Active, 0);
        authorization = _auth(c, ISSUER_KEY, false);
        vm.prank(controller);
        sbt.setPolicyControls(NS, true, false);
        vm.expectRevert(EvolvingSBT.EpochMismatch.selector);
        sbt.applyTransition(c, e, authorization);
    }

    function testLifecycleCannotSmuggleRecordsAndActiveNamespaceCannotReset() public {
        EvolvingSBT.Evidence memory e = _appendEvidence(1);
        e.operation = EvolvingSBT.Operation.Initialize;
        vm.expectRevert(EvolvingSBT.InvalidRecord.selector);
        sbt.previewTransition(token, NS, e, IEvolvingSBT.NamespaceStatus.Active, 0);
        _initialize();
        vm.expectRevert(EvolvingSBT.InvalidOperation.selector);
        sbt.previewTransition(
            token, NS, _lifecycle(EvolvingSBT.Operation.Initialize), IEvolvingSBT.NamespaceStatus.Active, 0
        );
    }

    function testERC1271HolderConsentAndIssuerAuthorizationAreCheckedLive() public {
        Mock1271Wallet holderWallet = new Mock1271Wallet(holder);
        Mock1271Wallet issuerWallet = new Mock1271Wallet(issuer);
        bytes32 smartNS = keccak256("contract-wallets");
        bytes32 smartPolicy =
            sbt.registerNamespace(smartNS, address(issuerWallet), controller, "ipfs://smart-wallet");
        vm.prank(address(holderWallet));
        uint256 smartToken = sbt.mint();
        (IEvolvingSBT.Transition memory c, bytes memory e) = _change(
            sbt,
            smartToken,
            smartNS,
            smartPolicy,
            _lifecycle(EvolvingSBT.Operation.Initialize),
            IEvolvingSBT.NamespaceStatus.Active,
            0
        );
        _submit(c, e, CONTROLLER_KEY);
        EvolvingSBT.Evidence memory append = _appendEvidence(1);
        append.record.subject = address(holderWallet);
        (c, e) =
            _change(sbt, smartToken, smartNS, smartPolicy, append, IEvolvingSBT.NamespaceStatus.Active, 0);
        _submit(c, e, ISSUER_KEY);
        append.record = _record(2);
        append.record.subject = address(holderWallet);
        (c, e) =
            _change(sbt, smartToken, smartNS, smartPolicy, append, IEvolvingSBT.NamespaceStatus.Active, 0);
        bytes memory pending = _auth(c, ISSUER_KEY, false);
        issuerWallet.disableSignatures();
        vm.expectRevert(EvolvingSBT.InvalidAuthorization.selector);
        sbt.applyTransition(c, e, pending);
        assertEq(sbt.stateOf(smartToken, smartNS).revision, 2);
    }

    function testMintReceiverCannotReenterMintOrBurn() public {
        ReentrantMintReceiver receiver = new ReentrantMintReceiver();
        uint256 minted = receiver.mint(sbt);
        assertFalse(receiver.nestedMintSucceeded());
        assertFalse(receiver.nestedBurnSucceeded());
        assertFalse(receiver.nestedTransferSucceeded());
        assertEq(sbt.ownerOf(minted), address(receiver));
        assertTrue(sbt.locked(minted));
        assertEq(sbt.balanceOf(address(receiver)), 1);
    }

    function testFuzzCorrectionChainsPreserveHistoryAndExperienceDedup(uint8 corrections) public {
        corrections = uint8(bound(corrections, 1, 8));
        _initialize();
        _append(1);
        bytes32 experience = _record(1).experienceId;
        bytes32 lastClaim = _record(1).claimId;
        for (uint256 i = 1; i <= corrections; i++) {
            EvolvingSBT.Evidence memory correction = _appendEvidence(i + 1);
            correction.operation = EvolvingSBT.Operation.Correct;
            correction.record.experienceId = experience;
            correction.record.replaces = lastClaim;
            (IEvolvingSBT.Transition memory c, bytes memory e) =
                _change(correction, IEvolvingSBT.NamespaceStatus.Active, 0);
            _submit(c, e, ISSUER_KEY);
            lastClaim = correction.record.claimId;
            assertTrue(sbt.isCredited(token, NS, experience));
            assertEq(sbt.stateOf(token, NS).revision, i + 2);
            assertEq(sbt.recordCount(token, NS), i + 1);
        }
        for (uint256 i; i <= corrections; i++) {
            (EvolvingSBT.Record memory record, bool active) = sbt.recordAt(token, NS, i);
            assertEq(record.experienceId, experience);
            assertEq(active, i == corrections);
        }
        EvolvingSBT.Evidence memory duplicate = _appendEvidence(100);
        duplicate.record.experienceId = experience;
        vm.expectRevert(EvolvingSBT.DuplicateExperience.selector);
        sbt.previewTransition(token, NS, duplicate, IEvolvingSBT.NamespaceStatus.Active, 0);
    }
}
