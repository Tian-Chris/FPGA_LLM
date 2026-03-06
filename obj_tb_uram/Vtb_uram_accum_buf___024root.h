// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vtb_uram_accum_buf.h for the primary calling header

#ifndef VERILATED_VTB_URAM_ACCUM_BUF___024ROOT_H_
#define VERILATED_VTB_URAM_ACCUM_BUF___024ROOT_H_  // guard

#include "verilated.h"
#include "verilated_timing.h"


class Vtb_uram_accum_buf__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vtb_uram_accum_buf___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    CData/*0:0*/ tb_uram_accum_buf__DOT__clk;
    CData/*0:0*/ tb_uram_accum_buf__DOT__rst_n;
    CData/*0:0*/ tb_uram_accum_buf__DOT__clear;
    CData/*5:0*/ tb_uram_accum_buf__DOT__eng_wr_en;
    CData/*5:0*/ tb_uram_accum_buf__DOT__eng_wr_accept;
    CData/*0:0*/ tb_uram_accum_buf__DOT__rd_en;
    CData/*5:0*/ tb_uram_accum_buf__DOT__rd_row;
    CData/*1:0*/ tb_uram_accum_buf__DOT__rd_col_word;
    CData/*0:0*/ tb_uram_accum_buf__DOT__dut__DOT__clearing;
    CData/*7:0*/ tb_uram_accum_buf__DOT__dut__DOT__clear_idx;
    CData/*2:0*/ tb_uram_accum_buf__DOT__dut__DOT__arb_ptr;
    CData/*0:0*/ tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux;
    CData/*7:0*/ tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux;
    CData/*0:0*/ tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found;
    CData/*2:0*/ tb_uram_accum_buf__DOT__dut__DOT__arb_winner;
    CData/*0:0*/ tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__clk__0;
    CData/*0:0*/ __Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__rst_n__0;
    SData/*11:0*/ tb_uram_accum_buf__DOT__eng_wr_col_word;
    VlWide<48>/*1535:0*/ tb_uram_accum_buf__DOT__eng_wr_data;
    IData/*31:0*/ tb_uram_accum_buf__DOT__errors;
    IData/*31:0*/ tb_uram_accum_buf__DOT__i;
    IData/*31:0*/ tb_uram_accum_buf__DOT__eng;
    IData/*31:0*/ tb_uram_accum_buf__DOT__row;
    IData/*31:0*/ tb_uram_accum_buf__DOT__col;
    VlWide<8>/*255:0*/ tb_uram_accum_buf__DOT__expected;
    IData/*31:0*/ tb_uram_accum_buf__DOT__make_pattern__Vstatic__k;
    VlWide<8>/*255:0*/ tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux;
    IData/*31:0*/ tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i;
    IData/*31:0*/ tb_uram_accum_buf__DOT__dut__DOT__e;
    IData/*31:0*/ tb_uram_accum_buf__DOT__dut__DOT__s;
    IData/*31:0*/ tb_uram_accum_buf__DOT__dut__DOT__init_i;
    IData/*31:0*/ __VactIterCount;
    QData/*35:0*/ tb_uram_accum_buf__DOT__eng_wr_row;
    VlUnpacked<VlWide<8>/*255:0*/, 256> tb_uram_accum_buf__DOT__dut__DOT__mem;
    VlUnpacked<CData/*2:0*/, 6> tb_uram_accum_buf__DOT__dut__DOT__pri_idx;
    VlUnpacked<VlWide<8>/*255:0*/, 1> tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data;
    VlUnpacked<CData/*0:0*/, 1> tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid;
    VlUnpacked<QData/*63:0*/, 1> __VstlTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VactTriggered;
    VlUnpacked<QData/*63:0*/, 1> __VnbaTriggered;
    VlUnpacked<CData/*0:0*/, 6> __Vm_traceActivity;
    VlDelayScheduler __VdlySched;
    VlTriggerScheduler __VtrigSched_h3248ee48__0;

    // INTERNAL VARIABLES
    Vtb_uram_accum_buf__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vtb_uram_accum_buf___024root(Vtb_uram_accum_buf__Syms* symsp, const char* v__name);
    ~Vtb_uram_accum_buf___024root();
    VL_UNCOPYABLE(Vtb_uram_accum_buf___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
