# Plugin catalog

`plugins.json` is the machine-readable index of DSH integrations reviewed by this repository. It is deliberately separate from the locked deployment contract.

## What an entry means

Two independent fields describe each plugin:

- `validation.level` records what was actually demonstrated.
- `recommendation` records whether the repository currently recommends the plugin for a particular class of use.

A high validation level does not automatically make a plugin broadly recommended. A desktop-control plugin can pass functional tests while remaining conditional because it can see screens, cookies, credentials, or native applications.

## Validation levels

| Level | Meaning |
|---|---|
| `L0` | Project discovered only. |
| `L1` | Source, package metadata, composition, lifecycle scripts, and obvious security boundaries reviewed. |
| `L2` | Static dependency analysis and a real host-entry import probe passed. |
| `L3` | Isolated DSH profile mounted; expected Cordis rows activated and tools registered. |
| `L4` | Representative end-to-end function passed against a controlled target. |
| `L5` | Exact identity, acceptance evidence, security notes, and rollback are recorded. |
| `baseline` | Component is included in a maintained deployment lock. |

Levels are cumulative claims. Do not promote an entry because an upstream README claims compatibility; attach evidence produced or independently checked by this repository.

## Recommendation states

- `recommended`: preferred for its documented use case.
- `conditional`: usable only under stated constraints.
- `experimental`: promising, but incomplete evidence or unstable behavior remains.
- `historical`: retained because the investigation or fix is useful; not a current install recommendation.
- `rejected`: evaluated and unsuitable; explain why in `notes`.
- `unreviewed`: discovered but not assessed.

## Updating the catalog

1. Review the source and package before installing it.
2. Run `node tools/dsh-compat-check.mjs <profile> --probe=<package>` after placing it in a disposable Profile.
3. Mount it in an isolated DSH home and record activation/tool evidence before claiming `L3`.
4. Exercise a harmless representative operation before claiming `L4`.
5. Record exact source/artifact identity, acceptance checks, and rollback before claiming `L5`.
6. Add it to a deployment lock only if it is part of the supported baseline.
7. Run `node tools/validate-plugin-catalog.mjs` before committing.

The schema is `schema/plugin-catalog.schema.json`. The validation tool performs the repository-specific semantic checks that plain JSON Schema cannot express without an additional dependency.

## Security fields

Unknown values stay `null`; do not guess. In particular, verify whether a plugin:

- controls the desktop;
- captures screenshots;
- reuses an existing browser profile and its cookies;
- sends page or screen data to another service;
- provides an approval gate for side effects.

See `docs/plugins/plugin-validation.md` and `docs/plugins/computer-use.md` for the full workflow.
