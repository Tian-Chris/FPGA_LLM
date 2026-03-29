// Verilator flags for 1K test with STEP_DEBUG (per-step URAM flushes)
+incdir+rtl
-DSIM_1K
-DSTEP_DEBUG
--x-assign 0
--x-initial 0
-Wno-fatal
--timing
-j 0
