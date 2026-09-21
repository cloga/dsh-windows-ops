# Offline original-ZIP and selected-member auditor

Tracking: [Ops #219](https://github.com/cloga/dsh-windows-ops/issues/219).

## Status and platform boundary

**Windows validation FAILED / HOLD USE. Linux validation is pending.** This is
maintained offline audit tooling preparation, not product qualification or
permission to use an unqualified revision on formal evidence.

The frozen Windows suite ran 59 methods: 58 passed and one DEFLATED 300 MiB
integration subcase errored with `input-changed-during-read`; zero skipped.
The author run took 22.502 seconds. An independent exact-frozen run took 23.478
seconds and failed the same subcase: device, inode and size were unchanged,
but **both mtime and ctime changed**. STORED passed its three modes; that does
not cover the failed DEFLATED subcase. The cause is unestablished. Do not call
it harmless, attribute it to security software, weaken timestamp checks or
rerun identically until green. This is not an npm dependency restriction.

The existing Linux `repository-content` CI job now explicitly invokes the same
59 methods. A future successful run qualifies only its exact source, Python/zlib
and Linux environment; it cannot erase the Windows failure or claim Windows
support. Record terminal results, not just suite startup or an earlier partial
pass. Real-artifact use needs separately authorized, platform-scoped review.

## Purpose, prerequisites and mutation

`tools/artifact-zip-audit.py` verifies an original classic ZIP against a supplied
GitHub artifact API snapshot and expected Core run/source, checks every member,
and optionally compares selected members byte-for-byte with existing retained
files. It is separate from the Ops runtime/native evidence reader. That reader's
API/original-JSON consistency is not proof of original ZIP membership.

- Python **3.12.10**, standard library only; no pip packages, npm, browser or app.
- Caller-owned, preexisting ordinary local input files and physical directories.
  Authenticate acquisition separately using the mandatory cloga identity gate.
- Explicit expected run ID and full source commit, independently established by
  the caller. The repository binding is fixed to `cloga/deepseek-harness`.
- Originals, snapshots and retained files are read-only. Default output is stdout.
  Optional `--report` creates a **new** ordinary file exclusively; it never
  overwrites and must be outside the retained root in comparison mode.
- No download, extraction, archive-code import/execution, package installation,
  configuration mutation, Desktop activation or restart. Offline parsing does
  not authenticate metadata, determine current remote expiry, or prove workflow
  success, accepted product inventory, installation or semantic acceptance.

No runtime state changes, so there is no installation rollback. Preserve original
inputs and evidence. If cleanup is explicitly wanted, remove only an owned optional
report; never use cleanup to replace or conceal a failed result. Inert tests own
and automatically clean their temporary fixtures; they do not overwrite real data.

## Invocation contract

From the repository root, `python -I -B tools/artifact-zip-audit.py --help` is
safe syntax/usage inspection. `-I` isolates Python import/environment behavior;
`-B` avoids bytecode files. The following is a **parameter template, not a real
artifact run or authorization**. Replace bracketed values with already acquired,
owned absolute paths and independently verified identities:

```text
python -I -B tools/artifact-zip-audit.py --zip <absolute-original.zip> --metadata <absolute-api.json> --expected-run <run-id> --expected-source <full-commit> --inspect-only
python -I -B tools/artifact-zip-audit.py --zip <absolute-original.zip> --metadata <absolute-api.json> --expected-run <run-id> --expected-source <full-commit> --target-root <absolute-retained-root> --mapping <absolute-mapping.json>
```

The mapping is a **nonempty JSON object** from exact original ZIP member names
to safe retained paths relative to the existing target root, for example:

```json
{"evidence/qualification.json": "qualification.json"}
```

This example does not identify a real member or authorize fabrication of a
qualification file. Every selected target must already exist as an ordinary
physical file. Missing targets are not extracted or created.

`--inspect-only` forbids `--mapping` and `--target-root`. It uses the same full
parser, original ZIP/API binding, structural checks and all-member decode/CRC
validation, but performs no selected comparison. Reports identify
`scope: offline-original-zip-inspection`, `selectedComparisonsPerformed: false`,
`selected: []`, and `targetRoot: null`. Final mode reports `compare-selected`
and successful selected comparisons only after the nonempty mapping passes.
A mapping selecting metadata alone is still comparison mode, **not** a separate
CLI mode or a way to skip decoding large unselected members.

Optional `--report <fresh-file>` requires an existing ordinary physical parent;
existing reports fail rather than being replaced. Success prints JSON and exits
zero. Validation/input errors print a `valid:false` error record and exit one;
argument syntax errors use argparse's nonzero exit. Preserve failures unchanged.
Reports always leave `metadataAuthenticationPerformed`, `workflowSuccessVerified`,
`acceptanceQualificationVerified`, `extracted`, and `packageCodeExecuted` false.

For separately authorized real promotion, the sequence remains authenticated
original acquisition → inspect-only → separately owned bounded selected
extraction from the **same validated original**, rechecking raw identity/hash →
final nonempty-mapping audit. Extraction is **not implemented here**. Do not
manufacture inspection targets, re-zip originals, or substitute synthetic CI
metadata for authenticated evidence. The actual four-original-ZIP promotion and
fresh Ops/native qualification remain separate owner-controlled gates.

## Fixed profiles and bounds

| Profile | Each uncompressed member | Total uncompressed |
|---|---:|---:|
| `evidence` (default) | 32 MiB / 33554432 bytes | 256 MiB / 268435456 bytes |
| `desktop-build` (explicit) | 384 MiB / 402653184 bytes | 448 MiB / 469762048 bytes |

Use `--profile desktop-build` explicitly, consistently for both inspection and
later comparison when authorized. The Python API accepts the keyword-only
`profile="desktop-build"`. Limits are owned per invocation; there is no numeric
override, mutable global default, automatic escalation or filename exception.

Shared limits remain: archive 512 MiB; metadata/mapping 1 MiB; central metadata
16 MiB; 10,000 members; names 4,096 UTF-8 bytes; per-entry extra/comment 4,096
bytes. Classic single-volume STORED/DEFLATED ZIPs with supported ordinary or
data-descriptor headers only. **ZIP64, unsupported extras/methods, encryption
and multipart archives are rejected**, not silently converted. Stop for review
when a real original exceeds these contracts.

Both profiles validate all members, including unselected large installers:

- Actual central count; local/central names, flags, sizes, CRC, method and
  descriptors; no gaps, overlap, prefix/trailing ambiguity or inconsistent types.
- Safe normalized relative paths; reject traversal, absolute/drive/ADS forms,
  aliases, duplicate/file-ancestor conflicts, links/reparse/special types, Windows
  reserved devices including `CONIN$`, `CONOUT$` and COM/LPT superscript aliases.
- Bind path-to-fd shared identity/size/mtime and birthtime, retaining the reviewed
  Python 3.12 Windows path/fd ctime distinction. Later descriptor stability keeps
  **all `(dev, ino, size, mtime_ns, ctime_ns)` fields**. No rebaseline or retry.
- Compressed reads and returned decoded pieces bounded to 65,536 bytes; drain
  `unconsumed_tail`, positive bounded overflow sentinel, bounded empty drains,
  progress/EOF/unused-data checks, exact size/CRC/SHA and retained comparisons.
  No decoder flush or whole-member buffering. Retained reads are bounded too.

These are finite resource and consistency policies, not a concurrent-filesystem
security boundary, exact RSS ceiling, NSIS validation or installer qualification.
The caller separately establishes authority, authentic provenance and correct
product/channel inventory before trusting artifact integrity.

## Regression suite and existing CI

```text
python -I -B tests/artifact-zip-audit-tests.py
```

All **59 methods** are retained: the original 35 plus 24 streaming/profile tests.
The Ops port changes only the module lookup from tests to `../tools/` and moves
owned temporary fixtures off the source directory to system/runner temp. No
assertion, test-method body, size/profile, production guard or decoder is weakened.
There are no platform skips or expected failures. Do not rerun the known failing
Windows full suite merely to seek green; static preservation/help checks are
not substitutes for a successful complete platform test.

The large integration case streams **300 MiB inert** DEFLATED and STORED
fixtures, checks inspection, metadata-only selection, complete retained
comparison and negative cases. Generation closes/fsyncs synthetic writes and
has exactly one fixed two-second settling pause per large fixture before the
first audit. That existing test-only pause is not a production sleep, retry,
timestamp reset or resolution of the observed Windows failure.

Only `.github/workflows/plugin-catalog.yml`'s existing Ubuntu
`repository-content` job adds Python steps. It retains its ten-minute timeout,
Node validator/tests, workflow read permissions and existing event triggers.
No new workflow/job/matrix/native lane is added; the manual native condition and
Windows validate block are unchanged. The Python invocation fails the job on
errors; no `continue-on-error`, selective methods or swallowed exits.

CI emits actual Python/platform/zlib versions, checked-out commit/tree, tool/test
SHA-256, event/GitHub SHA/job identity and run/attempt URL. PR checkout can be a
merge commit, so do not confuse it with the branch head. Acceptance requires the
exact-source terminal **59 tests, zero errors/failures/skips**, both large
compression subcases and all existing relevant checks. After source changes,
refresh evidence. Linux green is not Windows green or release qualification.

### Python action provenance and CI provisioning

Official [`actions/setup-python` v6.3.0](https://github.com/actions/setup-python/releases/tag/v6.3.0)
is pinned to [`ece7cb06caefa5fff74198d8649806c4678c61a1`](https://github.com/actions/setup-python/commit/ece7cb06caefa5fff74198d8649806c4678c61a1),
not a mutable version tag. Authenticated GitHub ref queries independently resolved
both `v6` and `v6.3.0` to this commit; commit tree is
`39217d5f784fb44e42ddb8e5702f05256b29829e`, with GitHub verification `valid`.
Reviewed pinned `action.yml`, `src/setup-python.ts` and `src/find-python.ts` for
inputs, Node 24 execution, runtime acquisition and conditional cache/pip behavior.
This is scoped integration/provenance review, not a full bundled dependency audit.

The workflow selects exact Python `3.12.10`, `check-latest: false`, and no
package-cache, `pip-version` or `pip-install` input. The action uses a matching
runner tool cache or acquires Python from `actions/python-versions`; ordinary
runner/Python setup may download dependencies. The **test body** is stdlib-only,
inert and offline, not the entire Actions job. Matching Python versions do not
imply matching zlib builds. A newer action major exists; this reviewed Node 24
v6.3.0 pin does not claim to be latest. No unreviewed action bump is implied.

### Resource estimate

Sequential fixtures may hold about **600 MiB plus overhead** at once (300 MiB
retained file plus STORED ZIP), with several GiB of logical I/O across passes.
Cleanup is per test. Streaming bounds do not equal total memory usage. Failed
Windows runtimes of roughly 23 seconds are not Linux timing proof; Linux time,
peak memory and actual disk use remain unmeasured. Measure within the existing
timeout rather than assuming success or adding a runner. Normal Linux Actions
minutes and runtime setup can consume account quota or incur charges; no new
paid service/model API is used.

## Frozen-source preservation record

The production file is adopted byte-for-byte from the reviewed frozen auditor;
only the two test infrastructure expressions described above change.

| Frozen input | SHA-256 |
|---|---|
| Auditor | `5b85ad6a935bb5b965893e6d181f0cbc62ebd3b74cc01b0d3a0027e57644f68d` |
| 59-test suite before portability edits | `b76203bb0d7813f81d8ade6c91cfe91f0865d924d5f933921da68f4d31107ab5` |

Record the maintained test file's new digest in CI/review rather than claiming it
retains the frozen digest. All 59 method ASTs and original 35 bodies must remain
unchanged. Historical small-archive integrity results cannot qualify this revision
or turn a failed installer acceptance record into success. No real artifacts,
locks, catalogs, qualification fixtures or published evidence are changed here.
