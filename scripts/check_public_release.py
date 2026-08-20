"""Static pre-publication audit for the personal SRF repository."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".v", ".cpp", ".h", ".md", ".py", ".bat"}
GENERATED_SUFFIXES = {
    ".vvp", ".vcd", ".fst", ".lxt", ".lxt2",
    ".exe", ".obj", ".o", ".out", ".log", ".csv",
}
RTL_MODULES = {
    "sr_leaf.v": "sr_leaf",
    "sr_column.v": "sr_column",
    "sr_direction_fabric.v": "sr_direction_fabric",
    "sr_hemisphere_fabric.v": "sr_hemisphere_fabric",
    "sr_fabric.v": "sr_fabric",
}
REQUIRED_DIRS = {"rtl", "cmodel", "tb", "scripts", "docs"}
REQUIRED_FILES = {
    "README.md", ".gitignore",
    "docs/architecture.md", "docs/verification.md",
    "cmodel/srf_model.h", "cmodel/srf_model.cpp",
    "cmodel/test_cmodel.cpp",
}

# Terms are assembled so this audit can check its own source without
# embedding the complete terms as plain text.
SENSITIVE_TERMS = (
    "FT" + "L" + "PU",
    "HW" + "SP" + "EC",
    "SP" + "EC",
    "L" + "PU",
    "inter" + "nal",
    "com" + "pany",
    "Shang" + "hai",
    chr(0x65F6) + chr(0x64CE),
)
FORBIDDEN_DIRS = {
    "com" + "pany",
    "sp" + "ec",
    "inter" + "nal",
    "present" + "ation",
}
FORBIDDEN_FILES = {
    "VERSION",
    "RELEASE.md",
    "sp" + "ec_compliance.md",
}

checks: dict[str, list[str]] = {
    "PUBLIC_FILE_SET": [],
    "PUBLIC_NAME_AUDIT": [],
    "PUBLIC_PATH_AUDIT": [],
    "PUBLIC_LINK_AUDIT": [],
    "PUBLIC_MODULE_AUDIT": [],
}


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def strip_verilog_comments(source: str) -> str:
    return re.sub(r"//.*?$|/\*.*?\*/", "", source,
                  flags=re.MULTILINE | re.DOTALL)


for directory in sorted(REQUIRED_DIRS):
    if not (ROOT / directory).is_dir():
        checks["PUBLIC_FILE_SET"].append(f"missing directory {directory}")

for filename in sorted(REQUIRED_FILES):
    if not (ROOT / filename).is_file():
        checks["PUBLIC_FILE_SET"].append(f"missing file {filename}")

actual_rtl = {path.name for path in (ROOT / "rtl").glob("*.v")}
if actual_rtl != set(RTL_MODULES):
    checks["PUBLIC_FILE_SET"].append(
        f"RTL file set mismatch: {sorted(actual_rtl)}")

for path in ROOT.rglob("*"):
    relative = path.relative_to(ROOT)
    lower_parts = {part.lower() for part in relative.parts}
    if path.name in FORBIDDEN_FILES:
        checks["PUBLIC_FILE_SET"].append(f"forbidden file {rel(path)}")
    if lower_parts & FORBIDDEN_DIRS:
        checks["PUBLIC_FILE_SET"].append(f"forbidden directory {rel(path)}")
    if path.is_file() and path.suffix.lower() in GENERATED_SUFFIXES:
        checks["PUBLIC_FILE_SET"].append(f"generated artifact {rel(path)}")
    if path.is_file() and path.suffix.lower() in {".pdf", ".ppt", ".pptx", ".doc", ".docx"}:
        checks["PUBLIC_FILE_SET"].append(f"document artifact {rel(path)}")

absolute_path = re.compile(r"(?<![A-Za-z0-9_])[A-Za-z]:[\\/]")
for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
        continue
    source = read(path)
    lower_source = source.lower()
    for term in SENSITIVE_TERMS:
        blocked = (term in source if term == SENSITIVE_TERMS[-1]
                   else re.search(rf"\b{re.escape(term.lower())}\b",
                                  lower_source) is not None)
        if blocked:
            checks["PUBLIC_NAME_AUDIT"].append(
                f"{rel(path)} contains blocked term {term}")
    if absolute_path.search(source):
        checks["PUBLIC_PATH_AUDIT"].append(
            f"absolute Windows path in {rel(path)}")

for filename, module in RTL_MODULES.items():
    path = ROOT / "rtl" / filename
    if not path.is_file():
        continue
    source = strip_verilog_comments(read(path))
    declarations = re.findall(
        r"\bmodule\s+([A-Za-z_][A-Za-z0-9_]*)", source)
    if declarations != [module]:
        checks["PUBLIC_MODULE_AUDIT"].append(
            f"{filename}: declarations {declarations}, expected {module}")

all_rtl = "\n".join(
    strip_verilog_comments(read(path))
    for path in (ROOT / "rtl").glob("*.v"))
for instance in re.findall(
        r"^\s*(sr_[A-Za-z0-9_]+)\s*#\s*\(", all_rtl,
        flags=re.MULTILINE):
    if instance not in set(RTL_MODULES.values()):
        checks["PUBLIC_MODULE_AUDIT"].append(
            f"unknown RTL instance {instance}")

for path in (ROOT / "tb").glob("*.v"):
    if "ft" + "lpu_sr_" in read(path).lower():
        checks["PUBLIC_MODULE_AUDIT"].append(
            f"stale module reference in {rel(path)}")

link_pattern = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
for path in [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]:
    if not path.is_file():
        continue
    for target in link_pattern.findall(read(path)):
        target = target.strip().split("#", 1)[0]
        if not target or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
            continue
        if not (path.parent / target).resolve().exists():
            checks["PUBLIC_LINK_AUDIT"].append(
                f"broken link {target} in {rel(path)}")

ignore_file = ROOT / ".gitignore"
if ignore_file.is_file():
    ignore_text = read(ignore_file)
    for pattern in ("*.vvp", "*.vcd", "*.exe", "*.obj", "*.log", "sim/", "build/"):
        if pattern not in ignore_text:
            checks["PUBLIC_FILE_SET"].append(
                f".gitignore missing {pattern}")

failed = False
for name, errors in checks.items():
    if errors:
        failed = True
        for error in errors:
            print(f"ERROR {name}: {error}")
        print(f"{name} FAIL")
    else:
        print(f"{name} PASS")

if failed:
    print("PUBLIC_RELEASE_AUDIT FAIL")
    sys.exit(1)

print("PUBLIC_RELEASE_AUDIT PASS")
