# Sources and adaptation

Reviewed 2026-11-14 (Asia/Shanghai).

- [Pstack README](https://github.com/cursor/plugins/tree/main/pstack): verification as a foundation for reliable engineering; only relevant verification practices were adapted.
- [Create verification skill](https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/SKILL.md): inspect the repo; launch/doctor/drive/evidence/cleanup; seed a feature map; prove one journey and retain evidence after teardown.
- [Maintain verification skill](https://github.com/cursor/plugins/blob/main/pstack/skills/maintain-verification-skill/SKILL.md): source reconciliation plus runtime exercise; distinguish drift from product regressions; re-drive harness fixes; preserve partial evidence.
- [Feature map example](https://github.com/cursor/plugins/tree/main/pstack/skills/create-verification-skill/references/feature-map-example): four-section feature entries and explicit entry-point coverage.
- [Lauren Tan talk](https://www.youtube.com/watch?v=I_oMJk6barY): English automatic captions retrieved using the YouTube transcript provider via Firecrawl. Provider title: “SpaceX AI engineer, Lauren Tan”. Automatic transcription may misrecognize terms. Relevant discussion describes running the user's actual surface, a feature map to help agents navigate, and evaluating verification skills rather than trusting prose. No literal transcript is redistributed here.

Adaptations: `.agents/skills` plus optional Codex user-skill symlink instead of `.cursor/skills`; subprocess and local JSON-RPC instead of browser/control-glass; durable JSON evidence instead of UI screenshots; no automatic PR/merge, no mandated multi-agent/model setup. Public ABI interactions are the real product surface for this contract-only repository. Existing test fixtures are explicitly labeled simulation rather than live user proof.

Investigation: README quickstart, foundry.toml, CI, pinned submodules, all src interfaces/implementation, test helpers and main suite, Demo, implementation specification, SECURITY, roadmap and discussion. Foundry compiles Solidity 0.8.30 for Cancun with optimizer 200 runs. CI pins Foundry 1.7.1, local environment currently 1.3.1; fmt differences were already observed before this task. No web server, auth provider, database or frontend exists. Dependency/compiler downloads are the only setup network needs; runtime helper targets only owned loopback Anvil.
