#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <numeric>
#include <random>
#include <stdexcept>
#include <vector>

constexpr int table_step = 128;
constexpr int table_end = 16 * table_step;
constexpr int max_degree = 160;
constexpr int labels = 32;
constexpr int slot_count = 5;

struct Graph {
    int n, k, transmitted;
    std::vector<int> offsets, variables;
};

struct Config {
    int iterations, demap_period, shuffle;
    bool min_sum;
    float scale, prior_weight, damp, check_weight, noise;
    uint32_t seed;
};

float jacobian(float magnitude) {
    static const auto values = [] {
        std::array<float, table_end + 1> out{};
        for (int i = 0; i <= table_end; ++i)
            out[i] = std::log1p(std::exp(-static_cast<float>(i) / table_step));
        return out;
    }();
    float index = magnitude * table_step;
    if (index >= table_end) return 0;
    int left = static_cast<int>(index);
    return values[left] + (index-left) * (values[left+1]-values[left]);
}

float log_add(float a, float b) {
    return std::max(a, b) + jacobian(std::fabs(a-b));
}

float box(float a, float b) {
    float magnitude = std::min(std::fabs(a), std::fabs(b));
    float signed_min = ((a < 0) != (b < 0)) ? -magnitude : magnitude;
    return signed_min + jacobian(std::fabs(a+b)) - jacobian(std::fabs(a-b));
}

Graph read_graph(const char* path) {
    std::ifstream f(path, std::ios::binary);
    int checks, edges;
    Graph g{};
    f.read(reinterpret_cast<char*>(&g.n), sizeof(int));
    f.read(reinterpret_cast<char*>(&g.k), sizeof(int));
    f.read(reinterpret_cast<char*>(&g.transmitted), sizeof(int));
    f.read(reinterpret_cast<char*>(&checks), sizeof(int));
    f.read(reinterpret_cast<char*>(&edges), sizeof(int));
    if (!f || g.n < g.transmitted || g.k <= 0 || checks <= 0 || edges <= 0)
        throw std::runtime_error("Invalid Tanner graph dimensions");
    g.offsets.resize(checks+1);
    g.variables.resize(edges);
    f.read(reinterpret_cast<char*>(g.offsets.data()), sizeof(int) * g.offsets.size());
    f.read(reinterpret_cast<char*>(g.variables.data()), sizeof(int) * g.variables.size());
    if (!f || g.offsets.front() != 0 || g.offsets.back() != edges)
        throw std::runtime_error("Truncated Tanner graph");
    for (int check = 0; check < checks; ++check) {
        int degree = g.offsets[check+1]-g.offsets[check];
        if (degree < 2 || degree > max_degree) throw std::runtime_error("Unexpected check degree");
    }
    for (int variable : g.variables)
        if (variable < 0 || variable >= g.n) throw std::runtime_error("Invalid variable");
    return g;
}

std::vector<float> read_metrics(const char* path, int symbols) {
    std::vector<float> values(symbols * labels);
    std::ifstream f(path, std::ios::binary);
    f.read(reinterpret_cast<char*>(values.data()), sizeof(float) * values.size());
    if (!f || f.peek() != std::ifstream::traits_type::eof()) throw std::runtime_error("Expected dense symbol metrics");
    for (float value : values)
        if (!std::isfinite(value)) throw std::runtime_error("Nonfinite metric");
    return values;
}

int syndrome(const Graph& g, const std::vector<float>& beliefs) {
    int failed = 0;
    for (size_t row = 0; row + 1 < g.offsets.size(); ++row) {
        bool parity = false;
        for (int edge = g.offsets[row]; edge < g.offsets[row+1]; ++edge)
            parity ^= beliefs[g.variables[edge]] < 0;
        failed += parity;
    }
    return failed;
}

void update_symbol_messages(const Graph& g, const Config& config,
                            const std::vector<float>& metrics, const std::vector<float>& offset,
                            bool initial, std::vector<float>& channel, std::vector<float>& beliefs) {
    const int erased = g.n - g.transmitted;
    for (int start = 0, symbol = 0; start < g.transmitted; start += slot_count, ++symbol) {
        std::array<int, slot_count> variable{};
        std::array<float, slot_count> prior{};
        std::array<float, labels> score{};
        int count = std::min(slot_count, g.transmitted-start);
        for (int j = 0; j < count; ++j) {
            int tx = start + j;
            variable[j] = tx < g.k ? tx : tx+erased;
            if (!initial) {
                int v = variable[j];
                prior[j] = config.prior_weight * std::clamp(beliefs[v]-channel[v], -28.f, 28.f);
            }
        }
        for (int code = 0; code < labels; ++code) {
            float s = config.scale * metrics[symbol*labels+code];
            for (int j = 0; j < count; ++j)
                if ((code>>j) & 1) s -= prior[j];
            score[code] = s;
        }
        for (int j = 0; j < count; ++j) {
            float zero = -1.e8f, one = -1.e8f;
            for (int code = 0; code < labels; ++code) {
                float& side = ((code>>j) & 1) ? one : zero;
                side = log_add(side, score[code]);
            }
            int v = variable[j];
            float target = std::clamp(zero-one-prior[j], -45.f, 45.f) + offset[v];
            float delta = (initial ? 1.f : config.damp) * (target-channel[v]);
            channel[v] += delta;
            beliefs[v] += delta;
        }
    }
}

void decode_check(const Graph& g, const Config& config, int row,
                  std::vector<float>& beliefs, std::vector<float>& messages) {
    const int from = g.offsets[row], degree = g.offsets[row+1]-from;
    std::array<float, max_degree> q, forward, reverse;
    for (int j = 0; j < degree; ++j)
        q[j] = std::clamp(beliefs[g.variables[from+j]] - messages[from+j], -45.f, 45.f);
    if (config.min_sum) {
        float first = 46.f, second = 46.f;
        int i_min = -1;
        bool parity = false;
        for (int j = 0; j < degree; ++j) {
            const float mag = std::fabs(q[j]);
            parity ^= q[j] < 0;
            if (mag < first) {
                second = first;
                first = mag;
                i_min = j;
            } else {
                second = std::min(second, mag);
            }
        }
        for (int j = 0; j < degree; ++j) {
            const float sign = (parity != (q[j] < 0)) ? -1.f : 1.f;
            forward[j] = sign * (j == i_min ? second : first);
        }
    } else {
        forward[0] = q[0];
        reverse[degree-1] = q[degree-1];
        for (int j = 1; j < degree; ++j) {
            forward[j] = box(forward[j-1], q[j]);
            reverse[degree-1-j] = box(reverse[degree-j], q[degree-1-j]);
        }
        for (int j = degree-1; j > 0; --j)
            forward[j] = j+1 == degree ? forward[j-1] : box(forward[j-1], reverse[j+1]);
        forward[0] = reverse[1];
    }
    for (int j = 0; j < degree; ++j) {
        const int edge = from+j, variable = g.variables[edge];
        float updated = config.check_weight * forward[j];
        beliefs[variable] += updated-messages[edge];
        messages[edge] = updated;
    }
}

#ifndef LDPC_ARCHIVE_WORKER
int main(int argc, char** argv) try {
    if (argc != 14) {
        std::cerr << "graph metrics result iterations demap_period scale prior_weight damp check_weight "
                     "min_sum shuffle seed noise\n";
        return 2;
    }
    Graph g = read_graph(argv[1]);
    auto metrics = read_metrics(argv[2], (g.transmitted+slot_count-1)/slot_count);
    Config c{std::stoi(argv[4]), std::stoi(argv[5]), std::stoi(argv[11]), std::stoi(argv[10]) != 0,
             std::stof(argv[6]), std::stof(argv[7]), std::stof(argv[8]), std::stof(argv[9]),
             std::stof(argv[13]), static_cast<uint32_t>(std::stoul(argv[12]))};
    std::vector<float> channel(g.n), beliefs(g.n), noise(g.n), messages(g.variables.size());
    std::mt19937 rng(c.seed);
    std::normal_distribution<float> normal(0, c.noise);
    if (c.noise > 0)
        for (int i = 0; i < g.n; ++i)
            if (i < g.k || i >= g.k+g.n-g.transmitted) noise[i] = normal(rng);
    std::vector<int> schedule(g.offsets.size()-1);
    std::iota(schedule.begin(), schedule.end(), 0);
    if (c.shuffle) std::shuffle(schedule.begin(), schedule.end(), rng);
    update_symbol_messages(g, c, metrics, noise, true, channel, beliefs);
    int best = syndrome(g, beliefs), best_iter = 0;
    std::vector<float> best_beliefs = beliefs;
    for (int iter = 1; iter <= c.iterations && best; ++iter) {
        if (c.shuffle == 2) std::shuffle(schedule.begin(), schedule.end(), rng);
        for (int row : schedule) decode_check(g, c, row, beliefs, messages);
        int failed = syndrome(g, beliefs);
        if (failed < best) {
            best = failed;
            best_iter = iter;
            best_beliefs = beliefs;
        }
        if (c.demap_period > 0 && iter % c.demap_period == 0)
            update_symbol_messages(g, c, metrics, noise, false, channel, beliefs);
    }
    std::ofstream out(argv[3], std::ios::binary | std::ios::trunc);
    out.write(reinterpret_cast<const char*>(best_beliefs.data()), sizeof(float)*best_beliefs.size());
    if (!out) throw std::runtime_error("Failed writing LDPC output");
    std::cout << best << ' ' << best_iter << '\n';
    return 0;
} catch (const std::exception& e) {
    std::cerr << e.what() << '\n';
    return 2;
}
#endif
