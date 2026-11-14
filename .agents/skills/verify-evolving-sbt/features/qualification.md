# F06 — External revocation and current contribution qualification

An application asks whether a holder has two distinct currently valid recognized contributions. After the issuer revokes a selected claim, qualification fails without any SBT update. The user-approved requirement and `docs/qualification-profile.md` are the expected-behavior sources; implementation is not itself the requirement.

## Sub-features

- F06-binding: immutable application consumer pins credential, namespace, policy and registry; registry authenticates issuer from policy commitments.
- F06-current: both selected records are currently valid, nonsuperseded and belong to the holder, with distinct experience IDs.
- F06-revoke: only issuer can irreversibly revoke; repeat revocation is idempotent.
- F06-independent: paused SBT updates and full record history do not prevent revocation.
- F06-isolation: revocation of another claim/token or a fresh registry does not change the consumer's selected trust configuration.

## How to get to it (user POV)

Application deployer selects a trusted EvolvingSBT and registered contribution namespace, creates ClaimRevocationRegistry with the correct issuer/controller preimages, then pins it in ContributionQualifier. Holder obtains two issuer-recognized records through the existing signed applyTransition path. The application calls `qualifies(tokenId, [0,1])`. The issuer calls `revoke(tokenId, claimId)`. The application repeats the same query; the holder need not submit anything.

There is no UI, login, public network deployment or ZK prover. `qualifies` is public and does not establish that its caller is the holder. No user-supplied registry argument is accepted.

## Driving it with Foundry simulation

Preconditions: pinned dependencies and Solidity compiler available; three separate test roles, a fresh contract, registered NS, initialized holder SBT and an application-pinned registry/consumer. Fixtures create these through public methods with real EIP-712 signatures; no direct storage writes.

Run `.agents/skills/verify-evolving-sbt/scripts/verify.py --feature qualification` from the repo. It selects `test(Fuzz)?Qualification` and captures full traces and source/test hashes. This route is EVM simulation using Foundry sender/time controls, not live RPC or browser-wallet coverage.

1. Append two recognized contributions. `qualifies` returns true.
2. Save complete SBT head hash and record count. Issuer revokes claim 1. Expect `ClaimRevoked` and registry query true.
3. Re-query exactly the same records. Expect false; complete SBT head hash/count remain unchanged; namespace is usable and local record active remains true.
4. Try holder/controller revocation: reject and preserve qualification. Repeat authorized revocation: no duplicate event, remains revoked.
5. Attempt consumer setup with wrong namespace/policy/deployment registry: reject. A separately deployed empty registry does not replace the pinned one, even though its query returns false for revocation.
6. Expire a record or namespace (inclusive boundary first), suspend/revoke namespace, disable uses, burn token: appropriate false result. Repeated/out-of-range indices and old/superseded records cannot produce two valid experiences.
7. Pause updates with uses enabled, then revoke: false without state update. Fill all 32 history slots, then revoke: false for affected pair, history unchanged. Another unaffected pair may still qualify.
8. Revoke old claim then correct with new claim ID/same experience: old selection fails, new distinct pair succeeds; original revocation persists. Pre-revoked claims remain unusable after admission.
9. Inspect report.json/actions.jsonl and verify checksums after temporary build/cache cleanup. Report selected test count and status; do not infer privacy or consumption coverage.

## Gotchas

Registry binding is application configuration, not a new registry field in old issuer-signed records. Trust only the configured consumer; another consumer may deliberately pick a fresh registry. The registry is concrete signed-growth-specific, non-upgradeable, and has no key rotation or unrevoke. A correction can authorize a new claim about the same experience; revocation is not an eternal ban on an experience. Evaluation is at the call block: granting applications must recheck atomically and separately authenticate the recipient. Tests use a local EVM, not real-time external finality. Zero active contributions in an uninitialized namespace is not a seed failure to bypass. No claims about hiding data should be made from this public route.
