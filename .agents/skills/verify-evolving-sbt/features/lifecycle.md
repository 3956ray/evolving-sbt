# F01 — Holder credential lifecycle

A holder creates a permanently nontransferable credential and may destroy it. Destruction does not allow the identifier to be reused. Expected behavior: specification sections Deployment and credential lifecycle; implementation entry points in `src/EvolvingSBT.sol`.

## Sub-features

- F01-mint: self-mint creates ownership, balance and a locked token.
- F01-transfer: ordinary, self, and both safe-transfer overloads reject.
- F01-burn: only the holder can burn; absent-token queries reject.
- F01-continuity: another mint uses token 2 rather than reusing token 1.

## How to get to it (user POV)

A wallet/SDK submits `mint()`, reads `ownerOf`, `balanceOf`, `locked`, tries ERC-721 transfer entry points, then submits `burn(tokenId)`. No namespace or issuer is needed. Approval behavior is a separate regression test and is not included in this live recipe.

## Driving it with local RPC

Preconditions: fresh owned Anvil, chain 31337, three funded unlocked test accounts, contract created with the admin account; no token exists. Run `.agents/skills/verify-evolving-sbt/scripts/verify.py --feature lifecycle` from the repo.

- Holder sends `mint()`: mined successful receipt contains Transfer and Locked topics; token 1 owner equals holder, locked is true, balance is 1.
- Holder calls `transferFrom(holder, other, 1)`, self-transfer, and both `safeTransferFrom` overloads: all return `Soulbound()` revert data through eth_call.
- Holder actually sends the ordinary transfer with explicit gas: mined receipt status 0; independent ownerOf still returns holder. Doctor rechecks instance.
- Other account sends `burn(1)`: mined status 0; token still exists.
- Holder sends `burn(1)`: mined status 1; ownerOf(1) and locked(1) revert; balance becomes 0.
- Holder sends `mint()` again: ownerOf(2) returns holder; ownerOf(1) still reverts.
- Inspect actions, read-back checks, receipts, then cleanup and evidence checks in report.json. Expected rejection is a passing assertion only for that specific negative step.

## Gotchas

All wallets here are local test actors, not browser wallet coverage. Safe-transfer variants and self-transfer are eth_call rejection checks; only ordinary transfer is also mined. Unregistered namespaces are intentionally irrelevant. Burn deletes usability, not blockchain history or privacy traces. No one-person-one-token claim. Do not use the example actors on a public network.
