---
name: verify-evolving-sbt
description: Verify Evolving SBT contract behavior through its public ABI on an isolated local chain, or run explicitly labeled Foundry simulations. Use for feature verification and maintaining this project's Feature Map and evidence.
---

# Verify Evolving SBT

This is a Codex-native, project-scoped adaptation of Pstack. Read [the Feature Map](features/README.md) and the selected feature before driving. Resolve the repository from this file's location, not the caller's cwd. It contains `src/EvolvingSBT.sol` and `foundry.toml`. No Cursor commands, browser, login, production RPC, or real wallet are required.

## Requirements and expected behavior

Use `docs/specification.md` and `SECURITY.md` for the documented v0.1 contract, and the user's explicit requirements for intended changes. Source shows behavior, not authority to redefine requirements. `docs/discussion.md` and `docs/roadmap.md` contain future functionality that is not necessarily implemented. Do not turn a failing expectation into a passing one by rewriting the map to match code. Record ambiguity and ask the user before changing the affected expectation; independent verification may continue.

Core baseline: commit a3a1b050606e670af5dc35bc6662cc69d887e7f0; v0.2 extension work may be uncommitted and must be identified by saved source/test hashes. Record the actual commit, dirty state, source hashes, dependency revisions, and tool versions on every run. A different version requires source reconciliation.

## Launch

Prerequisites: Python 3, `forge`, `cast`, `anvil`, Solidity 0.8.30, pinned submodules. Inspect `git submodule status`; if missing, use `git submodule update --init --recursive`. Dependency/compiler bootstrap may contact their download hosts. No application account, .env, API key, database, faucet, or funded public wallet is needed.

From the repository:

```sh
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature lifecycle
```

This builds the unchanged contract with temporary output/cache paths, starts its own Anvil on 127.0.0.1 and a dynamically allocated port, chain 31337, then creates the contract on that disposable chain. This local test fixture is not a public deployment. The helper accepts no external RPC argument and does not fork a network. It gets unlocked test actors from its own node; do not substitute personal keys. Ready requires owned process alive, Anvil client, expected chain, fresh block zero, funded actors, a successful creation receipt, and deployed bytecode.

For startup failure preserve artifacts, inspect logs, repair the harness/environment if justified, then rerun in a new directory. Do not patch product code as part of skill maintenance. Each invocation owns a fresh process/state; drives on one instance are serial.

## Doctor

The helper performs read-only process/client/chain checks before first drive and after expected rejected calls/transactions. It checks funded accounts and deployed bytecode before the scenario. Commands and JSON-RPC responses are recorded. A chain ID alone does not establish ownership: require the process spawned by this run to remain alive. Port allocation races fail closed if our child exits. If an unexpected drive fails, abort and tear down; do not keep driving an uncertain instance. A retry starts fresh.

For simulation features, doctor means recorded tool/dependency versions and successful isolated compilation; no persistent server exists. CI pins Foundry 1.7.1; local 1.3.1 was observed. Do not label a run CI-equivalent unless versions match. Do not install/replace the user's global toolchain automatically.

## Drive

`lifecycle` uses actual public ABI calls and mined transactions via local JSON-RPC. It observes receipts and queries state independently; no `vm.prank`, storage setters, mocks, or test-only contract endpoints are used in this mode. Exact actions appear in `actions.jsonl`, with `cast calldata` inputs and receipt status.

Other mapped features, including the v0.2 qualification extension, use Foundry tests, explicitly labeled **simulation**, not live RPC proof:

```sh
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature initialization
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature growth
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature validity
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature authorization
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature qualification
```

These record full `-vvvv` traces, exit status and selected test outcomes. Foundry supplies fresh fixtures, generated example signatures, simulated senders and time. `script/Demo.s.sol` is also simulation, not a wallet UI or live RPC proof. Never count test names as proof without executed results. `scripts/required-tests.json` pins the required test names and suite per simulation feature; the runner reads Foundry structured JSON test_results for the exact suite and fails if any required test is missing or skipped. Printed PASS-like text in test logs is not evidence of execution. Do not regenerate or shrink this manifest merely to make a run pass. Reconcile intentional scenario changes against requirements and update the Feature Map and manifest together. The map distinguishes each route's coverage.

## Evidence

Default durable location: `<repository-parent>/verification-evidence/<UTC timestamp>-<feature>/`, outside temporary build and chain state. To choose another new directory:

```sh
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature lifecycle --evidence /absolute/new/evidence-directory
```

The helper refuses to overwrite a run. Preserve `actions.jsonl` (commands, stdout/stderr, exit codes, RPC requests/results/receipts), `report.json` (identity, checks, source/tool versions, cleanup), `anvil.log` for live mode, and `sha256.json`. Local test accounts are public fixtures; no private keys are logged. Do not store real credentials.

A pass requires actions plus read-back state, including negative cases and unchanged state after failure. Verify evidence hashes after cleanup; inspect failed runs too. Evidence has no images because the product has no UI. This is functional verification, not a cryptographic audit, a public-chain test, or proof of human uniqueness.

## Cleanup

The helper's `finally` block terminates only its recorded child process, waits (kills that child only if needed), removes its own temporary build/cache directory, and verifies port closure and evidence survival. SIGINT/SIGTERM trigger cleanup. Never use `pkill`, `killall`, `git clean`, or remove the evidence directory. A hard machine crash cannot guarantee cleanup: inspect recorded PID, command and port ownership before any manual termination, because PIDs can be reused.

After a run, inspect `process_stopped`, `scratch_removed`, `port_closed` (live mode), `evidence_survived_cleanup`, and `git status --short`. Product code must remain unchanged. Compiler bootstrap cache may remain in Foundry's user cache; it is not a leaked app instance and should not be removed globally.

## Helpers

Executable helper: `scripts/verify.py`; all six invocations are above. Standard library only. RPC is forced to loopback with proxy bypass; inherited ETH/FOUNDRY/DAPP configuration is removed for this child run and compiler output/cache are isolated. Source and tests remain the repo's own files. No background job, scheduler, merge, PR, push, or public deployment is implied.

## Maintain

When asked to maintain: check the feature index against files, inspect changed requirements/source, then drive each affected feature. For a full maintenance pass require source and runtime coverage of every mapped feature, with simulation/live distinctions preserved. Diagnose doc drift, harness gaps, product regressions, or unmet prerequisites separately. Re-drive any changed harness. Preserve evidence after every attempt. Report clean/changed/blocked plus coverage. Do not open a PR or merge automatically. Parallel agents are optional only when separately authorized in the active environment.

For the qualification route read `docs/qualification-profile.md`: the application pins the consumer and registry, revocation is claim-scoped and monotonic, and a true result is not caller authentication or entitlement consumption. Compare the complete SBT head before and after external revocation; it must remain unchanged while the predicate becomes false. A new registry with the same policy is a different application configuration, not a valid substitute.

See [sources and adaptation](sources.md) for Pstack references and the talk caption provenance.
