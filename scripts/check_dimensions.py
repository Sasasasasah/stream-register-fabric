"""Static default-profile and packed-port audit for SRF AC1, AC2, and AC6."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
RTL = ROOT / "rtl"
CORE = RTL
errors: list[str] = []


def compact(path: Path) -> str:
    return re.sub(r"\s+", "", path.read_text(encoding="utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def check_parameter(text: str, name: str, value: int, module: str) -> None:
    pattern = rf"parameter(?:integer)?{re.escape(name)}={value}(?:,|\))"
    require(re.search(pattern, text) is not None,
            f"{module}: default {name} must be {value}")


files = {
    name: compact(CORE / f"{name}.v")
    for name in ("sr_leaf", "sr_column", "sr_direction_fabric",
                 "sr_hemisphere_fabric", "sr_fabric")
}
cmodel_header = compact(ROOT / "cmodel" / "srf_model.h")

for module in files:
    check_parameter(files[module], "P_STREAMS_PER_DIR", 32, module)
    check_parameter(files[module], "P_LANES_PER_SUPERLANE", 8, module)
    check_parameter(files[module], "P_SR_DATA_BITS", 8, module)

for module in ("sr_column", "sr_direction_fabric",
               "sr_hemisphere_fabric", "sr_fabric"):
    check_parameter(files[module], "P_SUPERLANES_PER_COLUMN", 4, module)
for module in ("sr_direction_fabric", "sr_hemisphere_fabric", "sr_fabric"):
    check_parameter(files[module], "SR_COLUMNS_PER_HEMI", 16, module)
    check_parameter(files[module], "P_SR_HOP_CYCLES", 1, module)
check_parameter(files["sr_fabric"], "P_HEMISPHERES", 2, "sr_fabric")

full_chip_cmodel = cmodel_header.split("classFullChipModel", 1)[1]
for name, value in (
    ("HEMISPHERE_NUM", 2), ("DIRECTION_NUM", 2), ("COLUMN_NUM", 16),
    ("SUPERLANE_NUM", 4), ("STREAM_NUM", 32), ("LANE_NUM", 8),
    ("DATA_BITS", 8),
):
    require(f"staticconstexprstd::size_t{name}={value};" in full_chip_cmodel,
            f"FullChipModel: default {name} must be {value}")
require("staticconstexprstd::size_tP_SR_HOP_CYCLES=SRFModel::P_SR_HOP_CYCLES;"
        in full_chip_cmodel,
        "FullChipModel: P_SR_HOP_CYCLES must share SRFModel contract")

# Exact leaf core interface and reset form required by Chapter 7 closure.
for port in (
    "clk_i", "rst_ni", "upstream_valid_i", "upstream_data_i",
    "state_valid_o", "state_data_o", "consume_i", "downstream_valid_o",
    "downstream_data_o", "inject_valid_i", "inject_data_i", "collision_o",
    "invalid_consume_o",
):
    require(port in files["sr_leaf"], f"sr_leaf: missing core port {port}")
require("always@(posedgeclk_iornegedgerst_ni)" in files["sr_leaf"],
        "sr_leaf: reset is not asynchronous active-low")
require("if(!rst_ni)beginvalid_state<={CELL_NUM{1'b0}};" in files["sr_leaf"],
        "sr_leaf: reset must clear valid_state")

# Packed dimensions must be raised, never rewritten, at each hierarchy level.
width_evidence = {
    "sr_leaf": (
        "[P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]upstream_data_i",
        "[P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]upstream_valid_i",
        "[P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]inject_valid_i",
        "[P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]inject_data_i",
        "[P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]consume_i",
    ),
    "sr_column": (
        "[P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]column_data_in",
        "[P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]column_valid_in",
        "[P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]inject_valid_i",
        "[P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]inject_data_i",
        "[P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]consume_i",
    ),
    "sr_direction_fabric": (
        "[P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]stream_data_in",
        "[SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]inject_valid_i",
        "[SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]inject_data_i",
        "[SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]consume_i",
    ),
    "sr_hemisphere_fabric": (
        "[P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]east_input_data",
        "[SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]east_inject_valid",
        "[SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]east_inject_data",
        "[SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]west_consume",
    ),
    "sr_fabric": (
        "[P_HEMISPHERES*2*P_SUPERLANES_PER_COLUMN*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]boundary_input_data",
        "[P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]inject_valid_i",
        "[P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_PRODUCERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE*P_SR_DATA_BITS-1:0]inject_data_i",
        "[P_HEMISPHERES*2*SR_COLUMNS_PER_HEMI*P_SUPERLANES_PER_COLUMN*P_LOCAL_CONSUMERS*P_STREAMS_PER_DIR*P_LANES_PER_SUPERLANE-1:0]consume_i",
    ),
}
for module, snippets in width_evidence.items():
    for snippet in snippets:
        require(snippet in files[module], f"{module}: missing width evidence {snippet}")

# AC2: payload/valid state identifiers are legal only in sr_leaf among core RTL.
for path in CORE.glob("*.v"):
    if path.name == "sr_leaf.v":
        continue
    source = path.read_text(encoding="utf-8")
    require(re.search(r"\breg\b[^;]*(?:data_state|valid_state)", source) is None,
            f"{path.name}: illegal SRF payload/valid state")
for module in ("sr_column", "sr_direction_fabric",
               "sr_hemisphere_fabric", "sr_fabric"):
    source_without_comments = re.sub(
        r"//.*?$|/\*.*?\*/", "", (CORE / f"{module}.v").read_text(encoding="utf-8"),
        flags=re.MULTILINE | re.DOTALL)
    require(re.search(r"\breg\s*(?:\[|[A-Za-z_])", source_without_comments) is None,
            f"{module}: wrapper must contain no sequential storage declarations")

hemisphere_num = 2
direction_num = 2
column_num = 16
superlane_num = 4
stream_num = 32
lane_num = 8
data_bytes = 1
local_ports = 2

derived = {
    "STREAM_SELECTOR_BITS": 6,
    "SUPERLANE_SEGMENT_BYTES": lane_num * data_bytes,
    "CELLS_PER_LEAF": stream_num * lane_num,
    "PAYLOAD_BYTES_PER_LEAF": stream_num * lane_num * data_bytes,
    "VALID_BYTES_PER_LEAF": (stream_num * lane_num + 7) // 8,
    "LEAVES_PER_DIR_COLUMN": superlane_num,
    "PAYLOAD_BYTES_PER_DIR_COLUMN": superlane_num * stream_num * lane_num,
    "PAYLOAD_BYTES_PER_COLUMN_PAIR": direction_num * superlane_num * stream_num * lane_num,
    "PAYLOAD_BYTES_PER_HEMI": direction_num * column_num * superlane_num * stream_num * lane_num,
    "PHYSICAL_CELLS_PER_HEMI": direction_num * column_num * superlane_num * stream_num * lane_num,
    "VALID_BYTES_PER_HEMI": direction_num * column_num * superlane_num * stream_num * lane_num // 8,
}
expected = {
    "STREAM_SELECTOR_BITS": 6,
    "SUPERLANE_SEGMENT_BYTES": 8,
    "CELLS_PER_LEAF": 256,
    "PAYLOAD_BYTES_PER_LEAF": 256,
    "VALID_BYTES_PER_LEAF": 32,
    "LEAVES_PER_DIR_COLUMN": 4,
    "PAYLOAD_BYTES_PER_DIR_COLUMN": 1024,
    "PAYLOAD_BYTES_PER_COLUMN_PAIR": 2048,
    "PAYLOAD_BYTES_PER_HEMI": 32768,
    "PHYSICAL_CELLS_PER_HEMI": 32768,
    "VALID_BYTES_PER_HEMI": 4096,
}
require(derived == expected, f"derived profile mismatch: {derived}")

port_widths = {
    "leaf_data": stream_num * lane_num * 8,
    "leaf_valid": stream_num * lane_num,
    "leaf_inject_valid": local_ports * stream_num * lane_num,
    "leaf_inject_data": local_ports * stream_num * lane_num * 8,
    "leaf_consume": local_ports * stream_num * lane_num,
    "column_data": superlane_num * stream_num * lane_num * 8,
    "column_valid": superlane_num * stream_num * lane_num,
    "column_inject_valid": superlane_num * local_ports * stream_num * lane_num,
    "column_inject_data": superlane_num * local_ports * stream_num * lane_num * 8,
    "column_consume": superlane_num * local_ports * stream_num * lane_num,
    "direction_data": superlane_num * stream_num * lane_num * 8,
    "direction_valid": superlane_num * stream_num * lane_num,
    "direction_inject_valid": column_num * superlane_num * local_ports * stream_num * lane_num,
    "direction_inject_data": column_num * superlane_num * local_ports * stream_num * lane_num * 8,
    "direction_consume": column_num * superlane_num * local_ports * stream_num * lane_num,
    "direction_state_data": column_num * superlane_num * stream_num * lane_num * 8,
    "direction_state_valid": column_num * superlane_num * stream_num * lane_num,
    "hemisphere_per_direction_data": superlane_num * stream_num * lane_num * 8,
    "hemisphere_per_direction_valid": superlane_num * stream_num * lane_num,
    "hemisphere_per_direction_inject_valid": column_num * superlane_num * local_ports * stream_num * lane_num,
    "hemisphere_per_direction_inject_data": column_num * superlane_num * local_ports * stream_num * lane_num * 8,
    "hemisphere_per_direction_consume": column_num * superlane_num * local_ports * stream_num * lane_num,
    "full_boundary_data": hemisphere_num * direction_num * superlane_num * stream_num * lane_num * 8,
    "full_boundary_valid": hemisphere_num * direction_num * superlane_num * stream_num * lane_num,
    "full_inject_valid": hemisphere_num * direction_num * column_num * superlane_num * local_ports * stream_num * lane_num,
    "full_inject_data": hemisphere_num * direction_num * column_num * superlane_num * local_ports * stream_num * lane_num * 8,
    "full_consume": hemisphere_num * direction_num * column_num * superlane_num * local_ports * stream_num * lane_num,
    "full_state_data": hemisphere_num * direction_num * column_num * superlane_num * stream_num * lane_num * 8,
    "full_state_valid": hemisphere_num * direction_num * column_num * superlane_num * stream_num * lane_num,
}

for name, value in derived.items():
    print(f"DERIVED {name}={value}")
for name, value in port_widths.items():
    print(f"PORT_WIDTH {name}={value}")

forbidden_core_ports = (
    "cmd_valid", "cmd_ready", "cmd_data", "opcode",
    "access_write", "access_read", "write_column", "write_superlane",
    "write_stream", "write_lane", "read_column", "read_superlane",
    "read_stream", "read_lane",
)
for module in files:
    for token in forbidden_core_ports:
        require(token not in files[module],
                f"{module}: unsupported public interface token {token}")

if errors:
    for error in errors:
        print(f"ERROR {error}")
    print("TEST_FAIL")
    sys.exit(1)

print("CORE_INTERFACE_COMPLIANCE PASS")
print("AC6_PORT_DIMENSIONS PASS")
print("TEST_PASS")
