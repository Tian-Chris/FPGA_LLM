// =============================================================================
// host.cpp — GPT-2 Medium Inference on Alveo U280
// =============================================================================
//
// End-to-end text generation: BPE tokenize → embed → FPGA (24 layers) →
// host ln_f → unembed → argmax → decode → print.
//
// Usage:
//   ./host <xclbin> <data_dir> ["prompt text"] [max_tokens]
//
// Data directory must contain:
//   weights.bin  — FPGA weight buffer (~604 MB, FP16 + inline biases, from export_gpt2.py)
//   embed.bin    — wte + wpe + ln_f (from export_gpt2.py)
//   vocab.json   — GPT-2 tokenizer vocabulary
//   merges.txt   — GPT-2 BPE merges
// =============================================================================

#include <cassert>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <numeric>
#include <string>
#include <thread>
#include <vector>

#include "xrt/xrt_bo.h"
#include "xrt/xrt_device.h"
#include "xrt/xrt_kernel.h"

#include "gpt2_bpe.h"

// =============================================================================
// Model Constants (must match RTL production config in defines.vh)
// =============================================================================
static constexpr int MODEL_DIM     = 1024;
static constexpr int NUM_HEADS     = 16;
static constexpr int HEAD_DIM      = MODEL_DIM / NUM_HEADS;  // 64
static constexpr int F_DIM         = 4096;
static constexpr int MAX_SEQ_LEN   = 128;
static int NUM_LAYERS              = 24;  // default; overridable via env NUM_LAYERS
static constexpr int BUS_ELEMS     = 16;   // 256-bit / 16-bit

// AXI-Lite debug register offsets (match vitis_control.v)
static constexpr uint32_t REG_DBG_STATE = 0x48;
static constexpr uint32_t REG_DBG_LAYER = 0x50;
static const char* FSM_NAMES[] = {
    "IDLE", "DECODE", "LN_RUN", "QKV_MM", "QKV_FL",
    "ATT_SCORE", "ATT_SM", "ATT_SM_FL", "ATT_OUT", "ATT_OUT_FL",
    "MM_RUN", "ACT_RUN", "RES_RUN", "UF_RUN", "NEXT_STEP",
    "DONE", "OUTPUT_COPY"
};
static constexpr int WORD_BYTES    = 32;   // 256 bits = 32 bytes
static constexpr int MODEL_STRIDE  = MODEL_DIM / BUS_ELEMS;  // 64 words

// Buffer sizes (LAYER_SIZE, KV_LAYER_SIZE, ACT_SCRATCH are compile-time constants;
// totals that depend on NUM_LAYERS are computed at runtime since NUM_LAYERS is configurable)
static constexpr size_t LAYER_SIZE        = 787264;  // words per layer (incl. bias)
static constexpr size_t ACT_SCRATCH_WORDS = 6 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS;  // 49152
static constexpr int    KV_LAYER_SIZE     = 2 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS;  // 16384
static constexpr size_t OUTPUT_BUF_SIZE   =  4 * 1024 * 1024;   //  4 MB
// Computed at runtime (depend on NUM_LAYERS):
static size_t WEIGHT_BUF_SIZE;
static size_t ACT_BUF_SIZE;

// Activation memory layout (word offsets, matching fsm_controller.v)
// WE = BUS_ELEMS = 16
static constexpr int ACT_EMBED_OFFSET = 0;
static constexpr int ACT_Q_OFFSET     = MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS;      // 8192
static constexpr int ACT_ATTN_OFFSET  = 4 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS;  // 32768
static constexpr int ACT_TEMP_OFFSET  = 5 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS;  // 40960
static constexpr int ACT_FFN_OFFSET   = 0;  // reuses embed region

// =============================================================================
// Embedding Data (loaded from embed.bin)
// =============================================================================
struct EmbedData {
    uint32_t vocab_size;
    uint32_t model_dim;
    uint32_t max_pos;

    std::vector<float> wte;      // vocab_size × model_dim
    std::vector<float> wpe;      // max_pos × model_dim
    std::vector<float> ln_f_g;   // model_dim (gamma)
    std::vector<float> ln_f_b;   // model_dim (beta)
};

static bool load_embed(const std::string& path, EmbedData& ed) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return false;

    uint32_t header[4];
    f.read(reinterpret_cast<char*>(header), 16);
    ed.vocab_size = header[0];
    ed.model_dim  = header[1];
    ed.max_pos    = header[2];

    ed.wte.resize(ed.vocab_size * ed.model_dim);
    f.read(reinterpret_cast<char*>(ed.wte.data()), ed.wte.size() * sizeof(float));

    ed.wpe.resize(ed.max_pos * ed.model_dim);
    f.read(reinterpret_cast<char*>(ed.wpe.data()), ed.wpe.size() * sizeof(float));

    ed.ln_f_g.resize(ed.model_dim);
    f.read(reinterpret_cast<char*>(ed.ln_f_g.data()), ed.model_dim * sizeof(float));

    ed.ln_f_b.resize(ed.model_dim);
    f.read(reinterpret_cast<char*>(ed.ln_f_b.data()), ed.model_dim * sizeof(float));

    return f.good();
}

// =============================================================================
// FP16 ↔ FP32 Conversion Helpers
// =============================================================================
static uint16_t float_to_fp16(float val) {
    uint32_t bits;
    std::memcpy(&bits, &val, 4);
    uint32_t sign = (bits >> 16) & 0x8000;
    int32_t exp = static_cast<int32_t>((bits >> 23) & 0xFF) - 127 + 15;
    uint32_t mant = bits & 0x7FFFFF;

    // Handle special cases
    if (((bits >> 23) & 0xFF) == 0xFF) {
        // Inf or NaN
        return static_cast<uint16_t>(sign | 0x7C00 | (mant ? 0x0200 : 0));
    }
    if (((bits >> 23) & 0xFF) == 0) {
        // Zero or FP32 denorm → FP16 zero
        return static_cast<uint16_t>(sign);
    }
    if (exp <= 0) return static_cast<uint16_t>(sign);        // underflow → ±0
    if (exp >= 31) return static_cast<uint16_t>(sign | 0x7C00); // overflow → ±Inf
    return static_cast<uint16_t>(sign | (exp << 10) | (mant >> 13));
}

static float fp16_to_float(uint16_t h) {
    uint32_t sign = static_cast<uint32_t>(h & 0x8000) << 16;
    uint32_t exp  = (h >> 10) & 0x1F;
    uint32_t mant = h & 0x3FF;

    uint32_t result_bits;
    if (exp == 0) {
        if (mant == 0) {
            result_bits = sign;  // ±0
        } else {
            // Denorm → normalized FP32
            int e = 0;
            while (!(mant & 0x400)) { mant <<= 1; e++; }
            mant &= 0x3FF;
            result_bits = sign | (static_cast<uint32_t>(127 - 15 + 1 - e) << 23) | (mant << 13);
        }
    } else if (exp == 31) {
        result_bits = sign | 0x7F800000u | (mant << 13);  // Inf/NaN
    } else {
        result_bits = sign | (static_cast<uint32_t>(exp - 15 + 127) << 23) | (mant << 13);
    }
    float result;
    std::memcpy(&result, &result_bits, 4);
    return result;
}

// =============================================================================
// Embedding: wte[token_id] + wpe[position] → FP32 → FP16
// =============================================================================

static void compute_embedding(const EmbedData& ed,
                               const std::vector<int>& token_ids,
                               int start_pos,
                               std::vector<float>& embed_fp32) {
    int seq_len = static_cast<int>(token_ids.size());
    embed_fp32.resize(seq_len * MODEL_DIM);

    for (int s = 0; s < seq_len; ++s) {
        int tid = token_ids[s];
        int pos = start_pos + s;
        assert(tid >= 0 && tid < static_cast<int>(ed.vocab_size));
        assert(pos < static_cast<int>(ed.max_pos));

        const float* wte_row = &ed.wte[tid * MODEL_DIM];
        const float* wpe_row = &ed.wpe[pos * MODEL_DIM];
        float* out = &embed_fp32[s * MODEL_DIM];

        for (int d = 0; d < MODEL_DIM; ++d) {
            out[d] = wte_row[d] + wpe_row[d];
        }
    }
}

static void embed_to_fp16(const std::vector<float>& embed_fp32,
                           uint16_t* act_buf,
                           int seq_len) {
    // Pack FP16 embeddings into activation buffer with MODEL_STRIDE layout
    // Row s at word offset ACT_EMBED_OFFSET + s * MODEL_STRIDE
    for (int s = 0; s < seq_len; ++s) {
        for (int d = 0; d < MODEL_DIM; ++d) {
            float v = embed_fp32[s * MODEL_DIM + d];
            uint16_t fp16 = float_to_fp16(v);

            // Compute byte offset: word_addr * WORD_BYTES + element_in_word * 2
            int word_in_row = d / BUS_ELEMS;
            int elem_in_word = d % BUS_ELEMS;
            size_t byte_offset = static_cast<size_t>(
                (ACT_EMBED_OFFSET + s * MODEL_STRIDE + word_in_row) * WORD_BYTES
                + elem_in_word * 2);

            act_buf[byte_offset / 2] = fp16;
        }
    }
}

// =============================================================================
// Host-side LayerNorm (for ln_f after FPGA output)
// =============================================================================
static void layer_norm(const float* input, float* output, int dim,
                       const float* gamma, const float* beta) {
    // Compute mean
    float mean = 0.0f;
    for (int i = 0; i < dim; ++i) mean += input[i];
    mean /= dim;

    // Compute variance
    float var = 0.0f;
    for (int i = 0; i < dim; ++i) {
        float d = input[i] - mean;
        var += d * d;
    }
    var /= dim;

    // Normalize
    float inv_std = 1.0f / std::sqrt(var + 1e-5f);
    for (int i = 0; i < dim; ++i) {
        output[i] = (input[i] - mean) * inv_std * gamma[i] + beta[i];
    }
}

// =============================================================================
// Unembed: hidden_state (1×1024) × wte^T (1024×50257) → logits
// =============================================================================
static int unembed_argmax(const float* hidden, const EmbedData& ed) {
    int best_id = 0;
    float best_logit = -1e30f;

    for (int v = 0; v < static_cast<int>(ed.vocab_size); ++v) {
        float logit = 0.0f;
        const float* wte_row = &ed.wte[v * MODEL_DIM];
        for (int d = 0; d < MODEL_DIM; ++d) {
            logit += hidden[d] * wte_row[d];
        }
        if (logit > best_logit) {
            best_logit = logit;
            best_id = v;
        }
    }
    return best_id;
}

// Temperature sampling (optional)
static int unembed_sample(const float* hidden, const EmbedData& ed, float temperature) {
    if (temperature <= 0.0f) return unembed_argmax(hidden, ed);

    std::vector<float> logits(ed.vocab_size);
    for (int v = 0; v < static_cast<int>(ed.vocab_size); ++v) {
        float logit = 0.0f;
        const float* wte_row = &ed.wte[v * MODEL_DIM];
        for (int d = 0; d < MODEL_DIM; ++d) {
            logit += hidden[d] * wte_row[d];
        }
        logits[v] = logit / temperature;
    }

    // Softmax
    float max_l = *std::max_element(logits.begin(), logits.end());
    float sum = 0.0f;
    for (auto& l : logits) {
        l = std::exp(l - max_l);
        sum += l;
    }
    for (auto& l : logits) l /= sum;

    // Sample
    float r = static_cast<float>(rand()) / RAND_MAX;
    float cumsum = 0.0f;
    for (int v = 0; v < static_cast<int>(ed.vocab_size); ++v) {
        cumsum += logits[v];
        if (r <= cumsum) return v;
    }
    return static_cast<int>(ed.vocab_size) - 1;
}

// =============================================================================
// Read FPGA output from activation buffer (FP16) and convert to FP32
// =============================================================================
// After all layers, the final residual2 output is flushed to ACT_EMBED in
// the activation buffer (step 14 of the step table). S_OUTPUT_COPY is skipped
// because the flush port (hbm12) can only reach the activation bank (HBM[4]).
static void read_output_fp32(const uint16_t* act_buf, int seq_pos,
                              float* hidden_fp32) {
    // Output is at ACT_EMBED_OFFSET + seq_pos * MODEL_STRIDE
    for (int d = 0; d < MODEL_DIM; ++d) {
        int word_in_row = d / BUS_ELEMS;
        int elem_in_word = d % BUS_ELEMS;
        size_t byte_offset = static_cast<size_t>(
            (ACT_EMBED_OFFSET + seq_pos * MODEL_STRIDE + word_in_row) * WORD_BYTES
            + elem_in_word * 2);

        uint16_t raw = act_buf[byte_offset / 2];
        hidden_fp32[d] = fp16_to_float(raw);
    }
}

// =============================================================================
// HBM Activation Region Checker — shows which flush stages have completed
// =============================================================================
// GPT-2 pre-norm step order and flush targets:
//   Step 0:  LN1          (no flush yet)
//   Step 1:  flush LN1     → ACT_TEMP
//   Step 2:  QKV matmul    → Q/K/V regions (3 internal flushes)
//   Step 3:  attention     → ATT scores → ACT_ATTN, ATT output → ACT_Q+head offsets
//   Step 4:  proj matmul   (result in URAM)
//   Step 5:  residual1     (result in URAM)
//   Step 6:  flush res1    → ACT_EMBED
//   Step 7:  LN2           (no flush yet)
//   Step 8:  flush LN2     → ACT_TEMP
//   Step 9:  FFN1 matmul   (result in URAM)
//   Step 10: ReLU          (result in URAM)
//   Step 11: flush act     → ACT_FFN (=0, overlaps ACT_EMBED)
//   Step 12: FFN2 matmul   (result in URAM)
//   Step 13: residual2     (result in URAM)
//   Step 14: flush res2    → ACT_EMBED
//   Step 15: END

struct ActRegion {
    const char* name;
    int word_offset;    // relative to act_base (in 256-bit words)
    int num_words;      // how many words to sample
};

static const ActRegion ACT_REGIONS[] = {
    {"EMBED",  0,                                               8},
    {"Q",      MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS,            8},
    {"K",      2 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS,        8},
    {"V",      3 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS,        8},
    {"ATTN",   4 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS,        8},
    {"TEMP",   5 * MAX_SEQ_LEN * MODEL_DIM / BUS_ELEMS,        8},
};
static constexpr int NUM_ACT_REGIONS = sizeof(ACT_REGIONS) / sizeof(ACT_REGIONS[0]);

// Check if a region has non-zero data (sample first num_words 256-bit words)
static bool region_has_data(const uint16_t* act_buf, int word_offset, int num_words) {
    for (int w = 0; w < num_words; ++w) {
        // Each 256-bit word = 16 FP16 elements
        size_t base_idx = static_cast<size_t>((word_offset + w) * WORD_BYTES / 2);
        for (int e = 0; e < BUS_ELEMS; ++e) {
            if (act_buf[base_idx + e] != 0) return true;
        }
    }
    return false;
}

// Compute a simple fingerprint (sum of absolute values of first N elements as FP16)
static int64_t region_fingerprint(const uint16_t* act_buf, int word_offset, int num_words) {
    int64_t sum = 0;
    for (int w = 0; w < num_words; ++w) {
        size_t base_idx = static_cast<size_t>((word_offset + w) * WORD_BYTES / 2);
        for (int e = 0; e < BUS_ELEMS; ++e) {
            // Use magnitude of FP16 value (clear sign bit)
            sum += static_cast<int64_t>(act_buf[base_idx + e] & 0x7FFF);
        }
    }
    return sum;
}

static void dump_activation_progress(xrt::bo& bo_act, const uint16_t* act_buf) {
    // Sync activation buffer back from device
    bo_act.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

    std::cout << "  [ACT HBM] ";
    for (int r = 0; r < NUM_ACT_REGIONS; ++r) {
        bool has = region_has_data(act_buf, ACT_REGIONS[r].word_offset,
                                   ACT_REGIONS[r].num_words);
        int64_t fp = has ? region_fingerprint(act_buf, ACT_REGIONS[r].word_offset,
                                               ACT_REGIONS[r].num_words) : 0;
        std::cout << ACT_REGIONS[r].name << "="
                  << (has ? std::to_string(fp) : "empty") << " ";
    }
    std::cout << "\n";
    std::cout.flush();
}

// =============================================================================
// File loading helper
// =============================================================================
static bool load_file(const char* path, std::vector<char>& buf) {
    std::ifstream ifs(path, std::ios::binary | std::ios::ate);
    if (!ifs.is_open()) return false;
    size_t sz = ifs.tellg();
    ifs.seekg(0);
    buf.resize(sz);
    ifs.read(buf.data(), sz);
    return true;
}

// =============================================================================
// Main
// =============================================================================
int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0]
                  << " <xclbin> <data_dir> [\"prompt\"] [max_tokens] [temperature]\n"
                  << "\n"
                  << "  data_dir must contain: weights.bin, embed.bin, vocab.json, merges.txt\n"
                  << "  Default prompt: \"The meaning of life is\"\n"
                  << "  Default max_tokens: 50\n"
                  << "  Default temperature: 0.0 (greedy)\n";
        return 1;
    }

    const char* xclbin_path = argv[1];
    std::string data_dir = argv[2];
    std::string prompt = (argc > 3) ? argv[3] : "The meaning of life is";
    int max_tokens = (argc > 4) ? std::atoi(argv[4]) : 50;
    float temperature = (argc > 5) ? std::atof(argv[5]) : 0.0f;

    // Override NUM_LAYERS from environment (e.g. NUM_LAYERS=2 ./host ...)
    if (const char* nl_env = std::getenv("NUM_LAYERS")) {
        NUM_LAYERS = std::atoi(nl_env);
        if (NUM_LAYERS < 1 || NUM_LAYERS > 24) {
            std::cerr << "ERROR: NUM_LAYERS must be 1..24, got " << NUM_LAYERS << "\n";
            return 1;
        }
    }
    std::cout << "NUM_LAYERS = " << NUM_LAYERS << "\n";
    WEIGHT_BUF_SIZE = LAYER_SIZE * NUM_LAYERS * WORD_BYTES;
    ACT_BUF_SIZE    = (ACT_SCRATCH_WORDS + NUM_LAYERS * KV_LAYER_SIZE) * WORD_BYTES;

    // Ensure data_dir ends with /
    if (!data_dir.empty() && data_dir.back() != '/') data_dir += '/';

    // -----------------------------------------------------------------
    // Load tokenizer
    // -----------------------------------------------------------------
    std::cout << "Loading tokenizer...\n";
    GPT2Tokenizer tokenizer(data_dir + "vocab.json", data_dir + "merges.txt");
    int eot = tokenizer.eot_token();
    std::cout << "  Vocab size: " << tokenizer.vocab_size() << ", EOT token: " << eot << "\n";

    // -----------------------------------------------------------------
    // Tokenize prompt
    // -----------------------------------------------------------------
    auto prompt_ids = tokenizer.encode(prompt);
    int prompt_len = static_cast<int>(prompt_ids.size());
    std::cout << "Prompt: \"" << prompt << "\"\n";
    std::cout << "  Tokens (" << prompt_len << "): [";
    for (int i = 0; i < prompt_len; ++i) {
        if (i > 0) std::cout << ", ";
        std::cout << prompt_ids[i];
    }
    std::cout << "]\n";

    if (prompt_len >= MAX_SEQ_LEN) {
        std::cerr << "ERROR: Prompt length " << prompt_len
                  << " exceeds MAX_SEQ_LEN " << MAX_SEQ_LEN << "\n";
        return 1;
    }

    // -----------------------------------------------------------------
    // Load embedding data
    // -----------------------------------------------------------------
    std::cout << "Loading embeddings...\n";
    EmbedData ed;
    if (!load_embed(data_dir + "embed.bin", ed)) {
        std::cerr << "ERROR: Cannot load " << data_dir << "embed.bin\n";
        return 1;
    }
    std::cout << "  wte: " << ed.vocab_size << "x" << ed.model_dim
              << ", wpe: " << ed.max_pos << "x" << ed.model_dim << "\n";

    // -----------------------------------------------------------------
    // Open FPGA device and load xclbin
    // -----------------------------------------------------------------
    std::cout << "Opening device 1 (U280)...\n";
    xrt::device device(1);  // device 0 is U200, device 1 is U280

    std::cout << "Loading xclbin: " << xclbin_path << "\n";
    auto uuid = device.load_xclbin(xclbin_path);

    std::cout << "Creating kernel handle...\n";
    xrt::kernel kernel(device, uuid, "fpga_kernel");

    // -----------------------------------------------------------------
    // Allocate device buffers
    // -----------------------------------------------------------------
    std::cout << "Allocating buffers...\n";
    std::cout << "  Weight: " << WEIGHT_BUF_SIZE / (1024*1024) << " MB\n";
    std::cout << "  Act:    " << ACT_BUF_SIZE / (1024*1024) << " MB\n";
    std::cout << "  Output: " << OUTPUT_BUF_SIZE / (1024*1024) << " MB\n";

    xrt::bo bo_weight(device, WEIGHT_BUF_SIZE, kernel.group_id(2));
    xrt::bo bo_act   (device, ACT_BUF_SIZE,    kernel.group_id(4));
    xrt::bo bo_output(device, OUTPUT_BUF_SIZE,  kernel.group_id(7));

    auto weight_map = bo_weight.map<char*>();
    auto act_map    = bo_act.map<uint16_t*>();
    auto output_map = bo_output.map<int16_t*>();

    // -----------------------------------------------------------------
    // Load weights
    // -----------------------------------------------------------------
    std::cout << "Loading weights...\n";
    {
        std::vector<char> wdata;
        if (!load_file((data_dir + "weights.bin").c_str(), wdata)) {
            std::cerr << "ERROR: Cannot load " << data_dir << "weights.bin\n";
            return 1;
        }
        size_t copy_size = std::min(wdata.size(), WEIGHT_BUF_SIZE);
        std::memcpy(weight_map, wdata.data(), copy_size);
        std::cout << "  Loaded " << copy_size / (1024*1024) << " MB\n";
    }

    std::cout << "Syncing weights to device...\n";
    bo_weight.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    // -----------------------------------------------------------------
    // Prefill: embed all prompt tokens → run kernel → get last logit
    // -----------------------------------------------------------------
    std::cout << "\n=== Prefill (" << prompt_len << " tokens) ===\n";

    // Compute embeddings
    std::vector<float> embed_fp32;
    compute_embedding(ed, prompt_ids, 0, embed_fp32);

    // Clear and fill activation buffer
    std::memset(act_map, 0, ACT_BUF_SIZE);
    embed_to_fp16(embed_fp32, act_map, prompt_len);

    bo_act.sync(XCL_BO_SYNC_BO_TO_DEVICE);

    // Run kernel: prefill mode
    uint32_t batch_size  = 1;
    uint32_t seq_len     = static_cast<uint32_t>(prompt_len);
    uint32_t decode_mode = 0;
    uint32_t cache_len   = 0;
    // KV cache starts right after activation scratch, within bo_act
    uint32_t kv_base     = static_cast<uint32_t>((bo_act.address() >> 5) + ACT_SCRATCH_WORDS);

    std::cout << "Running kernel (prefill): batch=" << batch_size
              << " seq=" << seq_len << "\n";

    std::cout << "  wgt_addr=0x" << std::hex << bo_weight.address()
              << " act_addr=0x" << bo_act.address()
              << " out_addr=0x" << bo_output.address() << std::dec << "\n";

    // Debug: verify kv_base address calculation
    std::cout << "  bo_act.address() = 0x" << std::hex << bo_act.address()
              << " (aligned=" << ((bo_act.address() & 0x1F) == 0 ? "yes" : "NO") << ")\n"
              << "  bo_act.address()>>5 = 0x" << (bo_act.address() >> 5)
              << " ACT_SCRATCH_WORDS=" << std::dec << ACT_SCRATCH_WORDS
              << " kv_base=0x" << std::hex << kv_base << std::dec << "\n";

    auto t0 = std::chrono::high_resolution_clock::now();
    uint32_t num_layers_arg = static_cast<uint32_t>(NUM_LAYERS);
    // Debug trace: put it at the end of the output buffer (word-addressed)
    uint32_t debug_base = static_cast<uint32_t>(bo_output.address() >> 5);
    std::cout << "  debug_base=0x" << std::hex << debug_base << std::dec << "\n";
    auto run = kernel(batch_size, seq_len,
                      bo_weight, bo_weight,
                      bo_act, bo_act, bo_act,
                      bo_output,
                      decode_mode, cache_len,
                      kv_base, num_layers_arg,
                      debug_base);

    // Poll forever (Ctrl+C to stop) — print status every 1s, dump HBM every 5s
    bool timed_out = true;
    for (int p = 0; ; ++p) {
        auto state = run.wait(std::chrono::milliseconds(1000));
        auto elapsed = std::chrono::duration<double>(
            std::chrono::high_resolution_clock::now() - t0).count();
        std::cout << "  Poll[" << p << "] " << elapsed << "s: ert="
                  << static_cast<int>(state) << "\n";
        std::cout.flush();
        if (state == ERT_CMD_STATE_COMPLETED) {
            timed_out = false;
            break;
        }
        if (state == ERT_CMD_STATE_ERROR || state == ERT_CMD_STATE_ABORT) {
            std::cerr << "ERROR: Kernel error state: " << static_cast<int>(state) << "\n";
            return 1;
        }
        // Every 5 polls (~5s), read HBM to show progress
        if (p % 5 == 4) {
            dump_activation_progress(bo_act, act_map);
        }
    }
    auto t1 = std::chrono::high_resolution_clock::now();
    double prefill_ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    std::cout << "  Prefill done in " << prefill_ms << " ms\n";

    // Read output from activation buffer (final res2 is at ACT_EMBED)
    bo_act.sync(XCL_BO_SYNC_BO_FROM_DEVICE);

    // Read and print debug trace from output buffer
    bo_output.sync(XCL_BO_SYNC_BO_FROM_DEVICE);
    {
        std::cout << "\n=== Debug Trace ===\n";
        // Each debug record is 256 bits = 16 x int16 = 32 bytes
        // Read up to 512 records (covers 24 layers × 16 steps + DONE)
        for (int rec = 0; rec < 512; ++rec) {
            uint32_t cycle = static_cast<uint32_t>(output_map[rec * 16 + 0]) |
                             (static_cast<uint32_t>(static_cast<uint16_t>(output_map[rec * 16 + 1])) << 16);
            uint16_t layer = static_cast<uint16_t>(output_map[rec * 16 + 2]);
            uint8_t  state = static_cast<uint8_t>(output_map[rec * 16 + 3] & 0xFF);
            uint8_t  step  = static_cast<uint8_t>((output_map[rec * 16 + 3] >> 8) & 0xFF);
            uint8_t  bt    = static_cast<uint8_t>(output_map[rec * 16 + 4] & 0xFF);
            uint8_t  cfg   = static_cast<uint8_t>((output_map[rec * 16 + 4] >> 8) & 0xFF);
            if (cycle == 0 && layer == 0 && state == 0 && step == 0)
                break;  // empty record — end of trace
            const char* sname = (state < 17) ? FSM_NAMES[state] : "???";
            std::cout << "  [" << rec << "] cyc=" << cycle
                      << " L" << layer << " " << sname
                      << " step=" << (int)step
                      << " bt=" << (int)bt << " cfg=" << (int)cfg;
            if (step == 0xFF)
                std::cout << " <<DONE>>";
            std::cout << "\n";
        }
        std::cout << "===================\n\n";
    }

    // Verify all layers completed by checking KV cache per layer
    // Each layer writes K/V to a unique address during QKV (step 2).
    // KV region starts at ACT_SCRATCH_WORDS within bo_act.
    std::cout << "  KV cache check:";
    for (int l = 0; l < NUM_LAYERS; ++l) {
        // Layer l's K starts at ACT_SCRATCH_WORDS + l * KV_LAYER_SIZE
        int kv_word_offset = ACT_SCRATCH_WORDS + l * KV_LAYER_SIZE;
        bool has = region_has_data(act_map, kv_word_offset, 4);
        if (!has) {
            std::cout << " L" << l << "=EMPTY";
        }
    }
    bool last_layer_kv = region_has_data(act_map, ACT_SCRATCH_WORDS + (NUM_LAYERS - 1) * KV_LAYER_SIZE, 4);
    bool embed_has_data = region_has_data(act_map, ACT_EMBED_OFFSET, 4);
    if (last_layer_kv && embed_has_data) {
        std::cout << " ALL " << NUM_LAYERS << " LAYERS OK\n";
    } else {
        std::cout << " INCOMPLETE (L" << NUM_LAYERS - 1 << "_KV="
                  << (last_layer_kv ? "yes" : "no") << " embed="
                  << (embed_has_data ? "yes" : "no") << ")\n";
    }

    std::vector<float> hidden(MODEL_DIM);
    std::vector<float> normed(MODEL_DIM);

    // Last position = prompt_len - 1
    read_output_fp32(act_map, prompt_len - 1, hidden.data());

    // Apply ln_f
    layer_norm(hidden.data(), normed.data(), MODEL_DIM,
               ed.ln_f_g.data(), ed.ln_f_b.data());

    // Unembed and get first generated token
    int next_token = (temperature > 0.0f)
        ? unembed_sample(normed.data(), ed, temperature)
        : unembed_argmax(normed.data(), ed);

    // Dump raw FP16 values from last position for debugging
    std::cout << "\n--- Raw FP16 output (last position, first 32 of " << MODEL_DIM << ") ---\n";
    {
        int last_pos = prompt_len - 1;
        int base = last_pos * MODEL_STRIDE;
        for (int i = 0; i < 32 && i < MODEL_DIM; ++i) {
            uint16_t raw = act_map[base + i];
            float val = fp16_to_float(raw);
            std::cout << val;
            if (i < 31) std::cout << ", ";
        }
        std::cout << "\n";

        // Check for all-zeros / Inf/NaN
        int zeros = 0, inf_nan = 0;
        for (int i = 0; i < MODEL_DIM; ++i) {
            uint16_t raw = act_map[base + i];
            if (raw == 0 || raw == 0x8000) zeros++;
            if ((raw & 0x7C00) == 0x7C00) inf_nan++;
        }
        std::cout << "  zeros=" << zeros << "/" << MODEL_DIM
                  << " inf_nan=" << inf_nan << "/" << MODEL_DIM << "\n";
    }

    // Print prompt and first predicted token (prefill only, no decode)
    std::cout << "\n--- Generated Text (prefill only) ---\n";
    std::cout << prompt;
    std::string tok_text = tokenizer.decode({next_token});
    std::cout << tok_text;
    std::cout << "\n--- End (prefill only, decode disabled for ILA debugging) ---\n";

    return 0;
}
