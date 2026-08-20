"""Compare the regenerable RTL and CModel SRF traces cycle by cycle."""

import csv
import hashlib
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
RTL_TRACE = ROOT / "sim" / "trace" / "rtl_srf_trace.csv"
CMODEL_TRACE = ROOT / "sim" / "trace" / "cmodel_srf_trace.csv"
FIELDS = ("cycle", "hemisphere", "direction", "column", "superlane",
          "stream", "lane", "valid", "data")
REFERENCE_TRACE_SHA256 = "af42233071488a097df9ebeb0f54a222ab483cf27659d9ddf31972f936b5d924"


def load(path: Path) -> list[tuple[int, ...]]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        if tuple(reader.fieldnames or ()) != FIELDS:
            raise ValueError(f"{path}: unexpected CSV header {reader.fieldnames}")
        return [tuple(int(row[field], 0) for field in FIELDS) for row in reader]


try:
    rtl_rows = load(RTL_TRACE)
    cmodel_rows = load(CMODEL_TRACE)
except (OSError, ValueError) as exc:
    print(f"ERROR {exc}")
    print("TEST_FAIL")
    sys.exit(1)

errors: list[str] = []
if len(rtl_rows) != 17 * 16:
    errors.append(f"RTL row count {len(rtl_rows)} != 272")
if len(cmodel_rows) != 17 * 16:
    errors.append(f"CModel row count {len(cmodel_rows)} != 272")
if rtl_rows != cmodel_rows:
    for index, (rtl, cmodel) in enumerate(zip(rtl_rows, cmodel_rows)):
        if rtl != cmodel:
            errors.append(f"row {index}: RTL={rtl} CModel={cmodel}")
            if len(errors) >= 10:
                break
    if len(rtl_rows) != len(cmodel_rows):
        errors.append("trace lengths differ")

rtl_sha256 = hashlib.sha256(RTL_TRACE.read_bytes()).hexdigest()
if rtl_sha256 != REFERENCE_TRACE_SHA256:
    errors.append(
        f"RTL trace SHA256 {rtl_sha256} != reference baseline {REFERENCE_TRACE_SHA256}")

# Independent timing sanity check for the trace token injected at column 0.
for row in rtl_rows:
    cycle, _, direction, column, superlane, stream, lane, valid, data = row
    expected_valid = int(cycle >= 1 and column == cycle - 1)
    expected_data = 0x5A if expected_valid else 0
    if (direction, superlane, stream, lane) != (0, 0, 0, 0):
        errors.append(f"unexpected coordinate in row {row}")
        break
    if (valid, data) != (expected_valid, expected_data):
        errors.append(f"formula mismatch at cycle={cycle} column={column}")
        if len(errors) >= 10:
            break

if errors:
    for error in errors:
        print(f"ERROR {error}")
    print("TEST_FAIL")
    sys.exit(1)

print(f"TRACE_MATCH rows={len(rtl_rows)} cycles=17 columns=16")
print(f"TRACE_SHA256 {rtl_sha256.upper()}")
print("AC5_RTL_CMODEL_COMPARE PASS")
print("TEST_PASS")
