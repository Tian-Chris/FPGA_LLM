// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table implementation internals

#include "Vtb_uram_accum_buf__pch.h"
#include "Vtb_uram_accum_buf.h"
#include "Vtb_uram_accum_buf___024root.h"
#include "Vtb_uram_accum_buf___024unit.h"

// FUNCTIONS
Vtb_uram_accum_buf__Syms::~Vtb_uram_accum_buf__Syms()
{
}

Vtb_uram_accum_buf__Syms::Vtb_uram_accum_buf__Syms(VerilatedContext* contextp, const char* namep, Vtb_uram_accum_buf* modelp)
    : VerilatedSyms{contextp}
    // Setup internal state of the Syms class
    , __Vm_modelp{modelp}
    // Setup module instances
    , TOP{this, namep}
{
    // Check resources
    Verilated::stackCheck(1590);
    // Configure time unit / time precision
    _vm_contextp__->timeunit(-12);
    _vm_contextp__->timeprecision(-12);
    // Setup each module's pointers to their submodules
    // Setup each module's pointer back to symbol table (for public functions)
    TOP.__Vconfigure(true);
}
