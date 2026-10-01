"""Inert archive data tests only; no archive extraction, package execution or network."""
import contextlib
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import struct
import sys
import tempfile
import time
import types
import unittest
from unittest import mock
import warnings
import zipfile
import zlib

HERE = Path(__file__).parent
spec = importlib.util.spec_from_file_location("artifact_zip_audit", HERE.parent / "tools" / "artifact-zip-audit.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
SOURCE = "a" * 40
RUN = "123"


def archive_bytes(entries=None, compression=zipfile.ZIP_DEFLATED, descriptors=False):
    class NonSeekable(io.BytesIO):
        def seek(self, *args):
            raise OSError("inert nonseekable writer")
    buffer = NonSeekable() if descriptors else io.BytesIO()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", UserWarning)
        with zipfile.ZipFile(buffer, "w", compression=compression, allowZip64=False) as output:
            for name, data, mode in entries or [("evidence/selected.json", b'{"inert":true}\n', stat.S_IFREG | 0o644),
                                              ("diagnostics.txt", b"inert diagnostics\n", stat.S_IFREG | 0o644)]:
                entry = zipfile.ZipInfo(name)
                # Keep deliberately unsafe test names as original bytes; Windows ZipInfo otherwise normalizes backslashes.
                entry.filename = name
                entry.orig_filename = name
                entry.compress_type = compression
                entry.create_system = 3
                entry.external_attr = mode << 16
                if name.endswith("/"):
                    entry.external_attr |= 0x10
                output.writestr(entry, data)
    return buffer.getvalue()


def edit_header(raw, local_offset=None, central_offset=None, value=None, fmt="H"):
    data = bytearray(raw)
    if local_offset is not None:
        struct.pack_into("<" + fmt, data, local_offset, value)
    if central_offset is not None:
        start = data.index(b"PK\x01\x02")
        struct.pack_into("<" + fmt, data, start + central_offset, value)
    return bytes(data)


def raw_deflate(data, finish=True):
    encoder = zlib.compressobj(wbits=-15)
    return encoder.compress(data) + encoder.flush(zlib.Z_FINISH if finish else zlib.Z_SYNC_FLUSH)


def crafted_archive(entries):
    """Small inert classic ZIP fixtures with independently controlled raw streams."""
    local = bytearray()
    central = bytearray()
    for row in entries:
        name = row["name"].encode("ascii")
        data = row.get("data", b"")
        method = row.get("method", zipfile.ZIP_DEFLATED)
        compressed = row.get("compressed")
        if compressed is None:
            compressed = raw_deflate(data) if method == zipfile.ZIP_DEFLATED else data
        size = row.get("declared", len(data))
        crc = row.get("crc", zlib.crc32(data) & 0xffffffff)
        descriptor = row.get("descriptor")
        flags = 8 if descriptor else 0
        offset = len(local)
        local.extend(struct.pack("<4s5H3L2H", b"PK\x03\x04", 20, flags, method, 0, 33,
                                 0 if descriptor else crc, 0 if descriptor else len(compressed),
                                 0 if descriptor else size, len(name), 0))
        local.extend(name)
        local.extend(compressed)
        if descriptor:
            if descriptor == "signed":
                local.extend(b"PK\x07\x08")
            local.extend(struct.pack("<3L", crc, len(compressed), size))
        central.extend(struct.pack("<4s6H3L5H2L", b"PK\x01\x02", (3 << 8) | 20,
                                   20, flags, method, 0, 33, crc, len(compressed), size,
                                   len(name), 0, 0, 0, 0, (stat.S_IFREG | 0o644) << 16, offset))
        central.extend(name)
    return bytes(local + central + struct.pack("<4s4H2LH", b"PK\x05\x06", 0, 0, len(entries),
                                              len(entries), len(central), len(local), 0))


class DecoderProbe:
    """Wrap real zlib without retaining payloads or per-call traces."""
    def __init__(self, case):
        self.case = case
        self.factory = zlib.decompressobj
        self.calls = self.tail_calls = self.empty_calls = self.output_bytes = 0
        self.max_output = self.max_input = self.max_requested = 0
        self.sentinel_calls = 0

    def __call__(self, wbits):
        self.case.assertEqual(wbits, -15)
        real = self.factory(wbits)
        probe = self
        class Adapter:
            def decompress(self, data, max_length):
                probe.case.assertGreater(max_length, 0)
                probe.case.assertLessEqual(max_length, audit.OUTPUT_CHUNK)
                probe.case.assertLessEqual(len(data), audit.CHUNK)
                result = real.decompress(data, max_length)
                probe.case.assertLessEqual(len(result), max_length)
                probe.calls += 1
                probe.tail_calls += bool(real.unconsumed_tail)
                probe.empty_calls += not data
                probe.sentinel_calls += max_length == 1
                probe.output_bytes += len(result)
                probe.max_output = max(probe.max_output, len(result))
                probe.max_input = max(probe.max_input, len(data))
                probe.max_requested = max(probe.max_requested, max_length)
                return result
            def __getattr__(self, name):
                if name == "flush":
                    raise AssertionError("decoder flush must never be used")
                return getattr(real, name)
        return Adapter()


class ReadProbe:
    """Bound selected payload reads without interfering with structural metadata reads."""
    def __init__(self, case, stream):
        self.case, self.stream = case, stream
        self.calls = self.max_requested = 0

    def read(self, size=-1):
        self.case.assertGreaterEqual(size, 0)
        self.case.assertLessEqual(size, audit.OUTPUT_CHUNK)
        self.calls += 1
        self.max_requested = max(self.max_requested, size)
        return self.stream.read(size)

    def __getattr__(self, name):
        return getattr(self.stream, name)


class AuditTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="artifact-audit-inert-")
        self.root = Path(self.temporary.name)
        self.target = self.root / "retained"
        self.target.mkdir()
        (self.target / "selected.json").write_bytes(b'{"inert":true}\n')
        self.zip = self.root / "original.zip"
        self.metadata = self.root / "api.json"
        self.mapping = {"evidence/selected.json": "selected.json"}
        self.install(archive_bytes())

    def tearDown(self):
        self.temporary.cleanup()

    def install(self, raw):
        self.zip.write_bytes(raw)
        self.bind_metadata()

    def bind_metadata(self):
        # Fixture finalization only: flush owned synthetic writes before binding.
        # Never relax or retry the auditor's identity/timestamp stability checks.
        with self.zip.open("r+b") as finalized:
            finalized.flush()
            audit.os.fsync(finalized.fileno())
        digest = hashlib.sha256()
        size = 0
        with self.zip.open("rb") as stream:
            for block in iter(lambda: stream.read(65536), b""):
                size += len(block)
                digest.update(block)
        value = {"id": 456, "name": "INERT artifact", "size_in_bytes": size, "expired": False,
                 "digest": "sha256:" + digest.hexdigest(),
                 "url": "https://api.github.com/repos/cloga/deepseek-harness/actions/artifacts/456",
                 "archive_download_url": "https://api.github.com/repos/cloga/deepseek-harness/actions/artifacts/456/zip",
                 "workflow_run": {"id": 123, "head_sha": SOURCE, "repository_id": 789, "head_repository_id": 789}}
        self.metadata.write_text(json.dumps(value), encoding="utf-8")

    def run_audit(self, **options):
        return audit.audit(options.get("zip_path", self.zip), self.metadata,
                           options.get("run", RUN), options.get("source", SOURCE),
                           options.get("target_root", self.target), options.get("mapping", self.mapping),
                           profile=options.get("profile", "evidence"))

    def rejected(self, raw=None, **options):
        if raw is not None:
            self.install(raw)  # Rebind inert API hash so parser/CRC failures cannot hide behind a hash mismatch.
        with self.assertRaises((audit.AuditError, ValueError, OSError, zipfile.BadZipFile, zlib.error)):
            self.run_audit(**options)

    def test_positive_stored_deflated_and_data_descriptors(self):
        for compression in [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED]:
            for descriptors in [False, True]:
                with self.subTest(compression=compression, descriptors=descriptors):
                    self.install(archive_bytes(compression=compression, descriptors=descriptors))
                    before = self.zip.read_bytes(), (self.target / "selected.json").read_bytes()
                    result = self.run_audit()
                    self.assertTrue(result["allMembersDecodedAndCrcVerified"])
                    self.assertTrue(result["selected"][0]["byteForByteEqual"])
                    self.assertFalse(result["metadataAuthenticationPerformed"])
                    self.assertFalse(result["acceptanceQualificationVerified"])
                    self.assertEqual(before, (self.zip.read_bytes(), (self.target / "selected.json").read_bytes()))

    def test_explicit_directories_and_empty_unselected_files(self):
        entries = [("evidence/", b"", stat.S_IFDIR | 0o755),
                   ("evidence/selected.json", b'{"inert":true}\n', stat.S_IFREG | 0o644),
                   ("empty", b"", stat.S_IFREG | 0o644)]
        self.install(archive_bytes(entries))
        self.assertEqual(self.run_audit()["memberCount"], 3)

    def test_exact_run_source_and_api_binding(self):
        self.rejected(run="124")
        self.rejected(source="b" * 40)
        for field, value in [("id", True), ("expired", True), ("size_in_bytes", 1), ("digest", "sha256:" + "0" * 64),
                             ("url", "https://example.com/artifact"), ("archive_download_url", "https://example.com/archive")]:
            with self.subTest(field=field):
                self.install(archive_bytes())
                metadata = json.loads(self.metadata.read_text())
                metadata[field] = value
                self.metadata.write_text(json.dumps(metadata))
                self.rejected()

    def test_raw_hash_change_not_accepted(self):
        self.zip.write_bytes(self.zip.read_bytes() + b"changed")
        self.rejected()

    def test_target_mismatch_same_size(self):
        (self.target / "selected.json").write_bytes(b'{"inert":fals}\n')
        self.rejected()

    def test_target_size_mismatch(self):
        (self.target / "selected.json").write_bytes(b"short")
        self.rejected()

    def test_missing_member_and_empty_mapping(self):
        self.rejected(mapping={"missing.json": "selected.json"})
        self.rejected(mapping={})

    def test_target_traversal_absolute_ads_and_duplicate_alias(self):
        for target in ["../selected.json", "/selected.json", "C:/selected.json", "selected.json:stream", "selected.json."]:
            with self.subTest(target=target):
                self.rejected(mapping={"evidence/selected.json": target})
        self.rejected(mapping={"evidence/selected.json": "selected.json", "diagnostics.txt": "SELECTED.JSON"})

    def test_reparse_root_detection_without_os_privilege(self):
        original = audit.os.lstat
        def fake(path, *args, **kwargs):
            value = original(path, *args, **kwargs)
            if Path(path) == self.target:
                return types.SimpleNamespace(st_mode=value.st_mode, st_file_attributes=0x400)
            return value
        with mock.patch.object(audit.os, "lstat", side_effect=fake):
            self.rejected()

    def test_duplicate_json_keys(self):
        self.metadata.write_text('{"id":456,"id":457}')
        self.rejected()

    def test_unsafe_member_names(self):
        for name in ["../escape", "/absolute", "C:/drive", "folder\\backslash", "file:stream", "folder/../escape",
                     "folder//empty", "folder/./dot", "folder/trailing.", "folder/trailing ", "NUL.txt", "e\u0301.txt"]:
            with self.subTest(name=name):
                self.rejected(archive_bytes([("evidence/selected.json", b'{"inert":true}\n', stat.S_IFREG | 0o644),
                                             (name, b"x", stat.S_IFREG | 0o644)]))

    def test_reserved_console_and_superscript_device_members(self):
        names = ["CONIN$", "CONOUT$", "conin$.txt", "ConOut$.log", "COM¹", "COM².txt", "COM³.log", "LPT¹.txt", "LPT²", "LPT³.log"]
        for name in names:
            with self.subTest(member=name):
                self.install(archive_bytes([("evidence/selected.json", b'{"inert":true}\n', stat.S_IFREG | 0o644),
                                            (name, b"inert", stat.S_IFREG | 0o644)]))
                with self.assertRaisesRegex(audit.AuditError, "unsafe-relative-component"):
                    self.run_audit()

    def test_reserved_console_and_superscript_retained_targets_never_open(self):
        names = ["CONIN$", "CONOUT$", "conin$.txt", "ConOut$.log", "COM¹", "COM².txt", "COM³.log", "LPT¹.txt", "LPT²", "LPT³.log"]
        original = audit.open_input
        for name in names:
            with self.subTest(target=name), mock.patch.object(audit, "open_input", wraps=original) as opened:
                with self.assertRaisesRegex(audit.AuditError, "unsafe-relative-component"):
                    self.run_audit(mapping={"evidence/selected.json": name})
                self.assertEqual(opened.call_count, 1)  # Only ordinary metadata was opened, not any target/device.
                self.assertEqual(opened.call_args.args[0], self.metadata)

    def test_reserved_devices_in_nested_components_and_nondevice_controls(self):
        for name in ["CONIN$", "conout$.txt", "COM¹", "COM².txt", "COM³", "LPT¹", "LPT².txt", "LPT³"]:
            for path in [f"parent/{name}/child.json", f"parent/{name}"]:
                with self.subTest(component=path):
                    with self.assertRaisesRegex(audit.AuditError, "unsafe-relative-component"):
                        audit.relative_name(path)
                    with self.assertRaisesRegex(audit.AuditError, "unsafe-relative-component"):
                        self.run_audit(mapping={"evidence/selected.json": path})
        for name in ["CONINPUT.txt", "COM10.txt", "LPT10.txt"]:
            self.assertEqual(audit.relative_name(name), name)  # String-only controls; no files/devices opened.

    def test_duplicate_case_component_and_file_ancestor_conflicts(self):
        for names in [["dup", "dup"], ["Case", "case"], ["Dir/a", "dir/b"], ["ancestor", "ancestor/child"]]:
            with self.subTest(names=names):
                self.rejected(archive_bytes([("evidence/selected.json", b'{"inert":true}\n', stat.S_IFREG | 0o644)] +
                                            [(name, b"x", stat.S_IFREG | 0o644) for name in names]))

    def test_links_fifo_and_directory_type_mismatch(self):
        for name, mode in [("link", stat.S_IFLNK | 0o777), ("fifo", stat.S_IFIFO | 0o644),
                           ("wrong", stat.S_IFDIR | 0o755), ("wrong/", stat.S_IFREG | 0o644)]:
            with self.subTest(name=name, mode=mode):
                self.rejected(archive_bytes([("evidence/selected.json", b'{"inert":true}\n', stat.S_IFREG | 0o644), (name, b"", mode)]))

    def test_encrypted_and_unsupported_compression(self):
        raw = archive_bytes()
        self.rejected(edit_header(raw, 6, 8, 1))
        self.rejected(edit_header(archive_bytes(compression=zipfile.ZIP_STORED), 8, 10, 99))

    def test_crc_corruption_selected_and_unselected(self):
        raw = bytearray(archive_bytes(compression=zipfile.ZIP_STORED))
        for payload in [b'{"inert":true}\n', b"inert diagnostics\n"]:
            with self.subTest(payload=payload):
                damaged = bytearray(raw)
                damaged[damaged.index(payload)] ^= 1
                self.rejected(bytes(damaged))

    def test_false_small_declared_size_cannot_hide_extra_deflate_output(self):
        self.rejected(edit_header(archive_bytes(), 22, 24, 1, "L"))

    def test_local_central_name_and_flags_mismatch(self):
        raw = bytearray(archive_bytes())
        raw[30] ^= 1
        self.rejected(bytes(raw))
        self.rejected(edit_header(archive_bytes(), local_offset=6, value=8))

    def test_descriptor_crc_mismatch(self):
        raw = bytearray(archive_bytes(descriptors=True))
        position = raw.index(b"PK\x07\x08")
        raw[position + 4] ^= 1
        self.rejected(bytes(raw))

    def test_unsupported_extra_and_zip64(self):
        entry = zipfile.ZipInfo("evidence/selected.json")
        entry.extra = struct.pack("<HH", 0x7075, 0)  # Alternate Unicode-name field is unsupported.
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as output:
            output.writestr(entry, b'{"inert":true}\n')
        self.rejected(buffer.getvalue())
        self.rejected(edit_header(archive_bytes(), local_offset=4, central_offset=6, value=45))

    def test_archive_prefix_trailing_and_overlapping_records(self):
        raw = archive_bytes()
        self.rejected(b"MZ executable prefix" + raw)
        self.rejected(raw + b"unaccounted tail")
        data = bytearray(raw)
        second = data.index(b"PK\x01\x02", data.index(b"PK\x01\x02") + 1)
        struct.pack_into("<L", data, second + 42, 0)
        self.rejected(bytes(data))

    def test_multi_disk(self):
        data = bytearray(archive_bytes())
        end = data.rindex(b"PK\x05\x06")
        struct.pack_into("<H", data, end + 4, 1)
        self.rejected(bytes(data))

    def test_member_total_count_and_archive_bounds(self):
        for key, value in [("members", 1), ("memberBytes", 5), ("totalBytes", 20), ("archiveBytes", 10)]:
            with self.subTest(key=key), mock.patch.dict(audit.LIMITS, {key: value}):
                self.rejected()

    def test_actual_central_count_cannot_exceed_declared_count(self):
        data = bytearray(archive_bytes())
        end = data.rindex(b"PK\x05\x06")
        struct.pack_into("<HH", data, end + 8, 1, 1)
        self.rejected(bytes(data))

    def test_corrupted_deflate_stream(self):
        data = bytearray(archive_bytes())
        name_length, extra_length = struct.unpack_from("<HH", data, 26)
        data[30 + name_length + extra_length] = 0xff
        self.rejected(bytes(data))

    def test_report_cannot_overwrite_or_write_inside_retained_root(self):
        mapping = self.root / "selection.json"
        mapping.write_text(json.dumps(self.mapping))
        existing = self.root / "existing-report.json"
        existing.write_text("inert sentinel")
        for output in [self.target / "new-report.json", existing]:
            arguments = ["audit", "--zip", str(self.zip), "--metadata", str(self.metadata),
                         "--expected-run", RUN, "--expected-source", SOURCE,
                         "--target-root", str(self.target), "--mapping", str(mapping), "--report", str(output)]
            with mock.patch.object(audit.sys, "argv", arguments), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises((audit.AuditError, FileExistsError)):
                    audit.main()
        self.assertFalse((self.target / "new-report.json").exists())
        self.assertEqual(existing.read_text(), "inert sentinel")

    def inspect(self):
        return audit.audit(self.zip, self.metadata, RUN, SOURCE, inspect_only=True)

    def test_inspect_only_uses_full_parser_without_retained_targets(self):
        compared = self.run_audit()
        (self.target / "selected.json").unlink()
        self.target.rmdir()
        inspected = self.inspect()
        self.assertEqual(inspected["inventory"], compared["inventory"])
        self.assertEqual(inspected["archiveSha256"], compared["archiveSha256"])
        self.assertEqual(inspected["mode"], "inspect-only")
        self.assertEqual(inspected["scope"], "offline-original-zip-inspection")
        self.assertEqual(inspected["selected"], [])
        self.assertIsNone(inspected["targetRoot"])
        self.assertFalse(inspected["selectedComparisonsPerformed"])
        self.assertTrue(compared["selectedComparisonsPerformed"])
        for field in ["extracted", "extractedToFilesystem", "packageCodeExecuted", "workflowSuccessVerified", "acceptanceQualificationVerified"]:
            self.assertFalse(inspected[field])

    def test_inspect_only_rejects_unsafe_late_unselected_member(self):
        self.install(archive_bytes([("safe.json", b"inert", stat.S_IFREG | 0o644),
                                    ("late/../escape", b"inert late payload", stat.S_IFREG | 0o644)]))
        with self.assertRaisesRegex(audit.AuditError, "unsafe-relative-component"):
            self.inspect()

    def test_inspect_only_checks_unselected_crc_and_deflate(self):
        raw = bytearray(archive_bytes(compression=zipfile.ZIP_STORED))
        raw[raw.index(b"inert diagnostics")] ^= 1
        self.install(bytes(raw))
        with self.assertRaisesRegex(audit.AuditError, "member-size-or-crc-mismatch"):
            self.inspect()
        raw = bytearray(archive_bytes())
        name_length, extra_length = struct.unpack_from("<HH", raw, 26)
        raw[30 + name_length + extra_length] = 0xff
        self.install(bytes(raw))
        with self.assertRaises((audit.AuditError, zlib.error)):
            self.inspect()

    def test_inspect_only_preserves_all_bounds(self):
        for key, value in [("members", 1), ("memberBytes", 5), ("totalBytes", 20), ("archiveBytes", 10), ("centralMetadataBytes", 10)]:
            with self.subTest(key=key), mock.patch.dict(audit.LIMITS, {key: value}):
                with self.assertRaises(audit.AuditError):
                    self.inspect()

    def test_inspect_function_rejects_targets_and_final_still_requires_selection(self):
        for root, mapping in [(self.target, None), (None, {}), (self.target, self.mapping)]:
            with self.assertRaisesRegex(audit.AuditError, "inspect-mode-forbids-targets"):
                audit.audit(self.zip, self.metadata, RUN, SOURCE, root, mapping, inspect_only=True)
        for root, mapping in [(None, None), (self.target, {}), (self.target, None)]:
            with self.assertRaisesRegex(audit.AuditError, "selection-required"):
                audit.audit(self.zip, self.metadata, RUN, SOURCE, root, mapping)

    def test_cli_rejects_ambiguous_modes_before_any_audit_or_mapping_read(self):
        base = ["audit", "--zip", str(self.zip), "--metadata", str(self.metadata), "--expected-run", RUN, "--expected-source", SOURCE]
        for extra in [["--inspect-only", "--target-root", str(self.target)], ["--inspect-only", "--mapping", "missing.json"],
                      ["--inspect-only", "--target-root", str(self.target), "--mapping", "missing.json"],
                      [], ["--target-root", str(self.target)], ["--mapping", "missing.json"]]:
            with self.subTest(arguments=extra), mock.patch.object(audit.sys, "argv", base + extra), \
                    mock.patch.object(audit, "audit") as run, mock.patch.object(audit, "read_json") as read:
                with self.assertRaises(audit.AuditError):
                    audit.main()
                run.assert_not_called()
                read.assert_not_called()

    def test_failed_acceptance_is_only_bytes_not_success(self):
        data = b'{"succeeded":false,"installerUpgradeVerified":false}\n'
        self.install(archive_bytes([("evidence/selected.json", data, stat.S_IFREG | 0o644)]))
        (self.target / "selected.json").write_bytes(data)
        result = self.run_audit()
        self.assertTrue(result["valid"])
        self.assertFalse(result["workflowSuccessVerified"])
        self.assertFalse(result["acceptanceQualificationVerified"])
        self.assertEqual((self.target / "selected.json").read_bytes(), data)

    # New streaming/profile coverage follows; the preceding 35 tests are retained.
    def inspect_profile(self, profile):
        return audit.audit(self.zip, self.metadata, RUN, SOURCE, inspect_only=True, profile=profile)

    def malformed_in_all_modes(self, row, reason=None):
        self.install(crafted_archive([{"name": "evidence/selected.json", "data": b'{"inert":true}\n'}, row]))
        declared = row.get("declared", len(row.get("data", b"")))
        payload = row.get("data", b"")
        if declared <= 1024 * 1024:
            (self.target / "probe.bin").write_bytes(payload[:declared] + b"\x00" * max(0, declared - len(payload)))
        for profile in ("evidence", "desktop-build"):
            for mode in ("inspect", "metadata", "selected"):
                if mode == "selected" and declared > 1024 * 1024:
                    continue
                with self.subTest(profile=profile, mode=mode), mock.patch.object(audit.zlib, "decompressobj", DecoderProbe(self)):
                    error = self.assertRaisesRegex(audit.AuditError, reason) if reason else self.assertRaises((audit.AuditError, zlib.error))
                    with error:
                        if mode == "inspect":
                            self.inspect_profile(profile)
                        else:
                            self.run_audit(profile=profile, mapping=self.mapping if mode == "metadata" else {row["name"]: "probe.bin"})

    def test_profile_fixed_limits_provenance_and_invocation_isolation(self):
        before = dict(audit.LIMITS)
        small = self.run_audit()
        large = self.run_audit(profile="desktop-build")
        again = self.run_audit()
        self.assertEqual(audit.LIMITS, before)
        self.assertEqual(small["profile"], "evidence")
        self.assertEqual(small["limits"], again["limits"])
        self.assertEqual(small["limits"]["memberBytes"], 33554432)
        self.assertEqual(small["limits"]["totalBytes"], 268435456)
        self.assertEqual(large["limits"]["memberBytes"], 402653184)
        self.assertEqual(large["limits"]["totalBytes"], 469762048)
        for key in before.keys() - {"memberBytes", "totalBytes"}:
            self.assertEqual(large["limits"][key], before[key])
        self.assertEqual(large["limits"]["archiveBytes"], 536870912)
        self.assertEqual(large["inputChunkBytes"], 65536)
        self.assertEqual(large["outputChunkBytes"], 65536)
        self.assertEqual(small["inventory"], large["inventory"])
        large["limits"]["memberBytes"] = 1  # Report is owned data, not a live policy reference.
        self.assertEqual(self.run_audit(profile="desktop-build")["limits"]["memberBytes"], 402653184)
        self.assertEqual(audit.LIMITS, before)

    def test_profile_api_invalid_values_fail_before_open(self):
        for profile in ("custom", "DESKTOP-BUILD", "", None, True, {}, 384):
            with self.subTest(profile=profile), mock.patch.object(audit, "open_input") as opened:
                with self.assertRaisesRegex(audit.AuditError, "audit-profile-invalid"):
                    self.run_audit(profile=profile)
                opened.assert_not_called()

    def test_profile_cli_is_finite_and_preserves_mode_rejection(self):
        base = ["audit", "--zip", str(self.zip), "--metadata", str(self.metadata),
                "--expected-run", RUN, "--expected-source", SOURCE]
        for extra in (["--profile", "custom"], ["--max-member-bytes", "999999999"],
                      ["--profile", "desktop-build", "--max-total-bytes", "999999999"]):
            with self.subTest(arguments=extra), mock.patch.object(audit.sys, "argv", base + ["--inspect-only"] + extra), \
                    mock.patch.object(audit, "audit") as run, contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    audit.main()
                self.assertEqual(raised.exception.code, 2)
                run.assert_not_called()
        for extra in (["--inspect-only", "--mapping", "missing.json"], []):
            with mock.patch.object(audit.sys, "argv", base + ["--profile", "desktop-build"] + extra), \
                    mock.patch.object(audit, "audit") as run:
                with self.assertRaises(audit.AuditError):
                    audit.main()
                run.assert_not_called()
        output = io.StringIO()
        with mock.patch.object(audit.sys, "argv", base + ["--profile", "desktop-build", "--inspect-only"]), contextlib.redirect_stdout(output):
            audit.main()
        result = json.loads(output.getvalue())
        self.assertEqual(result["profile"], "desktop-build")
        self.assertFalse(result["selectedComparisonsPerformed"])

    def test_bounded_real_deflate_tails_and_chunk_edges(self):
        for length in (0, 65535, 65536, 65537, 3 * 65536, 5 * 65536 + 1):
            payload = b"A" * length  # Small unit fixtures only; large integration is streamed.
            compressed = raw_deflate(payload)
            input_probe = ReadProbe(self, io.BytesIO(compressed))
            probe = DecoderProbe(self)
            digest = hashlib.sha256()
            crc = count = 0
            with self.subTest(length=length), mock.patch.object(audit.zlib, "decompressobj", probe):
                for piece in audit.member_chunks(input_probe, len(compressed), length, zipfile.ZIP_DEFLATED):
                    self.assertLessEqual(len(piece), 65536)
                    count += len(piece)
                    digest.update(piece)
                    crc = zlib.crc32(piece, crc)
            self.assertEqual(count, length)
            self.assertEqual(digest.hexdigest(), hashlib.sha256(payload).hexdigest())
            self.assertEqual(crc, zlib.crc32(payload))
            self.assertLessEqual(probe.max_output, 65536)
            if length > 65536:
                self.assertGreater(probe.calls, input_probe.calls)
            if length >= 3 * 65536:
                self.assertGreater(probe.tail_calls, 0)

    def test_bounded_less_compressible_and_stored_payload_reads(self):
        payload = b"".join(hashlib.sha256(struct.pack("<L", i)).digest() for i in range(10000))
        for method in (zipfile.ZIP_DEFLATED, zipfile.ZIP_STORED):
            self.install(crafted_archive([{"name": "probe.bin", "data": payload, "method": method}]))
            target = self.target / "probe.bin"
            target.write_bytes(payload)
            original_open = audit.open_input
            reads = []
            def opened(path, maximum):
                stream, stamp = original_open(path, maximum)
                if Path(path) == target:
                    stream = ReadProbe(self, stream)
                    reads.append(stream)
                return stream, stamp
            probe = DecoderProbe(self)
            with self.subTest(method=method), mock.patch.object(audit, "open_input", side_effect=opened), \
                    mock.patch.object(audit.zlib, "decompressobj", probe):
                result = self.run_audit(mapping={"probe.bin": "probe.bin"}, profile="desktop-build")
            self.assertEqual(result["selected"][0]["sha256"], hashlib.sha256(payload).hexdigest())
            self.assertGreater(reads[0].calls, 2)
            self.assertGreater(reads[0].max_requested, 0)
            self.assertLessEqual(reads[0].max_requested, 65536)
            if method == zipfile.ZIP_STORED:
                self.assertEqual(reads[0].max_requested, 65536)
            if method == zipfile.ZIP_DEFLATED:
                self.assertEqual(probe.max_input, 65536)

    def test_unsigned_signed_descriptors_with_multiple_output_chunks(self):
        payload = b"D" * (3 * 65536 + 1)
        for method in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            for descriptor in (None, "signed", "unsigned"):
                with self.subTest(method=method, descriptor=descriptor):
                    self.install(crafted_archive([{"name": "probe.bin", "data": payload, "method": method, "descriptor": descriptor}]))
                    (self.target / "probe.bin").write_bytes(payload)
                    final = self.run_audit(mapping={"probe.bin": "probe.bin"}, profile="desktop-build")
                    inspected = self.inspect_profile("desktop-build")
                    self.assertEqual(final["inventory"], inspected["inventory"])
                    self.assertTrue(final["selected"][0]["byteForByteEqual"])

    def test_underdeclared_output_all_modes_and_profiles(self):
        payload = b"U" * (2 * 65536 + 7)
        for declared in (0, 1, 65535, 65536, len(payload) - 1):
            with self.subTest(declared=declared):
                self.malformed_in_all_modes({"name": "probe.bin", "data": payload, "declared": declared},
                                            "decompressed-size-exceeds-declaration")

    def test_positive_overflow_sentinel_after_exact_chunk(self):
        payload = b"S" * 65537
        compressed = raw_deflate(payload)
        probe = DecoderProbe(self)
        with mock.patch.object(audit.zlib, "decompressobj", probe):
            with self.assertRaisesRegex(audit.AuditError, "decompressed-size-exceeds-declaration"):
                for _ in audit.member_chunks(io.BytesIO(compressed), len(compressed), 65536, zipfile.ZIP_DEFLATED):
                    pass
        self.assertGreater(probe.sentinel_calls, 0)
        self.assertEqual(probe.output_bytes, 65537)

    def test_overdeclared_output_all_modes_and_profiles(self):
        payload = b"O" * (65536 + 5)
        for declared in (len(payload) + 1, len(payload) + 65536):
            with self.subTest(declared=declared):
                self.malformed_in_all_modes({"name": "probe.bin", "data": payload, "declared": declared},
                                            "member-size-or-crc-mismatch")
        for profile, declared in (("evidence", 33554432), ("desktop-build", 402653184)):
            self.install(crafted_archive([{"name": "probe.bin", "data": b"tiny", "declared": declared}]))
            probe = DecoderProbe(self)
            with mock.patch.object(audit.zlib, "decompressobj", probe):
                with self.assertRaisesRegex(audit.AuditError, "member-size-or-crc-mismatch"):
                    self.inspect_profile(profile)
            self.assertEqual(probe.output_bytes, 4)
            self.assertLessEqual(probe.max_requested, 65536)

    def test_multichunk_crc_mismatch_all_modes_and_profiles(self):
        payload = b"C" * (3 * 65536)
        self.malformed_in_all_modes({"name": "probe.bin", "data": payload,
                                     "crc": (zlib.crc32(payload) ^ 1) & 0xffffffff}, "member-size-or-crc-mismatch")

    def test_full_output_crc_without_deflate_end_is_rejected(self):
        payload = b"E" * (3 * 65536)
        unfinished = raw_deflate(payload, finish=False)
        control = zlib.decompressobj(-15)
        self.assertEqual(control.decompress(unfinished), payload)
        self.assertFalse(control.eof)  # Intentional SYNC_FLUSH, not arbitrary byte removal.
        self.malformed_in_all_modes({"name": "probe.bin", "data": payload, "compressed": unfinished}, "deflate-incomplete")

    def test_trailing_junk_and_concatenated_deflate_all_modes(self):
        payload = b"T" * (2 * 65536)
        for suffix in (b"junk", raw_deflate(b"second-stream")):
            with self.subTest(suffix=suffix):
                self.malformed_in_all_modes({"name": "probe.bin", "data": payload,
                                             "compressed": raw_deflate(payload) + suffix}, "deflate-boundary-or-size")

    def test_eof_with_unread_compressed_extent_is_rejected(self):
        payload = b"boundary"
        compressed = raw_deflate(payload)
        # End falls exactly at the archive-read boundary: no unused_data yet,
        # but an unread declared compressed byte must still reject.
        with mock.patch.object(audit, "CHUNK", len(compressed)):
            self.malformed_in_all_modes({"name": "probe.bin", "data": payload,
                                         "compressed": compressed + b"!"}, "deflate-boundary-or-size")

    def test_truncated_invalid_and_zero_deflated_streams(self):
        payload = b"I" * (2 * 65536 + 1)
        for compressed in (raw_deflate(payload)[:5], b"\x07", b""):
            with self.subTest(compressed=compressed):
                self.malformed_in_all_modes({"name": "probe.bin", "data": payload, "compressed": compressed})
        self.malformed_in_all_modes({"name": "probe.bin", "data": b"", "compressed": b""}, "deflate-incomplete")

    def test_stored_under_and_overdeclared_output_all_modes(self):
        payload = b"P" * (2 * 65536 + 1)
        for declared, reason in ((len(payload) - 1, "decompressed-size-exceeds-declaration"),
                                 (len(payload) + 1, "member-size-or-crc-mismatch")):
            self.malformed_in_all_modes({"name": "probe.bin", "data": payload, "method": zipfile.ZIP_STORED,
                                         "declared": declared}, reason)

    def test_compressed_header_size_disagreement_still_rejected(self):
        raw = archive_bytes()
        compressed_size = struct.unpack_from("<L", raw, 18)[0]
        for value in (compressed_size - 1, compressed_size + 1):
            for profile in ("evidence", "desktop-build"):
                self.install(edit_header(raw, local_offset=18, value=value, fmt="L"))
                with self.assertRaisesRegex(audit.AuditError, "zip-local-sizes-or-crc"):
                    self.inspect_profile(profile)

    def test_no_progress_fault_and_empty_drain_termination(self):
        class Stalled:
            eof = False
            unused_data = b""
            def decompress(self, data, maximum):
                self.unconsumed_tail = data
                return b""
        with mock.patch.object(audit.zlib, "decompressobj", return_value=Stalled()):
            with self.assertRaisesRegex(audit.AuditError, "deflate-no-progress"):
                list(audit.member_chunks(io.BytesIO(b"x"), 1, 1, zipfile.ZIP_DEFLATED))
        class EmptyDrain:
            eof = False
            unused_data = unconsumed_tail = b""
            def __init__(self):
                self.calls = []
            def decompress(self, data, maximum):
                self.calls.append((data, maximum))
                if data:
                    return b"a"
                if len(self.calls) == 2:
                    return b"b"
                self.eof = True
                return b""
        decoder = EmptyDrain()
        with mock.patch.object(audit.zlib, "decompressobj", return_value=decoder):
            self.assertEqual(list(audit.member_chunks(io.BytesIO(b"x"), 1, 2, zipfile.ZIP_DEFLATED)), [b"a", b"b"])
        self.assertEqual(decoder.calls, [(b"x", 3), (b"", 2), (b"", 1)])
        class NoOutput:
            eof = False
            unused_data = unconsumed_tail = b""
            def __init__(self):
                self.calls = 0
            def decompress(self, data, maximum):
                self.calls += 1
                return b""
        decoder = NoOutput()
        with mock.patch.object(audit.zlib, "decompressobj", return_value=decoder):
            with self.assertRaisesRegex(audit.AuditError, "deflate-incomplete"):
                list(audit.member_chunks(io.BytesIO(b"x"), 1, 0, zipfile.ZIP_DEFLATED))
        self.assertEqual(decoder.calls, 2)  # One input consumption, one failed empty drain.

    def test_real_zlib_empty_drain_after_output_limit(self):
        # Discover a bounded deterministic fixture, not a mocked-zlib success.
        # zlib can consume all compressed input while holding pending match output.
        found = False
        for length in (258, 1024, 4096, 65536, 65537):
            payload = b"Q" * length
            compressed = raw_deflate(payload)
            probe = DecoderProbe(self)
            with mock.patch.object(audit, "OUTPUT_CHUNK", 17), mock.patch.object(audit.zlib, "decompressobj", probe):
                digest = hashlib.sha256()
                total = 0
                for piece in audit.member_chunks(io.BytesIO(compressed), len(compressed), length, zipfile.ZIP_DEFLATED):
                    total += len(piece)
                    digest.update(piece)
            self.assertEqual(total, length)
            self.assertEqual(digest.hexdigest(), hashlib.sha256(payload).hexdigest())
            found = found or probe.empty_calls > 0
        # Real-zlib availability is reported, not assumed. Fault coverage above
        # deterministically covers empty drain success/termination regardless.
        print("REAL_ZLIB_EMPTY_DRAIN_OBSERVED=" + str(found), flush=True)

    def test_inclusive_size_ceilings_and_predecode_rejection(self):
        payload = b"B" * 101
        self.install(crafted_archive([{"name": "probe.bin", "data": payload}]))
        archive_size = self.zip.stat().st_size
        for profile in ("evidence", "desktop-build"):
            for key, boundary in (("memberBytes", len(payload)), ("totalBytes", len(payload)), ("archiveBytes", archive_size)):
                for ceiling, passes in ((boundary, True), (boundary - 1, False)):
                    with self.subTest(profile=profile, key=key, ceiling=ceiling), \
                            mock.patch.dict(audit.PROFILES, {profile: {key: ceiling}}), \
                            mock.patch.object(audit, "member_chunks", wraps=audit.member_chunks) as decode:
                        if passes:
                            self.assertTrue(self.inspect_profile(profile)["valid"])
                            self.assertEqual(decode.call_count, 1)
                        else:
                            with self.assertRaises(audit.AuditError):
                                self.inspect_profile(profile)
                            decode.assert_not_called()
        self.install(crafted_archive([{"name": "a", "data": b"A" * 64}, {"name": "b", "data": b"B" * 64}]))
        for profile in ("evidence", "desktop-build"):
            with mock.patch.dict(audit.PROFILES, {profile: {"memberBytes": 64, "totalBytes": 128}}):
                self.assertTrue(self.inspect_profile(profile)["valid"])
            with mock.patch.dict(audit.PROFILES, {profile: {"memberBytes": 64, "totalBytes": 127}}), \
                    mock.patch.object(audit, "member_chunks") as decode:
                with self.assertRaisesRegex(audit.AuditError, "zip-total-size-bound"):
                    self.inspect_profile(profile)
                decode.assert_not_called()

    def test_actual_profile_overceilings_without_giant_fixtures(self):
        for profile in ("evidence", "desktop-build"):
            limits = dict(audit.LIMITS)
            limits.update(audit.PROFILES[profile])
            self.install(crafted_archive([{"name": "probe.bin", "data": b"", "declared": limits["memberBytes"] + 1}]))
            with mock.patch.object(audit, "member_chunks") as decode:
                with self.assertRaisesRegex(audit.AuditError, "zip-member-size-bound"):
                    self.inspect_profile(profile)
                decode.assert_not_called()
            # Each declaration fits individually, but the aggregate exceeds its cap.
            member = limits["memberBytes"]
            count, remainder = divmod(limits["totalBytes"], member)
            entries = [{"name": "part-" + str(i), "declared": member} for i in range(count)]
            entries.append({"name": "last", "declared": remainder + 1})
            self.install(crafted_archive(entries))
            with mock.patch.object(audit, "member_chunks") as decode:
                with self.assertRaisesRegex(audit.AuditError, "zip-total-size-bound"):
                    self.inspect_profile(profile)
                decode.assert_not_called()

    def test_desktop_profile_preserves_existing_security_guards(self):
        # Repeat representative original test methods under forced large profile;
        # the original 35 methods also run normally under their default policy.
        methods = ["test_exact_run_source_and_api_binding", "test_raw_hash_change_not_accepted",
                   "test_target_mismatch_same_size", "test_target_size_mismatch",
                   "test_missing_member_and_empty_mapping", "test_target_traversal_absolute_ads_and_duplicate_alias",
                   "test_reparse_root_detection_without_os_privilege", "test_duplicate_json_keys",
                   "test_unsafe_member_names", "test_reserved_console_and_superscript_device_members",
                   "test_reserved_console_and_superscript_retained_targets_never_open",
                   "test_duplicate_case_component_and_file_ancestor_conflicts",
                   "test_links_fifo_and_directory_type_mismatch", "test_encrypted_and_unsupported_compression",
                   "test_local_central_name_and_flags_mismatch", "test_descriptor_crc_mismatch",
                   "test_unsupported_extra_and_zip64", "test_archive_prefix_trailing_and_overlapping_records",
                   "test_multi_disk", "test_actual_central_count_cannot_exceed_declared_count",
                   "test_report_cannot_overwrite_or_write_inside_retained_root",
                   "test_inspect_function_rejects_targets_and_final_still_requires_selection",
                   "test_failed_acceptance_is_only_bytes_not_success"]
        original_audit = audit.audit
        def large(*args, **kwargs):
            kwargs["profile"] = "desktop-build"
            return original_audit(*args, **kwargs)
        with mock.patch.object(audit, "audit", side_effect=large):
            for method in methods:
                with self.subTest(original_method=method):
                    result = unittest.TestResult()
                    AuditTests(method).run(result)
                    self.assertEqual(result.testsRun, 1)
                    self.assertEqual(result.errors + result.failures + result.skipped, [])

    def stream_inert_fixture(self, length, method, corrupt_late=False):
        payload_name = "inert-payload.bin"
        retained = self.target / payload_name
        block = bytes(range(256)) * 256  # Exactly 64 KiB; never grows with fixture size.
        digest = hashlib.sha256()
        crc = 0
        entry = zipfile.ZipInfo(payload_name)
        entry.create_system = 3
        entry.external_attr = (stat.S_IFREG | 0o644) << 16
        entry.compress_type = method
        entry.file_size = length
        with zipfile.ZipFile(self.zip, "w", allowZip64=False) as archive, retained.open("wb") as target:
            archive.writestr("evidence/selected.json", b'{"inert":true}\n')
            with archive.open(entry, "w", force_zip64=False) as output:
                remaining = length
                while remaining:
                    piece = block[:min(len(block), remaining)]
                    output.write(piece)
                    target.write(piece)
                    digest.update(piece)
                    crc = zlib.crc32(piece, crc)
                    remaining -= len(piece)
            if corrupt_late:
                archive.writestr("late.bin", b"INERT-LATE-SENTINEL", compress_type=zipfile.ZIP_STORED)
        if corrupt_late:
            with zipfile.ZipFile(self.zip, "r") as archive:
                offset = archive.getinfo("late.bin").header_offset
            with self.zip.open("r+b") as stream:
                stream.seek(offset)
                header = stream.read(30)
                name_len, extra_len = struct.unpack_from("<HH", header, 26)
                stream.seek(offset + 30 + name_len + extra_len)
                stream.write(b"!")
        self.bind_metadata()
        for path in (retained, self.metadata):
            with path.open("r+b") as finalized:
                finalized.flush()
                audit.os.fsync(finalized.fileno())
        # Parent-approved fixed settling for freshly generated OWNED synthetic
        # fixtures only, after writes/fsync/close and before any audit baseline.
        # No polling, stamp reset, failed-audit retry, or production-auditor pause.
        time.sleep(2)
        return {"name": payload_name, "bytes": length, "sha256": digest.hexdigest(), "crc32": f"{crc & 0xffffffff:08x}"}

    def test_streamed_300mib_inert_deflated_and_stored_integration(self):
        for method in (zipfile.ZIP_DEFLATED, zipfile.ZIP_STORED):
            with self.subTest(method=method):
                expected = self.stream_inert_fixture(300 * 1024 * 1024, method)
                with mock.patch.object(audit, "member_chunks") as decode:
                    with self.assertRaisesRegex(audit.AuditError, "zip-member-size-bound"):
                        self.inspect()
                    decode.assert_not_called()
                probe = DecoderProbe(self)
                original_open = audit.open_input
                reads = []
                maxima = []
                def opened(path, maximum):
                    stream, stamp = original_open(path, maximum)
                    if Path(path) == self.target / expected["name"]:
                        maxima.append(maximum)
                        stream = ReadProbe(self, stream)
                        reads.append(stream)
                    return stream, stamp
                original_chunks = audit.member_chunks
                pieces = {"count": 0, "bytes": 0, "maximum": 0}
                def bounded_chunks(*args):
                    for piece in original_chunks(*args):
                        self.assertLessEqual(len(piece), 65536)
                        pieces["count"] += 1
                        pieces["bytes"] += len(piece)
                        pieces["maximum"] = max(pieces["maximum"], len(piece))
                        yield piece
                original_stable = audit.stable
                def checked_stable(stream, before):
                    after = audit.stamp(audit.os.fstat(stream.fileno()))
                    if before != after:
                        print("STABILITY_DIAGNOSTIC " + json.dumps({"file": str(stream.name),
                              "before": before, "after": after}), flush=True)
                    return original_stable(stream, before)
                with mock.patch.object(audit.zlib, "decompressobj", probe), \
                        mock.patch.object(audit, "open_input", side_effect=opened), \
                        mock.patch.object(audit, "member_chunks", side_effect=bounded_chunks), \
                        mock.patch.object(audit, "stable", side_effect=checked_stable):
                    inspected = self.inspect_profile("desktop-build")
                    metadata_only = self.run_audit(profile="desktop-build")
                    selected = self.run_audit(profile="desktop-build", mapping={expected["name"]: expected["name"]})
                for result in (inspected, metadata_only, selected):
                    row = next(row for row in result["inventory"] if row["name"] == expected["name"])
                    for key in ("bytes", "sha256", "crc32"):
                        self.assertEqual(row[key], expected[key])
                    self.assertTrue(result["allMembersDecodedAndCrcVerified"])
                    self.assertFalse(result["extracted"])
                    self.assertFalse(result["acceptanceQualificationVerified"])
                self.assertEqual(inspected["inventory"], selected["inventory"])
                self.assertEqual(metadata_only["inventory"], selected["inventory"])
                self.assertEqual(maxima, [402653184])
                self.assertEqual(reads[0].max_requested, 65536)
                self.assertEqual(pieces["maximum"], 65536)
                self.assertEqual(pieces["bytes"], 3 * (expected["bytes"] + len(b'{"inert":true}\n')))
                self.assertTrue(selected["selected"][0]["byteForByteEqual"])
                self.assertEqual(selected["selected"][0]["bytes"], 314572800)
                if method == zipfile.ZIP_DEFLATED:
                    self.assertGreater(probe.tail_calls, 0)
                    self.assertEqual(probe.max_output, 65536)
                print("INERT_300MIB " + json.dumps({"method": method, "archiveBytes": self.zip.stat().st_size,
                      "member": expected, "decodeCalls": probe.calls, "tailCalls": probe.tail_calls,
                      "decodedPieces": pieces, "maxDeflateOutput": probe.max_output,
                      "maxRetainedRead": reads[0].max_requested, "allThreeModesPassed": True}), flush=True)
                # Exact selected comparison remains required beyond the first chunks.
                target = self.target / expected["name"]
                with target.open("r+b") as stream:
                    stream.seek(-1, 2)
                    stream.write(b"!")
                with self.assertRaisesRegex(audit.AuditError, "retained-byte-mismatch"):
                    self.run_audit(profile="desktop-build", mapping={expected["name"]: expected["name"]})
                for size in (expected["bytes"] - 1, expected["bytes"] + 1):
                    with target.open("r+b") as stream:
                        stream.truncate(size)
                    with self.assertRaisesRegex(audit.AuditError, "retained-size-mismatch"):
                        self.run_audit(profile="desktop-build", mapping={expected["name"]: expected["name"]})

    def test_late_unselected_corruption_after_streamed_large_member(self):
        expected = self.stream_inert_fixture(33 * 1024 * 1024, zipfile.ZIP_DEFLATED, corrupt_late=True)
        self.assertGreater(expected["bytes"], audit.LIMITS["memberBytes"])
        for mode in ("inspect", "metadata"):
            with self.subTest(mode=mode):
                with self.assertRaisesRegex(audit.AuditError, "member-size-or-crc-mismatch"):
                    self.inspect_profile("desktop-build") if mode == "inspect" else self.run_audit(profile="desktop-build")

    def test_retained_stability_and_ancestor_guards_under_large_profile(self):
        original_stable = audit.stable
        target = self.target / "selected.json"
        def changed(stream, stamp):
            if Path(stream.name) == target:
                raise audit.AuditError("input-changed-during-read")
            return original_stable(stream, stamp)
        with mock.patch.object(audit, "stable", side_effect=changed):
            with self.assertRaisesRegex(audit.AuditError, "input-changed-during-read"):
                self.run_audit(profile="desktop-build")
        original_lstat = audit.os.lstat
        def reparse(path, *args, **kwargs):
            value = original_lstat(path, *args, **kwargs)
            if Path(path) == self.target:
                return types.SimpleNamespace(st_mode=value.st_mode, st_file_attributes=0x400)
            return value
        with mock.patch.object(audit.os, "lstat", side_effect=reparse):
            with self.assertRaisesRegex(audit.AuditError, "physical-link-or-reparse"):
                self.run_audit(profile="desktop-build")


if __name__ == "__main__":
    print("RUNTIME " + json.dumps({"python": sys.version, "executable": sys.executable,
          "zlibCompile": zlib.ZLIB_VERSION, "zlibRuntime": zlib.ZLIB_RUNTIME_VERSION}), flush=True)
    unittest.main(verbosity=2)
