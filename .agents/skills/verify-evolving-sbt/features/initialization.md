# F02 — Namespace initialization

An administrator registers a namespace and a holder consents to its first authorized state. Expectations derive from the corresponding sections of `docs/specification.md` and `SECURITY.md`; `docs/discussion.md` alone is not evidence of current support.

## Sub-features

- F02-register — admin-only immutable namespace registration.
- F02-relay — controller authorization plus holder consent for relayed initialization.
- F02-direct — holder caller supplies consent but still needs controller authorization.
- F02-reject — wrong issuer role cannot initialize.

## How to get to it (user POV)

Contract wallet/SDK entry points: `registerNamespace; mint; previewTransition; transitionDigest; applyTransition; stateOf; policyOf`. An administrator, holder, issuer, controller or relayer uses the relevant public method; there is no browser screen. See `script/Demo.s.sol` for request construction, but it does not exercise every route here.

## Driving it with Foundry simulation

Preconditions: Fresh test fixture: distinct issuer/controller, registered NS, live token, revision zero.

Run `.agents/skills/verify-evolving-sbt/scripts/verify.py --feature initialization` from the repository. The helper creates isolated build/cache state and invokes the selected existing tests with full traces. Test fixtures provide fresh deployment and prerequisites; failures must not be bypassed by direct storage writes.

Actions and observable expected results: Register namespace as admin; attempted unauthorized or duplicate registration rejects. Prepare Initialize with empty record, Active status, zero expiry, exact zero-head hash and current target epoch. Submit controller authorization without holder consent through relayer: reject and keep revision zero. Add holder signature: revision one. Direct holder submission substitutes for holder signature, never for controller signature. Issuer-only initialization rejects.

Inspect per-test PASS/FAIL, public calls and assertions in the saved trace. Require the corresponding named tests to execute; exit zero with no tests is not coverage. Read-back state after rejected operations is essential. This route is simulated EVM integration; live RPC execution of these paths remains unverified.

## Gotchas

The controller signs even when caller is the holder. Uninitialized stateHash is the hash of the zero struct, not bytes32(0). Registration and holder token are prerequisites; policy.verifier is the concrete contract.

Entry points not driven by the selected tests must be separately reported; do not infer wallet, external source, privacy or full qualification coverage from these results. Preserve actions.jsonl and report.json after cleanup.
