// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Tracing implementation internals
#include "verilated_vcd_c.h"
#include "Vtb_uram_accum_buf__Syms.h"


void Vtb_uram_accum_buf___024root__trace_chg_0_sub_0(Vtb_uram_accum_buf___024root* vlSelf, VerilatedVcd::Buffer* bufp);

void Vtb_uram_accum_buf___024root__trace_chg_0(void* voidSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root__trace_chg_0\n"); );
    // Body
    Vtb_uram_accum_buf___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtb_uram_accum_buf___024root*>(voidSelf);
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    if (VL_UNLIKELY(!vlSymsp->__Vm_activity)) return;
    Vtb_uram_accum_buf___024root__trace_chg_0_sub_0((&vlSymsp->TOP), bufp);
}

void Vtb_uram_accum_buf___024root__trace_chg_0_sub_0(Vtb_uram_accum_buf___024root* vlSelf, VerilatedVcd::Buffer* bufp) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root__trace_chg_0_sub_0\n"); );
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    auto& vlSelfRef = std::ref(*vlSelf).get();
    // Body
    uint32_t* const oldp VL_ATTR_UNUSED = bufp->oldp(vlSymsp->__Vm_baseCode + 1);
    if (VL_UNLIKELY(((vlSelfRef.__Vm_traceActivity[1U] 
                      | vlSelfRef.__Vm_traceActivity
                      [2U])))) {
        bufp->chgBit(oldp+0,(vlSelfRef.tb_uram_accum_buf__DOT__rst_n));
        bufp->chgBit(oldp+1,(vlSelfRef.tb_uram_accum_buf__DOT__clear));
        bufp->chgCData(oldp+2,(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_en),6);
        bufp->chgQData(oldp+3,(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_row),36);
        bufp->chgSData(oldp+5,(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_col_word),12);
        bufp->chgWData(oldp+6,(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_data),1536);
        bufp->chgBit(oldp+54,(vlSelfRef.tb_uram_accum_buf__DOT__rd_en));
        bufp->chgCData(oldp+55,(vlSelfRef.tb_uram_accum_buf__DOT__rd_row),6);
        bufp->chgCData(oldp+56,(vlSelfRef.tb_uram_accum_buf__DOT__rd_col_word),2);
        bufp->chgIData(oldp+57,(vlSelfRef.tb_uram_accum_buf__DOT__errors),32);
        bufp->chgWData(oldp+58,(vlSelfRef.tb_uram_accum_buf__DOT__expected),256);
        bufp->chgIData(oldp+66,(vlSelfRef.tb_uram_accum_buf__DOT__make_pattern__Vstatic__k),32);
    }
    if (VL_UNLIKELY(((vlSelfRef.__Vm_traceActivity[3U] 
                      | vlSelfRef.__Vm_traceActivity
                      [5U])))) {
        bufp->chgCData(oldp+67,(vlSelfRef.tb_uram_accum_buf__DOT__eng_wr_accept),6);
        bufp->chgBit(oldp+68,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_en_mux));
        bufp->chgCData(oldp+69,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_addr_mux),8);
        bufp->chgWData(oldp+70,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__wr_data_mux),256);
        bufp->chgBit(oldp+78,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_eng_found));
        bufp->chgCData(oldp+79,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_winner),3);
    }
    if (VL_UNLIKELY((vlSelfRef.__Vm_traceActivity[4U]))) {
        bufp->chgWData(oldp+80,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data
                                [0U]),256);
        bufp->chgBit(oldp+88,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid
                              [0U]));
        bufp->chgBit(oldp+89,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clearing));
        bufp->chgCData(oldp+90,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__clear_idx),8);
        bufp->chgCData(oldp+91,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__arb_ptr),3);
        bufp->chgCData(oldp+92,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[0]),3);
        bufp->chgCData(oldp+93,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[1]),3);
        bufp->chgCData(oldp+94,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[2]),3);
        bufp->chgCData(oldp+95,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[3]),3);
        bufp->chgCData(oldp+96,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[4]),3);
        bufp->chgCData(oldp+97,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_idx[5]),3);
        bufp->chgIData(oldp+98,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__pri_sum_i),32);
        bufp->chgIData(oldp+99,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__e),32);
        bufp->chgWData(oldp+100,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_data[0]),256);
        bufp->chgBit(oldp+108,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__rd_pipe_valid[0]));
        bufp->chgIData(oldp+109,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__s),32);
    }
    bufp->chgBit(oldp+110,(vlSelfRef.tb_uram_accum_buf__DOT__clk));
    bufp->chgIData(oldp+111,(vlSelfRef.tb_uram_accum_buf__DOT__dut__DOT__init_i),32);
}

void Vtb_uram_accum_buf___024root__trace_cleanup(void* voidSelf, VerilatedVcd* /*unused*/) {
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vtb_uram_accum_buf___024root__trace_cleanup\n"); );
    // Body
    Vtb_uram_accum_buf___024root* const __restrict vlSelf VL_ATTR_UNUSED = static_cast<Vtb_uram_accum_buf___024root*>(voidSelf);
    Vtb_uram_accum_buf__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    vlSymsp->__Vm_activity = false;
    vlSymsp->TOP.__Vm_traceActivity[0U] = 0U;
    vlSymsp->TOP.__Vm_traceActivity[1U] = 0U;
    vlSymsp->TOP.__Vm_traceActivity[2U] = 0U;
    vlSymsp->TOP.__Vm_traceActivity[3U] = 0U;
    vlSymsp->TOP.__Vm_traceActivity[4U] = 0U;
    vlSymsp->TOP.__Vm_traceActivity[5U] = 0U;
}
