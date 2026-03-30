## Project Conventions (FPGA LLM Accelerator)

### Codebase Structure
- `rtl/` — Verilog RTL modules (snake_case names, e.g. `matmul_engine.v`)
- `tb/` — Direct RTL testbenches (`tb_*.v`)
- `verify/` — Python verification framework with golden models
- `verify/debug/` — Manual diagnostic/debugging scripts
- `verify/tb_cosim/` — Co-simulation testbenches (`tb_cosim_*.v`)
- `fpga/` — Vitis/Vivado deployment (Alveo U280, 150MHz, HBM)
- `scripts/` — Verilator configs, Vivado TCL
- `constraints/` — XDC timing constraints
- `tasks/` — Task tracking (`todo.md`, `lessons.md`, `summary.md`)

### Naming Conventions
- **Modules**: `snake_case` (e.g. `uram_prefetch_buf`, `matmul_engine`)
- **Ports**: `snake_case` with directional suffixes (e.g. `a_valid`, `b_data`)
- **States**: `UPPER_SNAKE` with prefix (e.g. `S_IDLE`, `ST_TILE_START`, `PF_IDLE`)
- **Parameters**: `UPPER_SNAKE` (e.g. `DATA_WIDTH`, `MODEL_DIM`)
- **Testbenches**: `tb_<module>.v` or `tb_cosim_<module>.v`
- **Headers**: `.vh` files in `rtl/` (`defines.vh`, `fp_funcs.vh`)

### Build System
- **Simulator**: Verilator (`make sim`, `make test-small`, `make test-1k`, `make test-decode`)
- **Linter**: Verilator lint (`make lint`, `make lint-all`)
- **Synthesis**: Yosys (`make synth`), Vivado (`fpga/build.tcl`)
- **Co-simulation**: `make cosim-*` (Python golden + HDL)
- **FPGA build**: `fpga/Makefile` (Vitis v++ flow)

### Hardware Details
- **Target**: Xilinx Alveo U280 (xcvu47p, HBM2)
- **Datapath**: FP16 input → FP32 accumulation → FP16 output
- **Architecture**: HBM → URAM prefetch → 32×32 MatMul Engine → Non-matmul units → HBM
- **Memory**: URAM for on-chip buffering, 32 HBM channels (10 used)

---

## RTL-Specific Rules

### Verification Standard
- Ask yourself: "Would a senior hardware engineer approve this?"
- Run testbenches, check simulation logs, demonstrate correctness

### Bug Fixing & Debugging
- **Waveform Protocol:** You cannot see waveforms. If text outputs are insufficient to find the root cause, DO NOT guess wildly or write speculative fixes.
- When confused or stuck, you must ask the user to inspect the waveform.
- **Hypothesis First:** Before asking the user to check the waveform, you MUST state:
  1. Your current thoughts on what is going wrong.
  2. The specific modules, signals, registers, or state machines you suspect contain the bug.
- Tell the user exactly what behavior or signal transitions to look for in the waveform viewer.

### The Architecture Summary (`summary.md`)
- Maintain a high-level `tasks/summary.md` file that acts as a map of the repository.
- **Never re-read files just to check interfaces.** Check `summary.md` first.
- The summary MUST include: module names, descriptions of their purpose, parameters, and input/output port definitions.
- Keep implementation details OUT of the summary. It is for architectural and interface reference only.
- **Strict Update Rule:** If you modify a module's ports, add a new parameter, or create a new file, you MUST update `summary.md` immediately before marking the task complete.
