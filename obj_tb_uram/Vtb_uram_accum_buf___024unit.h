// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_uram_accum_buf.h for the primary calling header

#ifndef VERILATED_VTB_URAM_ACCUM_BUF___024UNIT_H_
#define VERILATED_VTB_URAM_ACCUM_BUF___024UNIT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vtb_uram_accum_buf__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_uram_accum_buf___024unit final : public VerilatedModule {
  public:

    // INTERNAL VARIABLES
    Vtb_uram_accum_buf__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtb_uram_accum_buf___024unit(Vtb_uram_accum_buf__Syms* symsp, const char* v__name);
    ~Vtb_uram_accum_buf___024unit();
    VL_UNCOPYABLE(Vtb_uram_accum_buf___024unit);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
