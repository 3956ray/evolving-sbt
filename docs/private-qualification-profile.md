# Private contribution qualification — design boundary, not implemented

This document specifies the intended relation for a future private counterpart to [public qualification](qualification-profile.md). It is not a circuit, a deployed verifier or a finalized cryptographic encoding. The public consumer provides an oracle for bounded eligibility; a private presentation additionally requires proof of current subject authorization and request binding.

## First predicate

Two distinct recognized experiences, both currently admissible, belonging to one authorized credential subject. No balances, scores, uniqueness-of-human claims, or one-time consumption in the first implementation slice.

## Public inputs and outside checks

The verifier must obtain or authenticate these values, not accept arbitrary prover-selected references:

- Qualification profile ID/version and accepted credential/namespace/recognition-policy configuration.
- Accepted shared credential-registry root and its provenance.
- Accepted revocation-registry identity and authenticated state commitment/checkpoint.
- Applicable policy-use controls, authenticated evaluation time and snapshot/finality rules.
- Chain/verifier/application domain, request hash, challenge, deadline, recipient session or ephemeral recipient key.
- A scoped nullifier only if a later application grants a limited-use entitlement.

At acceptance, the outer contract checks those public inputs against current accepted on-chain state and checks deadline/request binding. The strict initial design accepts the current credential root; it also checks revocation and policy dependencies independently. A valid proof against an obsolete root is rejected. Revocation need not change the SBT root. A mapping-based v0.2 registry has no succinct non-revocation API yet; v0.3 needs an authenticated revocation structure or authenticated state-proof adapter, not a fabricated root or unauthenticated indexer response.

## Private witness

- Credential identity/location and membership path in a common credential registry.
- Selected namespace head(s), claim records, content openings and membership/status paths.
- Experience identities, expiry and authenticated issuer/registry/revocation-key bindings.
- Non-revocation witnesses for the accepted revocation state.
- Current holder authorization witness, subject-binding material and any necessary issuance evidence.
- Randomness for hiding commitments and, for later consumption, a stable enrolled entitlement secret.

A unique per-token root published as a public input can reveal the token even when record contents are hidden. The common root should let the prover hide the leaf/index. Registry membership alone does not provide practical anonymity if the set is tiny or updates and submissions identify the holder.

## Commitments and binding relation

The future leaf conceptually binds the credential location, current namespace-heads commitment, stable subject/entitlement commitment, current authorization commitment/epoch, and liveness. The per-claim commitment binds its schema/domain, subject, issuer, namespace/policy, experience ID, claim ID, content, expiry and authenticated revocation locator. Use a reviewed hiding commitment construction with adequate randomness and explicit domain-separated encodings; a low-entropy content hash is not sufficient. Exact hash, field encoding, tree structure, proof system and parameters are not selected by this document.

The proof must establish, within one relation:

1. A live credential leaf belongs to the accepted shared registry and binds current heads/authorization.
2. Both claims are in the accepted namespace state, not merely valid unrelated signatures.
3. Local statuses are admissible, experience IDs differ, expiry checks pass at authenticated time.
4. Issuance/recognition authenticates the claims and the expected revocation locators; both claims are unrevoked in the accepted registry state.
5. Claims and authorization resolve to the same bound subject; knowing public account information is not possession of authority.
6. The predicate is satisfied and the proof is bound to this request and recipient.

A private updater cannot expose secret records in calldata/events before proving them. The current v0.1 public record history cannot retroactively become private. A separately versioned private profile and its admission path are required for confidentiality from issuance. The shared credential registry must be synchronously updated on every relevant head change, burn and coordinated authorization change; an asynchronous indexer is not proof of current validity.

## Privacy target and decisions still open

Candidate target: hide selected experiences and the credential identifier from the relying application; disclose only eligibility and necessary public context. Cross-application unlinkability is a separate acceptance property, not a consequence assumed from ZK. This target still needs user/community confirmation before a circuit is built. Public namespace/issuer choice, event timing, relayer/network metadata, repeated challenges and recipient identities can leak links. State who is protected from whom: public observer, relying application, issuer, and proving service have different views. Issuers already know what they issue; a remote prover receiving the witness can learn it.

## Public/private equivalence tests to add in v0.3

For the same authenticated configuration, time and claim set, private eligibility must agree with `ContributionQualifier` on positive, revoked, expired, superseded and duplicate-experience cases. Additionally reject wrong roots/registries, mixed subjects, stale authorization, altered request/recipient and revoked dependencies after proof generation. Measure proving time/memory, verifier gas and witness refresh cost. Confirm no intended private input appears in public calldata/events. No ZK capability is claimed until a real prover/verifier and these tests exist.
