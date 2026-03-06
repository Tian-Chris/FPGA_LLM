--timing

// Strict Warnings
-Wall

// Don't exit on warnings
-Wno-fatal

// Parallelized
-j 0

// Enables sv asserts
--assert

// Xs are zero (fast init for small design)
--x-assign 0

// all variables zero-initialized
--x-initial 0

// SIM_SMALL define
-DSIM_SMALL

// Include path for defines.vh
+incdir+rtl
