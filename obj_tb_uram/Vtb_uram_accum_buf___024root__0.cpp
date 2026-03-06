// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_uram_accum_buf.h for the primary calling header

#include "Vtb_uram_accum_buf__pch.h"

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_initial__TOP(Vtb_uram_accum_buf___024root* vlSelf);
VlCoroutine Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__0(Vtb_uram_accum_buf___024root* vlSelf);
VlCoroutine Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__1(Vtb_uram_accum_buf___024root* vlSelf);

void Vtb_uram_accum_buf___024root___eval_initial(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_initial\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    Vtb_uram_accum_buf___024root___eval_initial__TOP(vlSelf);
    vlSelfRef.__Vm_traceActivity[1U] = 1U;
    Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__0(vlSelf);
    Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__1(vlSelf);
}

extern const VlWide<48>/*1535:0*/ Vtb_uram_accum_buf__ConstPool__CONST_h22f5c49d_0;
extern const VlWide<8>/*255:0*/ Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0;

VlCoroutine Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__0(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__0\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ tb_uram_accum_buf__DOT__unnamedblk1_1__DOT____Vrepeat0;
    tb_uram_accum_buf__DOT__unnamedblk1_1__DOT____Vrepeat0 = 0;
    IData/*31:0*/ tb_uram_accum_buf__DOT__unnamedblk1_2__DOT____Vrepeat1;
    tb_uram_accum_buf__DOT__unnamedblk1_2__DOT____Vrepeat1 = 0;
    IData/*31:0*/ tb_uram_accum_buf__DOT__unnamedblk1_3__DOT____Vrepeat2;
    tb_uram_accum_buf__DOT__unnamedblk1_3__DOT____Vrepeat2 = 0;
    CData/*5:0*/ tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0;
    tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0 = 0;
    CData/*1:0*/ tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0;
    tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0 = 0;
    VlWide<8>/*255:0*/ tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0;
    VL_ZERO_W(256, tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0);
    IData/*31:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id;
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id = 0;
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_row;
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_col;
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_col = 0;
    VlWide<8>/*255:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val;
    VL_ZERO_W(256, __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val);
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout);
    IData/*31:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id;
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id = 0;
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_row;
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_col;
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_col = 0;
    VlWide<8>/*255:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val;
    VL_ZERO_W(256, __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val);
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout);
    IData/*31:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id;
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id = 0;
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_row;
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_col;
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_col = 0;
    VlWide<8>/*255:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val;
    VL_ZERO_W(256, __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val);
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout);
    IData/*31:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id;
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id = 0;
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_row;
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_col;
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_col = 0;
    VlWide<8>/*255:0*/ __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val;
    VL_ZERO_W(256, __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val);
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_col = 0;
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_col = 0;
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_col = 0;
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_col = 0;
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout);
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout);
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_col = 0;
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_col = 0;
    VlWide<8>/*255:0*/ __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout;
    VL_ZERO_W(256, __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout);
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_col = 0;
    CData/*5:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_row;
    __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_row = 0;
    CData/*1:0*/ __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_col;
    __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_col = 0;
    // Body
    VL_WRITEF_NX("=== tb_uram_accum_buf ===\n",0);
    vlSelfRef.tb_uram_accum_buf__DOT__errors = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__rst_n = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__clear = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 0ULL;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word = 0U;
    IData/*31:0*/ __Vilp1;
    __Vilp1 = 0U;
    while ((__Vilp1 <= 0x0000002fU)) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__Vilp1] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h22f5c49d_0[__Vilp1];
        __Vilp1 = ((IData)(1U) + __Vilp1);
    }
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = 0U;
    tb_uram_accum_buf__DOT__unnamedblk1_1__DOT____Vrepeat0 = 5U;
    while (VL_LTS_III(32, 0U, tb_uram_accum_buf__DOT__unnamedblk1_1__DOT____Vrepeat0)) {
        co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                             nullptr, 
                                                             "@(posedge tb_uram_accum_buf.clk)", 
                                                             "tb/tb_uram_accum_buf.v", 
                                                             130);
        vlSelfRef.__Vm_traceActivity[2U] = 1U;
        tb_uram_accum_buf__DOT__unnamedblk1_1__DOT____Vrepeat0 
            = (tb_uram_accum_buf__DOT__unnamedblk1_1__DOT____Vrepeat0 
               - (IData)(1U));
    }
    vlSelfRef.tb_uram_accum_buf__DOT__rst_n = 1U;
    tb_uram_accum_buf__DOT__unnamedblk1_2__DOT____Vrepeat1 = 2U;
    while (VL_LTS_III(32, 0U, tb_uram_accum_buf__DOT__unnamedblk1_2__DOT____Vrepeat1)) {
        co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                             nullptr, 
                                                             "@(posedge tb_uram_accum_buf.clk)", 
                                                             "tb/tb_uram_accum_buf.v", 
                                                             132);
        vlSelfRef.__Vm_traceActivity[2U] = 1U;
        tb_uram_accum_buf__DOT__unnamedblk1_2__DOT____Vrepeat1 
            = (tb_uram_accum_buf__DOT__unnamedblk1_2__DOT____Vrepeat1 
               - (IData)(1U));
    }
    VL_WRITEF_NX("Test 1: Multi-engine writes\n",0);
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[0U] 
        = (0x0064U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[0U] 
        = (0x00650000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[1U] 
        = (0x0066U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[1U] 
        = (0x00670000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[2U] 
        = (0x0068U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[2U] 
        = (0x00690000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[3U] 
        = (0x006aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[3U] 
        = (0x006b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[4U] 
        = (0x006cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[4U] 
        = (0x006d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[5U] 
        = (0x006eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[5U] 
        = (0x006f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[6U] 
        = (0x0070U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[6U] 
        = (0x00710000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[7U] 
        = (0x0072U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[7U] 
        = (0x00730000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[0U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[1U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[2U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[3U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[4U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[5U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[6U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__1__Vfuncout[7U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_row = 0U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = (0x0000003fU 
                                                   & VL_SHIFTL_III(6,32,32, (IData)(1U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id));
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 0ULL;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word = 0U;
    IData/*31:0*/ __Vilp2;
    __Vilp2 = 0U;
    while ((__Vilp2 <= 0x0000002fU)) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__Vilp2] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h22f5c49d_0[__Vilp2];
        __Vilp2 = ((IData)(1U) + __Vilp2);
    }
    tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_row;
    if (VL_LIKELY(((0x23U >= (0x0000003fU & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
            = (((~ (0x000000000000003fULL << (0x0000003fU 
                                              & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))) 
                & vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row) 
               | (0x0000000fffffffffULL & ((QData)((IData)(tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0)) 
                                           << (0x0000003fU 
                                               & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_col;
    if (VL_LIKELY(((0x0bU >= (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word 
            = (((~ ((IData)(3U) << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))) 
                & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word)) 
               | (0x0fffU & ((IData)(tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0) 
                             << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[0U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[0U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[1U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[1U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[2U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[2U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[3U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[3U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[4U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[4U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[5U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[5U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[6U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[6U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[7U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__0__wr_data_val[7U];
    if (VL_LIKELY(((0x05ffU >= (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)))))) {
        VL_ASSIGNSEL_WW(1536, 256, (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__0__eng_id)), vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data, tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0);
    }
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         87);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[0U] 
        = (0x00c8U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[0U] 
        = (0x00c90000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[1U] 
        = (0x00caU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[1U] 
        = (0x00cb0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[2U] 
        = (0x00ccU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[2U] 
        = (0x00cd0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[3U] 
        = (0x00ceU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[3U] 
        = (0x00cf0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[4U] 
        = (0x00d0U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[4U] 
        = (0x00d10000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[5U] 
        = (0x00d2U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[5U] 
        = (0x00d30000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[6U] 
        = (0x00d4U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[6U] 
        = (0x00d50000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[7U] 
        = (0x00d6U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[7U] 
        = (0x00d70000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[0U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[1U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[2U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[3U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[4U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[5U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[6U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__3__Vfuncout[7U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_col = 1U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_row = 0U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = (0x0000003fU 
                                                   & VL_SHIFTL_III(6,32,32, (IData)(1U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id));
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 0ULL;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word = 0U;
    IData/*31:0*/ __Vilp3;
    __Vilp3 = 0U;
    while ((__Vilp3 <= 0x0000002fU)) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__Vilp3] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h22f5c49d_0[__Vilp3];
        __Vilp3 = ((IData)(1U) + __Vilp3);
    }
    tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_row;
    if (VL_LIKELY(((0x23U >= (0x0000003fU & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
            = (((~ (0x000000000000003fULL << (0x0000003fU 
                                              & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))) 
                & vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row) 
               | (0x0000000fffffffffULL & ((QData)((IData)(tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0)) 
                                           << (0x0000003fU 
                                               & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_col;
    if (VL_LIKELY(((0x0bU >= (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word 
            = (((~ ((IData)(3U) << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))) 
                & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word)) 
               | (0x0fffU & ((IData)(tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0) 
                             << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[0U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[0U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[1U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[1U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[2U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[2U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[3U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[3U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[4U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[4U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[5U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[5U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[6U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[6U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[7U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__2__wr_data_val[7U];
    if (VL_LIKELY(((0x05ffU >= (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)))))) {
        VL_ASSIGNSEL_WW(1536, 256, (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__2__eng_id)), vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data, tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0);
    }
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         87);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[0U] 
        = (0x012cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[0U] 
        = (0x012d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[1U] 
        = (0x012eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[1U] 
        = (0x012f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[2U] 
        = (0x0130U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[2U] 
        = (0x01310000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[3U] 
        = (0x0132U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[3U] 
        = (0x01330000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[4U] 
        = (0x0134U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[4U] 
        = (0x01350000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[5U] 
        = (0x0136U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[5U] 
        = (0x01370000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[6U] 
        = (0x0138U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[6U] 
        = (0x01390000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[7U] 
        = (0x013aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[7U] 
        = (0x013b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[0U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[1U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[2U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[3U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[4U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[5U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[6U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__5__Vfuncout[7U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_row = 1U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id = 2U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = (0x0000003fU 
                                                   & VL_SHIFTL_III(6,32,32, (IData)(1U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id));
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 0ULL;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word = 0U;
    IData/*31:0*/ __Vilp4;
    __Vilp4 = 0U;
    while ((__Vilp4 <= 0x0000002fU)) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__Vilp4] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h22f5c49d_0[__Vilp4];
        __Vilp4 = ((IData)(1U) + __Vilp4);
    }
    tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_row;
    if (VL_LIKELY(((0x23U >= (0x0000003fU & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
            = (((~ (0x000000000000003fULL << (0x0000003fU 
                                              & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))) 
                & vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row) 
               | (0x0000000fffffffffULL & ((QData)((IData)(tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0)) 
                                           << (0x0000003fU 
                                               & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_col;
    if (VL_LIKELY(((0x0bU >= (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word 
            = (((~ ((IData)(3U) << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))) 
                & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word)) 
               | (0x0fffU & ((IData)(tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0) 
                             << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[0U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[0U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[1U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[1U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[2U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[2U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[3U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[3U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[4U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[4U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[5U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[5U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[6U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[6U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[7U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__4__wr_data_val[7U];
    if (VL_LIKELY(((0x05ffU >= (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)))))) {
        VL_ASSIGNSEL_WW(1536, 256, (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__4__eng_id)), vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data, tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0);
    }
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         87);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[0U] 
        = (0x0190U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[0U] 
        = (0x01910000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[1U] 
        = (0x0192U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[1U] 
        = (0x01930000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[2U] 
        = (0x0194U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[2U] 
        = (0x01950000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[3U] 
        = (0x0196U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[3U] 
        = (0x01970000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[4U] 
        = (0x0198U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[4U] 
        = (0x01990000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[5U] 
        = (0x019aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[5U] 
        = (0x019b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[6U] 
        = (0x019cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[6U] 
        = (0x019d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[7U] 
        = (0x019eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[7U] 
        = (0x019f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[0U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[1U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[2U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[3U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[4U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[5U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[6U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__7__Vfuncout[7U];
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_col = 1U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_row = 1U;
    __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id = 3U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = (0x0000003fU 
                                                   & VL_SHIFTL_III(6,32,32, (IData)(1U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id));
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 0ULL;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word = 0U;
    IData/*31:0*/ __Vilp5;
    __Vilp5 = 0U;
    while ((__Vilp5 <= 0x0000002fU)) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__Vilp5] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h22f5c49d_0[__Vilp5];
        __Vilp5 = ((IData)(1U) + __Vilp5);
    }
    tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_row;
    if (VL_LIKELY(((0x23U >= (0x0000003fU & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
            = (((~ (0x000000000000003fULL << (0x0000003fU 
                                              & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))) 
                & vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row) 
               | (0x0000000fffffffffULL & ((QData)((IData)(tb_uram_accum_buf__DOT____Vlvbound_had381ac9__0)) 
                                           << (0x0000003fU 
                                               & VL_MULS_III(32, (IData)(6U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_col;
    if (VL_LIKELY(((0x0bU >= (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))))) {
        vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word 
            = (((~ ((IData)(3U) << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))) 
                & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word)) 
               | (0x0fffU & ((IData)(tb_uram_accum_buf__DOT____Vlvbound_hffb1425d__0) 
                             << (0x0000000fU & VL_MULS_III(32, (IData)(2U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))));
    }
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[0U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[0U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[1U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[1U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[2U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[2U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[3U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[3U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[4U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[4U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[5U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[5U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[6U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[6U];
    tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0[7U] 
        = __Vtask_tb_uram_accum_buf__DOT__write_word__6__wr_data_val[7U];
    if (VL_LIKELY(((0x05ffU >= (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)))))) {
        VL_ASSIGNSEL_WW(1536, 256, (0x000007ffU & VL_MULS_III(32, (IData)(0x00000100U), __Vtask_tb_uram_accum_buf__DOT__write_word__6__eng_id)), vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data, tb_uram_accum_buf__DOT____Vlvbound_he794c22f__0);
    }
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         87);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_row = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__8__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[0U] 
        = (0x0064U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[0U] 
        = (0x00650000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[1U] 
        = (0x0066U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[1U] 
        = (0x00670000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[2U] 
        = (0x0068U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[2U] 
        = (0x00690000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[3U] 
        = (0x006aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[3U] 
        = (0x006b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[4U] 
        = (0x006cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[4U] 
        = (0x006d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[5U] 
        = (0x006eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[5U] 
        = (0x006f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[6U] 
        = (0x0070U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[6U] 
        = (0x00710000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[7U] 
        = (0x0072U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[7U] 
        = (0x00730000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__expected[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__9__Vfuncout[7U];
    if (VL_UNLIKELY(((0U != ((((((((vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[0U]) 
                                   | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                      [0U][1U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[1U])) 
                                  | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[2U])) 
                                 | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][3U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[3U])) 
                                | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[4U])) 
                               | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                  [0U][5U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[5U])) 
                              | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[6U])) 
                             | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U][7U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[7U])))))) {
        VL_WRITEF_NX("FAIL: row=0 col=0 got %x exp %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data(),256,vlSelfRef.tb_uram_accum_buf__DOT__expected.data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_col = 1U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_row = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__10__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[0U] 
        = (0x00c8U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[0U] 
        = (0x00c90000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[1U] 
        = (0x00caU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[1U] 
        = (0x00cb0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[2U] 
        = (0x00ccU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[2U] 
        = (0x00cd0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[3U] 
        = (0x00ceU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[3U] 
        = (0x00cf0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[4U] 
        = (0x00d0U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[4U] 
        = (0x00d10000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[5U] 
        = (0x00d2U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[5U] 
        = (0x00d30000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[6U] 
        = (0x00d4U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[6U] 
        = (0x00d50000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[7U] 
        = (0x00d6U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[7U] 
        = (0x00d70000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__expected[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__11__Vfuncout[7U];
    if (VL_UNLIKELY(((0U != ((((((((vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[0U]) 
                                   | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                      [0U][1U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[1U])) 
                                  | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[2U])) 
                                 | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][3U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[3U])) 
                                | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[4U])) 
                               | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                  [0U][5U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[5U])) 
                              | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[6U])) 
                             | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U][7U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[7U])))))) {
        VL_WRITEF_NX("FAIL: row=0 col=1 got %x exp %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data(),256,vlSelfRef.tb_uram_accum_buf__DOT__expected.data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_row = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__12__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[0U] 
        = (0x012cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[0U] 
        = (0x012d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[1U] 
        = (0x012eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[1U] 
        = (0x012f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[2U] 
        = (0x0130U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[2U] 
        = (0x01310000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[3U] 
        = (0x0132U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[3U] 
        = (0x01330000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[4U] 
        = (0x0134U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[4U] 
        = (0x01350000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[5U] 
        = (0x0136U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[5U] 
        = (0x01370000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[6U] 
        = (0x0138U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[6U] 
        = (0x01390000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[7U] 
        = (0x013aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[7U] 
        = (0x013b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__expected[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__13__Vfuncout[7U];
    if (VL_UNLIKELY(((0U != ((((((((vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[0U]) 
                                   | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                      [0U][1U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[1U])) 
                                  | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[2U])) 
                                 | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][3U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[3U])) 
                                | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[4U])) 
                               | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                  [0U][5U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[5U])) 
                              | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[6U])) 
                             | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U][7U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[7U])))))) {
        VL_WRITEF_NX("FAIL: row=1 col=0 got %x exp %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data(),256,vlSelfRef.tb_uram_accum_buf__DOT__expected.data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_col = 1U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_row = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__14__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[0U] 
        = (0x0190U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[0U] 
        = (0x01910000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[1U] 
        = (0x0192U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[1U] 
        = (0x01930000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[2U] 
        = (0x0194U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[2U] 
        = (0x01950000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[3U] 
        = (0x0196U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[3U] 
        = (0x01970000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[4U] 
        = (0x0198U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[4U] 
        = (0x01990000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[5U] 
        = (0x019aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[5U] 
        = (0x019b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[6U] 
        = (0x019cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[6U] 
        = (0x019d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[7U] 
        = (0x019eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[7U] 
        = (0x019f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__expected[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__15__Vfuncout[7U];
    if (VL_UNLIKELY(((0U != ((((((((vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[0U]) 
                                   | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                      [0U][1U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[1U])) 
                                  | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[2U])) 
                                 | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][3U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[3U])) 
                                | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[4U])) 
                               | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                  [0U][5U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[5U])) 
                              | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[6U])) 
                             | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U][7U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[7U])))))) {
        VL_WRITEF_NX("FAIL: row=1 col=1 got %x exp %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data(),256,vlSelfRef.tb_uram_accum_buf__DOT__expected.data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    VL_WRITEF_NX("Test 2: Simultaneous multi-engine write\n",0);
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 3U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 
        (5ULL | (0x0000000fffffffc0ULL & vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row));
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word 
        = (0x0ffcU & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word));
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[0U] 
        = (0x01f4U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[0U] 
        = (0x01f50000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[1U] 
        = (0x01f6U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[1U] 
        = (0x01f70000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[2U] 
        = (0x01f8U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[2U] 
        = (0x01f90000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[3U] 
        = (0x01faU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[3U] 
        = (0x01fb0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[4U] 
        = (0x01fcU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[4U] 
        = (0x01fd0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[5U] 
        = (0x01feU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[5U] 
        = (0x01ff0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[6U] 
        = (0x0200U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[6U] 
        = (0x02010000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[7U] 
        = (0x0202U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[7U] 
        = (0x02030000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__16__Vfuncout[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row = 
        (0x0000000000000140ULL | (0x0000000ffffff03fULL 
                                  & vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row));
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word 
        = (4U | (0x0ff3U & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word)));
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[0U] 
        = (0x0258U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[0U] 
        = (0x02590000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[1U] 
        = (0x025aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[1U] 
        = (0x025b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[2U] 
        = (0x025cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[2U] 
        = (0x025d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[3U] 
        = (0x025eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[3U] 
        = (0x025f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[4U] 
        = (0x0260U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[4U] 
        = (0x02610000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[5U] 
        = (0x0262U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[5U] 
        = (0x02630000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[6U] 
        = (0x0264U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[6U] 
        = (0x02650000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[7U] 
        = (0x0266U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[7U] 
        = (0x02670000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[8U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[9U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0x0000000aU] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0x0000000bU] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0x0000000cU] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0x0000000dU] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0x0000000eU] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[0x0000000fU] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__17__Vfuncout[7U];
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         189);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_row = 5U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__18__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[0U] 
        = (0x01f4U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[0U] 
        = (0x01f50000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[1U] 
        = (0x01f6U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[1U] 
        = (0x01f70000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[2U] 
        = (0x01f8U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[2U] 
        = (0x01f90000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[3U] 
        = (0x01faU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[3U] 
        = (0x01fb0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[4U] 
        = (0x01fcU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[4U] 
        = (0x01fd0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[5U] 
        = (0x01feU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[5U] 
        = (0x01ff0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[6U] 
        = (0x0200U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[6U] 
        = (0x02010000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[7U] 
        = (0x0202U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[7U] 
        = (0x02030000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__expected[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__19__Vfuncout[7U];
    if (VL_UNLIKELY(((0U != ((((((((vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[0U]) 
                                   | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                      [0U][1U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[1U])) 
                                  | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[2U])) 
                                 | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][3U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[3U])) 
                                | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[4U])) 
                               | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                  [0U][5U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[5U])) 
                              | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[6U])) 
                             | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U][7U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[7U])))))) {
        VL_WRITEF_NX("FAIL: sim write eng0 got %x exp %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data(),256,vlSelfRef.tb_uram_accum_buf__DOT__expected.data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_col = 1U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_row = 5U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__20__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[0U] 
        = (0x0258U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 1U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[0U] 
        = (0x02590000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[0U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 2U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[1U] 
        = (0x025aU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 3U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[1U] 
        = (0x025b0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[1U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 4U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[2U] 
        = (0x025cU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 5U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[2U] 
        = (0x025d0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[2U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 6U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[3U] 
        = (0x025eU | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 7U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[3U] 
        = (0x025f0000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[3U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 8U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[4U] 
        = (0x0260U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 9U;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[4U] 
        = (0x02610000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[4U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000aU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[5U] 
        = (0x0262U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000bU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[5U] 
        = (0x02630000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[5U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000cU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[6U] 
        = (0x0264U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000dU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[6U] 
        = (0x02650000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[6U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000eU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[7U] 
        = (0x0266U | (0xffff0000U & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x0000000fU;
    __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[7U] 
        = (0x02670000U | (0x0000ffffU & __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[7U]));
    vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = 0x00000010U;
    vlSelfRef.tb_uram_accum_buf__DOT__expected[0U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[1U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[2U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[3U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[4U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[5U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[6U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__expected[7U] 
        = __Vfunc_tb_uram_accum_buf__DOT__make_pattern__21__Vfuncout[7U];
    if (VL_UNLIKELY(((0U != ((((((((vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[0U]) 
                                   | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                      [0U][1U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[1U])) 
                                  | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[2U])) 
                                 | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][3U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[3U])) 
                                | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[4U])) 
                               | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                  [0U][5U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[5U])) 
                              | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[6U])) 
                             | (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U][7U] ^ vlSelfRef.tb_uram_accum_buf__DOT__expected[7U])))))) {
        VL_WRITEF_NX("FAIL: sim write eng1 got %x exp %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data(),256,vlSelfRef.tb_uram_accum_buf__DOT__expected.data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    VL_WRITEF_NX("Test 3: Clear\n",0);
    vlSelfRef.tb_uram_accum_buf__DOT__clear = 1U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         211);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__clear = 0U;
    tb_uram_accum_buf__DOT__unnamedblk1_3__DOT____Vrepeat2 = 0x0000010aU;
    while (VL_LTS_III(32, 0U, tb_uram_accum_buf__DOT__unnamedblk1_3__DOT____Vrepeat2)) {
        co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                             nullptr, 
                                                             "@(posedge tb_uram_accum_buf.clk)", 
                                                             "tb/tb_uram_accum_buf.v", 
                                                             215);
        vlSelfRef.__Vm_traceActivity[2U] = 1U;
        tb_uram_accum_buf__DOT__unnamedblk1_3__DOT____Vrepeat2 
            = (tb_uram_accum_buf__DOT__unnamedblk1_3__DOT____Vrepeat2 
               - (IData)(1U));
    }
    __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_row = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__22__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    if (VL_UNLIKELY(((0U != ((((((((Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U] 
                                    ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U]) | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U] 
                                                 ^ 
                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                                 [0U][1U])) 
                                  | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U] 
                                     ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U])) | (
                                                   Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U] 
                                                   ^ 
                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                                   [0U][3U])) 
                                | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U] 
                                   ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U])) | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U] 
                                                 ^ 
                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                                 [0U][5U])) 
                              | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U] 
                                 ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U])) | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U] 
                                               ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                               [0U][7U])))))) {
        VL_WRITEF_NX("FAIL: after clear row=0 col=0 not zero, got %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_col = 0U;
    __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_row = 5U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_row = __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_row;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word = __Vtask_tb_uram_accum_buf__DOT__read_word__23__r_col;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         100);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.tb_uram_accum_buf__DOT__rd_en = 0U;
    co_await vlSelfRef.__VtrigSched_h3248ee48__0.trigger(0U, 
                                                         nullptr, 
                                                         "@(posedge tb_uram_accum_buf.clk)", 
                                                         "tb/tb_uram_accum_buf.v", 
                                                         102);
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    if (VL_UNLIKELY(((0U != ((((((((Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U] 
                                    ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                    [0U][0U]) | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U] 
                                                 ^ 
                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                                 [0U][1U])) 
                                  | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U] 
                                     ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                     [0U][2U])) | (
                                                   Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U] 
                                                   ^ 
                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                                   [0U][3U])) 
                                | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U] 
                                   ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                   [0U][4U])) | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U] 
                                                 ^ 
                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                                 [0U][5U])) 
                              | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U] 
                                 ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                 [0U][6U])) | (Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U] 
                                               ^ vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                               [0U][7U])))))) {
        VL_WRITEF_NX("FAIL: after clear row=5 col=0 not zero, got %x\n",0,
                     256,vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                     [0U].data());
        vlSelfRef.tb_uram_accum_buf__DOT__errors = 
            ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    if ((0U == vlSelfRef.tb_uram_accum_buf__DOT__errors)) {
        VL_WRITEF_NX("ALL TESTS PASSED\n",0);
    } else {
        VL_WRITEF_NX("FAILED: %0d errors\n",0,32,vlSelfRef.tb_uram_accum_buf__DOT__errors);
    }
    VL_FINISH_MT("tb/tb_uram_accum_buf.v", 237, "");
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
}

VlCoroutine Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__1(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_initial__TOP__Vtiming__1\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    while (VL_LIKELY(!vlSymsp->_vm_contextp__->gotFinish())) {
        co_await vlSelfRef.__VdlySched.delay(5ULL, 
                                             nullptr, 
                                             "tb/tb_uram_accum_buf.v", 
                                             67);
        vlSelfRef.tb_uram_accum_buf__DOT__clk = (1U 
                                                 & (~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__clk)));
    }
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_uram_accum_buf___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG

void Vtb_uram_accum_buf___024root___eval_triggers__act(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_triggers__act\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VactTriggered[0U] = (QData)((IData)(
                                                    ((vlSelfRef.__VdlySched.awaitingCurrentTime() 
                                                      << 2U) 
                                                     | ((((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rst_n)) 
                                                          & (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__rst_n__0)) 
                                                         << 1U) 
                                                        | ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__clk) 
                                                           & (~ (IData)(vlSelfRef.__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__clk__0)))))));
    vlSelfRef.__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__clk__0 
        = vlSelfRef.tb_uram_accum_buf__DOT__clk;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__rst_n__0 
        = vlSelfRef.tb_uram_accum_buf__DOT__rst_n;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtb_uram_accum_buf___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
    }
#endif
}

bool Vtb_uram_accum_buf___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___trigger_anySet__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        if (in[n]) {
            return (1U);
        }
        n = ((IData)(1U) + n);
    } while ((1U > n));
    return (0U);
}

void Vtb_uram_accum_buf___024root___act_sequent__TOP__0(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___act_sequent__TOP__0\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VExpandSel_WordIdx_1;
    IData/*31:0*/ __VExpandSel_LoShift_1;
    CData/*0:0*/ __VExpandSel_Aligned_1;
    IData/*31:0*/ __VExpandSel_HiShift_1;
    IData/*31:0*/ __VExpandSel_HiMask_1;
    IData/*31:0*/ __VExpandSel_WordIdx_2;
    IData/*31:0*/ __VExpandSel_LoShift_2;
    CData/*0:0*/ __VExpandSel_Aligned_2;
    IData/*31:0*/ __VExpandSel_HiShift_2;
    IData/*31:0*/ __VExpandSel_HiMask_2;
    IData/*31:0*/ __VExpandSel_WordIdx_3;
    IData/*31:0*/ __VExpandSel_LoShift_3;
    CData/*0:0*/ __VExpandSel_Aligned_3;
    IData/*31:0*/ __VExpandSel_HiShift_3;
    IData/*31:0*/ __VExpandSel_HiMask_3;
    IData/*31:0*/ __VExpandSel_WordIdx_4;
    IData/*31:0*/ __VExpandSel_LoShift_4;
    CData/*0:0*/ __VExpandSel_Aligned_4;
    IData/*31:0*/ __VExpandSel_HiShift_4;
    IData/*31:0*/ __VExpandSel_HiMask_4;
    IData/*31:0*/ __VExpandSel_WordIdx_5;
    IData/*31:0*/ __VExpandSel_LoShift_5;
    CData/*0:0*/ __VExpandSel_Aligned_5;
    IData/*31:0*/ __VExpandSel_HiShift_5;
    IData/*31:0*/ __VExpandSel_HiMask_5;
    IData/*31:0*/ __VExpandSel_WordIdx_6;
    IData/*31:0*/ __VExpandSel_LoShift_6;
    CData/*0:0*/ __VExpandSel_Aligned_6;
    IData/*31:0*/ __VExpandSel_HiShift_6;
    IData/*31:0*/ __VExpandSel_HiMask_6;
    // Body
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
        = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner = 0U;
    if (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clearing) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clear_idx;
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    } else {
        if (((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found)) 
             & ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [0U]) && (1U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en) 
                                 >> vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                 [0U]))))) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                [0U];
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
                = (0x000000ffU & (VL_SHIFTL_III(8,32,32, 
                                                ((0x23U 
                                                  >= 
                                                  (0x0000003fU 
                                                   & ((IData)(6U) 
                                                      * 
                                                      vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                      [0U])))
                                                  ? 
                                                 (0x0000003fU 
                                                  & (IData)(
                                                            (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
                                                             >> 
                                                             (0x0000003fU 
                                                              & ((IData)(6U) 
                                                                 * 
                                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                 [0U])))))
                                                  : 0U), 2U) 
                                  + ((0x0bU >= (0x0000000fU 
                                                & VL_SHIFTL_III(4,32,32, 
                                                                vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                [0U], 1U)))
                                      ? (3U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word) 
                                               >> (0x0000000fU 
                                                   & VL_SHIFTL_III(4,32,32, 
                                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                   [0U], 1U))))
                                      : 0U)));
            __VExpandSel_WordIdx_1 = (0x0000003fU & 
                                      (VL_SHIFTL_III(11,32,32, 
                                                     vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                     [0U], 8U) 
                                       >> 5U));
            __VExpandSel_LoShift_1 = (0x0000001fU & 
                                      VL_SHIFTL_III(11,32,32, 
                                                    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                    [0U], 8U));
            __VExpandSel_Aligned_1 = (0U == __VExpandSel_LoShift_1);
            __VExpandSel_HiShift_1 = (__VExpandSel_Aligned_1
                                       ? 0U : ((IData)(0x00000020U) 
                                               - __VExpandSel_LoShift_1));
            __VExpandSel_HiMask_1 = (__VExpandSel_Aligned_1
                                      ? 0U : 0xffffffffU);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(1U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__VExpandSel_WordIdx_1] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(2U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(1U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(3U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(2U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(4U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(3U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(5U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(4U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(6U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(5U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(7U) + __VExpandSel_WordIdx_1)] 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(6U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [0U], 8U)))
                    ? (((((0x00000028U <= __VExpandSel_WordIdx_1)
                           ? 0U : vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                          ((IData)(8U) + __VExpandSel_WordIdx_1)]) 
                         << __VExpandSel_HiShift_1) 
                        & __VExpandSel_HiMask_1) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(7U) + __VExpandSel_WordIdx_1)] 
                        >> __VExpandSel_LoShift_1))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U]);
            if ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [0U])) {
                vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept 
                    = (((~ ((IData)(1U) << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                            [0U])) & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept)) 
                       | (0x3fU & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0) 
                                   << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                   [0U])));
            }
        }
        if (((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found)) 
             & ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [1U]) && (1U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en) 
                                 >> vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                 [1U]))))) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                [1U];
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
                = (0x000000ffU & (VL_SHIFTL_III(8,32,32, 
                                                ((0x23U 
                                                  >= 
                                                  (0x0000003fU 
                                                   & ((IData)(6U) 
                                                      * 
                                                      vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                      [1U])))
                                                  ? 
                                                 (0x0000003fU 
                                                  & (IData)(
                                                            (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
                                                             >> 
                                                             (0x0000003fU 
                                                              & ((IData)(6U) 
                                                                 * 
                                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                 [1U])))))
                                                  : 0U), 2U) 
                                  + ((0x0bU >= (0x0000000fU 
                                                & VL_SHIFTL_III(4,32,32, 
                                                                vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                [1U], 1U)))
                                      ? (3U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word) 
                                               >> (0x0000000fU 
                                                   & VL_SHIFTL_III(4,32,32, 
                                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                   [1U], 1U))))
                                      : 0U)));
            __VExpandSel_WordIdx_2 = (0x0000003fU & 
                                      (VL_SHIFTL_III(11,32,32, 
                                                     vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                     [1U], 8U) 
                                       >> 5U));
            __VExpandSel_LoShift_2 = (0x0000001fU & 
                                      VL_SHIFTL_III(11,32,32, 
                                                    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                    [1U], 8U));
            __VExpandSel_Aligned_2 = (0U == __VExpandSel_LoShift_2);
            __VExpandSel_HiShift_2 = (__VExpandSel_Aligned_2
                                       ? 0U : ((IData)(0x00000020U) 
                                               - __VExpandSel_LoShift_2));
            __VExpandSel_HiMask_2 = (__VExpandSel_Aligned_2
                                      ? 0U : 0xffffffffU);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(1U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__VExpandSel_WordIdx_2] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(2U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(1U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(3U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(2U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(4U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(3U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(5U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(4U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(6U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(5U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(7U) + __VExpandSel_WordIdx_2)] 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(6U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [1U], 8U)))
                    ? (((((0x00000028U <= __VExpandSel_WordIdx_2)
                           ? 0U : vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                          ((IData)(8U) + __VExpandSel_WordIdx_2)]) 
                         << __VExpandSel_HiShift_2) 
                        & __VExpandSel_HiMask_2) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(7U) + __VExpandSel_WordIdx_2)] 
                        >> __VExpandSel_LoShift_2))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U]);
            if ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [1U])) {
                vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept 
                    = (((~ ((IData)(1U) << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                            [1U])) & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept)) 
                       | (0x3fU & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0) 
                                   << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                   [1U])));
            }
        }
        if (((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found)) 
             & ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [2U]) && (1U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en) 
                                 >> vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                 [2U]))))) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                [2U];
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
                = (0x000000ffU & (VL_SHIFTL_III(8,32,32, 
                                                ((0x23U 
                                                  >= 
                                                  (0x0000003fU 
                                                   & ((IData)(6U) 
                                                      * 
                                                      vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                      [2U])))
                                                  ? 
                                                 (0x0000003fU 
                                                  & (IData)(
                                                            (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
                                                             >> 
                                                             (0x0000003fU 
                                                              & ((IData)(6U) 
                                                                 * 
                                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                 [2U])))))
                                                  : 0U), 2U) 
                                  + ((0x0bU >= (0x0000000fU 
                                                & VL_SHIFTL_III(4,32,32, 
                                                                vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                [2U], 1U)))
                                      ? (3U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word) 
                                               >> (0x0000000fU 
                                                   & VL_SHIFTL_III(4,32,32, 
                                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                   [2U], 1U))))
                                      : 0U)));
            __VExpandSel_WordIdx_3 = (0x0000003fU & 
                                      (VL_SHIFTL_III(11,32,32, 
                                                     vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                     [2U], 8U) 
                                       >> 5U));
            __VExpandSel_LoShift_3 = (0x0000001fU & 
                                      VL_SHIFTL_III(11,32,32, 
                                                    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                    [2U], 8U));
            __VExpandSel_Aligned_3 = (0U == __VExpandSel_LoShift_3);
            __VExpandSel_HiShift_3 = (__VExpandSel_Aligned_3
                                       ? 0U : ((IData)(0x00000020U) 
                                               - __VExpandSel_LoShift_3));
            __VExpandSel_HiMask_3 = (__VExpandSel_Aligned_3
                                      ? 0U : 0xffffffffU);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(1U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__VExpandSel_WordIdx_3] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(2U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(1U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(3U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(2U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(4U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(3U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(5U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(4U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(6U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(5U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(7U) + __VExpandSel_WordIdx_3)] 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(6U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [2U], 8U)))
                    ? (((((0x00000028U <= __VExpandSel_WordIdx_3)
                           ? 0U : vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                          ((IData)(8U) + __VExpandSel_WordIdx_3)]) 
                         << __VExpandSel_HiShift_3) 
                        & __VExpandSel_HiMask_3) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(7U) + __VExpandSel_WordIdx_3)] 
                        >> __VExpandSel_LoShift_3))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U]);
            if ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [2U])) {
                vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept 
                    = (((~ ((IData)(1U) << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                            [2U])) & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept)) 
                       | (0x3fU & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0) 
                                   << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                   [2U])));
            }
        }
        if (((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found)) 
             & ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [3U]) && (1U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en) 
                                 >> vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                 [3U]))))) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                [3U];
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
                = (0x000000ffU & (VL_SHIFTL_III(8,32,32, 
                                                ((0x23U 
                                                  >= 
                                                  (0x0000003fU 
                                                   & ((IData)(6U) 
                                                      * 
                                                      vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                      [3U])))
                                                  ? 
                                                 (0x0000003fU 
                                                  & (IData)(
                                                            (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
                                                             >> 
                                                             (0x0000003fU 
                                                              & ((IData)(6U) 
                                                                 * 
                                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                 [3U])))))
                                                  : 0U), 2U) 
                                  + ((0x0bU >= (0x0000000fU 
                                                & VL_SHIFTL_III(4,32,32, 
                                                                vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                [3U], 1U)))
                                      ? (3U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word) 
                                               >> (0x0000000fU 
                                                   & VL_SHIFTL_III(4,32,32, 
                                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                   [3U], 1U))))
                                      : 0U)));
            __VExpandSel_WordIdx_4 = (0x0000003fU & 
                                      (VL_SHIFTL_III(11,32,32, 
                                                     vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                     [3U], 8U) 
                                       >> 5U));
            __VExpandSel_LoShift_4 = (0x0000001fU & 
                                      VL_SHIFTL_III(11,32,32, 
                                                    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                    [3U], 8U));
            __VExpandSel_Aligned_4 = (0U == __VExpandSel_LoShift_4);
            __VExpandSel_HiShift_4 = (__VExpandSel_Aligned_4
                                       ? 0U : ((IData)(0x00000020U) 
                                               - __VExpandSel_LoShift_4));
            __VExpandSel_HiMask_4 = (__VExpandSel_Aligned_4
                                      ? 0U : 0xffffffffU);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(1U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__VExpandSel_WordIdx_4] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(2U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(1U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(3U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(2U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(4U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(3U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(5U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(4U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(6U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(5U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(7U) + __VExpandSel_WordIdx_4)] 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(6U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [3U], 8U)))
                    ? (((((0x00000028U <= __VExpandSel_WordIdx_4)
                           ? 0U : vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                          ((IData)(8U) + __VExpandSel_WordIdx_4)]) 
                         << __VExpandSel_HiShift_4) 
                        & __VExpandSel_HiMask_4) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(7U) + __VExpandSel_WordIdx_4)] 
                        >> __VExpandSel_LoShift_4))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U]);
            if ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [3U])) {
                vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept 
                    = (((~ ((IData)(1U) << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                            [3U])) & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept)) 
                       | (0x3fU & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0) 
                                   << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                   [3U])));
            }
        }
        if (((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found)) 
             & ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [4U]) && (1U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en) 
                                 >> vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                 [4U]))))) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                [4U];
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
                = (0x000000ffU & (VL_SHIFTL_III(8,32,32, 
                                                ((0x23U 
                                                  >= 
                                                  (0x0000003fU 
                                                   & ((IData)(6U) 
                                                      * 
                                                      vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                      [4U])))
                                                  ? 
                                                 (0x0000003fU 
                                                  & (IData)(
                                                            (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
                                                             >> 
                                                             (0x0000003fU 
                                                              & ((IData)(6U) 
                                                                 * 
                                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                 [4U])))))
                                                  : 0U), 2U) 
                                  + ((0x0bU >= (0x0000000fU 
                                                & VL_SHIFTL_III(4,32,32, 
                                                                vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                [4U], 1U)))
                                      ? (3U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word) 
                                               >> (0x0000000fU 
                                                   & VL_SHIFTL_III(4,32,32, 
                                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                   [4U], 1U))))
                                      : 0U)));
            __VExpandSel_WordIdx_5 = (0x0000003fU & 
                                      (VL_SHIFTL_III(11,32,32, 
                                                     vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                     [4U], 8U) 
                                       >> 5U));
            __VExpandSel_LoShift_5 = (0x0000001fU & 
                                      VL_SHIFTL_III(11,32,32, 
                                                    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                    [4U], 8U));
            __VExpandSel_Aligned_5 = (0U == __VExpandSel_LoShift_5);
            __VExpandSel_HiShift_5 = (__VExpandSel_Aligned_5
                                       ? 0U : ((IData)(0x00000020U) 
                                               - __VExpandSel_LoShift_5));
            __VExpandSel_HiMask_5 = (__VExpandSel_Aligned_5
                                      ? 0U : 0xffffffffU);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(1U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__VExpandSel_WordIdx_5] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(2U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(1U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(3U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(2U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(4U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(3U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(5U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(4U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(6U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(5U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(7U) + __VExpandSel_WordIdx_5)] 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(6U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [4U], 8U)))
                    ? (((((0x00000028U <= __VExpandSel_WordIdx_5)
                           ? 0U : vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                          ((IData)(8U) + __VExpandSel_WordIdx_5)]) 
                         << __VExpandSel_HiShift_5) 
                        & __VExpandSel_HiMask_5) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(7U) + __VExpandSel_WordIdx_5)] 
                        >> __VExpandSel_LoShift_5))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U]);
            if ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [4U])) {
                vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept 
                    = (((~ ((IData)(1U) << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                            [4U])) & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept)) 
                       | (0x3fU & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0) 
                                   << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                   [4U])));
            }
        }
        if (((~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found)) 
             & ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [5U]) && (1U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en) 
                                 >> vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                 [5U]))))) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                [5U];
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = 1U;
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux 
                = (0x000000ffU & (VL_SHIFTL_III(8,32,32, 
                                                ((0x23U 
                                                  >= 
                                                  (0x0000003fU 
                                                   & ((IData)(6U) 
                                                      * 
                                                      vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                      [5U])))
                                                  ? 
                                                 (0x0000003fU 
                                                  & (IData)(
                                                            (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row 
                                                             >> 
                                                             (0x0000003fU 
                                                              & ((IData)(6U) 
                                                                 * 
                                                                 vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                 [5U])))))
                                                  : 0U), 2U) 
                                  + ((0x0bU >= (0x0000000fU 
                                                & VL_SHIFTL_III(4,32,32, 
                                                                vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                [5U], 1U)))
                                      ? (3U & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word) 
                                               >> (0x0000000fU 
                                                   & VL_SHIFTL_III(4,32,32, 
                                                                   vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                                   [5U], 1U))))
                                      : 0U)));
            __VExpandSel_WordIdx_6 = (0x0000003fU & 
                                      (VL_SHIFTL_III(11,32,32, 
                                                     vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                     [5U], 8U) 
                                       >> 5U));
            __VExpandSel_LoShift_6 = (0x0000001fU & 
                                      VL_SHIFTL_III(11,32,32, 
                                                    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                    [5U], 8U));
            __VExpandSel_Aligned_6 = (0U == __VExpandSel_LoShift_6);
            __VExpandSel_HiShift_6 = (__VExpandSel_Aligned_6
                                       ? 0U : ((IData)(0x00000020U) 
                                               - __VExpandSel_LoShift_6));
            __VExpandSel_HiMask_6 = (__VExpandSel_Aligned_6
                                      ? 0U : 0xffffffffU);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(1U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[__VExpandSel_WordIdx_6] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(2U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(1U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(3U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(2U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(4U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(3U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(5U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(4U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(6U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(5U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                         ((IData)(7U) + __VExpandSel_WordIdx_6)] 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(6U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U]);
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U] 
                = ((0x05ffU >= (0x000007ffU & VL_SHIFTL_III(11,32,32, 
                                                            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                                            [5U], 8U)))
                    ? (((((0x00000028U <= __VExpandSel_WordIdx_6)
                           ? 0U : vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                          ((IData)(8U) + __VExpandSel_WordIdx_6)]) 
                         << __VExpandSel_HiShift_6) 
                        & __VExpandSel_HiMask_6) | 
                       (vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data[
                        ((IData)(7U) + __VExpandSel_WordIdx_6)] 
                        >> __VExpandSel_LoShift_6))
                    : Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U]);
            if ((5U >= vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                 [5U])) {
                vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept 
                    = (((~ ((IData)(1U) << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                            [5U])) & (IData)(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept)) 
                       | (0x3fU & ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0) 
                                   << vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx
                                   [5U])));
            }
        }
    }
}

void Vtb_uram_accum_buf___024root___eval_act(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_act\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VactTriggered[0U])) {
        Vtb_uram_accum_buf___024root___act_sequent__TOP__0(vlSelf);
        vlSelfRef.__Vm_traceActivity[3U] = 1U;
    }
}

void Vtb_uram_accum_buf___024root___nba_sequent__TOP__0(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___nba_sequent__TOP__0\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*2:0*/ tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 = 0;
    CData/*0:0*/ __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing;
    __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing = 0;
    CData/*7:0*/ __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx;
    __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx = 0;
    CData/*0:0*/ __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid__v0;
    __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid__v0 = 0;
    VlWide<8>/*255:0*/ __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0;
    VL_ZERO_W(256, __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0);
    CData/*0:0*/ __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0;
    __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0 = 0;
    CData/*0:0*/ __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v1;
    __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v1 = 0;
    // Body
    __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0 = 0U;
    __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v1 = 0U;
    __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx 
        = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clear_idx;
    __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing 
        = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clearing;
    if (vlSelfRef.tb_uram_accum_buf__DOT__rst_n) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__s = 1U;
        if (vlSelfRef.tb_uram_accum_buf__DOT__rd_en) {
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[0U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][0U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[1U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][1U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[2U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][2U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[3U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][3U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[4U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][4U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[5U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][5U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[6U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][6U];
            __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[7U] 
                = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem
                [(0x000000ffU & (VL_SHIFTL_III(8,32,32, (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_row), 2U) 
                                 + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word)))][7U];
            __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0 = 1U;
        }
        if (vlSelfRef.tb_uram_accum_buf__DOT__clear) {
            __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing = 1U;
            __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx = 0U;
        } else if (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clearing) {
            if ((0xffU == (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clear_idx))) {
                __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing = 0U;
            } else {
                __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx 
                    = (0x000000ffU & ((IData)(1U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clear_idx)));
            }
        }
        if (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found) {
            vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr 
                = ((5U == (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner))
                    ? 0U : (7U & ((IData)(1U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner))));
        }
    } else {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__s = 1U;
        __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v1 = 1U;
        __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing = 0U;
        __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx = 0U;
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr = 0U;
    }
    __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid__v0 
        = ((IData)(vlSelfRef.tb_uram_accum_buf__DOT__rst_n) 
           && (IData)(vlSelfRef.tb_uram_accum_buf__DOT__rd_en));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid[0U] 
        = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid__v0;
    if (__VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][0U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[0U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][1U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[1U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][2U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[2U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][3U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[3U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][4U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[4U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][5U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[5U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][6U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[6U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][7U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v0[7U];
    }
    if (__VdlySet__tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data__v1) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][0U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][1U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][2U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][3U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][4U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][5U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][6U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0U][7U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
    }
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clear_idx 
        = __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clear_idx;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clearing 
        = __Vdly__tb_uram_accum_buf__DOT__dut__DOT__clearing;
    if ((1U & (~ (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clearing)))) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__e = 6U;
    }
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
        = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr;
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 
        = (7U & (VL_LTES_III(32, 6U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i)
                  ? (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
                     - (IData)(6U)) : vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[0U] 
        = tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
        = ((IData)(1U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr));
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 
        = (7U & (VL_LTES_III(32, 6U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i)
                  ? (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
                     - (IData)(6U)) : vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[1U] 
        = tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
        = ((IData)(2U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr));
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 
        = (7U & (VL_LTES_III(32, 6U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i)
                  ? (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
                     - (IData)(6U)) : vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[2U] 
        = tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
        = ((IData)(3U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr));
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 
        = (7U & (VL_LTES_III(32, 6U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i)
                  ? (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
                     - (IData)(6U)) : vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[3U] 
        = tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
        = ((IData)(4U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr));
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 
        = (7U & (VL_LTES_III(32, 6U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i)
                  ? (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
                     - (IData)(6U)) : vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[4U] 
        = tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
        = ((IData)(5U) + (IData)(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr));
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 
        = (7U & (VL_LTES_III(32, 6U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i)
                  ? (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i 
                     - (IData)(6U)) : vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i));
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[5U] 
        = tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
}

void Vtb_uram_accum_buf___024root___nba_sequent__TOP__1(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___nba_sequent__TOP__1\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    VlWide<8>/*255:0*/ __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0;
    VL_ZERO_W(256, __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0);
    CData/*7:0*/ __VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0;
    __VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0 = 0;
    CData/*0:0*/ __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__mem__v0;
    __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__mem__v0 = 0;
    // Body
    __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__mem__v0 = 0U;
    if (vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux) {
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[0U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[0U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[1U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[1U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[2U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[2U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[3U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[3U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[4U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[4U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[5U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[5U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[6U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[6U];
        __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[7U] 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux[7U];
        __VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0 
            = vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux;
        __VdlySet__tb_uram_accum_buf__DOT__dut__DOT__mem__v0 = 1U;
    }
    if (__VdlySet__tb_uram_accum_buf__DOT__dut__DOT__mem__v0) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][0U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[0U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][1U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[1U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][2U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[2U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][3U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[3U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][4U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[4U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][5U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[5U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][6U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[6U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[__VdlyDim0__tb_uram_accum_buf__DOT__dut__DOT__mem__v0][7U] 
            = __VdlyVal__tb_uram_accum_buf__DOT__dut__DOT__mem__v0[7U];
    }
}

void Vtb_uram_accum_buf___024root___eval_nba(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_nba\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vtb_uram_accum_buf___024root___nba_sequent__TOP__0(vlSelf);
        vlSelfRef.__Vm_traceActivity[4U] = 1U;
    }
    if ((1ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vtb_uram_accum_buf___024root___nba_sequent__TOP__1(vlSelf);
    }
    if ((3ULL & vlSelfRef.__VnbaTriggered[0U])) {
        Vtb_uram_accum_buf___024root___act_sequent__TOP__0(vlSelf);
        vlSelfRef.__Vm_traceActivity[5U] = 1U;
    }
}

void Vtb_uram_accum_buf___024root___timing_commit(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___timing_commit\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((! (1ULL & vlSelfRef.__VactTriggered[0U]))) {
        vlSelfRef.__VtrigSched_h3248ee48__0.commit(
                                                   "@(posedge tb_uram_accum_buf.clk)");
    }
}

void Vtb_uram_accum_buf___024root___timing_resume(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___timing_resume\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VactTriggered[0U])) {
        vlSelfRef.__VtrigSched_h3248ee48__0.resume(
                                                   "@(posedge tb_uram_accum_buf.clk)");
    }
    if ((4ULL & vlSelfRef.__VactTriggered[0U])) {
        vlSelfRef.__VdlySched.resume();
    }
}

void Vtb_uram_accum_buf___024root___trigger_orInto__act(VlUnpacked<QData/*63:0*/, 1> &out, const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___trigger_orInto__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = (out[n] | in[n]);
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vtb_uram_accum_buf___024root___eval_phase__act(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_phase__act\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VactExecute;
    // Body
    Vtb_uram_accum_buf___024root___eval_triggers__act(vlSelf);
    Vtb_uram_accum_buf___024root___timing_commit(vlSelf);
    Vtb_uram_accum_buf___024root___trigger_orInto__act(vlSelfRef.__VnbaTriggered, vlSelfRef.__VactTriggered);
    __VactExecute = Vtb_uram_accum_buf___024root___trigger_anySet__act(vlSelfRef.__VactTriggered);
    if (__VactExecute) {
        Vtb_uram_accum_buf___024root___timing_resume(vlSelf);
        Vtb_uram_accum_buf___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

void Vtb_uram_accum_buf___024root___trigger_clear__act(VlUnpacked<QData/*63:0*/, 1> &out) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___trigger_clear__act\n"); );
    // Locals
    IData/*31:0*/ n;
    // Body
    n = 0U;
    do {
        out[n] = 0ULL;
        n = ((IData)(1U) + n);
    } while ((1U > n));
}

bool Vtb_uram_accum_buf___024root___eval_phase__nba(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_phase__nba\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = Vtb_uram_accum_buf___024root___trigger_anySet__act(vlSelfRef.__VnbaTriggered);
    if (__VnbaExecute) {
        Vtb_uram_accum_buf___024root___eval_nba(vlSelf);
        Vtb_uram_accum_buf___024root___trigger_clear__act(vlSelfRef.__VnbaTriggered);
    }
    return (__VnbaExecute);
}

void Vtb_uram_accum_buf___024root___eval(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VnbaIterCount;
    // Body
    __VnbaIterCount = 0U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VnbaIterCount)))) {
#ifdef VL_DEBUG
            Vtb_uram_accum_buf___024root___dump_triggers__act(vlSelfRef.__VnbaTriggered, "nba"s);
#endif
            VL_FATAL_MT("tb/tb_uram_accum_buf.v", 12, "", "NBA region did not converge after 100 tries");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        vlSelfRef.__VactIterCount = 0U;
        do {
            if (VL_UNLIKELY(((0x00000064U < vlSelfRef.__VactIterCount)))) {
#ifdef VL_DEBUG
                Vtb_uram_accum_buf___024root___dump_triggers__act(vlSelfRef.__VactTriggered, "act"s);
#endif
                VL_FATAL_MT("tb/tb_uram_accum_buf.v", 12, "", "Active region did not converge after 100 tries");
            }
            vlSelfRef.__VactIterCount = ((IData)(1U) 
                                         + vlSelfRef.__VactIterCount);
        } while (Vtb_uram_accum_buf___024root___eval_phase__act(vlSelf));
    } while (Vtb_uram_accum_buf___024root___eval_phase__nba(vlSelf));
}

#ifdef VL_DEBUG
void Vtb_uram_accum_buf___024root___eval_debug_assertions(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_debug_assertions\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}
#endif  // VL_DEBUG
