# Public contribution qualification — v0.2 first slice

This application profile adds independent single-claim revocation and a bounded public predicate to the v0.1 signed-growth implementation. It does not change `IEvolvingSBT`, its interface ID, existing record encoding, or existing state commitments. It is not the full v0.2 milestone: one-time consumption, recovery and balance checkpoints remain deferred.

## Trust and deployment binding

An application chooses a trusted, non-upgradeable `EvolvingSBT` deployment and contribution namespace. Every issuer-accepted record in this chosen namespace counts as a contribution; there is no additional interpretation of `contentHash`, no score and no external-chain truth proof.

Deploy `ClaimRevocationRegistry(credential, namespace, issuer, controller)` after namespace registration. Its constructor reads the policy and verifies the supplied authority preimages against `authorizationHash` and `verifierConfigHash`, as well as the concrete verifier, schema and rules. Issuer and controller addresses are not accepted merely because a caller supplied them. This is a concrete signed-growth adapter, not a general ERC verifier plug-in or a defense against an application selecting a malicious SBT contract.

Deploy `ContributionQualifier(credential, namespace, policyId, registry)` and pin that consumer address in the application. Its constructor checks registry scope against the selected credential, namespace and policy. All four references are immutable. `qualifies` takes only a token ID and two record indices: no caller-selected registry, policy or credential.

Binding chain:

- Issuer signatures accepted by the SBT bind records (including subject, claim ID and content) into its state.
- Immutable SBT policy commitments authenticate the issuer recognized by the registry.
- The application's immutable consumer configuration selects that registry for those claims.
- The registry derives the claim key from the complete scope below.

This is application-level registry binding. The old Record schema does **not** contain a portable issuer-signed registry locator. No claim is made that old claims cryptographically named this new registry. For portability, the future private profile must authenticate the registry locator in issuance or an explicitly versioned recognition/application policy. An application must not accept arbitrary user-provided qualifier deployments: another registry and qualifier can be deployed with the same scope but different revocation history. That is a different trust configuration, not an interchangeable endpoint.

## Revocation semantics

`revoke(tokenId, claimId)` can be called only by the fixed issuer address. A contract issuer invokes it from its wallet execution path; relayed revocation signatures and key rotation are not added here. A controller or holder has no implicit revocation authority.

The key is:

```text
keccak256(abi.encode(
  deploymentChainId, credentialAddress, namespace, policyId, tokenId, claimId
))
```

The chain ID is captured at deployment so a subsequent chain-ID change cannot make stored revocations disappear. Registry identity is fixed by the consumer and is a separate part of the full locator. This does not promise cross-chain revocation synchronization or fork resolution.

Revocation is monotonic and idempotent. The first call records true and emits `ClaimRevoked`; repeated calls do not emit another event. A zero claim ID is rejected. Revocation before admission is permitted and persists if that claim later enters the SBT. No capacity, liveness, update-permission or holder-consent check blocks revocation. There is no restoration method and no migration/reset path.

The revoked object is a **claim**, not the whole experience or person. Correcting a revoked claim issues a new claim ID linked to the same experience. In this workflow revoke the old claim first, then have the issuer authorize the normal correction; there can be a temporary qualification gap. The original revocation remains recorded. The v0.1 correction method itself is unchanged and does not automatically write the external registry. Local supersession also excludes an unrevoked old record from this consumer.

## Predicate and observable behavior

`qualifies(tokenId, uint256[2] indices)` evaluates in the call's block:

1. Credential exists; namespace is initialized, Active and unexpired; policy permits use (`isUsable`).
2. Current head policy equals the consumer's pinned policy.
3. Two different indices are in bounds.
4. Both records are nonsuperseded, belong to the current holder, and have no expiry or `block.timestamp <= validUntil`.
5. Their experience identifiers differ.
6. Neither claim is revoked in the pinned registry.

False is returned for absent/burned/uninitialized tokens, inadequate records, expiry, supersession, revocation or failed namespace conditions. Unexpected dependency errors revert; they are never converted into a successful qualification. `updatesEnabled` does not govern use. Two qualifying records may be selected from a larger history; revocation of an unused record does not necessarily remove all possible qualifying pairs.

This is a public predicate, not caller authentication, a signed certificate, historical inclusion proof, admission grant or consumption ledger. Anyone may ask about another holder's token. An application granting a benefit must separately authenticate the intended holder/recipient and recheck in the granting transaction, rather than rely on an earlier off-chain boolean.

## Acceptance and execution

Run:

```sh
forge test --match-contract ContributionQualifierTest -vvvv
.agents/skills/verify-evolving-sbt/scripts/verify.py --feature qualification
```

The latter preserves command/trace evidence, source and test hashes, tool versions and cleanup results. These are Foundry EVM simulations with real contract logic and EIP-712 signatures; they do not claim a live RPC or browser-wallet journey.

The central test asserts true before revocation and false after it, while the complete SBT head hash, count and local record status remain unchanged. Additional cases cover issuer authorization, events/idempotence, scope binding, a fresh unrevoked registry that cannot replace the pinned one, duplicate/invalid selections, pre-admission revocation, inclusive expiry, supersession, suspension, policy use controls, burned tokens, paused updates, and full 32-record history.

## Limitations

Authority addresses and consumer policy configuration are immutable; key recovery and registry migration require a separate design. SBT subjects are account addresses, not unique people. Issuer trust and identifier canonicalization remain essential. This public profile discloses token IDs, selected records and revocations and must not be advertised as privacy protection. See [the private profile design](private-qualification-profile.md).
