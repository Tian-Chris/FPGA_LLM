// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_uram_accum_buf.h for the primary calling header

#include "Vtb_uram_accum_buf__pch.h"

void Vtb_uram_accum_buf___024root___ctor_var_reset(Vtb_uram_accum_buf___024root* vlSelf);

Vtb_uram_accum_buf___024root::Vtb_uram_accum_buf___024root(Vtb_uram_accum_buf__Syms* symsp, const char* v__name)
    : VerilatedModule{v__name}
    , __VdlySched{*symsp->_vm_contextp__}
    , vlSymsp{symsp}
 {
    // Reset structure values
    Vtb_uram_accum_buf___024root___ctor_var_reset(this);
}

void Vtb_uram_accum_buf___024root::__Vconfigure(bool first) {
    (void)first;  // Prevent unused variable warning
}

Vtb_uram_accum_buf___024root::~Vtb_uram_accum_buf___024root() {
}
