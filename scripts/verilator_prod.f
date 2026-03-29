// Verilator flags for production (no SIM_SMALL, no trace)

// Include path for defines.vh
+incdir+rtl

// Xs are zero (fast init for large HBM arrays)
--x-assign 0

// all variables zero-initialized (critical for 262144-depth HBMs)
--x-initial 0

// Don't exit on warnings
-Wno-fatal

// Timing support (needed for #delay in testbenches)
--timing
