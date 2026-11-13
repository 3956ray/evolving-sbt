# [Pre-ERC Discussion] Evolving SBT with Namespaced State Transitions

Published discussion: https://ethereum-magicians.org/t/pre-erc-discussion-evolving-sbt-with-namespaced-state-transitions/30361

This is the design discussion, not a claim that all profiles are implemented in v0.1.

I am exploring an extension for soulbound credentials that accumulate verified experiences over time and allow those experiences to support different applications.

The motivation is:

> Past activity scattered across different protocols should be reusable as evidence for future eligibility.

A person may participate in governance, complete community tasks, provide liquidity, borrow and repay assets, or receive an educational qualification. These experiences can support future requirements such as membership upgrades, contributor access, professional eligibility, or admission to an event.

The proposed design uses a persistent, non-transferable credential to maintain continuity across those experiences. Applications can discover its currently accepted state, identify the rules that authorized that state, and evaluate whether the supporting claims remain usable.

For privacy-sensitive applications, a holder should be able to prove a requirement such as “I have at least two qualifying contributions and satisfy a balance threshold” without including their complete activity history or exact balance in the presentation.

This is a pre-ERC discussion. The core interface and implementation profiles below are proposals for review. No audited implementation or benchmark results are claimed.

**Growth and dynamic validity have different meanings.** Growth means that the credential can accumulate recognized experiences and support additional qualifications. Dynamic validity means that its usable state can respond to corrections, expiration, revocation, changes in authorization, and explicitly permitted policy migrations.

These properties can coexist:

- A completed community task adds an accepted experience.
- A correction changes how an existing experience is recognized.
- An issuer revokes a certification that was issued incorrectly.
- A membership expires while its participation history remains.
- An application changes its requirements without rewriting the holder’s past.

State revisions increase with accepted transitions. Scores, levels, and current eligibility do not have to increase monotonically.

The design distinguishes three things throughout:

1. Accepted historical records.
2. Whether those records currently satisfy an application’s requirements.
3. Whether a particular application entitlement has already been consumed.

**The proposed core standardizes accepted state and its evolution.** The complete system has several responsibilities:

| Responsibility | Proposed location |
|---|---|
| Collect transactions, attestations, and snapshots | Indexers and source adapters |
| Interpret actions and establish their source | Evidence verification rules |
| Establish which subject an action belongs to | Subject-attribution rules |
| Decide who can recognize or change a claim | Namespace policy |
| Maintain the current accepted state and revision | SBT state-transition interface |
| Retain private claims and proving materials | Holder’s wallet or chosen storage |
| Define qualification requirements | Application policy |
| Generate a selective-disclosure presentation | Holder-controlled prover |
| Check current validity and consume limited-use rights | Application verifier and consumption ledger |

The core covers state discovery, policy discovery, and authorized state transitions. It does not require a universal indexer, classification service, reputation formula, or zero-knowledge system.

A common submission interface lets compatible wallets and relayers handle updates consistently. Generating evidence for a particular policy still requires support for that policy’s data and verification profile.

**Existing standards already provide substantial dynamic functionality.** The case for an extension must therefore be more specific than “SBTs should be dynamic.”

| Standard | Relevant capability | Relationship to this proposal |
|---|---|---|
| [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192) | Minimal locked-token interface and transfer restrictions while locked | A possible base for non-transferability; it does not define the state-transition model proposed here. |
| [ERC-5484](https://eips.ethereum.org/EIPS/eip-5484) | Consent at issuance, burn authorization, and immutable issued metadata | Relevant lifecycle constraints; evolving state must be reconciled with its metadata requirements. |
| [ERC-5727](https://eips.ethereum.org/EIPS/eip-5727) | Token and credit issuance/revocation, verification, and optional lifecycle extensions | Already supports dynamic behavior; this proposal adds common semantics for independently governed, versioned state within one credential. |
| [ERC-7508](https://eips.ethereum.org/EIPS/eip-7508) | Dynamic on-chain attributes and granular access control | Relevant attribute infrastructure; the proposed addition concerns evidence constraints and predecessor-bound transitions. |
| [ERC-7208](https://eips.ethereum.org/EIPS/eip-7208) | Separation of underlying data from managing logic | Possible implementation infrastructure; credential-specific transition semantics would still need definition. |

In ERC-5727, a token belongs to one slot at a time. Here, a credential can contain multiple namespaces, each with a current state head and acceptance rules. An ERC-5727 implementation could provide these capabilities through an extension. The question is whether their shared semantics are useful to standardize.

ERC-5484 compatibility is not assumed. An implementation claiming compatibility must preserve the metadata agreed at issuance and satisfy its other requirements. Keeping a `tokenURI` string unchanged while changing the metadata it resolves to does not establish compatibility. ERC-5727 inherits ERC-5484, so this also matters when considering an extension to ERC-5727. [ERC-5484 specification](https://eips.ethereum.org/EIPS/eip-5484#specification), [ERC-5727 core](https://eips.ethereum.org/EIPS/eip-5727#core).

Related work includes the proposed [ERC-8415](https://github.com/ethereum/ERCs/pull/2149), concerning versioned commitments and proof-bound admission for external register projections, and the proposed [ERC-8404](https://github.com/ethereum/ERCs/pull/1980), concerning recomputable verification receipts. Both are represented by open pull requests at the time of this draft.

The contribution being explored is a common contract for:

> The current state of a credential namespace, the policy governing that state, and an evidence-authorized transition from an exact predecessor.

Namespacing, commitments, version checks, and atomic transactions are existing mechanisms. The proposed value is their interoperable meaning for evolving credentials.

**A namespace represents a semantic and authorization boundary.** A state is addressed by:

```text
(chainId, credentialContract, tokenId, namespace)
```

One credential might contain namespaces for community contributions, educational qualifications, and verified protocol activity.

Each namespace identifies its schema, recognized authorities, permitted operations, and transition rules. Authority over one namespace does not automatically grant authority over another.

The same namespace identifier used by different deployments does not automatically establish equivalent meaning. Consumers must recognize the deployment and its applicable policies.

Namespaces also do not require a universal activity taxonomy. Protocol names and action categories can be fields within records.

Illustrative classifications include:

| Activity family | Example actions | Required interpretation |
|---|---|---|
| Asset movements | Send, receive, mint, burn | Asset, units, actor role, and whether the movement was voluntary |
| Exchange and liquidity | Swap, add liquidity, remove liquidity | Participant, pool or position, assets, and action boundaries |
| Lending | Supply, withdraw, borrow, repay, liquidate | Actor role, position, and historical versus current-state meaning |
| Prediction markets | Acquire positions, trade, redeem settled positions | Market, position, outcome, and settlement context |
| Governance | Propose, vote, delegate | Governance system, proposal, role, and checkpoint |
| Community and qualifications | Complete a task, attend, receive certification | Recognizing issuer, criteria, validity, and revocation |

Interacting with a Uniswap, Aave, or Polymarket-related contract does not by itself establish a particular meaningful action. Source adapters must account for routers, smart accounts, relayers, and position ownership.

Existing Etherscan labels can help identify entities and explain activity. They do not establish that a subject performed an action or that the action qualifies as a contribution. If a policy relies on an external classification dataset, it must identify the dataset version and trust assumptions. [Etherscan metadata documentation](https://docs.etherscan.io/metadata/introduction).

**Accepted evidence requires both attribution and recognition.** The verification process must answer separate questions:

1. Does the underlying event, state, or attestation exist?
2. Does it belong to the credential’s subject under the attribution rules?
3. Is the source or issuer recognized for this type of claim?
4. Does the evidence authorize the requested state change?

Possession of the SBT does not authorize arbitrary recognized claims.

A record schema should identify, where applicable:

- Schema and version.
- Subject binding.
- Source chain, contract, authenticated checkpoint, and event or state reference.
- Protocol action and subject role.
- Assets, quantities, and units.
- Issuer or verification method.
- Validity bounds.
- Claim identifier and canonical experience or action identifier.
- Authenticated revocation registry and revocation key.
- A reference to an earlier claim when correcting or replacing it.

A cryptographic proof establishes the statement encoded by its verification rules. It does not make an untrusted issuer authoritative or establish that an authentic transaction represents valuable contribution.

For example, a community’s statement that a task was completed carries that community’s authority. The application must decide whether to accept it.

**The initial growth profile separates historical records, record status, and duplicate accounting.** A generic `stateRoot` cannot by itself establish that prior experiences were retained or that an action was counted only once.

To make growth concrete, the first implementation profile would commit to the following structure:

```text
stateRoot = Commit(
    profileId,
    recordsRoot,
    recordCount,
    recordStatusRoot,
    creditedActionsRoot
)
```

Here:

- `recordsRoot` commits to an append-only sequence of accepted claim records.
- `recordCount` describes that sequence; it is not a contribution score.
- `recordStatusRoot` commits to the current local status of records, including active or superseded status and replacement relationships.
- `creditedActionsRoot` commits to canonical experience or action identifiers already admitted for accounting.
- `profileId` identifies the applicable encoding and transition rules.

The commitment construction and proof algorithms must be fixed by the profile. Privacy-sensitive fields require suitable hiding commitments.

An append operation proves that the previous records remain committed, new records have valid recognition evidence, and any newly credited action has not already been credited.

A correction appends a new record linked to the affected record. It updates the relevant record statuses and preserves the underlying experience identifier.

A new claim identifier does not create a new experience. Applications count distinct qualifying experience identifiers according to their rules.

For example, correcting the category of an accepted task may change its qualification value. It must not turn one completed task into two completed tasks.

The current record-status commitment is necessary because an append-only history still contains old records. A presentation cannot rely solely on historical inclusion: it must also establish that the selected record is currently usable.

External revocation is checked separately. A record marked active in the SBT’s last accepted state can still have become unusable through its issuer’s revocation registry.

This profile supplies one concrete meaning of verifiable growth. Other profiles may use different data structures, but must state their preservation and accounting guarantees.

**The candidate core has three methods and one transition event.** The following sketch shows the additions; base token and interface-discovery methods are omitted.

```solidity
interface IEvolvingSBT {
    enum NamespaceStatus {
        Uninitialized,
        Active,
        Suspended,
        Revoked
    }

    struct StateHead {
        uint64 revision;
        bytes32 stateRoot;
        bytes32 policyId;
        NamespaceStatus status;
        uint64 validUntil;
    }

    struct PolicyDefinition {
        bytes32 schemaId;
        bytes32 rulesHash;
        address verifier;
        bytes32 verifierConfigHash;
        bytes32 authorizationHash;
        string specificationURI;
    }

    struct PolicyStatus {
        uint64 epoch;
        bool updatesEnabled;
        bool usesEnabled;
    }

    struct StateUpdate {
        bytes32 stateRoot;
        bytes32 policyId;
        NamespaceStatus status;
        uint64 validUntil;
    }

    struct Transition {
        uint256 tokenId;
        bytes32 namespace;

        uint64 expectedRevision;
        bytes32 expectedStateHash;

        uint64 sourcePolicyEpoch;
        uint64 targetPolicyEpoch;

        StateUpdate nextState;

        bytes32 operationsCommitment;
        uint64 deadline;
    }

    function stateOf(
        uint256 tokenId,
        bytes32 namespace
    ) external view returns (StateHead memory);

    function policyOf(
        bytes32 namespace,
        bytes32 policyId
    )
        external
        view
        returns (
            PolicyDefinition memory definition,
            PolicyStatus memory status
        );

    function applyTransition(
        Transition calldata change,
        bytes calldata evidence,
        bytes calldata authorization
    ) external returns (uint64 newRevision);

    event StateTransitioned(
        uint256 indexed tokenId,
        bytes32 indexed namespace,
        uint64 revision,
        bytes32 previousStateHash,
        bytes32 nextStateHash,
        bytes32 policyId,
        bytes32 transitionId
    );
}
```

`stateOf` exposes the currently accepted head.

`policyOf` exposes the immutable rule definition and its current operational controls.

`applyTransition` provides a common submission interface for evidence-bearing updates. The contract assigns the next revision.

The write method is included because the intended workflow lets holders carry evidence and submit it through compatible wallets or relayers. A narrower, consumer-only design could separate the write interface into an extension.

This core does not introduce separate methods for every experience category, score update, or protocol integration. Those operations are interpreted under the applicable policy.

A standardized verifier plug-in ABI, if needed, would be a separate addition. A verifier address alone does not make independently implemented plug-ins interchangeable.

**Policy identity and live controls must remain separate.** A `policyId` identifies an immutable definition covering schema, verification behavior, configuration, and authorization rules.

`specificationURI` is a discovery location. Its normative content must match the committed definition. Changing content at a URL cannot silently change an existing policy.

A fixed verifier address is also insufficient if its behavior can change through an upgradeable proxy. The baseline requires pinned verification behavior and dependencies. Normative changes require a new policy identity.

The live controls have different meanings:

- `updatesEnabled` controls whether new transitions may be accepted.
- `usesEnabled` controls whether applications may rely on the policy.
- `epoch` changes whenever these live controls change.

For each registered `(namespace, policyId)`, the epoch starts at a defined nonzero value, increases monotonically, and cannot be reset. Overflow reverts.

An epoch change invalidates pending updates and presentations bound to an earlier epoch. It does not erase historical records.

Pausing and resuming a policy therefore cannot reactivate an old pending authorization.

Policy administration remains outside the minimal ABI, but the implementation must disclose and enforce its controlling authority. Applications choose which policies and authorities they accept.

**Every transition must satisfy shared invariants.**

1. **Existence and registration.** The credential must exist, and the namespace and target policy must be recognized by the deployment. Unknown policies and unsupported namespaces are rejected.

2. **Authorized initialization.** A registered but uninitialized namespace has a canonical revision-zero head. Initialization requires the namespace’s acceptance rules and any required holder consent.

3. **Exact predecessor.** The expected revision and state hash must match the stored predecessor and remain valid when the update is committed.

4. **Sequential revision.** The contract assigns the current revision plus one. The caller cannot skip or reset revisions.

5. **Deadline.** The request has a nonzero deadline and is rejected after it.

6. **Current policy controls.** The relevant update controls must permit the operation, and the supplied policy epochs must match live state. Initialization has no source policy and uses source epoch zero.

7. **Complete binding.** Verification binds the chain, credential contract, token, namespace, predecessor, proposed state, policies, epochs, operations commitment, and deadline.

8. **Evidence and permission.** Verification checks source authenticity, subject attribution, recognized authority, operation permissions, and accounting constraints.

9. **Migration approval.** Changing `policyId` requires the source policy’s permission to migrate and the target policy’s permission to accept.

10. **Atomic admission.** Verification, state storage, and event emission succeed together. A failed operation leaves no partial update.

For an ordinary update under one policy, the source and target policy epochs are the same.

The evidence and authorization bytes must follow a discoverable profile. They cannot serve as unchecked assertions about the proposed result.

Authorization depending on holder control must check the current authorization state or epoch specified by that profile.

**Operation permissions must be narrower than a general “can update” permission.**

| Operation | Required authority and constraint |
|---|---|
| Append | Recognized issuer or source verifier; only supported claims may be added |
| Correct | Defined correction authority; the affected record and replacement must be linked |
| Suspend | Defined namespace authority |
| Resume | Explicit reinstatement authority and rules |
| Revoke namespace | Defined revocation authority |
| Extend expiration | Authority permitted to grant that validity |
| Migrate policy | Source migration approval and target acceptance |

An ordinary append cannot remove a suspension or extend validity merely because it supplies a new experience.

The initial lifecycle profile permits authorized transitions between `Active` and `Suspended` and treats `Revoked` as terminal for that namespace.

`validUntil == 0` means no namespace-level expiration. Individual records may still expire.

Expiration is evaluated against time. Time passing does not automatically execute a transaction or advance the revision.

**Credential and namespace identities cannot be reset.** The baseline adopts these restrictions:

- A `tokenId` is never reused within the same credential contract, including after burning.
- An initialized namespace cannot be cleared and reinitialized at revision zero.
- An initialized namespace cannot return to `Uninitialized`.
- Revisions and policy epochs cannot wrap around or reset.

Burned credentials remain unusable, and public state queries may revert according to the base lifecycle rules. The implementation must still retain enough lifecycle information to prevent identifier reuse.

These restrictions prevent an old authorization from becoming valid again because the same identity domain has returned to an earlier apparent state.

A future profile allowing identifier reuse would need an explicit instance generation bound into every relevant commitment, authorization, and proof.

**Compatible migration must preserve more than historical references.** For the proposed growth profile, migration must preserve or provide a verifiable mapping for:

- Accepted historical records.
- Canonical action identifiers already admitted.
- Current record status and replacement relationships.
- Applicable revocation dependencies.
- Stable subject and entitlement bindings.

A migration cannot make an already counted action appear new or restore a superseded record merely by changing the data structure.

The target policy may change how accepted experiences are evaluated, but that change must be explicit and accepted by the consuming application.

A migration that discards these continuity guarantees cannot claim compatibility with this growth profile.

**Revision protection and evidence deduplication address different failures.** Revision checking prevents competing updates from overwriting the same predecessor.

It does not prevent the same action from being submitted again against a later revision.

For a normalized liquidity action, the policy can derive a canonical identifier from its authenticated source references and participant role. The adapter must define when several logs represent one action.

Submitting a different proof of the same action does not create another credit.

For attestations, the profile distinguishes a stable experience identifier from the identifier of a particular issued claim. This permits a corrected claim about an existing experience without creating another experience.

Deduplication applies to the relevant accounting rule. The same history can still support multiple applications.

**Individual claim revocation must work without holder cooperation.** The initial profile uses an issuer-controlled revocation registry on the same chain.

Each revocable claim authenticates its issuer, registry, and revocation key together with its subject and content. A holder cannot substitute a registry in which the claim happens to be unrevoked.

The issuer can revoke a claim directly, without possessing the holder’s private SBT witnesses or obtaining a holder signature.

The initial registry profile uses monotonic revocation: once revoked, a claim remains revoked. An erroneous revocation is addressed by issuing a new, linked claim under the correction rules.

For a correction that invalidates an old revocable claim, the old claim is revoked before, or atomically with, acceptance of the replacement. The replacement retains the experience identifier and receives a new claim identifier.

This creates a useful property: if the holder refuses to update the SBT, the invalid old claim still cannot support a new qualification.

The registry must define authority rotation, recovery, and historical interpretation. Its behavior cannot be silently changed, and migration cannot erase existing revocations.

Issuer-key rotation also needs an admission rule. A newly submitted claim cannot be treated as genuinely old merely because it contains an earlier timestamp signed by a retired key. Late admission under an old key requires authenticated issuance or registration evidence satisfying the applicable cutoff rules.

**Current validity includes all supporting dependencies.** A qualification using revocable claims must prove their current non-revocation and the validity of any supporting dependencies.

This includes dependencies inherited through cached levels, scores, or intermediate calculations.

A previously valid computation proof does not establish that its underlying claims remain valid today.

The initial implementation therefore uses a bounded supporting set that can be checked completely. A cached score whose supporting dependencies cannot be validated is insufficient for current qualification.

An SBT head may remain unchanged after external revocation. A later state transition can update local bookkeeping, but it is not a prerequisite for revocation to affect eligibility.

If namespace updates are paused, the independent revocation registry remains usable. Policy-wide reliance can separately be stopped through `usesEnabled`.

**A private presentation must prove that its materials belong to the accepted SBT state.** The proof relation must connect all of the following:

1. A live credential appears in the current accepted credential registry.
2. Its selected namespace heads are current.
3. Every claim used for qualification is committed by those namespace states.
4. Each selected record has an admissible current local status.
5. Issuance evidence is recognized and authenticates the claim’s content, subject, and revocation information.
6. Required external validity and freshness checks hold.
7. All selected namespaces, accounts, current authorization, and entitlement material belong to the same subject.
8. The application predicate and request binding hold.

Proving possession of several valid claims is insufficient if those claims have not been accepted into the relevant credential state.

A holder may choose a sufficient subset for a positive qualification, but cannot omit dependencies necessary to validate that subset.

The exact circuit or other proof construction is part of the presentation profile.

**The application publishes the request, and the holder produces the presentation.** A qualification request identifies:

- The qualification policy and version.
- Accepted credential deployments, namespaces, and recognition policies.
- Required predicates and thresholds.
- Accepted source checkpoints and freshness limits.
- The verifier domain.
- The application-defined entitlement scope.
- A challenge and deadline.
- The receiving session or an ephemeral recipient key.

The wallet uses the holder’s private claims and witnesses to construct the proof. The verifier receives the proof and necessary public inputs.

Private claims must not first be published in calldata or events. Those channels are public. A private update can instead carry a proof over hidden claims and signatures, together with suitable commitments.

Later zero-knowledge presentation cannot remove earlier public disclosure.

**The privacy registry must track actual current state.** To support presentation without exposing the token identifier, the profile can use a shared commitment registry.

Conceptually, each credential leaf binds:

```text
credential location
current namespace-heads commitment
stable subject / entitlement commitment
current authorization commitment and epoch
credential liveness
```

The profile fixes the leaf encoding and commitment construction.

In the initial implementation, only the credential contract’s authorized synchronization path updates this registry. Every relevant namespace transition, burn, and authorization change updates it in the same transaction.

Restricting the root setter alone is insufficient. There must be no alternative lifecycle or authorization path that changes the underlying state without synchronization.

Accordingly, the first account profile supports control-key changes through a coordinated account-and-credential update path. Arbitrary smart-account authorization schemes are not automatically compatible.

The verifier accepts the current root. A root asynchronously published by an indexer does not establish immediate current-state validity.

This strict approach can require refreshed witnesses or proofs when the registry changes. Its operational cost needs measurement.

The root has a limited scope: it commits to credential state and authorization. Applications also check current policy controls, revocation state, and authenticated dynamic-state dependencies.

**A recent balance requirement needs its own authenticated evidence.** Historical activity and changing state should be treated differently.

“Previously repaid a loan” is a historical claim. “Currently has no outstanding debt” requires a sufficiently complete and fresh view of obligations.

Likewise, a balance threshold requires an authenticated snapshot accepted by the application.

For a narrow prototype, a designated checkpoint publisher could register accepted finalized state roots, with that trust assumption disclosed. The proof authenticates the account state against an accepted root, and the application enforces an age limit.

This proves a balance at that checkpoint. It does not prove a continuously maintained balance.

The balance account must be bound to the same credential subject as the other qualification materials.

The initial profile supports positive, bounded requirements. Statements about all liabilities, total trading performance, or all activity across chains require additional completeness guarantees.

**One-time entitlements are enforced by application consumption.** Historical materials can be reused across applications, and presentation bytes can be copied.

For a limited-use entitlement, the application performs these operations atomically:

1. Check current credential, policy, revocation, and required snapshot state.
2. Verify the proof and request binding.
3. Verify the intended recipient or session binding.
4. Check that the entitlement nullifier is unused.
5. Record consumption and grant the result.

A conceptual nullifier is:

```text
nullifier = PRF(
    stableSubjectEntitlementSecret,
    applicationDomain || entitlementScope
)
```

The stable secret is bound at enrollment. It cannot be replaced through an ordinary update, correction, policy migration, or control-key recovery.

The application defines or approves the entitlement scope.

State revision, root, challenge, policy epoch, and rotating control keys must not change the nullifier for the same entitlement. A change in qualification-policy version also must not accidentally create a new admission right.

The precise guarantee is:

> The same bound entitlement identity cannot redeem the same entitlement scope more than once within the application’s consumption system.

This does not establish one-person-one-credential or one-person-one-redemption across independently issued credentials. Those properties require additional issuance or identity rules.

Recipient binding matters because an otherwise valid copied proof could be submitted first by someone else. The resulting benefit must be delivered only to the intended recipient or session.

Multiple entrances need a shared consumption ledger. A physical gate can act on confirmed redemption. Offline gates require a separate consistency model.

**Recovery preserves control continuity and consumed rights.** The initial profile keeps the SBT owned by a stable smart account and supports preconfigured recovery of control keys.

Recovery updates the current authorization commitment through the synchronized path. An old control key can no longer satisfy the current presentation authorization requirement.

The stable entitlement commitment and application consumption records remain unchanged. Burning a credential also does not erase application consumption records.

The first profile does not promise transparent replacement with a newly issued credential. A future replacement mechanism would need an authenticated mapping preserving the relevant entitlement identity and lifecycle constraints.

Recovering account control also does not reconstruct lost private claims or entitlement secrets. The holder needs appropriate backup or recovery arrangements for those materials.

Non-transferability restricts token transfers. It does not prevent voluntary secret sharing or establish a unique civil identity.

For an ERC-5192-based implementation, the initial profile would require permanent locking during the credential’s lifetime, with recovery handled through account control.

**User-carried materials need delivery and availability rules.** Issuance should deliver the claim, required signatures or proof artifacts, revocation locator, commitment material, and applicable schema information to the holder.

Wallets need retention, export, backup, and witness-update support. A state commitment is not a backup of the private material it commits to.

If current revocation or other required evidence cannot be authenticated, the implementation cannot assume validity.

Proof-generation services also have different privacy properties. A service receiving a complete witness may learn details that the final verifier does not.

Public ownership, update timing, selected policies, and application context can still create correlations. The presentation profile must state which information is disclosed and which information remains observable elsewhere.

**A membership-and-admission example exercises the proposed design.**

Consider one credential with two namespaces:

- `CommunityContributions`, recognizing task-completion claims from an accepted community.
- `ProtocolActivity`, recognizing actions through a specified protocol adapter.

The holder completes two community tasks and performs one recognized liquidity action.

The community issues subject-bound claims with experience identifiers and authenticated revocation information. The protocol adapter provides evidence for the liquidity action and participant role.

The wallet submits transitions. Each transition verifies the evidence and authority, checks its exact predecessor, updates the profile’s records and accounting commitments, and advances the affected namespace revision.

The holder now has richer accepted experience under the same SBT. A membership application may use the protocol activity. Another application may use only the community contributions.

An event publishes this requirement:

> Present two currently valid community contributions and prove a balance of at least 1 ETH at an accepted recent checkpoint.

The wallet generates a proof that the selected contributions belong to the credential’s current namespace state, remain usable, and belong to the same subject as the authenticated balance account and current authorization.

The presentation does not include individual task descriptions or the exact balance. It is bound to the event request and receiving session.

Suppose one task claim is revoked before acceptance. The revocation registry changes. A proof relying on the previous revocation root fails the current-state check, even if the SBT head is unchanged.

If the issuer provides a corrected replacement, the wallet can append it, mark the original record superseded, and preserve the same experience identifier. The correction does not create an additional contribution.

Alternatively, completing a genuinely new qualifying task adds a new experience and can restore eligibility.

If admission was already redeemed before revocation, the system cannot undo physical entry. Subsequent checks use the new validity state.

Neither a new contribution, a correction, a policy migration, nor control-key recovery resets the consumed event entitlement.

**The first implementation should remain bounded.** I would begin with:

- One chain.
- Two namespaces.
- One community issuer.
- One protocol adapter.
- One fixed growth profile.
- One explicit account-authorization profile.
- A membership consumer and a private event-admission consumer.

Important tests include:

- Unrecognized issuance and incorrect subject attribution.
- Claims that are valid but absent from the accepted SBT state.
- Replay across contracts, chains, or namespaces.
- Stale predecessors and conflicting updates.
- The same action submitted through different proofs.
- Corrections counted as additional experiences.
- Selection of superseded records.
- Unauthorized suspension removal or expiration extension.
- Old authorization after a policy pause-and-resume cycle.
- Migration that resets deduplication or record status.
- Burn-and-remint or namespace-reset attempts.
- Revoked dependencies hidden behind cached scores.
- Credential or authorization changes that bypass registry synchronization.
- Stale roots or snapshots.
- Copied presentations bound to a different recipient.
- Consumption reset through growth, recovery, or migration.

Useful measurements include update gas, proof-generation latency and memory, verification and consumption cost, and witness-maintenance overhead.

Two independent implementations using the same interfaces and profiles would help establish whether the proposed semantics provide practical interoperability.

**Several details must be fixed before a formal ERC submission.** The discussion establishes candidate behavior, but the formal specification still needs:

- Canonical encodings and domain-separated hashes for policy identity, state heads, operations, and transitions.
- Exact initial-state encoding and error behavior.
- Defined evidence and authorization format identifiers.
- Commitment algorithms and proof statements for the example growth profile.
- Privacy-registry and revocation-registry interfaces and state machines.
- Base-token compatibility requirements and interface discovery.
- Reference implementations and positive and negative test vectors.

These are specification and implementation tasks. They do not necessarily require more methods in the core SBT interface.

**The main questions for discussion are about the smallest useful interoperability boundary.**

1. Does namespace state discovery, policy discovery, and predecessor-bound admission provide enough shared value to standardize as an SBT extension?

2. Should the submission method be mandatory, or should reading and policy discovery form a smaller core?

3. Which existing verification-receipt or data-management interfaces should be reused?

4. Should verifiable historical preservation remain a profile-level guarantee, or should the core require a common historical commitment?

5. Is strict current-root verification a useful initial privacy profile given its witness-refresh costs?

6. What minimum common profile would allow independently developed wallets and applications to interoperate without requiring a universal identity, reputation, or classification system?
