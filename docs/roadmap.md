# Implementation milestones

These milestones are an implementation plan, not a claim of ERC acceptance or a schedule commitment.

## v0.1 — Evidence-authorized state evolution

The first reference profile uses a non-transferable credential with independent namespaces and real signed authorizations. It implements the candidate reading and transition interface, exact-predecessor checks, monotonically increasing revisions and policy epochs, explicit lifecycle permissions, bounded accepted history, linked corrections, and stable experience identifiers for accounting.

The acceptance criterion is a reproducible local example and meaningful rejection tests. A reviewer should be able to establish why a transition was accepted and why a competing, unauthorized, stale, duplicate, or malformed transition is rejected.

The implementation is transparent. All submitted data and state are observable. The selected issuer is trusted to recognize experiences; arbitrary on-chain history is not independently verified.

## v0.2 — Current qualification and application consumption

First slice implemented: fixed-policy single-claim revocation and public two-contribution qualification, with rejection tests. See [profile](qualification-profile.md). One-time consumption, recovery continuity and authenticated balance checkpoints below remain planned.

Add an independently operated issuer revocation registry and a small public-data qualification example. Revocation must affect qualification even when the holder does not update the SBT. A cached level or score must expose enough dependencies for current validation.

Add application-side one-time entitlement consumption with an explicitly scoped identifier and atomic validation plus consumption. Updating the SBT or regenerating a presentation must not create another copy of the same entitlement. Recovery must preserve the identity used for consumption.

Acceptance examples include two qualifying contributions, an externally revoked claim, an expired namespace, and a second attempt to consume the same admission right. Balance requirements need authenticated checkpoint semantics and must not be represented as permanent historical attributes.

## v0.3 — Private presentations

Implement a real proof relation and verifier. A presentation must connect recognized claims to the current accepted credential state, current local record status, external non-revocation dependencies, and one consistent subject. A holder's possession of unrelated valid claims is insufficient.

The profile also needs a current credential registry, lifecycle synchronization, witness delivery and refresh rules, and a defined privacy boundary. It must explain which identifiers, events, timing, and application interactions remain linkable.

Acceptance requires positive and negative proof tests plus measured proving and verification costs. A mock verifier or a public hash does not satisfy this milestone.

## Later work

- Protocol adapters for particular authenticated sources, including their attribution rules and action boundaries.
- Cross-chain finality and source-authentication policies.
- Policy migration preserving history, current status, deduplication, revocation dependencies, and stable subject bindings.
- Scalable accumulators and authenticated record-status structures replacing the 32-record public-history bound, with continuity proofs for accepted records and accounting.
- Recovery through stable smart-account control, including invalidation of pending authorizations.
- Additional independent implementations and shared test vectors.
- A formal ERC submission once the interoperability boundary has been reviewed and its encodings and failure semantics are stable.

Each addition should preserve the distinction between core interoperability, a particular verification profile, and an application's eligibility policy.
