# Stream Register Fabric

A parameterized Stream Register Fabric implementation with Verilog RTL and a cycle-accurate C++ reference model.

## 项目简介 Project Overview

这是一个个人 RTL / CModel engineering practice project，用于探索固定延迟 streaming register fabric 的 hierarchy 组织、state ownership、cycle semantics，以及 RTL/CModel consistency 的验证流程。

项目关注数据如何在预先确定的 register pipeline 中按 cycle 推进：`data` 与 `valid` 同步传播，local `inject` 和 `consume` 作为 leaf cell 的控制语义参与状态更新。项目以可读的 RTL、reference model 和 self-checking testbench 为主，方便理解设计和验证之间的对应关系。

## 功能特性 Features

- Parameterized Verilog RTL hierarchy
- Fixed-latency East / West directional propagation
- Per-cell `data` / `valid` state ownership
- Local `inject` / `consume` semantics
- Collision and invalid-consume detection
- Bubble propagation using `valid=0`
- Cycle-accurate C++ CModel with `step()`
- RTL/CModel trace comparison with `TRACE_MATCH`
- Automated regression scripts and self-checking testbench output

## 架构 Architecture

```text
sr_fabric
`-- sr_hemisphere_fabric
    `-- sr_direction_fabric
        `-- sr_column
            `-- sr_leaf
```

`sr_leaf` 是唯一保存 per-cell `data` / `valid` state 的模块。`sr_column` 负责组织多个 leaf，并保持为 state-free wrapper。`sr_direction_fabric` 把 column 连接为固定方向的 pipeline；`sr_hemisphere_fabric` 组合独立的 directional fabric；`sr_fabric` 作为 top-level wrapper 提供完整 hierarchy。

默认配置使用两个 hemisphere、每个方向 16 个 column、每个 column 4 个 superlane、每个 superlane 32 个 stream 和 8 个 lane。更多结构说明见 [Architecture Notes](docs/architecture.md)。

## 数据与周期语义 Data & Cycle Semantics

- 数据按 clock cycle 在相邻 column 之间推进，每个 registered hop 引入固定 latency。
- `valid` 与 `data` 始终同步传播；bubble 通过 `valid=0` 表示并保持其 pipeline 位置。
- `consume` 会影响当前 cell 对 downstream 的可见性，避免被消费的数据继续被动传播。
- `inject` 提供新的 local producer candidate，与 upstream propagation 一起参与 next-state 选择。
- 当多个 producer 同时写入同一 cell 时，模块报告 `collision`。

The current implementation uses a deterministic collision resolution policy as an implementation choice. `collision` status remains visible, so a resolved value is not treated as conflict-free data.

## 仓库结构 Repository Structure

```text
stream_register_fabric_personal/
├── rtl/        Verilog RTL modules
├── cmodel/     cycle-accurate C++ reference model
├── tb/         self-checking RTL testbench collection
├── scripts/    build, regression, trace comparison, and static-check scripts
├── docs/       architecture and verification notes
├── .gitignore  generated artifact ignore rules
└── README.md    project overview and usage guide
```

## RTL 模块 RTL Modules

| Module | Responsibility |
|---|---|
| `sr_leaf` | Stores per-cell state and handles propagation, `inject`, `consume`, and collision reporting. |
| `sr_column` | Instantiates multiple leaf modules without adding state. |
| `sr_direction_fabric` | Connects columns into a fixed Eastward or Westward pipeline. |
| `sr_hemisphere_fabric` | Groups independent directional fabric instances. |
| `sr_fabric` | Provides the top-level multi-path wrapper. |

## CModel

`cmodel/srf_model.h` and `cmodel/srf_model.cpp` provide a cycle-accurate behavioral reference model. Each `step()` corresponds to one hardware cycle and advances the modeled fabric state.

该 CModel 用于对照 RTL behavior、生成 trace，并支持 RTL/CModel comparison；它不是完整的 processor 或 accelerator simulator。相关测试入口位于 `cmodel/test_cmodel.cpp`。

## Verification

当前 testbench 覆盖 reset semantics、leaf behavior、column behavior、East / West directional propagation、hemisphere/full-fabric behavior、continuous saturation、hop timing 和 RTL/CModel trace comparison。

测试采用 self-checking 方式，正常完成时输出：

```text
TEST_PASS
```

RTL 与 CModel 的 trace comparison 在一致时输出 `TRACE_MATCH`。Waveform 不会提交到仓库；本地调试可按需启用 VCD dump，生成的 `*.vcd`、`*.vvp`、logs 与 `sim/` 内容由 `.gitignore` 排除。更多信息见 [Verification Notes](docs/verification.md)。

## 构建与运行 Build & Run

Windows 环境下可使用 Icarus Verilog（`iverilog` / `vvp`）、Python 和 C++17 compiler。所有命令均从 repository root 执行，使用相对路径：

```bat
scripts\run_compile.bat
scripts\run_regression.bat
```

完成 trace generation 后，可执行：

```bat
python scripts\compare_rtl_cmodel.py
```

公开前的静态检查入口为：

```bat
python scripts\check_public_release.py
```

## 当前状态 Current Status

- RTL hierarchy 已完成并保留 parameterized configuration。
- Cycle-accurate CModel 已提供 `step()`、state update 和 trace 支持。
- Self-checking testbench 与 regression scripts 已包含在仓库中。
- RTL/CModel trace comparison 工具已提供，用于检查 cycle-level consistency。

这些状态描述当前仓库已有的工程内容，不表示量产、signoff 或完整系统实现状态。

## 项目定位 Project Positioning

这个项目主要用于练习和理解以下工程主题：

- architecture decomposition 与 hierarchy organization
- state ownership 与 fixed-latency pipeline design
- cycle-accurate modeling
- RTL verification 与 self-checking testbench
- reference model comparison
- engineering repository organization

它定位为个人 RTL / CModel 实践项目，强调清晰的结构、可追踪的周期行为，以及设计与验证之间的对应关系。
