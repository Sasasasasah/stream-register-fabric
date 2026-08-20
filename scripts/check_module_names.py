"""Audit public RTL file names, module names, and parent hierarchy."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"

PUBLIC_MODULES = {
    "sr_leaf.v": "sr_leaf",
    "sr_column.v": "sr_column",
    "sr_direction_fabric.v": "sr_direction_fabric",
    "sr_hemisphere_fabric.v": "sr_hemisphere_fabric",
    "sr_fabric.v": "sr_fabric",
}
errors: list[str] = []


def strip_comments(text: str) -> str:
    return re.sub(r"//.*?$|/\*.*?\*/", "", text,
                  flags=re.MULTILINE | re.DOTALL)


actual_files = {path.name for path in RTL.glob("*.v")}
if actual_files != set(PUBLIC_MODULES):
    errors.append(f"public RTL file set mismatch: {sorted(actual_files)}")

sources: dict[str, str] = {}
for filename, module in PUBLIC_MODULES.items():
    path = RTL / filename
    if not path.is_file():
        continue
    source = strip_comments(path.read_text(encoding="utf-8"))
    sources[module] = source
    declarations = re.findall(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", source)
    if declarations != [module]:
        errors.append(f"{filename}: declarations {declarations}, expected [{module}]")

def instance_count(parent: str, child: str) -> int:
    source = sources.get(parent, "")
    return len(re.findall(rf"\b{re.escape(child)}\s*#\s*\(", source))


if instance_count("sr_fabric", "sr_hemisphere_fabric") != 2:
    errors.append("sr_fabric must directly instantiate two hemisphere fabrics")
if instance_count("sr_hemisphere_fabric", "sr_direction_fabric") != 2:
    errors.append("sr_hemisphere_fabric must directly instantiate two directions")
if instance_count("sr_direction_fabric", "sr_column") != 1:
    errors.append("sr_direction_fabric must contain one generated column template")
if instance_count("sr_column", "sr_leaf") != 1:
    errors.append("sr_column must contain one generated leaf template")

direction = sources.get("sr_direction_fabric", "")
column = sources.get("sr_column", "")
if not re.search(r"for\s*\([^;]+;[^;]*SR_COLUMNS_PER_HEMI", direction):
    errors.append("direction fabric column generate bound is missing")
if not re.search(r"for\s*\([^;]+;[^;]*P_SUPERLANES_PER_COLUMN", column):
    errors.append("column superlane generate bound is missing")

if errors:
    for error in errors:
        print(f"ERROR {error}")
    print("CORE_MODULE_NAMING FAIL")
    print("TEST_FAIL")
    sys.exit(1)

print("CORE_MODULE_NAMING PASS")
print("TEST_PASS")
