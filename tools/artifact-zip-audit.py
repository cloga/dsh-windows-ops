"""Offline classic ZIP/member byte audit. Never extract, import or execute archive code.
Metadata authentication and target-root ownership are caller responsibilities.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import struct
import sys
import unicodedata
import zipfile
import zlib

LIMITS = {"archiveBytes": 512 * 1024 * 1024, "metadataBytes": 1024 * 1024,
          "members": 10000, "memberBytes": 32 * 1024 * 1024,
          "totalBytes": 256 * 1024 * 1024, "nameBytes": 4096,
          "centralMetadataBytes": 16 * 1024 * 1024}
CHUNK = 65536
OUTPUT_CHUNK = 65536
# Only these finite policies are supported. Resolve into an owned dict per audit;
# never mutate LIMITS or another invocation's policy to select a profile.
PROFILES = {"evidence": {},
            "desktop-build": {"memberBytes": 384 * 1024 * 1024,
                              "totalBytes": 448 * 1024 * 1024}}
REPOSITORY = "cloga/deepseek-harness"


class AuditError(ValueError):
    pass


def need(condition, code):
    if not condition:
        raise AuditError(code)


def integer(value):
    return type(value) is int


def physical(path, directory=False):
    raw = os.fspath(path)
    need(os.path.isabs(raw) and not raw.startswith(("\\\\", "//")), "physical-absolute-local-path-required")
    need(os.path.normcase(raw) == os.path.normcase(os.path.abspath(raw)), "physical-lexical-alias")
    if os.name == "nt":
        need(":" not in raw[2:], "physical-alternate-stream")
    result = Path(raw)
    for current in [result, *result.parents]:
        value = os.lstat(current)
        need(not stat.S_ISLNK(value.st_mode) and not (getattr(value, "st_file_attributes", 0) & 0x400), "physical-link-or-reparse")
        need(os.path.normcase(os.path.realpath(current)) == os.path.normcase(str(current)), "physical-alias")
        need(stat.S_ISDIR(value.st_mode) if current != result or directory else stat.S_ISREG(value.st_mode), "physical-type")
    return result


def stamp(value):
    return value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns


def open_input(path, maximum):
    path = physical(path)
    before = os.lstat(path)
    need(0 <= before.st_size <= maximum, "input-size-bound")
    stream = path.open("rb")
    try:
        opened = os.fstat(stream.fileno())
        # Python 3.12/Windows path stat may expose birth time as ctime while fd stat exposes change time.
        # Compare shared identity/size/mtime across path->fd, then bind all fd timestamps for stability.
        need(stamp(opened)[:4] == stamp(before)[:4], "input-open-identity-changed")
        need(getattr(opened, "st_birthtime_ns", None) == getattr(before, "st_birthtime_ns", None), "input-open-birthtime-changed")
    except BaseException:
        stream.close()
        raise
    return stream, stamp(opened)


def stable(stream, before):
    need(stamp(os.fstat(stream.fileno())) == before, "input-changed-during-read")


def pairs(items):
    result = {}
    for key, value in items:
        need(key not in result, "duplicate-json-key")
        result[key] = value
    return result


def read_json(path, with_digest=False):
    stream, before = open_input(path, LIMITS["metadataBytes"])
    with stream:
        data = stream.read(LIMITS["metadataBytes"] + 1)
        need(len(data) <= LIMITS["metadataBytes"], "json-size-bound")
        stable(stream, before)
    value = json.loads(data.decode("utf-8-sig"), object_pairs_hook=pairs)
    need(type(value) is dict, "json-object-required")
    return (value, hashlib.sha256(data).hexdigest()) if with_digest else value


def relative_name(name, directory=False):
    need(type(name) is str and 0 < len(name.encode("utf-8")) <= LIMITS["nameBytes"], "member-name-bound")
    need(name == unicodedata.normalize("NFC", name), "member-unicode-alias")
    need(not name.startswith("/") and not re.search(r'[\\:\x00-\x1f\x7f<>"|?*]', name), "unsafe-relative-name")
    value = name[:-1] if directory and name.endswith("/") else name
    parts = value.split("/")
    need(all(p not in ("", ".", "..") and not p.endswith((".", " ")) and
             not re.match(r"^(?:con|prn|aux|nul|conin\$|conout\$|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)", p, re.I) for p in parts), "unsafe-relative-component")
    return value


def extra_fields(data):
    cursor = 0
    seen = set()
    while cursor < len(data):
        need(cursor + 4 <= len(data), "zip-extra-truncated")
        kind, size = struct.unpack_from("<HH", data, cursor)
        cursor += 4
        need(cursor + size <= len(data) and kind not in seen, "zip-extra-ambiguous")
        # Timestamp/NTFS/uid+gid only. No ZIP64, alternate Unicode paths or Unix link metadata.
        need(kind in (0x5455, 0x000A, 0x7875), "zip-extra-unsupported")
        seen.add(kind)
        cursor += size


def end_record(stream, size):
    length = min(size, 65557)
    stream.seek(size - length)
    tail = stream.read(length)
    position = tail.rfind(b"PK\x05\x06")
    need(position >= 0 and position + 22 <= len(tail), "zip-end-record-missing")
    _, disk, central_disk, count_disk, count, central_size, central_offset, comment = struct.unpack_from("<4s4H2LH", tail, position)
    absolute = size - length + position
    need(position + 22 + comment == len(tail), "zip-trailing-data")
    need(disk == central_disk == 0 and count_disk == count, "zip-multipart-unsupported")
    need(count != 65535 and central_size != 0xffffffff and central_offset != 0xffffffff, "zip64-unsupported")
    need(0 < count <= LIMITS["members"] and central_offset + central_size == absolute, "zip-central-boundary")
    need(central_size <= LIMITS["centralMetadataBytes"], "zip-central-metadata-bound")
    # Bound the ACTUAL central-entry count before ZipFile materializes its metadata objects.
    cursor = central_offset
    actual_count = 0
    while cursor < absolute:
        stream.seek(cursor)
        header = stream.read(46)
        need(len(header) == 46 and header[:4] == b"PK\x01\x02", "zip-central-record-invalid")
        name_size, extra_size, comment_size = struct.unpack_from("<3H", header, 28)
        need(0 < name_size <= LIMITS["nameBytes"] and extra_size <= 4096 and comment_size <= 4096, "zip-central-entry-bound")
        cursor += 46 + name_size + extra_size + comment_size
        actual_count += 1
        need(actual_count <= count and cursor <= absolute, "zip-central-count-or-size-mismatch")
    need(actual_count == count and cursor == absolute, "zip-central-count-or-size-mismatch")
    return count, central_offset


def local_record(stream, info, central_offset):
    need(0 <= info.header_offset < central_offset, "zip-local-offset")
    stream.seek(info.header_offset)
    header = stream.read(30)
    need(len(header) == 30, "zip-local-truncated")
    signature, version, flags, method, _time, _date, crc, compressed, size, name_len, extra_len = struct.unpack("<4s5H3L2H", header)
    need(signature == b"PK\x03\x04" and version == info.extract_version and version <= 20, "zip-local-version")
    need(flags == info.flag_bits and method == info.compress_type, "zip-local-central-mismatch")
    need(0 < name_len <= LIMITS["nameBytes"], "zip-local-name-bound")
    name = stream.read(name_len).decode("utf-8" if flags & 0x800 else "cp437")
    need(name == info.orig_filename, "zip-local-name-mismatch")
    extra = stream.read(extra_len)
    need(len(extra) == extra_len, "zip-local-extra-truncated")
    extra_fields(extra)
    start = info.header_offset + 30 + name_len + extra_len
    end = start + info.compress_size
    need(end <= central_offset, "zip-data-overlap")
    if flags & 8:
        need((crc, compressed, size) in ((0, 0, 0), (info.CRC, info.compress_size, info.file_size)), "zip-descriptor-header-mismatch")
        stream.seek(end)
        marker = stream.read(4)
        if marker == b"PK\x07\x08":
            descriptor = stream.read(12)
            end += 16
        else:
            descriptor = marker + stream.read(8)
            end += 12
        need(len(descriptor) == 12 and struct.unpack("<3L", descriptor) == (info.CRC, info.compress_size, info.file_size), "zip-descriptor-mismatch")
    else:
        need((crc, compressed, size) == (info.CRC, info.compress_size, info.file_size), "zip-local-sizes-or-crc")
    need(end <= central_offset, "zip-descriptor-overlap")
    return start, end


def member_chunks(stream, compressed_size, declared_size, method):
    """Yield bounded decoded pieces; never clip success to the declared output size."""
    remaining = compressed_size
    produced = 0
    if method == zipfile.ZIP_STORED:
        while remaining:
            data = stream.read(min(CHUNK, OUTPUT_CHUNK, remaining))
            need(data, "compressed-data-truncated")
            remaining -= len(data)
            produced += len(data)
            need(produced <= declared_size, "decompressed-size-exceeds-declaration")
            yield data
        return

    decoder = zlib.decompressobj(-15)
    pending = b""
    while True:
        # Never append fresh bytes to an unconsumed tail or read past this member.
        if not pending and remaining:
            pending = stream.read(min(CHUNK, remaining))
            need(pending, "compressed-data-truncated")
            remaining -= len(pending)
        supplied = pending
        # max_length=0 means unlimited in zlib. Keep a positive one-byte overflow
        # sentinel even after the declared output is complete; EOF is still required.
        maximum = min(OUTPUT_CHUNK, declared_size - produced + 1)
        need(0 < maximum <= OUTPUT_CHUNK, "deflate-output-bound")
        data = decoder.decompress(supplied, maximum)
        pending = decoder.unconsumed_tail
        need(not decoder.unused_data, "deflate-boundary-or-size")
        produced += len(data)
        need(produced <= declared_size, "decompressed-size-exceeds-declaration")
        if data:
            yield data
        if decoder.eof:
            need(not pending and remaining == 0, "deflate-boundary-or-size")
            return
        if pending:
            need(len(pending) < len(supplied) or data, "deflate-no-progress")
            continue
        # An empty-input bounded call may drain buffered output/end state. Never
        # use flush(length): that length is not a hard returned-output ceiling.
        need(remaining or supplied or data, "deflate-incomplete")


def audit(zip_path, metadata_path, expected_run, expected_source, target_root=None, mapping=None, *, inspect_only=False, profile="evidence"):
    need(type(profile) is str and profile in PROFILES, "audit-profile-invalid")
    limits = dict(LIMITS)
    limits.update(PROFILES[profile])
    need(type(inspect_only) is bool, "inspect-mode-invalid")
    need(not inspect_only or (target_root is None and mapping is None), "inspect-mode-forbids-targets")
    need(type(expected_run) is str and re.fullmatch(r"[1-9][0-9]*", expected_run), "expected-run-invalid")
    need(type(expected_source) is str and re.fullmatch(r"[a-f0-9]{40}", expected_source), "expected-source-invalid")
    metadata, metadata_sha256 = read_json(metadata_path, with_digest=True)
    need(integer(metadata.get("id")) and metadata["id"] > 0, "artifact-id-invalid")
    need(integer(metadata.get("size_in_bytes")) and 0 < metadata["size_in_bytes"] <= limits["archiveBytes"], "artifact-size-invalid")
    need(metadata.get("expired") is False, "artifact-expired-at-snapshot")
    need(type(metadata.get("digest")) is str and re.fullmatch(r"sha256:[a-f0-9]{64}", metadata["digest"]), "artifact-digest-invalid")
    endpoint = f"https://api.github.com/repos/{REPOSITORY}/actions/artifacts/{metadata['id']}"
    need(metadata.get("url") == endpoint and metadata.get("archive_download_url") == endpoint + "/zip", "artifact-repository-binding")
    run = metadata.get("workflow_run")
    need(type(run) is dict and integer(run.get("id")) and run["id"] == int(expected_run) and
         run.get("head_sha") == expected_source, "artifact-run-source-binding")
    need(integer(run.get("repository_id")) and run["repository_id"] > 0 and
         integer(run.get("head_repository_id")) and run["head_repository_id"] == run["repository_id"], "artifact-head-repository-binding")
    targets = {}
    if not inspect_only:
        need(target_root is not None and type(mapping) is dict and 0 < len(mapping) <= LIMITS["members"], "selection-required")
        target_root = physical(target_root, directory=True)
        aliases = set()
        for member, target in mapping.items():
            relative_name(member)
            target = relative_name(target)
            need(target.casefold() not in aliases, "duplicate-target-alias")
            aliases.add(target.casefold())
            targets[member] = target_root.joinpath(*target.split("/"))
    stream, initial = open_input(zip_path, limits["archiveBytes"])
    with stream:
        digest = hashlib.sha256()
        actual_size = 0
        for chunk in iter(lambda: stream.read(CHUNK), b""):
            actual_size += len(chunk)
            need(actual_size <= metadata["size_in_bytes"], "archive-size-mismatch")
            digest.update(chunk)
        need(actual_size == metadata["size_in_bytes"] and "sha256:" + digest.hexdigest() == metadata["digest"], "archive-size-or-hash-mismatch")
        count, central_offset = end_record(stream, actual_size)
        stream.seek(0)
        with zipfile.ZipFile(stream, "r") as archive:
            infos = archive.infolist()
            need(len(infos) == count and archive.start_dir == central_offset, "zip-inventory-mismatch")
            names = set()
            prefixes = {}
            file_names = set()
            records = []
            total = 0
            for info in infos:
                need(info.orig_filename == info.filename, "zip-truncated-name")
                name = relative_name(info.filename, info.is_dir())
                folded = name.casefold()
                need(folded not in names, "zip-duplicate-or-case-alias")
                names.add(folded)
                components = name.split("/")
                for index in range(1, len(components) + 1):
                    prefix = "/".join(components[:index])
                    need(prefixes.setdefault(prefix.casefold(), prefix) == prefix, "zip-component-case-alias")
                need(info.create_system in (0, 3), "zip-platform-unsupported")
                mode = info.external_attr >> 16
                kind = stat.S_IFMT(mode)
                need(kind in (0, stat.S_IFREG, stat.S_IFDIR) and not (info.external_attr & 0x400), "zip-link-or-type-unsupported")
                need((kind != stat.S_IFDIR or info.is_dir()) and (kind != stat.S_IFREG or not info.is_dir()), "zip-directory-type-mismatch")
                need(not (info.external_attr & 0x10) or info.is_dir(), "zip-dos-directory-mismatch")
                need(info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), "zip-compression-unsupported")
                allowed_flags = 0x808 | (6 if info.compress_type == zipfile.ZIP_DEFLATED else 0)
                need(info.flag_bits & ~allowed_flags == 0, "zip-encryption-or-flags-unsupported")
                need(info.extract_version <= 20 and info.volume == 0, "zip-version-or-volume-unsupported")
                need(0 <= info.file_size <= limits["memberBytes"] and 0 <= info.compress_size <= actual_size, "zip-member-size-bound")
                need(not info.is_dir() or info.file_size == 0, "zip-directory-has-payload")
                total += info.file_size
                need(total <= limits["totalBytes"], "zip-total-size-bound")
                extra_fields(info.extra)
                start, end = local_record(stream, info, central_offset)
                records.append((info, name, start, end))
                if not info.is_dir():
                    file_names.add(folded)
            for _, name, _, _ in records:
                parts = name.casefold().split("/")
                need(all("/".join(parts[:i]) not in file_names for i in range(1, len(parts))), "zip-file-ancestor-conflict")
            cursor = 0
            for info, _, _, end in sorted(records, key=lambda row: row[0].header_offset):
                need(info.header_offset == cursor, "zip-overlap-gap-or-prefix")
                cursor = end
            need(cursor == central_offset, "zip-unaccounted-data")
            need(set(targets) <= {name for info, name, _, _ in records if not info.is_dir()}, "selected-member-missing-or-not-file")
            inventory = []
            selected = []
            for info, name, start, _ in records:
                retained = None
                retained_stamp = None
                if name in targets:
                    retained, retained_stamp = open_input(targets[name], limits["memberBytes"])
                try:
                    if retained is not None:
                        need(retained_stamp[2] == info.file_size, "retained-size-mismatch")
                    stream.seek(start)
                    produced = 0
                    crc = 0
                    member_hash = hashlib.sha256()
                    for data in member_chunks(stream, info.compress_size, info.file_size, info.compress_type):
                        produced += len(data)
                        need(produced <= info.file_size, "decompressed-size-exceeds-declaration")
                        crc = zlib.crc32(data, crc)
                        member_hash.update(data)
                        if retained is not None:
                            need(retained.read(len(data)) == data, "retained-byte-mismatch")
                    need(produced == info.file_size and crc & 0xffffffff == info.CRC, "member-size-or-crc-mismatch")
                    if retained is not None:
                        need(retained.read(1) == b"", "retained-trailing-data")
                        stable(retained, retained_stamp)
                        selected.append({"member": name, "retainedRelativePath": mapping[name], "bytes": produced,
                                         "sha256": member_hash.hexdigest(), "byteForByteEqual": True})
                    inventory.append({"name": info.filename, "type": "directory" if info.is_dir() else "regular",
                                      "bytes": produced, "compressedBytes": info.compress_size, "crc32": f"{info.CRC:08x}",
                                      "sha256": member_hash.hexdigest()})
                finally:
                    if retained is not None:
                        retained.close()
        stable(stream, initial)
    return {"schemaVersion": 1, "mode": "inspect-only" if inspect_only else "compare-selected",
            "scope": "offline-original-zip-inspection" if inspect_only else "offline-original-zip-and-selected-retained-byte-consistency", "valid": True,
            "artifactId": metadata["id"], "artifactName": metadata.get("name"), "repository": REPOSITORY,
            "runId": expected_run, "sourceCommit": expected_source, "metadataSha256": metadata_sha256,
            "targetRoot": None if inspect_only else str(target_root), "archiveBytes": actual_size,
            "archiveSha256": digest.hexdigest(), "memberCount": count, "declaredUncompressedBytes": total,
            "allMembersDecodedAndCrcVerified": True, "selectedComparisonsPerformed": not inspect_only,
            "selected": selected, "inventory": inventory,
            "profile": profile, "limits": limits,
            "inputChunkBytes": CHUNK, "outputChunkBytes": OUTPUT_CHUNK,
            "metadataAuthenticationPerformed": False,
            "ownershipAuthority": "no-targets-in-inspect-mode" if inspect_only else "caller-supplied-target-root",
            "workflowSuccessVerified": False, "acceptanceQualificationVerified": False,
            "extracted": False, "extractedToFilesystem": False, "packageCodeExecuted": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("zip", "metadata", "expected-run", "expected-source"):
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--profile", choices=tuple(PROFILES), default="evidence", help="Fixed size policy; desktop-build permits larger members, never partial auditing")
    parser.add_argument("--inspect-only", action="store_true", help="Full archive inspection before extraction; no retained-byte comparison")
    parser.add_argument("--target-root")
    parser.add_argument("--mapping")
    parser.add_argument("--report", help="Fresh output outside any retained target root; never overwritten")
    args = parser.parse_args()
    if args.inspect_only:
        need(args.target_root is None and args.mapping is None, "inspect-mode-forbids-targets")
    else:
        need(args.target_root is not None and args.mapping is not None, "final-mode-requires-target-root-and-mapping")
    result = audit(args.zip, args.metadata, args.expected_run, args.expected_source, args.target_root,
                   None if args.inspect_only else read_json(args.mapping), inspect_only=args.inspect_only, profile=args.profile)
    text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        target = Path(os.path.abspath(args.report))
        relative_name(target.name)
        physical(target.parent, directory=True)
        if not args.inspect_only:
            root = str(physical(args.target_root, directory=True))
            try:
                within_retained = os.path.normcase(os.path.commonpath([str(target), root])) == os.path.normcase(root)
            except ValueError:  # Different ordinary local drives are outside the retained root.
                within_retained = False
            need(not within_retained, "report-must-be-outside-retained-root")
        if os.name == "nt":
            need(":" not in str(target)[2:], "report-alternate-stream")
        with target.open("x", encoding="utf-8", newline="\n") as output:
            output.write(text)
    print(text, end="")


if __name__ == "__main__":
    try:
        main()
    except (AuditError, OSError, ValueError, zipfile.BadZipFile, zlib.error, struct.error, UnicodeError) as error:
        reason = str(error) if isinstance(error, AuditError) else type(error).__name__
        print(json.dumps({"valid": False, "error": reason, "packageCodeExecuted": False}), file=sys.stderr)
        sys.exit(1)
