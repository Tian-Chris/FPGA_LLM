// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vtb_uram_accum_buf.h for the primary calling header

#include "Vtb_uram_accum_buf__pch.h"

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_static(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_static\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__clk__0 
        = vlSelfRef.tb_uram_accum_buf__DOT__clk;
    vlSelfRef.__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__rst_n__0 
        = vlSelfRef.tb_uram_accum_buf__DOT__rst_n;
}

extern const VlWide<8>/*255:0*/ Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0;

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_initial__TOP(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_initial__TOP\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.tb_uram_accum_buf__DOT__clk = 0U;
    vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i = 0U;
    while (VL_GTS_III(32, 0x00000100U, vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)) {
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][0U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[0U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][1U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[1U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][2U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[2U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][3U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[3U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][4U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[4U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][5U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[5U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][6U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[6U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__mem[(0x000000ffU 
                                                         & vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i)][7U] 
            = Vtb_uram_accum_buf__ConstPool__CONST_h9e67c271_0[7U];
        vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i 
            = ((IData)(1U) + vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i);
    }
}

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_final(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_final\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_uram_accum_buf___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vtb_uram_accum_buf___024root___eval_phase__stl(Vtb_uram_accum_buf___024root* vlSelf);

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_settle(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_settle\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    IData/*31:0*/ __VstlIterCount;
    // Body
    __VstlIterCount = 0U;
    vlSelfRef.__VstlFirstIteration = 1U;
    do {
        if (VL_UNLIKELY(((0x00000064U < __VstlIterCount)))) {
#ifdef VL_DEBUG
            Vtb_uram_accum_buf___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
#endif
            VL_FATAL_MT("tb/tb_uram_accum_buf.v", 12, "", "Settle region did not converge after 100 tries");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
    } while (Vtb_uram_accum_buf___024root___eval_phase__stl(vlSelf));
}

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_triggers__stl(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_triggers__stl\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__VstlTriggered[0U] = ((0xfffffffffffffffeULL 
                                      & vlSelfRef.__VstlTriggered
                                      [0U]) | (IData)((IData)(vlSelfRef.__VstlFirstIteration)));
    vlSelfRef.__VstlFirstIteration = 0U;
#ifdef VL_DEBUG
    if (VL_UNLIKELY(vlSymsp->_vm_contextp__->debug())) {
        Vtb_uram_accum_buf___024root___dump_triggers__stl(vlSelfRef.__VstlTriggered, "stl"s);
    }
#endif
}

VL_ATTR_COLD bool Vtb_uram_accum_buf___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_uram_accum_buf___024root___dump_triggers__stl(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ (IData)(Vtb_uram_accum_buf___024root___trigger_anySet__stl(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD bool Vtb_uram_accum_buf___024root___trigger_anySet__stl(const VlUnpacked<QData/*63:0*/, 1> &in) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___trigger_anySet__stl\n"); );
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

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___stl_sequent__TOP__0(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___stl_sequent__TOP__0\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*2:0*/ tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0;
    tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_h1091f52c__0 = 0;
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

VL_ATTR_COLD void Vtb_uram_accum_buf___024root____Vm_traceActivitySetAll(Vtb_uram_accum_buf___024root* vlSelf);

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___eval_stl(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_stl\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    if ((1ULL & vlSelfRef.__VstlTriggered[0U])) {
        Vtb_uram_accum_buf___024root___stl_sequent__TOP__0(vlSelf);
        Vtb_uram_accum_buf___024root____Vm_traceActivitySetAll(vlSelf);
    }
}

VL_ATTR_COLD bool Vtb_uram_accum_buf___024root___eval_phase__stl(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___eval_phase__stl\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Locals
    CData/*0:0*/ __VstlExecute;
    // Body
    Vtb_uram_accum_buf___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = Vtb_uram_accum_buf___024root___trigger_anySet__stl(vlSelfRef.__VstlTriggered);
    if (__VstlExecute) {
        Vtb_uram_accum_buf___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

bool Vtb_uram_accum_buf___024root___trigger_anySet__act(const VlUnpacked<QData/*63:0*/, 1> &in);

#ifdef VL_DEBUG
VL_ATTR_COLD void Vtb_uram_accum_buf___024root___dump_triggers__act(const VlUnpacked<QData/*63:0*/, 1> &triggers, const std::string &tag) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ (IData)(Vtb_uram_accum_buf___024root___trigger_anySet__act(triggers))))) {
        VL_DBG_MSGS("         No '" + tag + "' region triggers active\n");
    }
    if ((1U & (IData)(triggers[0U]))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 0 is active: @(posedge tb_uram_accum_buf.clk)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 1U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 1 is active: @(negedge tb_uram_accum_buf.rst_n)\n");
    }
    if ((1U & (IData)((triggers[0U] >> 2U)))) {
        VL_DBG_MSGS("         '" + tag + "' region trigger index 2 is active: @([true] __VdlySched.awaitingCurrentTime())\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vtb_uram_accum_buf___024root____Vm_traceActivitySetAll(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root____Vm_traceActivitySetAll\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    vlSelfRef.__Vm_traceActivity[0U] = 1U;
    vlSelfRef.__Vm_traceActivity[1U] = 1U;
    vlSelfRef.__Vm_traceActivity[2U] = 1U;
    vlSelfRef.__Vm_traceActivity[3U] = 1U;
    vlSelfRef.__Vm_traceActivity[4U] = 1U;
    vlSelfRef.__Vm_traceActivity[5U] = 1U;
}

VL_ATTR_COLD void Vtb_uram_accum_buf___024root___ctor_var_reset(Vtb_uram_accum_buf___024root* vlSelf) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root___ctor_var_reset\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    const uint64_t __VscopeHash = VL_MURMUR64_HASH(vlSelf->name());
    vlSelf->tb_uram_accum_buf__DOT__clk = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17307462804525967327ull);
    vlSelf->tb_uram_accum_buf__DOT__rst_n = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1138304814846558135ull);
    vlSelf->tb_uram_accum_buf__DOT__clear = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 965064469103866593ull);
    vlSelf->tb_uram_accum_buf__DOT__eng_wr_en = VL_SCOPED_RAND_RESET_I(6, __VscopeHash, 17629638768542198287ull);
    vlSelf->tb_uram_accum_buf__DOT__eng_wr_row = VL_SCOPED_RAND_RESET_Q(36, __VscopeHash, 627848086238867949ull);
    vlSelf->tb_uram_accum_buf__DOT__eng_wr_col_word = VL_SCOPED_RAND_RESET_I(12, __VscopeHash, 12584587736213379610ull);
    VL_SCOPED_RAND_RESET_W(1536, vlSelf->tb_uram_accum_buf__DOT__eng_wr_data, __VscopeHash, 6164529854706200085ull);
    vlSelf->tb_uram_accum_buf__DOT__eng_wr_accept = VL_SCOPED_RAND_RESET_I(6, __VscopeHash, 5466786683602687813ull);
    vlSelf->tb_uram_accum_buf__DOT__rd_en = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17086822162522836076ull);
    vlSelf->tb_uram_accum_buf__DOT__rd_row = VL_SCOPED_RAND_RESET_I(6, __VscopeHash, 75317450211222219ull);
    vlSelf->tb_uram_accum_buf__DOT__rd_col_word = VL_SCOPED_RAND_RESET_I(2, __VscopeHash, 10742886769814376004ull);
    vlSelf->tb_uram_accum_buf__DOT__errors = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 12015669609589206511ull);
    vlSelf->tb_uram_accum_buf__DOT__i = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2530096712281534377ull);
    vlSelf->tb_uram_accum_buf__DOT__eng = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2508709859641369645ull);
    vlSelf->tb_uram_accum_buf__DOT__row = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 2634943120755506208ull);
    vlSelf->tb_uram_accum_buf__DOT__col = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 11568761667889865958ull);
    VL_SCOPED_RAND_RESET_W(256, vlSelf->tb_uram_accum_buf__DOT__expected, __VscopeHash, 13217820324843874517ull);
    vlSelf->tb_uram_accum_buf__DOT__make_pattern__Vstatic__k = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 15648416934968779930ull);
    for (int __Vi0 = 0; __Vi0 < 256; ++__Vi0) {
        VL_SCOPED_RAND_RESET_W(256, vlSelf->tb_uram_accum_buf__DOT__dut__DOT__mem[__Vi0], __VscopeHash, 2988380722086208500ull);
    }
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__clearing = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 13044501019549418487ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__clear_idx = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 8999306357227475439ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__arb_ptr = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 10337617004528371357ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 1524211255133219004ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux = VL_SCOPED_RAND_RESET_I(8, __VscopeHash, 14211931598979028334ull);
    VL_SCOPED_RAND_RESET_W(256, vlSelf->tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux, __VscopeHash, 6878693409563396886ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 14992916844946221220ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__arb_winner = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 14269780227450161835ull);
    for (int __Vi0 = 0; __Vi0 < 6; ++__Vi0) {
        vlSelf->tb_uram_accum_buf__DOT__dut__DOT__pri_idx[__Vi0] = VL_SCOPED_RAND_RESET_I(3, __VscopeHash, 10375446073934993258ull);
    }
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 10760006061212066236ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__e = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 3445278515415076145ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        VL_SCOPED_RAND_RESET_W(256, vlSelf->tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[__Vi0], __VscopeHash, 17810949269781473281ull);
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid[__Vi0] = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 3609563319939470472ull);
    }
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__s = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 5430345620071643693ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT__init_i = VL_SCOPED_RAND_RESET_I(32, __VscopeHash, 9668374388633659741ull);
    vlSelf->tb_uram_accum_buf__DOT__dut__DOT____Vlvbound_haf74398b__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 9987159005347098626ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VstlTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VactTriggered[__Vi0] = 0;
    }
    vlSelf->__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__clk__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 6380990705380630067ull);
    vlSelf->__Vtrigprevexpr___TOP__tb_uram_accum_buf__DOT__rst_n__0 = VL_SCOPED_RAND_RESET_I(1, __VscopeHash, 17058429719894563911ull);
    for (int __Vi0 = 0; __Vi0 < 1; ++__Vi0) {
        vlSelf->__VnbaTriggered[__Vi0] = 0;
    }
    for (int __Vi0 = 0; __Vi0 < 6; ++__Vi0) {
        vlSelf->__Vm_traceActivity[__Vi0] = 0;
    }
}
