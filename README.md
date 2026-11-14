# Evolving SBT with Namespaced State Transitions

An experimental reference implementation of a proposed interface for a non-transferable credential whose independently governed namespaces can evolve through evidence-authorized state transitions.

**Status: pre-ERC research implementation. No ERC number has been assigned.** The candidate interface and this implementation may change in response to review.

[Ethereum Magicians discussion](https://ethereum-magicians.org/t/pre-erc-discussion-evolving-sbt-with-namespaced-state-transitions/30361) · [Implementation specification](docs/specification.md) · [Design discussion](docs/discussion.md) · [Roadmap](docs/roadmap.md) · [Security and trust assumptions](SECURITY.md)

中文概览：本项目实现一个不可转移的 SBT，并让不同命名空间依据各自的权限和证据规则持续更新。第一版验证认可方的真实签名、状态前驱、经历追加、纠错和去重；数据公开，尚未实现 ZK 隐私证明、跨链历史验证或一次性权益核销。

## What this repository tests

The proposed interoperability boundary is small:

| Candidate method or event | Meaning |
|---|---|
| `stateOf(tokenId, namespace)` | Read the currently accepted state head. |
| `policyOf(namespace, policyId)` | Discover the immutable rule definition and its live operational controls. |
| `applyTransition(change, evidence, authorization)` | Submit an authorized transition from an exact predecessor. |
| `StateTransitioned(...)` | Observe an accepted revision and its state hashes. |

The full candidate ABI is in [`IEvolvingSBT.sol`](src/interfaces/IEvolvingSBT.sol). Minting, policy administration, profile helpers, and record inspection are implementation-specific additions, not additional proposed core methods.

A namespace is a semantic and authorization boundary. Two namespaces in the same credential can recognize different authorities and maintain independent histories. A later revision is not necessarily a higher score: correction, suspension, expiration, and revocation can reduce current usability while history remains recorded.

## v0.1 scope

The first profile uses real signed authorizations and a bounded, transparent record history. It checks the actual proposed transition; it does not accept an arbitrary administrator-supplied root or use a verifier that always returns `true`. The lifetime limit is 32 accepted records per credential and namespace, including corrections, so correction capacity must be planned.

| Implemented in the first reference profile | Deferred |
|---|---|
| ERC-721 credential with permanent ERC-5192 locking | One-person-one-credential or proof of humanity |
| Independent namespace state and policy discovery | Universal action taxonomy or reputation formula |
| Exact predecessor, sequential revision, deadline, and policy-epoch checks | Cross-chain history verification and protocol adapters |
| Signed operation authorization and holder consent for initialization | General verifier plug-in interoperability |
| Append-only accepted records and linked corrections | Policy migration |
| Stable experience identifiers and duplicate accounting checks | Independent per-claim issuer revocation registry |
| Namespace lifecycle and policy operational controls | Qualification applications and one-time entitlement consumption |
| Holder burn and non-reused credential identifiers | Account recovery integration |
| Deterministically checked public state commitments | ZK presentations, anonymous membership, and private witness management |

Signature verification establishes that a recognized authority authorized a particular statement and state change. It does not independently prove that a community task occurred or that a transaction on another protocol represents a qualifying contribution. The issuer must assign stable experience identifiers consistently; deduplication prevents reuse of the same identifier within a token and namespace, not dishonest recognition under different identifiers. Applications must accept the relevant issuer, deployment, and policy.

Record inclusion and current qualification are separate. Historical expired records may be admitted, and an expired namespace can continue accumulating records while its lifecycle status remains active. Consumers must check current namespace usability and record validity when making a decision. No balance, contribution count, or reputation score is automatically produced by this profile.

## v0.2 first slice — public qualification

The optional `ClaimRevocationRegistry` and `ContributionQualifier` add issuer-controlled single-claim revocation and a public two-contribution predicate. Revocation invalidates qualification without a holder update, including while updates are paused or history is full. The application pins the consumer's immutable registry configuration; users cannot select a fresh registry during verification.

See [qualification profile](docs/qualification-profile.md) for trust binding, correction semantics and commands, and [private profile design](docs/private-qualification-profile.md) for the future proof relation. This slice does not implement private presentations, authenticated caller admission, one-time consumption, recovery or registry migration. The v0.1 core and public record schema remain unchanged. Run `forge test --match-contract ContributionQualifierTest -vvvv` or the project verification skill's `--feature qualification` route.

## Run locally

Install [Foundry](https://getfoundry.sh/introduction/installation/), then:

```sh
git clone --recurse-submodules https://github.com/XiaoHai67890/evolving-sbt.git
cd evolving-sbt
forge build
forge test
forge script script/Demo.s.sol:Demo
```

The demo runs in local simulation by default; no RPC endpoint or funded account is required. It registers contribution and education namespaces, mints a credential, initializes both namespaces, appends and corrects an experience, and demonstrates duplicate rejection and preserved history. The tests use generated test keys and exercise accepted updates as well as rejected transitions, including independent reproductions of the commitment and typed-signature encodings.

If you cloned without submodules:

```sh
git submodule update --init --recursive
```

The repository pins dependencies through Git submodule commits. The implementation is built with Solidity 0.8.30, the Cancun EVM target, OpenZeppelin Contracts 5.7.0, and forge-std 1.17.0. See `foundry.toml` for the compiler and test configuration.

## Read the implementation

- [`src/interfaces/IEvolvingSBT.sol`](src/interfaces/IEvolvingSBT.sol): candidate core interface from the discussion.
- [`src/`](src): concrete non-transferable credential and signed growth profile.
- [`test/`](test): executable behavior, rejection cases, and regression tests.
- [`script/Demo.s.sol`](script/Demo.s.sol): reproducible local walkthrough.
- [`docs/specification.md`](docs/specification.md): concrete v0.1 encoding, authorization, lifecycle, and state-transition rules.
- [`docs/discussion.md`](docs/discussion.md): the broader proposal, including future privacy and application profiles.

The discussion describes a larger system than v0.1 implements. The implementation specification and executable tests define this repository's current behavior.

## Relationship to existing standards

The implementation uses [ERC-721](https://eips.ethereum.org/EIPS/eip-721) with [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192) permanent locking as its token base. The proposed extension explores common semantics for independently governed namespace state, policy discovery, and predecessor-bound updates.

[ERC-5727](https://eips.ethereum.org/EIPS/eip-5727) already provides dynamic issuance, revocation, and verification functionality. This proposal is not premised on existing SBT standards being universally static. This repository does not claim [ERC-5484](https://eips.ethereum.org/EIPS/eip-5484) or ERC-5727 compatibility: their lifecycle and metadata requirements need a separate compatibility analysis. The comparison and rationale are recorded in the [published design discussion](docs/discussion.md).

## Contributing

Review the [implementation specification](docs/specification.md), reproduce the demo, and bring concrete interoperability or security findings to GitHub issues or the [Magicians thread](https://ethereum-magicians.org/t/pre-erc-discussion-evolving-sbt-with-namespaced-state-transitions/30361). Include the expected behavior, observed behavior, and a minimal test where possible. Changes to the candidate ABI should explain the effect on independent consumers and distinguish core requirements from profile-specific behavior.

This code has not received an independent security audit. Read [SECURITY.md](SECURITY.md) before adapting it for a deployment with real credentials or entitlements.
