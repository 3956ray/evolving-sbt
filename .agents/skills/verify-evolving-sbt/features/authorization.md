# F05 — Authorized updates and replay rejection

A relayer submits an exact signed transition; stale, altered, wrong-domain and no-longer-authorized requests reject. Expectations derive from the corresponding sections of `docs/specification.md` and `SECURITY.md`; `docs/discussion.md` alone is not evidence of current support.

## Sub-features

- F05-predecessor — replay and conflicting updates reject.
- F05-binding — evidence, proposed root and identity domain are bound.
- F05-epoch — pause/resume does not revive stale authorization.
- F05-wallet — ERC-1271 authorization is checked at submission time.

## How to get to it (user POV)

Contract wallet/SDK entry points: `transitionDigest; applyTransition; stateOf; setPolicyControls`. An administrator, holder, issuer, controller or relayer uses the relevant public method; there is no browser screen. See `script/Demo.s.sol` for request construction, but it does not exercise every route here.

## Driving it with Foundry simulation

Preconditions: Fresh fixture with signed transitions, exact prior state, policy epochs and a nonzero deadline; mock ERC-1271 wallet only for isolated signature boundary tests.

Run `.agents/skills/verify-evolving-sbt/scripts/verify.py --feature authorization` from the repository. The helper creates isolated build/cache state and invokes the selected existing tests with full traces. Test fixtures provide fresh deployment and prerequisites; failures must not be bypassed by direct storage writes.

Actions and observable expected results: Submit a valid update, then replay: WrongPredecessor. Race two updates with one predecessor: only first succeeds. Change evidence or invent root: reject and preserve state. Pause/resume policy: old epoch stays stale. Change chain, contract, credential or namespace: signatures no longer authorize request. Disable ERC-1271 signature validity before submission: reject pending update.

Inspect per-test PASS/FAIL, public calls and assertions in the saved trace. Require the corresponding named tests to execute; exit zero with no tests is not coverage. Read-back state after rejected operations is essential. This route is simulated EVM integration; live RPC execution of these paths remains unverified.

## Gotchas

Signature authentication is not independent truth of the underlying contribution. Mock1271Wallet is a test boundary, not production recovery. Preview is not reservation. Scope includes update replay, not one-time application redemption.

Entry points not driven by the selected tests must be separately reported; do not infer wallet, external source, privacy or full qualification coverage from these results. Preserve actions.jsonl and report.json after cleanup.
