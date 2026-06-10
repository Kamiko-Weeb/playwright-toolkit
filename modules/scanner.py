"""
Virus Scanner — signature, heuristic and (optional) cloud-reputation file scanner.

Detection layers, cheapest to most expensive:
  1. Hash signatures   — SHA-256/MD5 of the file vs a known-bad hash database.
  2. Pattern signatures — byte/regex indicators scanned inside the file body.
  3. Entropy heuristic  — high Shannon entropy flags packed/encrypted payloads.
  4. VirusTotal lookup  — optional online hash reputation (needs VT_API_KEY).

Nothing here detonates or executes a sample — files are only read, hashed and
pattern-matched. Detections can be copied into an isolated quarantine folder.

Prove it works without real malware: pick the "generate EICAR test file" option,
then scan. EICAR is a harmless 68-byte string every antivirus is built to flag.
"""

import csv
import json
import math
import re
import shutil
import time
from collections import Counter
from datetime import datetime
from hashlib import md5, sha256
from pathlib import Path

from config.settings import (
    CSV_DIR,
    LOGS_DIR,
    QUARANTINE_DIR,
    RULES_DIR,
    SIGNATURES_FILE,
    VT_API_KEY,
)

# Files larger than this are hashed but not byte-pattern scanned (keeps it fast).
MAX_PATTERN_SCAN_BYTES = 8 * 1024 * 1024  # 8 MB
# Entropy at/above this (out of 8.0 bits/byte) suggests packing/encryption.
ENTROPY_FLAG = 7.2
# Extensions that earn a closer look when also high-entropy.
RISKY_EXTS = {".exe", ".dll", ".scr", ".js", ".vbs", ".ps1", ".bat",
              ".cmd", ".jar", ".sh", ".php", ".hta", ".com"}
# Archive types whose members get scanned in memory (.jar is a zip too).
ARCHIVE_EXTS = {".zip", ".jar", ".tar", ".tgz", ".gz", ".tar.gz"}
# Zip-bomb guards: skip any single member or total expansion beyond these.
MAX_ARCHIVE_MEMBER_BYTES = 64 * 1024 * 1024   # 64 MB per member
MAX_ARCHIVE_TOTAL_BYTES = 256 * 1024 * 1024   # 256 MB per archive
MAX_ARCHIVE_DEPTH = 4                          # how deep to recurse into nested archives

# True file types that are executable code.
EXECUTABLE_TYPES = {"PE", "ELF", "Mach-O"}
# Extensions a user trusts as "just a document/image" — an executable wearing
# one of these is almost certainly trying to deceive (extension spoofing).
DECEPTIVE_EXTS = {".pdf", ".doc", ".docx", ".txt", ".rtf", ".csv",
                  ".jpg", ".jpeg", ".png", ".gif", ".xls", ".xlsx"}

EICAR = (
    r"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"
)


# ──────────────────────────────────────────────────────────────────────────
# Signature loading
# ──────────────────────────────────────────────────────────────────────────
def load_signatures() -> dict:
    with open(SIGNATURES_FILE, encoding="utf-8") as f:
        sigs = json.load(f)

    compiled = []
    for p in sigs.get("pattern_signatures", []):
        entry = {"name": p["name"], "severity": p.get("severity", "suspicious"),
                 "description": p.get("description", "")}
        if "bytes_hex" in p:
            entry["needle"] = bytes.fromhex(p["bytes_hex"])
        elif "regex" in p:
            entry["regex"] = re.compile(p["regex"].encode(), re.IGNORECASE)
        compiled.append(entry)

    return {
        "hashes": sigs.get("hash_signatures", {}),
        "patterns": compiled,
        "yara": load_yara_rules(),
    }


def load_yara_rules():
    """Compile any rules/*.yar — only if the optional yara-python lib is present.

    Returns a compiled yara.Rules object, or None when YARA is unavailable or no
    rule files exist. Never raises: a bad rule file just disables the layer.
    """
    try:
        import yara
    except ImportError:
        return None

    rule_files = sorted(RULES_DIR.glob("*.yar")) if RULES_DIR.exists() else []
    if not rule_files:
        return None
    try:
        return yara.compile(filepaths={p.stem: str(p) for p in rule_files})
    except Exception as e:  # malformed rule — log and carry on without it
        print(f"  YARA: skipping rules ({e})")
        return None


# ──────────────────────────────────────────────────────────────────────────
# Primitives
# ──────────────────────────────────────────────────────────────────────────
def detect_filetype(data: bytes) -> str | None:
    """Identify a file's true type from its magic bytes, ignoring the extension."""
    if data[:2] == b"MZ":
        return "PE"            # Windows executable / DLL
    if data[:4] == b"\x7fELF":
        return "ELF"           # Linux executable
    if data[:4] in (b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf",
                    b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe"):
        return "Mach-O"        # macOS executable
    if data[:4] == b"PK\x03\x04":
        return "ZIP"
    if data[:4] == b"%PDF":
        return "PDF"
    if data[:2] == b"\x1f\x8b":
        return "GZIP"
    if data[:3] == b"\xff\xd8\xff":
        return "JPEG"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "PNG"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "GIF"
    return None


def hash_file(path: Path) -> tuple[str, str]:
    """Stream the file once, return (sha256_hex, md5_hex)."""
    h_sha, h_md5 = sha256(), md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h_sha.update(chunk)
            h_md5.update(chunk)
    return h_sha.hexdigest(), h_md5.hexdigest()


def shannon_entropy(data: bytes) -> float:
    """Bits of entropy per byte, 0.0 (uniform) .. 8.0 (random/encrypted)."""
    if not data:
        return 0.0
    counts = Counter(data)
    length = len(data)
    return -sum((c / length) * math.log2(c / length) for c in counts.values())


def vt_lookup(sha_hex: str) -> dict | None:
    """Query VirusTotal for a file hash. Returns None if no key/offline/unknown."""
    if not VT_API_KEY:
        return None
    try:
        import requests
    except ImportError:
        return None
    try:
        r = requests.get(
            f"https://www.virustotal.com/api/v3/files/{sha_hex}",
            headers={"x-apikey": VT_API_KEY},
            timeout=15,
        )
        if r.status_code == 404:
            return {"known": False}
        r.raise_for_status()
        stats = r.json()["data"]["attributes"]["last_analysis_stats"]
        return {"known": True, "malicious": stats.get("malicious", 0),
                "suspicious": stats.get("suspicious", 0),
                "harmless": stats.get("harmless", 0)}
    except Exception as e:
        return {"error": str(e)}


# ──────────────────────────────────────────────────────────────────────────
# Per-file scan
# ──────────────────────────────────────────────────────────────────────────
def _escalate(result: dict, verdict: str) -> None:
    """Raise the verdict only upward: clean → suspicious → malicious."""
    order = {"clean": 0, "suspicious": 1, "malicious": 2}
    if order[verdict] > order.get(result["verdict"], 0):
        result["verdict"] = verdict


def _evaluate(result: dict, sha_hex: str, body: bytes | None,
              suffix: str, sigs: dict, use_vt: bool) -> dict:
    """Apply all detection layers given a precomputed hash and (optional) body."""
    # Layer 1 — known-bad hash
    if sha_hex in sigs["hashes"]:
        _escalate(result, "malicious")
        result["detections"].append(f"hash: {sigs['hashes'][sha_hex]}")

    # Layers 2 & 3 — pattern + entropy (body is None when too large to read)
    if body is not None:
        # Layer 2.0 — true file type vs claimed extension (spoofing)
        ftype = detect_filetype(body)
        result["filetype"] = ftype
        if ftype in EXECUTABLE_TYPES and suffix in DECEPTIVE_EXTS:
            result["detections"].append(
                f"spoofing: {suffix} file is actually a {ftype} executable")
            _escalate(result, "malicious")

        for sig in sigs["patterns"]:
            hit = ("needle" in sig and sig["needle"] in body) or (
                "regex" in sig and sig["regex"].search(body))
            if hit:
                sev = sig["severity"]
                result["detections"].append(f"pattern: {sig['name']} ({sev})")
                _escalate(result, "malicious" if sev in ("malicious", "test")
                          else "suspicious")

        ent = shannon_entropy(body)
        result["entropy"] = round(ent, 2)
        if ent >= ENTROPY_FLAG and suffix in RISKY_EXTS:
            result["detections"].append(
                f"heuristic: high entropy {ent:.2f} on risky type {suffix}")
            _escalate(result, "suspicious")

        # Layer 3.5 — optional YARA rules
        rules = sigs.get("yara")
        if rules is not None:
            try:
                for match in rules.match(data=body):
                    sev = match.meta.get("severity", "suspicious")
                    result["detections"].append(f"yara: {match.rule} ({sev})")
                    _escalate(result, "malicious" if sev in ("malicious", "test")
                              else "suspicious")
            except Exception as e:
                result["detections"].append(f"yara: match error ({e})")

    # Layer 4 — VirusTotal reputation
    if use_vt:
        vt = vt_lookup(sha_hex)
        if vt and vt.get("known") and vt.get("malicious", 0) > 0:
            result["detections"].append(
                f"virustotal: {vt['malicious']} engines flagged malicious")
            _escalate(result, "malicious")
        elif vt and "error" in vt:
            result["detections"].append(f"virustotal: lookup error ({vt['error']})")

    return result


def scan_bytes(name: str, data: bytes, sigs: dict, use_vt: bool = False) -> dict:
    """Scan an in-memory blob (e.g. an archive member) by name + content."""
    result = {"path": name, "size": len(data),
              "sha256": sha256(data).hexdigest(), "md5": md5(data).hexdigest(),
              "entropy": 0.0, "verdict": "clean", "detections": []}
    body = data if len(data) <= MAX_PATTERN_SCAN_BYTES else None
    suffix = Path(name.split("::")[-1]).suffix.lower()
    return _evaluate(result, result["sha256"], body, suffix, sigs, use_vt)


def scan_file(path: Path, sigs: dict, use_vt: bool = False) -> dict:
    result = {"path": str(path), "size": 0, "sha256": "", "md5": "",
              "entropy": 0.0, "verdict": "clean", "detections": []}

    try:
        result["size"] = path.stat().st_size
        sha_hex, md5_hex = hash_file(path)
        result["sha256"], result["md5"] = sha_hex, md5_hex
    except (OSError, PermissionError) as e:
        result["verdict"] = "error"
        result["detections"].append(f"unreadable: {e}")
        return result

    body = None
    if result["size"] <= MAX_PATTERN_SCAN_BYTES:
        try:
            body = path.read_bytes()
        except (OSError, PermissionError):
            body = b""

    _evaluate(result, sha_hex, body, path.suffix.lower(), sigs, use_vt)

    # Peek inside archives for members that on-disk scanning would never see.
    if path.suffix.lower() in ARCHIVE_EXTS:
        result["members"] = scan_archive(path, sigs, use_vt)
        for m in result["members"]:
            if m["verdict"] != "clean":
                _escalate(result, m["verdict"])
                result["detections"].append(
                    f"archive member {Path(m['path']).name}: {m['verdict']}")

    return result


# ──────────────────────────────────────────────────────────────────────────
# Archive inspection  ·  scan members of zip/tar without extracting to disk
# ──────────────────────────────────────────────────────────────────────────
def _looks_like_archive(name: str, data: bytes) -> bool:
    suffix = "".join(Path(name).suffixes[-2:]).lower()
    if Path(name).suffix.lower() in ARCHIVE_EXTS or suffix in ARCHIVE_EXTS:
        return True
    return detect_filetype(data) in ("ZIP", "GZIP")


def scan_archive(source, sigs: dict, use_vt: bool = False,
                 depth: int = 0, label: str | None = None) -> list[dict]:
    """Scan members of a zip/tar (bomb-guarded), recursing into nested archives.

    `source` may be a filesystem Path (top level) or raw bytes (a nested archive
    member). Recursion stops at MAX_ARCHIVE_DEPTH.
    """
    import io
    import tarfile
    import zipfile

    members: list[dict] = []
    budget = MAX_ARCHIVE_TOTAL_BYTES

    if isinstance(source, (str, Path)):
        path = Path(source)
        arc_label = label or path.name
        zip_src = lambda: zipfile.ZipFile(path)
        tar_src = lambda: tarfile.open(path)
        is_zip = zipfile.is_zipfile(path)
        is_tar = (not is_zip) and tarfile.is_tarfile(path)
    else:
        arc_label = label or "<archive>"
        zip_src = lambda: zipfile.ZipFile(io.BytesIO(source))
        tar_src = lambda: tarfile.open(fileobj=io.BytesIO(source))
        is_zip = zipfile.is_zipfile(io.BytesIO(source))
        is_tar = False
        if not is_zip:
            try:
                tarfile.open(fileobj=io.BytesIO(source)).close()
                is_tar = True
            except Exception:
                is_tar = False

    def consider(name: str, declared_size: int, reader) -> None:
        nonlocal budget
        mlabel = f"{arc_label}::{name}"
        if declared_size > MAX_ARCHIVE_MEMBER_BYTES:
            members.append(_bomb(mlabel, declared_size, "oversized member"))
            return
        if declared_size > budget:
            members.append(_bomb(mlabel, declared_size, "total extract budget exceeded"))
            return
        try:
            data = reader()
        except Exception as e:
            members.append({"path": mlabel, "size": declared_size, "sha256": "",
                            "md5": "", "entropy": 0.0, "verdict": "error",
                            "detections": [f"archive: unreadable member ({e})"]})
            return
        budget -= len(data)
        members.append(scan_bytes(mlabel, data, sigs, use_vt))

        # Recurse into nested archives, depth-limited.
        if depth + 1 < MAX_ARCHIVE_DEPTH and _looks_like_archive(name, data):
            members.extend(scan_archive(data, sigs, use_vt,
                                        depth=depth + 1, label=mlabel))
        elif depth + 1 >= MAX_ARCHIVE_DEPTH and _looks_like_archive(name, data):
            members.append({"path": f"{mlabel}::<nested>", "size": 0, "sha256": "",
                            "md5": "", "entropy": 0.0, "verdict": "suspicious",
                            "detections": [f"archive: nesting deeper than "
                                           f"{MAX_ARCHIVE_DEPTH} levels — possible bomb"]})

    try:
        if is_zip:
            with zip_src() as zf:
                for info in zf.infolist():
                    if info.is_dir():
                        continue
                    consider(info.filename, info.file_size,
                             lambda i=info, z=zf: z.read(i))
        elif is_tar:
            with tar_src() as tf:
                for info in tf.getmembers():
                    if not info.isfile():
                        continue
                    consider(info.name, info.size,
                             lambda i=info, t=tf: t.extractfile(i).read())
    except Exception as e:
        members.append({"path": f"{arc_label}::<archive>", "size": 0,
                        "sha256": "", "md5": "", "entropy": 0.0,
                        "verdict": "error",
                        "detections": [f"archive: could not open ({e})"]})

    return members


def _bomb(label: str, size: int, why: str) -> dict:
    return {"path": label, "size": size, "sha256": "", "md5": "", "entropy": 0.0,
            "verdict": "suspicious", "detections": [f"archive: {why} — possible bomb"]}


# ──────────────────────────────────────────────────────────────────────────
# Directory walk
# ──────────────────────────────────────────────────────────────────────────
def scan_path(target: Path, sigs: dict, use_vt: bool = False) -> list[dict]:
    files = [target] if target.is_file() else [
        p for p in target.rglob("*")
        if p.is_file() and QUARANTINE_DIR not in p.parents
    ]
    total = len(files)
    print(f"  Scanning {total} file(s) under {target} ...\n")

    results = []
    for i, fp in enumerate(files, 1):
        res = scan_file(fp, sigs, use_vt=use_vt)
        results.append(res)
        if res["verdict"] != "clean":
            tag = res["verdict"].upper()
            print(f"  [{tag}] {fp}")
            for d in res["detections"]:
                print(f"           └─ {d}")
            for m in res.get("members", []):
                if m["verdict"] != "clean":
                    print(f"           └─ inside: {Path(m['path']).name} "
                          f"[{m['verdict']}] {'; '.join(m['detections'])}")
        if i % 50 == 0 or i == total:
            print(f"  ...{i}/{total} scanned")
    return results


def quarantine(results: list[dict]) -> int:
    """Copy malicious/suspicious files into the isolated quarantine folder."""
    moved = 0
    for r in results:
        if r["verdict"] in ("malicious", "suspicious"):
            src = Path(r["path"])
            if not src.exists():
                continue
            dest = QUARANTINE_DIR / f"{r['sha256'][:12]}_{src.name}.quarantined"
            try:
                shutil.copy2(src, dest)
                moved += 1
            except (OSError, PermissionError) as e:
                print(f"  Could not quarantine {src}: {e}")
    return moved


def save_report(results: list[dict], target: Path) -> tuple[str, str]:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_path = CSV_DIR / f"scan_{ts}.csv"
    json_path = LOGS_DIR / f"scan_{ts}.json"

    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["path", "verdict", "sha256", "size", "entropy", "detections"])
        for r in results:
            w.writerow([r["path"], r["verdict"], r["sha256"], r["size"],
                        r["entropy"], " | ".join(r["detections"])])

    with open(json_path, "w", encoding="utf-8") as f:
        json.dump({"target": str(target),
                   "scanned_at": ts,
                   "results": results}, f, indent=2)

    return str(csv_path), str(json_path)


def make_eicar_sample() -> Path:
    """Drop a harmless EICAR test file so detection can be verified end-to-end."""
    from config.settings import DATA_DIR
    sample = DATA_DIR / "eicar_test.txt"
    sample.write_text(EICAR, encoding="ascii")
    print(f"  Wrote EICAR test file → {sample}")
    print("  (harmless 68-byte string; real AV on your host may flag it too)")
    return sample


def summarise(results: list[dict], elapsed: float) -> Counter:
    counts = Counter(r["verdict"] for r in results)
    print("\n  ── Summary ─────────────────────────────")
    print(f"    Files scanned : {len(results)}")
    print(f"    Malicious     : {counts.get('malicious', 0)}")
    print(f"    Suspicious    : {counts.get('suspicious', 0)}")
    print(f"    Clean         : {counts.get('clean', 0)}")
    print(f"    Errors        : {counts.get('error', 0)}")
    print(f"    Time          : {elapsed:.2f}s")
    return counts


# ──────────────────────────────────────────────────────────────────────────
# Non-interactive CLI  ·  python -m modules.scanner <path> [--quarantine] [--vt]
# ──────────────────────────────────────────────────────────────────────────
def cli(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        prog="scanner",
        description="Signature & heuristic virus scanner (non-interactive).",
    )
    parser.add_argument("path", help="file or folder to scan")
    parser.add_argument("-q", "--quarantine", action="store_true",
                        help="copy flagged files into output/quarantine/")
    parser.add_argument("--vt", action="store_true",
                        help="enable VirusTotal lookups (needs VT_API_KEY)")
    parser.add_argument("--no-report", action="store_true",
                        help="skip writing the CSV/JSON report")
    args = parser.parse_args(argv)

    target = Path(args.path).expanduser()
    if not target.exists():
        print(f"  Path not found: {target}")
        return 2
    if args.vt and not VT_API_KEY:
        print("  --vt given but VT_API_KEY is not set; continuing offline.")

    sigs = load_signatures()
    start = time.time()
    results = scan_path(target, sigs, use_vt=args.vt and bool(VT_API_KEY))
    counts = summarise(results, time.time() - start)

    if args.quarantine and (counts.get("malicious") or counts.get("suspicious")):
        moved = quarantine(results)
        print(f"  Quarantined {moved} file(s) → {QUARANTINE_DIR}")

    if not args.no_report:
        csv_path, json_path = save_report(results, target)
        print(f"\n  Report: {csv_path}\n          {json_path}")

    # Exit non-zero when something was flagged — handy for scripts/CI.
    return 1 if counts.get("malicious") else 0


# ──────────────────────────────────────────────────────────────────────────
# Interactive entry point
# ──────────────────────────────────────────────────────────────────────────
def run():
    sigs = load_signatures()
    yara_state = "on" if sigs.get("yara") is not None else "off (install yara-python)"
    print(f"\n  Loaded {len(sigs['hashes'])} hash + "
          f"{len(sigs['patterns'])} pattern signatures · YARA {yara_state}.")

    choice = input("\n  Generate an EICAR test file first? [y/N]: ").strip().lower()
    default_target = make_eicar_sample().parent if choice == "y" else None

    prompt = "\n  Path to scan (file or folder)"
    if default_target:
        prompt += f" [{default_target}]"
    raw = input(prompt + ": ").strip()
    target = Path(raw).expanduser() if raw else default_target
    if not target or not target.exists():
        print("  Path not found.")
        return

    use_vt = False
    if VT_API_KEY:
        use_vt = input("  Use VirusTotal lookups? [y/N]: ").strip().lower() == "y"

    start = time.time()
    results = scan_path(target, sigs, use_vt=use_vt)
    counts = summarise(results, time.time() - start)

    if counts.get("malicious") or counts.get("suspicious"):
        if input("\n  Quarantine flagged files? [y/N]: ").strip().lower() == "y":
            moved = quarantine(results)
            print(f"  Quarantined {moved} file(s) → {QUARANTINE_DIR}")

    csv_path, json_path = save_report(results, target)
    print(f"\n  Report: {csv_path}")
    print(f"          {json_path}")


if __name__ == "__main__":
    import sys
    sys.exit(cli())
