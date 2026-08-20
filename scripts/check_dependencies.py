"""Check that the public SRF RTL contains only the documented hierarchy."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
EXPECTED = {
    "sr_leaf.v",
    "sr_column.v",
    "sr_direction_fabric.v",
    "sr_hemisphere_fabric.v",
    "sr_fabric.v",
}
ALLOWED_INSTANCES = {
    "sr_leaf",
    "sr_column",
    "sr_direction_fabric",
    "sr_hemisphere_fabric",
}
errors: list[str] = []


def strip_comments(source: str) -> str:
    return re.sub(r"//.*?$|/\*.*?\*/", "", source,
                  flags=re.MULTILINE | re.DOTALL)


actual = {path.name for path in RTL.glob("*.v")}
if actual != EXPECTED:
    errors.append(f"public RTL file set mismatch: {sorted(actual)}")

for path in sorted(RTL.glob("*.v")):
    source = strip_comments(path.read_text(encoding="utf-8"))
    module_name = path.stem
    declared = re.search(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", source)
    if not declared or declared.group(1) != module_name:
        errors.append(f"{path.name}: module/file naming mismatch")

    instances = re.findall(
        r"^\s*(sr_[A-Za-z0-9_]+)\s*(?:#\s*\(|[A-Za-z_][A-Za-z0-9_]*\s*\()",
        source, flags=re.MULTILINE)
    for instance in instances:
        if instance != module_name and instance not in ALLOWED_INSTANCES:
            errors.append(f"{path.name}: non-core instance {instance}")

if errors:
    for error in errors:
        print(f"ERROR {error}")
    print("CORE_DEPENDENCY_AUDIT FAIL")
    print("TEST_FAIL")
    sys.exit(1)

print("CORE_FILES " + " ".join(sorted(EXPECTED)))
print("CORE_DEPENDENCY_AUDIT PASS")
print("TEST_PASS")
