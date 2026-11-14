// Scope and prefetch limit, source-preserving TOML editing using toml++ v3.4.0 (MIT).
#include "../ThirdParty/tomlplusplus/toml.hpp"
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
#include <algorithm>

static std::string render(const toml::node& n) {
    std::ostringstream out; out << toml::toml_formatter{n}; return out.str();
}
static size_t offset(const std::string& text, toml::source_position pos) {
    size_t i = 0; unsigned line = 1, column = 1;
    while (i < text.size() && line < pos.line) if (text[i++] == '\n') ++line;
    while (i < text.size() && column < pos.column) {
        ++i; while (i < text.size() && (static_cast<unsigned char>(text[i]) & 0xc0) == 0x80) ++i;
        ++column;
    }
    if (line != pos.line || column != pos.column) throw std::runtime_error("invalid TOML source region");
    return i;
}
int main(int argc, char** argv) {
    try {
        if (argc != 2) throw std::runtime_error("expected a configuration snapshot");
        std::ifstream file(argv[1], std::ios::binary);
        if (!file) throw std::runtime_error("cannot read configuration snapshot");
        std::string original((std::istreambuf_iterator<char>(file)), {});
        std::string updates((std::istreambuf_iterator<char>(std::cin)), {});
        auto config = toml::parse(original);
        auto desired = toml::parse(updates);
        static const std::vector<std::string> keys{"index_paths", "exclude", "exclude_paths", "include_hidden", "max_results"};
        if (desired.size() != keys.size()) throw std::runtime_error("unexpected managed fields");
        for (auto& key : keys) {
            auto* value = desired.get(key);
            if (!value) throw std::runtime_error("missing managed field");
            if (key == "max_results") {
                if (!value->is_integer() || value->value<int64_t>().value_or(0) <= 0) throw std::runtime_error("expected a positive result limit");
            } else if (key == "include_hidden") {
                if (!value->is_boolean()) throw std::runtime_error("expected a boolean");
            } else {
                if (!value->is_array()) throw std::runtime_error("expected a string array");
                for (auto& item : *value->as_array()) if (!item.is_string()) throw std::runtime_error("expected a string array");
            }
        }
        struct Edit { size_t start, end; std::string text; };
        std::vector<Edit> edits;
        auto* indexNode = config.get("index");
        auto* index = indexNode ? indexNode->as_table() : nullptr;
        if (indexNode && (!index || index->is_inline())) throw std::runtime_error("[index] must be a standard table; original file was not changed");
        std::string missing;
        for (auto& key : keys) {
            auto* value = desired.get(key);
            if (auto* current = index ? index->get(key) : nullptr) {
                if (render(*current) == render(*value)) continue;
                auto region = current->source();
                edits.push_back({offset(original, region.begin), offset(original, region.end), render(*value)});
            } else { missing += key + " = " + render(*value) + "\n"; }
        }
        if (!missing.empty()) {
            if (!index) {
                edits.push_back({original.size(), original.size(), "\n[index]\n" + missing});
            } else {
                size_t begin = offset(original, index->source().begin);
                if (begin >= original.size() || original[begin] != '[') throw std::runtime_error("cannot locate explicit [index] header; original file was not changed");
                size_t at = original.find('\n', begin);
                if (at == std::string::npos) edits.push_back({original.size(), original.size(), "\n" + missing});
                else edits.push_back({at + 1, at + 1, missing});
            }
        }
        std::sort(edits.begin(), edits.end(), [](auto& a, auto& b) { return a.start > b.start; });
        auto result = original;
        for (auto& edit : edits) result.replace(edit.start, edit.end - edit.start, edit.text);
        auto validated = toml::parse(result);
        for (auto& key : keys) {
            auto* actual = validated["index"].as_table()->get(key);
            if (!actual || render(*actual) != render(*desired.get(key))) throw std::runtime_error("scope verification failed");
        }
        std::cout << result;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n'; return 1;
    }
}
