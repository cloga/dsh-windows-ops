# Choosing a DSH plugin

Start with the capability and trust boundary, not with a package name.

## Decision order

1. **Can the built-in DSH capability do it?** Avoid another plugin when the Host already provides the required service or tool.
2. **Is the capability shared across sessions?** Model routes, persistence, settings, credentials, sandboxes, and subagent registries belong to the Host composition.
3. **Is it one agent's contribution?** Persona, tool rows, prompt sections, and compaction policy belong to an agent preset.
4. **Does it publish a preset-owned Service?** Keep its provider and consumers in one isolated realm.
5. **Does it need a browser or desktop?** Prefer the narrowest executor: isolated browser, then existing browser, then native UIA, then general screenshot/coordinate control.
6. **What evidence exists?** Consult `catalog/plugins.json`; do not infer support from project popularity or an upstream compatibility claim.

## Reading the catalog

Use both:

- `validation.level`: the strongest demonstrated technical evidence;
- `recommendation`: the operational recommendation under the documented security constraints.

A `baseline` component is supported by a maintained deployment lock. An `L0` or `L1` candidate may still be worth testing, but it should not be installed into a production Profile.

## User-reported high-privilege candidates

| Plugin | User experience signal | Repository evidence | Recommendation |
|---|---|---|---|
| [`csyangwen/dsh-memory-evolve`](https://github.com/csyangwen/dsh-memory-evolve/tree/c337dc1af7b5c8a5578e03150bf5c4d6133f66f9) | User-reported useful for cross-session memory/evolution workflows. | `L1` source review at commit `c337dc1af7b5c8a5578e03150bf5c4d6133f66f9` / tag `v26091501`; MIT license; private package with no declared DSH peer range; Release has no assets or checksum manifest; no isolated DSH mount or functional smoke. | `experimental`. Do not treat the user report as repository functional or security validation. |

This plugin can persist long-term memory, manage or modify skills and prompts, write tasks, inject context, check for and apply source updates, and optionally dispatch external CLIs, search local/session data, create or wake Sessions, synchronize memory through Git, and send channel messages. Its runtime data defaults to `DSH_HOME/memories`, while skill writes can reach `~/.agents/skills`; uninstalling retains those files. Evaluate it in an isolated Profile, inspect the data-retention and automatic-modification boundaries, and enable optional capabilities individually. It is not in the Windows locked baseline, the Desktop required plugin set, default automatic installation, or the optional companion suite.

Because the reviewed Release contains no immutable package asset, this repository does not publish a verified Release artifact hash or recommend a production installation command for it. The [unreleased Desktop source-snapshot work](desktop-source-installation.md#evidence-recorded-for-issue-50) separately records acquisition, packing, and validation of this exact source commit without Host activation. Its local packed-byte hash is not an upstream Release checksum, and this evidence does not promote the catalog's `L1`/`experimental` classification. A source import alone is not the `L2` host-entry probe defined by this catalog.

## Safe evaluation path

1. unpack and source-review the exact artifact;
2. use a disposable Profile and `tools/dsh-compat-check.mjs`;
3. use an isolated `DSH_HOME` for composition and functional smoke;
4. capture evidence and update the catalog;
5. install into a maintained Profile only after the result meets that Profile's support policy.

See `plugin-validation.md` for evidence requirements and `computer-use.md` for browser/desktop-specific controls.
