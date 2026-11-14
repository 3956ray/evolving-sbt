# Evolving SBT Feature Map

Read this index, then the feature recipe. This is a maintained map of documented user-facing contract behavior, not a declaration that all behavior is correct or all paths are verified.

## Baseline and entry surface

Primary surface: public contract ABI used by holders, issuers, controllers and relayers. There is no frontend, login, HTTP app server or persistent database. Existing secondary surfaces are Foundry tests and the local Demo script. Fixtures create a new contract, distinct role accounts, namespaces and a holder token as needed. No public-chain assets or real user data.

Expected v0.1 behavior comes from `docs/specification.md` and `SECURITY.md`. The separate `docs/qualification-profile.md` specifies the implemented external revocation and public qualification extension. Consumption and private presentations remain future capabilities. Check source for reachability, not to invent requirements.

## Features and coverage at creation

| ID | Feature | Executable route | Coverage |
|---|---|---|---|
| F01 | [Credential lifecycle](lifecycle.md) | local RPC public ABI | Run result in evidence report; all listed lifecycle steps required |
| F02 | [Namespace initialization](initialization.md) | Foundry simulation | Recipe mapped; not run in this creation pass |
| F03 | [Growth and correction](growth.md) | Foundry simulation | Recipe mapped; not run in this creation pass |
| F04 | [Current namespace usability](validity.md) | Foundry simulation | Recipe mapped; not run in this creation pass |
| F05 | [Authorization and replay](authorization.md) | Foundry simulation | Recipe mapped; not run in initial creation pass |
| F06 | [External revocation and current qualification](qualification.md) | Foundry simulation | Executable acceptance route; see saved qualification run for results |

Prior 51-test suite success is context, not new evidence for these recipes. All mapped features have source coverage; only a saved run establishes runtime coverage. Simulated sender/time tests do not establish live wallet integration.

## Evidence and interpretation

Use the skill helper; every run writes actions and result outside scratch. A successful transaction requires receipt status 1 and independent read-back, not a submitted transaction hash alone. A rejected action requires the intended error/failed receipt and preserved state, not just any command error. Capture feature and entry route, commit, tool versions and cleanup. Never equate `active`, `isCredited` or `isUsable` with full application eligibility.

## Open requirements for future features

The current lifecycle expectations are documented and sufficient for F01; no user decision is required to exercise them. F06 fixes application-pinned issuer/registry/key binding as documented in the qualification profile. Before v0.3 implementation, confirm cross-credential entitlement scope and privacy target (hidden materials versus hidden/linkable identity). Do not infer these from the v0.1 storage layout. No future feature is marked verified here.
