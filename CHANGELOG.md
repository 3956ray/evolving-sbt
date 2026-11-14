# Changelog

## Unreleased — v0.2 public qualification slice

- Add application-pinned single-claim revocation with issuer authority checked against immutable policy commitments.
- Add public two-distinct-contribution qualification checking namespace, policy, expiry, supersession, subject and external revocation.
- Cover revocation without SBT updates, update pauses, full history, trusted registry binding and negative cases.
- Document the public predicate and future private proof relation; extend the verification skill and Feature Map with durable simulation evidence.
- Core ABI and v0.1 record/state encodings remain unchanged. ZK and entitlement consumption remain deferred.


## 0.1.0 — Initial experimental reference implementation

- Preserve the candidate three-method, one-event interface from the pre-ERC discussion.
- Implement a permanently locked credential with independent namespace state.
- Add a concrete signed growth profile with accepted history, linked corrections, and duplicate accounting checks.
- Check exact predecessor state, sequential revision, policy epochs, operation authority, and deadlines.
- Separate policy operational controls from immutable definitions and enforce namespace lifecycle rules.
- Include a local demonstration, executable tests, implementation documentation, and explicit trust assumptions.

Independent per-claim revocation, qualification and consumption applications, policy migration, account recovery, protocol adapters, and ZK privacy remain future work. No ERC number, independent audit, or production readiness is claimed.
