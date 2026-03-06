// Verilator flags for production 1024x1024 full pipeline test
// Uses SIM_1K: production dimensions (MODEL_DIM=1024) but single layer

// Include path for defines.vh
+incdir+rtl

// SIM_1K define: production dims, NUM_ENC_LAYERS=1
-DSIM_1K

// Xs are zero (fast init for large HBM arrays)
--x-assign 0

// all variables zero-initialized (critical for 1M-depth HBMs)
--x-initial 0

// Don't exit on warnings
-Wno-fatal

// Timing support (needed for #delay in testbench)
--timing

// Parallel compilation (use all cores)
-j 0
