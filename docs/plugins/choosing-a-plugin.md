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

## Safe evaluation path

1. unpack and source-review the exact artifact;
2. use a disposable Profile and `tools/dsh-compat-check.mjs`;
3. use an isolated `DSH_HOME` for composition and functional smoke;
4. capture evidence and update the catalog;
5. install into a maintained Profile only after the result meets that Profile's support policy.

See `plugin-validation.md` for evidence requirements and `computer-use.md` for browser/desktop-specific controls.
