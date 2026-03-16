#pragma once
// =============================================================================
// gpt2_bpe.h — Lightweight GPT-2 BPE Tokenizer (C++17, header-only)
// =============================================================================
//
// Load vocab.json + merges.txt from HuggingFace GPT-2 tokenizer files.
// Implements byte-level BPE encoding and decoding.
//
// Usage:
//   GPT2Tokenizer tok("path/to/vocab.json", "path/to/merges.txt");
//   auto ids = tok.encode("Hello, world!");
//   std::string text = tok.decode(ids);
// =============================================================================

#include <algorithm>
#include <cassert>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <regex>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

// ---------------------------------------------------------------------------
// Minimal JSON string parser (handles vocab.json: {"token": id, ...})
// ---------------------------------------------------------------------------
namespace gpt2_detail {

inline void skip_ws(const std::string& s, size_t& i) {
    while (i < s.size() && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t'))
        ++i;
}

inline std::string parse_json_string(const std::string& s, size_t& i) {
    assert(s[i] == '"');
    ++i;
    std::string out;
    while (i < s.size() && s[i] != '"') {
        if (s[i] == '\\') {
            ++i;
            switch (s[i]) {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'n':  out += '\n'; break;
                case 'r':  out += '\r'; break;
                case 't':  out += '\t'; break;
                case 'u': {
                    // Parse 4-hex-digit unicode escape
                    std::string hex = s.substr(i + 1, 4);
                    uint32_t cp = std::stoul(hex, nullptr, 16);
                    i += 4;
                    if (cp < 0x80) {
                        out += static_cast<char>(cp);
                    } else if (cp < 0x800) {
                        out += static_cast<char>(0xC0 | (cp >> 6));
                        out += static_cast<char>(0x80 | (cp & 0x3F));
                    } else {
                        out += static_cast<char>(0xE0 | (cp >> 12));
                        out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                        out += static_cast<char>(0x80 | (cp & 0x3F));
                    }
                    break;
                }
                default: out += s[i]; break;
            }
        } else {
            out += s[i];
        }
        ++i;
    }
    ++i; // skip closing "
    return out;
}

inline int parse_json_int(const std::string& s, size_t& i) {
    size_t start = i;
    if (s[i] == '-') ++i;
    while (i < s.size() && s[i] >= '0' && s[i] <= '9') ++i;
    return std::stoi(s.substr(start, i - start));
}

// Parse vocab.json: {"token_string": integer_id, ...}
inline std::unordered_map<std::string, int> parse_vocab_json(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open()) {
        std::cerr << "ERROR: Cannot open vocab file: " << path << "\n";
        std::exit(1);
    }
    std::string content((std::istreambuf_iterator<char>(f)),
                         std::istreambuf_iterator<char>());
    f.close();

    std::unordered_map<std::string, int> vocab;
    size_t i = 0;
    skip_ws(content, i);
    assert(content[i] == '{'); ++i;

    while (true) {
        skip_ws(content, i);
        if (content[i] == '}') break;
        if (content[i] == ',') { ++i; skip_ws(content, i); }

        std::string key = parse_json_string(content, i);
        skip_ws(content, i);
        assert(content[i] == ':'); ++i;
        skip_ws(content, i);
        int val = parse_json_int(content, i);
        vocab[key] = val;
    }
    return vocab;
}

// GPT-2 byte-to-unicode mapping
inline std::unordered_map<uint8_t, std::string>& byte_encoder() {
    static std::unordered_map<uint8_t, std::string> enc;
    static bool init = false;
    if (!init) {
        init = true;
        // Printable byte ranges that map to themselves as unicode chars
        // From openai/gpt-2 encoder.py bytes_to_unicode()
        std::vector<int> bs;
        for (int b = '!'; b <= '~'; ++b) bs.push_back(b);
        for (int b = 0xA1; b <= 0xAC; ++b) bs.push_back(b);
        for (int b = 0xAE; b <= 0xFF; ++b) bs.push_back(b);

        std::vector<int> cs(bs.begin(), bs.end());
        int n = 0;
        for (int b = 0; b < 256; ++b) {
            if (std::find(bs.begin(), bs.end(), b) == bs.end()) {
                bs.push_back(b);
                cs.push_back(256 + n);
                ++n;
            }
        }
        for (size_t j = 0; j < bs.size(); ++j) {
            // Convert unicode codepoint to UTF-8
            int cp = cs[j];
            std::string s;
            if (cp < 0x80) {
                s += static_cast<char>(cp);
            } else if (cp < 0x800) {
                s += static_cast<char>(0xC0 | (cp >> 6));
                s += static_cast<char>(0x80 | (cp & 0x3F));
            } else {
                s += static_cast<char>(0xE0 | (cp >> 12));
                s += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
                s += static_cast<char>(0x80 | (cp & 0x3F));
            }
            enc[static_cast<uint8_t>(bs[j])] = s;
        }
    }
    return enc;
}

inline std::unordered_map<std::string, uint8_t>& byte_decoder() {
    static std::unordered_map<std::string, uint8_t> dec;
    static bool init = false;
    if (!init) {
        init = true;
        auto& enc = byte_encoder();
        for (auto& kv : enc) dec[kv.second] = kv.first;
    }
    return dec;
}

} // namespace gpt2_detail


// ---------------------------------------------------------------------------
// GPT2Tokenizer
// ---------------------------------------------------------------------------
class GPT2Tokenizer {
public:
    GPT2Tokenizer(const std::string& vocab_path, const std::string& merges_path) {
        // Load vocab
        encoder_ = gpt2_detail::parse_vocab_json(vocab_path);
        for (auto& kv : encoder_) {
            decoder_[kv.second] = kv.first;
        }

        // Load merges
        std::ifstream mf(merges_path);
        if (!mf.is_open()) {
            std::cerr << "ERROR: Cannot open merges file: " << merges_path << "\n";
            std::exit(1);
        }
        std::string line;
        std::getline(mf, line); // skip header "#version: ..."
        int rank = 0;
        while (std::getline(mf, line)) {
            if (line.empty()) continue;
            auto sp = line.find(' ');
            if (sp == std::string::npos) continue;
            std::string a = line.substr(0, sp);
            std::string b = line.substr(sp + 1);
            bpe_ranks_[{a, b}] = rank++;
        }
        mf.close();

        // GPT-2 tokenization regex (portable pattern without \p{} classes)
        pat_ = std::regex(
            R"('s|'t|'re|'ve|'m|'ll|'d| ?[a-zA-Z]+| ?[0-9]+| ?[^ \t\na-zA-Z0-9]+|[ \t\n]+)",
            std::regex::optimize);
        pat_simple_ = pat_;
    }

    // Encode text to token IDs
    std::vector<int> encode(const std::string& text) const {
        std::vector<int> ids;
        auto& benc = gpt2_detail::byte_encoder();

        // Tokenize with regex
        auto words_begin = std::sregex_iterator(text.begin(), text.end(), pat_simple_);
        auto words_end = std::sregex_iterator();

        for (auto it = words_begin; it != words_end; ++it) {
            std::string word = it->str();

            // Convert bytes to unicode tokens
            std::string encoded_word;
            for (unsigned char c : word) {
                encoded_word += benc.at(c);
            }

            // Apply BPE
            auto bpe_tokens = bpe(encoded_word);

            for (auto& tok : bpe_tokens) {
                auto eit = encoder_.find(tok);
                if (eit != encoder_.end()) {
                    ids.push_back(eit->second);
                }
            }
        }
        return ids;
    }

    // Decode token IDs to text
    std::string decode(const std::vector<int>& ids) const {
        auto& bdec = gpt2_detail::byte_decoder();

        std::string text;
        for (int id : ids) {
            auto dit = decoder_.find(id);
            if (dit == decoder_.end()) continue;
            const std::string& tok = dit->second;
            // Convert unicode chars back to bytes
            // Process multi-byte UTF-8 sequences
            size_t i = 0;
            while (i < tok.size()) {
                // Determine UTF-8 char length
                size_t len = 1;
                unsigned char c = tok[i];
                if ((c & 0xE0) == 0xC0) len = 2;
                else if ((c & 0xF0) == 0xE0) len = 3;
                else if ((c & 0xF8) == 0xF0) len = 4;

                std::string ch = tok.substr(i, len);
                auto bdit = bdec.find(ch);
                if (bdit != bdec.end()) {
                    text += static_cast<char>(bdit->second);
                } else {
                    text += ch; // pass through
                }
                i += len;
            }
        }
        return text;
    }

    int vocab_size() const { return static_cast<int>(encoder_.size()); }

    // Special token IDs
    int eot_token() const {
        auto it = encoder_.find("<|endoftext|>");
        return (it != encoder_.end()) ? it->second : -1;
    }

private:
    // BPE merge on a single word (as unicode-encoded string)
    std::vector<std::string> bpe(const std::string& token) const {
        // Split token into individual unicode characters
        std::vector<std::string> word;
        size_t i = 0;
        while (i < token.size()) {
            size_t len = 1;
            unsigned char c = token[i];
            if ((c & 0xE0) == 0xC0) len = 2;
            else if ((c & 0xF0) == 0xE0) len = 3;
            else if ((c & 0xF8) == 0xF0) len = 4;
            word.push_back(token.substr(i, len));
            i += len;
        }

        if (word.size() <= 1) return word;

        while (true) {
            // Find the lowest-rank merge pair
            int best_rank = INT32_MAX;
            size_t best_idx = SIZE_MAX;

            for (size_t j = 0; j + 1 < word.size(); ++j) {
                auto it = bpe_ranks_.find({word[j], word[j + 1]});
                if (it != bpe_ranks_.end() && it->second < best_rank) {
                    best_rank = it->second;
                    best_idx = j;
                }
            }

            if (best_idx == SIZE_MAX) break; // no more merges

            // Apply the merge
            std::string merged = word[best_idx] + word[best_idx + 1];
            std::vector<std::string> new_word;
            for (size_t j = 0; j < word.size(); ++j) {
                if (j == best_idx) {
                    new_word.push_back(merged);
                    ++j; // skip next
                } else {
                    new_word.push_back(word[j]);
                }
            }
            word = std::move(new_word);

            if (word.size() == 1) break;
        }

        return word;
    }

    std::unordered_map<std::string, int> encoder_;
    std::unordered_map<int, std::string> decoder_;

    struct PairHash {
        size_t operator()(const std::pair<std::string, std::string>& p) const {
            size_t h1 = std::hash<std::string>{}(p.first);
            size_t h2 = std::hash<std::string>{}(p.second);
            return h1 ^ (h2 * 0x9e3779b97f4a7c15ULL + 0x9e3779b9 + (h1 << 6) + (h1 >> 2));
        }
    };
    std::unordered_map<std::pair<std::string, std::string>, int, PairHash> bpe_ranks_;

    std::regex pat_;
    std::regex pat_simple_;
};
