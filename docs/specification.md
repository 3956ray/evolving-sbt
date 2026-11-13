# Experimental v0.1 implementation specification

This document describes the concrete signed growth profile in this repository. The [candidate interface](../src/interfaces/IEvolvingSBT.sol) preserves the published pre-ERC ABI. The profile's registration, evidence, authorization, and inspection helpers are implementation-specific; they are not proposed universal additions to the core ABI.

The words **must** and **reject** below describe the behavior of this implementation. They do not claim a finalized ERC requirement. The [discussion](discussion.md) covers additional profiles that v0.1 does not implement.

## Deployment and credential lifecycle

`EvolvingSBT(admin)` deploys a concrete, non-upgradeable implementation. It uses an ERC-721 token base and reports ERC-5192 permanent locking. No external verifier plug-in or upgradeable proxy is installed by this reference implementation.

`mint()` creates a credential owned by the caller. This is the issuance-consent mechanism: another account cannot mint a credential to a holder through this function. Token identifiers are assigned sequentially and are never reused. There is no one-person or one-account uniqueness guarantee.

`burn(tokenId)` requires the current holder. Burning makes the credential unusable, without permitting its identifier or previous namespace revisions to be reinitialized. Transferring a live token to another account is rejected, including through safe-transfer functions. Minting and burning are distinct from an account-to-account transfer.

## Namespaces and policies

The administrator registers a namespace with:

```text
registerNamespace(namespace, issuer, controller, specificationURI)
```

Registration requires a nonzero, previously unregistered namespace and two nonzero, distinct authority addresses. It returns the immutable policy identifier. v0.1 supports one immutable policy per namespace. The issuer and controller addresses are fixed at registration. A request changing the policy is rejected; migration and authority-address rotation are not implemented.

The `PolicyDefinition` identifies the concrete schema, verification rules, configuration, and authorization rules. Its verifier is this implementation itself. The policy does not hand execution to an arbitrary caller-supplied verifier. `specificationURI` is a discovery location, not mutable authority over the policy's meaning.

The issuer recognizes appended and corrected experiences. The controller manages namespace initialization, suspension, resumption, revocation, validity extension, and live policy controls. Their addresses must differ, though this cannot establish that different people control them.

The contract owner registers new namespaces but receives no automatic authority to modify an existing namespace's policy or state. A policy definition commits to authority addresses, not to their future account implementation or signing behavior. ERC-1271 authorities may change their validation behavior or account control outside this contract; applications must include that trust assumption in their policy assessment.

`setPolicyControls(namespace, updatesEnabled, usesEnabled)` requires the registered controller. The epoch starts at one and increases when controls change. A no-op call does not manufacture a new epoch. The epoch cannot wrap around or reset. Pending signatures bound to an earlier epoch cannot be reused after pausing and resuming.

- `updatesEnabled` controls acceptance of new transitions.
- `usesEnabled` signals whether consumers may rely on the policy.

Consumers must consider both values according to their purpose. An accepted state head alone does not establish present application eligibility.

## Candidate state interface

A state is scoped by `(chainId, credentialContract, tokenId, namespace)` and is represented by:

```solidity
struct StateHead {
    uint64 revision;
    bytes32 stateRoot;
    bytes32 policyId;
    NamespaceStatus status;
    uint64 validUntil;
}
```

The enum order is `Uninitialized`, `Active`, `Suspended`, `Revoked`. A registered but uninitialized namespace has the canonical all-zero head. Initialization is the only operation that leaves `Uninitialized`.

`stateOf` returns the accepted head. `policyOf` returns both the immutable definition and current controls. `applyTransition` checks the predecessor, policies, epochs, evidence, authority, and requested result before committing a new revision. Its return value is the assigned revision. `StateTransitioned` reports the accepted transition.

The caller supplies `expectedRevision` and `expectedStateHash`. Both must match the current head. The contract assigns exactly the previous revision plus one; it does not accept a caller-selected revision. The namespace cannot be cleared or return to `Uninitialized`.

For initialization, `sourcePolicyEpoch` is zero and `targetPolicyEpoch` is the registered current epoch. For subsequent transitions, both are the same current policy epoch. An unsupported target policy is rejected.

The request has a nonzero deadline, and submission at `block.timestamp == deadline` is accepted. It binds the entire `StateUpdate`, operation commitment, and current policy epochs in addition to the exact predecessor and identity domain. Validation and mutation are atomic: failure does not leave an updated root, record, counter, or event.

## Transparent growth evidence

Each transition carries exactly one operation:

```solidity
enum Operation {
    Initialize,
    Append,
    Correct,
    Suspend,
    Resume,
    Revoke,
    Extend
}

struct Record {
    bytes32 claimId;
    bytes32 experienceId;
    address subject;
    bytes32 contentHash;
    uint64 validUntil;
    bytes32 replaces;
}

struct Evidence {
    Operation operation;
    Record record;
}
```

The ABI encoding is `abi.encode(Evidence)`. `operationsCommitment` is `keccak256(evidence)`, binding the actual submitted evidence bytes. This is Solidity ABI encoding, not packed encoding, JSON, or an Ethereum personal-sign message.

`claimId` identifies one accepted claim. `experienceId` identifies the underlying experience for accounting. Both IDs and `contentHash` must be nonzero. `subject` must equal the credential's current holder account. `contentHash` commits to the recognized content; it does not supply a universal meaning for that content, authenticate external source data, or require the content itself to be published. `validUntil` is the record's validity bound. `replaces` links a correction to a previously accepted claim.

The profile is bounded to **32 accepted records per credential and namespace, including corrections**. A correction appends a record and consumes capacity. At capacity, no further append or correction is possible; deployments must reserve headroom if they need later corrections. Namespace lifecycle operations remain possible. The lifetime bound makes the first public implementation small and inspectable; it is not an unbounded accumulator.

All submitted evidence is public calldata. Stored commitments, record inspection, subjects, and transition events are observable. A `contentHash` is not a hiding commitment or a privacy guarantee.

## Operations and authority

| Operation | Authority | Required effect |
|---|---|---|
| Initialize | Controller, plus holder consent | Revision zero to `Active`; namespace expiry is zero or strictly greater than the current timestamp. |
| Append | Issuer | Requires `Active`; append a recognized record for a previously uncredited experience, preserving namespace status and expiry. |
| Correct | Issuer | Requires `Active`; append a replacement for a nonsuperseded claim, retain its experience identity, and supersede the replaced claim; preserve namespace status and expiry. |
| Suspend | Controller | `Active` to `Suspended`, preserving expiry and history. |
| Resume | Controller | `Suspended` to `Active`, preserving expiry and history. |
| Revoke | Controller | `Active` or `Suspended` to terminal `Revoked`, preserving expiry and history. |
| Extend | Controller | Preserve status and history; the existing and new expiry must both be nonzero, with the new expiry strictly greater than both the existing expiry and the current timestamp. |

Ordinary issuer authority cannot remove suspension, extend namespace validity, or change policy identity. Lifecycle operations do not invent accepted experience records. Revocation is terminal for this namespace; a later append or resume cannot restore it.

Initialization and every lifecycle operation require the evidence's `record` to have all-zero fields. An ordinary append requires `replaces == bytes32(0)`. An expired namespace whose status remains `Active` may still accept append and correction operations when updates are enabled; these operations do not extend its expiry or make it usable. An already expired record may be admitted as history. Record expiry is an application-time validity check, not a condition of historical admission. Resuming an expired namespace also does not renew it. `Extend` may renew an expired finite validity bound, but cannot turn it into unlimited validity or alter an already unlimited bound.

Initialization requires consent from the holder, either through the holder's direct call or the profile's holder signature. Relayers can submit appropriately authorized transitions; being the submitter grants no issuer or controller authority.

The authorization bytes encode:

```solidity
struct Authorization {
    bytes authoritySignature;
    bytes holderSignature;
}
```

The authorization bytes are `abi.encode(Authorization)`. Authority signatures authenticate the operation-specific authority over the complete transition using the EIP-712 digest defined below. An initial holder signature, when needed, approves the same transition. A holder signature is not a substitute for an issuer or controller signature. Its bytes may be empty for a holder-submitted initialization, and are not checked for other operations.

The implementation uses OpenZeppelin `SignatureChecker.isValidSignatureNow`, supporting EOA signatures and ERC-1271 contract signatures. Contract-signature validity is evaluated when the transition is submitted. It may differ from validity when the signature was prepared. This is not an implementation of coordinated account recovery or authorization epochs for account-level changes.

## Historical preservation and accounting

Accepted records remain in insertion order. An append extends this history and cannot replace an earlier record. Claim identifiers cannot be reused in the same credential and namespace.

A correction must refer to an existing, nonsuperseded claim and retain its stable experience identifier. The original record remains in the history, but its local active status changes. The replacement receives a new claim identifier. A later correction can replace that replacement. A different claim ID or signature cannot obtain another append credit for the same `experienceId`.

The issuer must assign experience identifiers canonically. The contract cannot infer that two different identifiers describe the same real-world action. A dishonest issuer can recognize false experiences or assign multiple identifiers to one source; the signed recognition profile does not remove this trust boundary.

Deduplication is scoped to the credential and namespace. It is not global proof of human uniqueness. The same underlying source may have meaning in different namespaces or applications, whose policies must define their own accounting boundaries.

Applications must inspect the current local record status as well as historical inclusion. The `active` boolean returned by `recordAt` means only **not superseded**; it does not include record expiry, namespace expiry, policy controls, or independent revocation. Superseded records remain historical evidence but cannot be treated as independent current experiences. `isCredited` records whether an experience has ever been appended in this accounting scope; correction, expiry, suspension, or revocation does not reset it.

## Exact encodings and commitments

All hashes in this section use Ethereum Keccak-256. Unless explicitly stated otherwise, tuples use Solidity `abi.encode`, not `abi.encodePacked`. `bytes32`, `address`, `bool`, and integer fields retain the types declared by the contract. The two enums use their zero-based numeric values and ABI `uint8` encoding.

The profile constants are the Keccak-256 hashes of these exact UTF-8 strings:

```text
PROFILE_ID: evolving-sbt.signed-growth.v1
SCHEMA_ID: Record(bytes32 claimId,bytes32 experienceId,address subject,bytes32 contentHash,uint64 validUntil,bytes32 replaces)
RULES_HASH: evolving-sbt.signed-growth.v1:bounded32:append-correct:issuer:controller:no-migration
```

For a deployed contract `credential`, namespace registration computes:

```solidity
verifierConfigHash = keccak256(abi.encode(
    PROFILE_ID, uint256(32), issuer, controller
));
authorizationHash = keccak256(abi.encode(issuer, controller));
policyId = keccak256(abi.encode(
    namespace,
    SCHEMA_ID,
    RULES_HASH,
    credential,
    verifierConfigHash,
    authorizationHash,
    keccak256(bytes(specificationURI))
));
```

The policy identifier includes the concrete verifier address. It does not itself include the chain ID; a policy reference must retain its chain and contract context. The signed transition domain includes both.

The canonical state and record hashes are:

```solidity
stateHash = keccak256(abi.encode(StateHead(
    revision, stateRoot, policyId, status, validUntil
)));
recordHash = keccak256(abi.encode(Record(
    claimId, experienceId, subject, contentHash, validUntil, replaces
)));
```

These two helper hashes do not add an EIP-712 type prefix. They must not be substituted for EIP-712 struct hashes. In particular, the predecessor hash of an uninitialized namespace is the hash of its all-zero `StateHead` encoding, **not** `bytes32(0)`.

The growth commitment is an ordered hash-chain construction with a recomputed local-status commitment. It is not a Merkle tree and this version exposes no compact inclusion-proof API. For the accepted records in insertion order, define:

```text
recordsRoot[0] = bytes32(0)
recordsRoot[i + 1] = keccak256(abi.encode(recordsRoot[i], hashRecord(record[i])))

statusRoot[0] = bytes32(0)
statusRoot[i + 1] = keccak256(abi.encode(
    statusRoot[i], record[i].claimId, !superseded[record[i].claimId]
))
```

For the experience identifiers admitted by `Append` operations in order, define:

```text
creditedActionsRoot[0] = bytes32(0)
creditedActionsRoot[j + 1] = keccak256(abi.encode(
    creditedActionsRoot[j], appendedExperienceId[j]
))
```

`Correct` extends `recordsRoot`, marks its target superseded in `statusRoot`, and appends the new claim with nonsuperseded status. It does not extend `creditedActionsRoot`. Let `count` be the total accepted record count, including corrections. The resulting growth root is:

```solidity
stateRoot = keccak256(abi.encode(
    PROFILE_ID,
    recordsRoot,
    uint64(count),
    statusRoot,
    creditedActionsRoot
));
```

Initialization commits the empty-growth root produced by that formula, which differs from the uninitialized head's zero `stateRoot`. Subsequent lifecycle operations preserve the growth root. Their revision, status, or expiry changes still change the complete state hash.

## Exact transition signing

The full `Transition` and nested `StateUpdate` declarations are in the [candidate ABI](../src/interfaces/IEvolvingSBT.sol). The EIP-712 domain is:

```text
name: EvolvingSBT
version: 1
chainId: current execution chain ID
verifyingContract: deployed EvolvingSBT address
```

The type hashes are Keccak-256 of these exact strings, including the nested type appended to the transition type:

```text
StateUpdate(bytes32 stateRoot,bytes32 policyId,uint8 status,uint64 validUntil)
Transition(uint256 tokenId,bytes32 namespace,uint64 expectedRevision,bytes32 expectedStateHash,uint64 sourcePolicyEpoch,uint64 targetPolicyEpoch,StateUpdate nextState,bytes32 operationsCommitment,uint64 deadline)StateUpdate(bytes32 stateRoot,bytes32 policyId,uint8 status,uint64 validUntil)
```

Construct the digest as follows:

```solidity
nextHash = keccak256(abi.encode(
    STATE_UPDATE_TYPEHASH,
    change.nextState.stateRoot,
    change.nextState.policyId,
    change.nextState.status,
    change.nextState.validUntil
));
transitionStructHash = keccak256(abi.encode(
    TRANSITION_TYPEHASH,
    change.tokenId,
    change.namespace,
    change.expectedRevision,
    change.expectedStateHash,
    change.sourcePolicyEpoch,
    change.targetPolicyEpoch,
    nextHash,
    change.operationsCommitment,
    change.deadline
));
domainSeparator = keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    keccak256(bytes("EvolvingSBT")),
    keccak256(bytes("1")),
    block.chainid,
    address(credential)
));
digest = keccak256(abi.encodePacked(hex"1901", domainSeparator, transitionStructHash));
```

The authority and any required holder sign this digest, without an Ethereum personal-sign prefix. `operationsCommitment = keccak256(evidence)` binds the exact evidence bytes supplied to `applyTransition`. The `StateTransitioned.transitionId` emitted on success is this digest. It is an identifier for the signed state update, not a one-time application entitlement identifier.

## Client construction and discovery

The concrete implementation provides helpers for constructing and checking requests:

- `previewTransition(...)` returns the deterministic `StateUpdate` for current state, concrete evidence, requested namespace status, and requested namespace expiry. It validates operation rules, but does not build the complete `Transition`, validate signatures, check live policy controls, or check a deadline.
- `hashState(head)` computes the canonical hash of a state head.
- `transitionDigest(change)` computes the signing digest for a request.

A preview is not a reservation. Another valid transition can be accepted before submission; the stale preview then fails the exact-predecessor check and must be rebuilt and reauthorized.

To prepare a request, a client reads the current head and policy epoch, chooses and ABI-encodes the evidence, derives the next state, fills the predecessor and epoch fields, chooses a nonzero deadline, and obtains the required signatures over the exact digest. It then ABI-encodes `Authorization` and submits all three arguments. A relayer can perform submission without acquiring authority over the transition.

`stateOf`, `recordCount`, `recordAt`, and `isCredited` require a live credential and a registered namespace. They revert for nonexistent or burned credentials and for unknown namespaces. `recordAt` additionally reverts for an out-of-range index. `policyOf` and `policyIdOf` reject unknown namespaces, and `policyOf` rejects any policy ID other than the registered one. `isUsable` returns `false` for a nonexistent or burned credential; for a live credential, an unknown namespace reverts. The preview uses the same credential and namespace checks. These helper semantics are specific to this implementation.

## Current usability and deferred behavior

Namespace expiration does not remove history or automatically advance a revision. The helper `isUsable` returns true only when the credential exists, the policy's `usesEnabled` is true, the namespace is `Active`, and its expiry is zero or `block.timestamp <= validUntil`. It does not require `updatesEnabled`: an update pause and a reliance pause are deliberately independent.

A consumer must additionally evaluate the current status and validity of the records it uses, its accepted policy set, and its complete qualification predicate. `validUntil == 0` represents no expiry at that level; applications following this profile treat a finite record validity bound as inclusive too. `isUsable` alone does not establish eligibility, and the `recordAt` active flag alone does not establish present record validity.

This implementation does not include an independent issuer revocation registry. Namespace revocation is not a substitute for external per-claim revocation. It also does not evaluate an application's complete eligibility predicate or track consumption of an entitlement.

The following are not implemented: policy migration, authority rotation, account recovery, cross-chain finality, source adapters, private material delivery, ZK proving and verification, anonymous credential registry membership, and one-time application admission. Their proposed requirements are described in the [discussion](discussion.md) and [roadmap](roadmap.md).
