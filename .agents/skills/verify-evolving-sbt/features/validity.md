# F04 — Current namespace usability

A consumer checks whether a namespace can currently be relied on, separately from permission to update it. Expectations derive from the corresponding sections of `docs/specification.md` and `SECURITY.md`; `docs/discussion.md` alone is not evidence of current support.

## Sub-features

- F04-expiry — namespace expiry and controller-only extension.
- F04-controls — permission to use differs from permission to update.
- F04-lifecycle — suspend, resume and terminal revoke.
- F04-record — record expiry is separate from namespace usability.

## How to get to it (user POV)

Contract wallet/SDK entry points: `isUsable; stateOf; policyOf; setPolicyControls; applyTransition; recordAt`. An administrator, holder, issuer, controller or relayer uses the relevant public method; there is no browser screen. See `script/Demo.s.sol` for request construction, but it does not exercise every route here.

## Driving it with Foundry simulation

Preconditions: Fresh initialized NS, controlled simulated clock and controller account.

Run `.agents/skills/verify-evolving-sbt/scripts/verify.py --feature validity` from the repository. The helper creates isolated build/cache state and invokes the selected existing tests with full traces. Test fixtures provide fresh deployment and prerequisites; failures must not be bypassed by direct storage writes.

Actions and observable expected results: Advance time to expiry: usable at equality, unusable after. Only controller can extend finite expiry. Disable uses while updates remain enabled: unusable but append still succeeds. Suspend/resume: usability changes while growth root and credited experiences persist. Revoke: terminal, cannot reset/resume. Expire an individual record: namespace may remain usable and recordAt active remains true; consumer still needs record expiry checks.

Inspect per-test PASS/FAIL, public calls and assertions in the saved trace. Require the corresponding named tests to execute; exit zero with no tests is not coverage. Read-back state after rejected operations is essential. This route is simulated EVM integration; live RPC execution of these paths remains unverified.

## Gotchas

Time travel is Foundry simulation, not wall-clock chain coverage. isUsable is not an application predicate. The v0.1 core does not check external single-claim revocation; the optional consumer covers it in F06. No expiry is encoded as zero; restore only through documented operations.

Entry points not driven by the selected tests must be separately reported; do not infer wallet, external source, privacy or full qualification coverage from these results. Preserve actions.jsonl and report.json after cleanup.
