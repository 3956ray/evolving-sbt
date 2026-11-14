# F03 — Accumulate and correct experiences

An issuer appends accepted experiences and corrects claims while retaining historical records and stable accounting. Expectations derive from the corresponding sections of `docs/specification.md` and `SECURITY.md`; `docs/discussion.md` alone is not evidence of current support.

## Sub-features

- F03-append — accepted experience advances history and revision.
- F03-correct — linked correction retains old record and experience identity.
- F03-dedup — repeated claim/experience is rejected.
- F03-capacity — record limit includes corrections; lifecycle revocation remains possible.

## How to get to it (user POV)

Contract wallet/SDK entry points: `previewTransition; transitionDigest; applyTransition; recordAt; recordCount; isCredited; stateOf`. An administrator, holder, issuer, controller or relayer uses the relevant public method; there is no browser screen. See `script/Demo.s.sol` for request construction, but it does not exercise every route here.

## Driving it with Foundry simulation

Preconditions: Fresh initialized NS and holder-bound records with distinct nonzero IDs and content hashes.

Run `.agents/skills/verify-evolving-sbt/scripts/verify.py --feature growth` from the repository. The helper creates isolated build/cache state and invokes the selected existing tests with full traces. Test fixtures provide fresh deployment and prerequisites; failures must not be bypassed by direct storage writes.

Actions and observable expected results: Append an issuer-authorized record: record count and revision increase. Append duplicate experience under another claim ID: reject. Correct original with same experience ID/new claim ID: retain original, mark it superseded, append active replacement, preserve credited experience. Reject correction with a different experience ID. Rejected correction leaves history and state unchanged. At 32 records reject append and correction while namespace revocation still works. Independently reproduce state commitments.

Inspect per-test PASS/FAIL, public calls and assertions in the saved trace. Require the corresponding named tests to execute; exit zero with no tests is not coverage. Read-back state after rejected operations is essential. This route is simulated EVM integration; live RPC execution of these paths remains unverified.

## Gotchas

Historical records may be expired. Correction consumes capacity. Hash-chain roots are not Merkle trees. isCredited is historical accounting, not present qualification. This profile trusts the issuer to assign canonical experiences.

Entry points not driven by the selected tests must be separately reported; do not infer wallet, external source, privacy or full qualification coverage from these results. Preserve actions.jsonl and report.json after cleanup.
