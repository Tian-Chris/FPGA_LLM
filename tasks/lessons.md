# Lessons Learned

## 1. Always Update summary.md After Changes
After modifying any module's ports, parameters, or creating a new file, update `tasks/summary.md` IMMEDIATELY before moving on. Never mark a task complete without the summary reflecting the current state. This is the architectural map — if it's stale, future work builds on wrong assumptions.

## 2. Always Update todo.md After Completing Plan Steps
Mark items in `tasks/todo.md` as done (or "written but not verified") as soon as each step finishes. Track the exact current step so a new chat session can resume without re-reading the entire codebase. Distinguish between "code written" and "code verified" — they are not the same.

## 3. Write Latency-Resilient Modules — Never Hardcode Pipeline Depth
When one module depends on another's output timing (e.g., waiting for a MAC pipeline to drain), use dynamic guard signals (`!busy`, `!enable`, drain conditions) instead of counting a fixed number of cycles. This way, if a module's internal latency changes (e.g., adding an input register stage to a MAC for timing closure), nothing downstream breaks. The matmul_engine's output serialization correctly uses `!b_compute_r && !mac_enable` to detect pipeline drain rather than a hardcoded cycle count — this survived the MAC going from 2 to 3 stages with only a tile_done delay adjustment.

## 4. Freeze Shared Registers Before Pipeline Consumers
When a register (e.g., `b_reg`) is shared between a loading path and a combinational broadcast path, and the pipeline adds latency between loading and consumption, the register WILL be overwritten by the next data before the consumer reads it. Solution: add a `b_frozen` buffer that captures `b_reg` at the right pipeline stage and use THAT for the broadcast. Key timing: the frozen latch must fire 1 cycle after data is complete (when the NBA update has settled but before the next data overwrites). In the matmul_engine, `b_frozen` latches on `b_row_complete` (not `b_compute_r` which is 1 cycle later and too late).

## 5. NBA Timing for Index Counters vs Enable Signals
When a counter (e.g., `b_k_cnt`) and an enable signal (e.g., `mac_enable`) are both driven from the same source (e.g., `b_compute_r`), they update via NBA at the same time. If the counter feeds a combinational path read by the consumer on the enable edge, the counter value is WRONG (already advanced). Fix: drive the counter from the NEXT pipeline stage (e.g., `mac_enable` instead of `b_compute_r`) so it advances 1 cycle later, keeping the correct value when the consumer reads.

## 6. Softmax/LayerNorm Use 8-bit Output — Don't Pass DATA_WIDTH
The softmax and layernorm modules have internal LUTs tuned for 8-bit output (OUT_W=8, PARAM_W=8). When the global DATA_WIDTH was changed from 8 to 16, the top_level.v incorrectly passed DATA_WIDTH for their OUT_W/PARAM_W parameters. Always hardcode these to 8 in the instantiation — they are module-specific, not system-wide.

## 7. Per-Row vs Whole-Matrix Processing in Non-Matmul Units
Softmax and LayerNorm are inherently per-row operations — they process one row of `dim` elements independently. If there are BT rows, the FSM must loop BT times with a row counter (`nm_row_cnt`) and address offset (`nm_addr_offset = nm_row_cnt * row_dim`). In contrast, activation (ReLU) and residual_add process ALL `bt*dim` elements at once — no row loop needed. When adding new non-matmul stages, determine upfront whether it needs per-row looping.

## 8. Integer Division Underflow in Verilog
`seq_r / WE` (e.g. 32 / 16 = 2) works fine, but if `seq_r < WE` the result is 0. This caused silent misconfiguration of flush parameters. Use ceiling division: `wire [W-1:0] seq_div_WE = (seq_r + WE - 1) / WE;` whenever the result feeds a count-1 parameter.

## 9. URAM NM Adapter Write Buffer Seeding
When the adapter starts a new write buffer word, it must seed the buffer from the read cache (if available) rather than zeros. Otherwise, writes to elements 0-14 clobber elements already in the URAM word with zeros. The write buffer only modifies the specific element being written; the rest must reflect current URAM contents.

## 10. One-Shot Signals Need Guard Flags When Default-Cleared
When a one-shot signal (e.g., `uram_flush_start`) is default-cleared at the top of an always block and re-asserted conditionally (`if (!signal && !done)`), it oscillates every cycle: the default clears it, then the condition re-fires it. If the consumer returns to IDLE while the signal is high (from the oscillation), it re-triggers. Fix: use a `_sent` guard flag that's set when the pulse fires and cleared only when the consumer signals done. The condition becomes `if (!guard && !done)` — the guard stays high regardless of the one-shot's cycle-to-cycle behavior. This bug caused ghost flushes that corrupted URAM reads via shared port contention.

## 12. Vivado RAM Inference Requires Strict Port Templates
Vivado can only infer BRAM/URAM from code matching specific templates: one `always` block for write, one for read (simple dual-port). Multiple `always` blocks writing to the same `reg` array = unsupported template → synthesis failure. The `for` loop expanding N_ENG engine writes is also problematic — Vivado sees N write ports, not 1. **Verilator doesn't catch this** (it's a simulator, not synthesizer). **Yosys didn't catch it** because uram_accum_buf was excluded (too large). Always validate multi-writer RAM designs against Vivado's UG901 RAM inference templates before the first real build. For multi-port writes, use either column banking (if bank count fits URAM budget) or write serialization with backpressure.

## 13. Backpressure Requires Valid-Hold, Not Valid-Pulse
When adding backpressure (stall) to a producer→consumer pipeline, the producer must **hold** its `out_valid` high during stalls, not default it to 0. A 1-cycle `out_valid` pulse combined with registered stall feedback creates a pipeline bubble: the producer advances counters and packs new data on cycle N (stall not yet visible), then on cycle N+1 the stall kicks in but the previous beat is already gone from the registered output. Fix: remove `out_valid <= 0` default; only clear `out_valid` when the consumer has accepted (not stalled). The producer holds `out_valid`, `out_data`, and `out_row` stable until `!out_stall`. This is the standard valid/ready handshake — valid stays high until ready. The 1-cycle round-trip delay in `wr_pending → arbiter → uram_wr_accept → mm_out_stall → out_stall` means the producer always has one beat "in flight" that must be held, not dropped.

## 14. BRAM Internal Read Latency Must Align with External Memory Latency
When converting a combinational register-array read (`input_buffer[idx]`) to an internal BRAM read, the BRAM adds 1 cycle of read latency: set `bram_rd_addr` at cycle N → `bram_rd_data` available at cycle N+2 (BRAM block reads at N+1, NBA settles by N+2). If a second data source (e.g., external param memory) is issued simultaneously, the two only arrive aligned if the external memory also has >= 1 cycle latency. **0-cycle (combinational) external reads misalign by 1 cycle.** Fix: update cosim testbenches to use 1-cycle registered reads (matching real hardware: URAM adapter, act_dma). Never assume the old 0-cycle TB convention still applies after adding internal BRAMs.

## 15. RTL SIM_SMALL Defines Must Match Python Test Parameters
The `defines.vh` SIM_SMALL parameters (MODEL_DIM, F_DIM, MAX_SEQ_LEN, URAM_ROWS, URAM_COLS) must exactly match the Python test generator (`verify/test_top.py`). A mismatch causes the Python to generate HBM data for one model size while the RTL processes it as another, producing silent corruption (near-zero results). The RTL had MODEL_DIM=32 while Python used MODEL_DIM=64 — the URAM was 4 rows × 2 col_words (8 entries total) while the test expected 32 rows × 8 col_words (256 entries). After fixing, all tests pass. **Always verify Python params vs RTL defines when debugging integration test failures.**

## 16. Count Fields Need Wider Widths Than Address Fields
Address widths ($clog2(N)) can represent values 0..N-1, but COUNT values of N require $clog2(N)+1 bits. For PREFETCH buffers with 32 rows, PF_ROW_W=$clog2(32)=5 can hold 0..31, but the count value 32 requires 6 bits. Fix: use a wider DIM_W (16-bit) for all count fields in prefetch commands and internal counters, and only truncate to address width when indexing into memory.

## 17. Check DIM_W Overflow When Multiplying Dimensions
When computing `bt * F_DIM` or similar products for element counts, verify the result fits in the register width. `bt=32 * F_DIM=4096 = 131072` overflows 16-bit (DIM_W=16), silently becoming 0 and causing the processing unit to skip all elements. Fix: either widen the dimension port or process row-by-row (like S_LN_RUN does for layernorm), keeping per-invocation element counts within 16-bit range. The nm_adapter's SCALAR_AW must also be wide enough — widened to NM_ADDR_W=20 to support large row offsets.

## 18. Always Add nm_addr_offset to ALL Non-Matmul Unit Addresses
When a non-matmul unit (softmax, layernorm, activation, residual_add) accesses URAM through the nm_adapter, its flat address must include fsm_nm_addr_offset for correct URAM row mapping. Missing the offset means the unit reads/writes to URAM row 0 instead of the intended row. The top_level mux must apply the offset to ALL unit addresses, not just softmax and layernorm.

## 19. Last-Beat Loss on Stalled Output Serialization
When an engine output serializer unconditionally clears `out_valid` after the last beat (`if (!outputting) out_valid <= 0`), the last beat can be LOST if the downstream write port is stalled at that exact cycle. With backpressure (e.g. URAM accumulation read-modify-write), the stall prevents the beat from being consumed, and the unconditional clear kills it permanently. Fix: gate the clear with the stall — `if (!outputting && !(out_valid && out_stall)) out_valid <= 0`. This holds `out_valid` during stall, and clears it the same cycle the beat is consumed (when stall lifts). No infinite re-issue occurs because `out_valid` goes to 0 one cycle after consumption. Symptom: every OTHER output tile has wrong data (column swap + wrong bias) because `wr_sub_col` drifts by 1 per lost beat.

## 11. Flush Mirror Must Include Zero-Valued Words
In simulation, flush/act/wgt HBMs are separate instances. The TB mirrors flush HBM to engine HBMs after each URAM→HBM flush. The mirror MUST copy zero-valued words too — not just non-zero ones. After ReLU, many URAM words are all zeros. If the mirror skips them, engine HBMs retain stale data from prior flushes. Fix: track the flush region parameters (base, stride, num_rows, num_col_words) on uram_flush_start, then mirror the exact region unconditionally on uf_done.
