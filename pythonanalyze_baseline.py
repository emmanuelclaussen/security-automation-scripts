#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from datetime import datetime

ALLOWED_STATUS = {"OK", "WARN", "FAIL"}

def read_jsonl_file(path: Path):
    """Read a JSONL file and return (entries, errors)."""
    entries = []
    errors = []

    try:
        with path.open("r", encoding="utf-8-sig") as f:
            for lineno, line in enumerate(f, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    entries.append(obj)
                except json.JSONDecodeError as e:
                    errors.append(f"{path.name}:{lineno} JSONDecodeError: {e}")
    except Exception as e:
        errors.append(f"{path.name}: Could not read file: {e}")

    return entries, errors

def normalize_status(s):
    if not isinstance(s, str):
        return "FAIL"
    s = s.strip().upper()
    return s if s in ALLOWED_STATUS else "FAIL"

def score_status(status):
    # Higher = worse
    return {"OK": 0, "WARN": 1, "FAIL": 2}.get(status, 2)

def main():
    if len(sys.argv) != 3:
        print("Usage: python3 analyze_baseline.py <logdir> <output_report_md>")
        sys.exit(2)

    logdir = Path(sys.argv[1]).expanduser().resolve()
    out_path = Path(sys.argv[2]).expanduser().resolve()

    if not logdir.exists() or not logdir.is_dir():
        print(f"ERROR: logdir does not exist or is not a directory: {logdir}")
        sys.exit(2)

    log_files = sorted(logdir.glob("*.jsonl"))
    if not log_files:
        print(f"ERROR: no .jsonl files found in: {logdir}")
        sys.exit(2)

    all_entries = []
    all_errors = []
    for lf in log_files:
        entries, errors = read_jsonl_file(lf)
        all_entries.extend(entries)
        all_errors.extend(errors)

    # Filter out only "real checks" (ignore run_start/run_summary)
    check_entries = []
    for e in all_entries:
        check = e.get("check", "")
        if check in ("run_start", "run_summary"):
            continue
        status = normalize_status(e.get("status"))
        e["_norm_status"] = status
        check_entries.append(e)

    # Summaries
    counts = {"OK": 0, "WARN": 0, "FAIL": 0}
    worst = "OK"
    findings = []

    for e in check_entries:
        st = e["_norm_status"]
        counts[st] += 1
        if score_status(st) > score_status(worst):
            worst = st
        if st in ("WARN", "FAIL"):
            findings.append(e)

    # Simple risk level
    fail_count = counts["FAIL"]
    if fail_count == 0:
        risk = "Låg"
    elif fail_count == 1:
        risk = "Medel"
    else:
        risk = "Hög"

    out_path.parent.mkdir(parents=True, exist_ok=True)

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with out_path.open("w", encoding="utf-8") as rep:
        rep.write(f"# Security baseline-rapport\n\n")
        rep.write(f"**Genererad:** {now}\n\n")
        rep.write(f"## Inlästa loggfiler\n")
        for lf in log_files:
            rep.write(f"- {lf.name}\n")
        rep.write("\n")

        rep.write("## Sammanfattning\n")
        rep.write(f"- Totalt antal kontroller (exkl. start/summering): {len(check_entries)}\n")
        rep.write(f"- OK: {counts['OK']}\n")
        rep.write(f"- WARN: {counts['WARN']}\n")
        rep.write(f"- FAIL: {counts['FAIL']}\n")
        rep.write(f"- Värsta status: **{worst}**\n")
        rep.write(f"- Bedömd risknivå (enkel modell): **{risk}**\n\n")

        rep.write("## Avvikelser (WARN/FAIL)\n")
        if not findings:
            rep.write("Inga avvikelser identifierades.\n\n")
        else:
            for e in findings:
                rep.write(f"- **{e.get('host','?')}** / {e.get('os','?')} / `{e.get('check','?')}` → **{e.get('_norm_status')}**\n")
                rep.write(f"  - Detaljer: {e.get('details','')}\n")
            rep.write("\n")

        rep.write("## Fel vid inläsning (om några)\n")
        if not all_errors:
            rep.write("Inga inläsningsfel.\n")
        else:
            for err in all_errors:
                rep.write(f"- {err}\n")

    print(f"OK: Report written to: {out_path}")

    # Exit code: 0 if no FAIL, 1 if FAIL exists (valfritt men rimligt)
    sys.exit(0 if counts["FAIL"] == 0 else 1)

if __name__ == "__main__":
    main()
