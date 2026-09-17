# Actual Ops qualification — Desktop 0.1.6-alpha.1.cloga.1

`qualification.json` is the unchanged, bounded summary from the successful
[genuine manual run 35210215981](https://github.com/cloga/dsh-windows-ops/actions/runs/35210215981),
not a synthetic fixture or a claim of local activation.

- Qualified **code head**: `83b0303c250b62f55424be3d88347bf147c593d8`.
- Registered caller: Plugin catalog validation (`345664659`), manual opt-in;
  same-commit callee: `.github/workflows/native-asar-release.yml`.
- Called job: `105165989138`, `native-asar-qualification / qualify`; all steps,
  including summary upload and private cleanup, completed successfully.
- Artifact: `10492165208`, `native-asar-qualification-35210215981-1`.
- Raw artifact ZIP: **731 bytes**, SHA-256
  `67a5221217841b94a4a7699a6f6db5b6b0949fea19d9e23a5b4f7eff496abb96`.
- Sole raw entry `qualification.json`: **1071 bytes**, SHA-256
  `c6066e0d632bb5777c44da193ebd695a7094195319b6835ef94ddb86031df648`.

The artifact API identity, raw ZIP digest, sole entry bytes and downloaded
summary were independently compared. This directory is **separate** from the
11 raw formal-release inputs in `../formal-cloga016-1/`; those inputs were not
rewritten or expanded to manufacture qualification.

The summary binds source `fae12b69dcd28413518f68b5770e40f8eb2ff730`, source tree,
installer/EXE/descriptor digests, all **9806** runtime files, and the actual
`app.asar/package.json` name/full version/raw digest. It records real public
resolver metadata+CJS+ESM proof through the shipped native-addon path, exactly
one source-owned observer invocation, removed owned profile, and rejection of
three invalid **request copies** (descriptor digest, version, absent home).

It does **not** claim whole-carrier/DLL loaded-image attestation, a real model or
OAuth round, installer upgrade, local installation/activation, or a complete
private-peer/custom-home/missing-addon negative matrix. Source UI/restart and
ancestor-bait acceptance are separate source-owned checks in this successful
run. Output quotas are not decoder RSS/CPU limits. No raw profiles, credentials,
source logs or dependency trees are retained in this fixture.

Later documentation/evidence-only commits do not change the qualified code
head above. Runtime-affecting changes require new genuine qualification; the
final repository head must still pass fresh required CI before PR176 merges.
