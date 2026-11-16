// Streaming LDPC replay using the check update from the two-frame verifier.
#define LDPC_ARCHIVE_WORKER
#include "mcs92_joint_decoder.cpp"
#include <cstring>
#include <unordered_map>
#if defined(_WIN32) || defined(__CYGWIN__)
#include <fcntl.h>
#include <io.h>
#endif

template<class T>
void receive(T* values, size_t count = 1) {
    if (!std::cin.read(reinterpret_cast<char*>(values), sizeof(T)*count))
        throw std::runtime_error("Incomplete decoder request");
}

template<class T>
void send(const T* values, size_t count = 1) {
    std::cout.write(reinterpret_cast<const char*>(values), sizeof(T)*count);
}

Graph receive_graph() {
    int header[5];
    receive(header, 5);
    int n = header[0], k = header[1], transmitted = header[2];
    int nr = header[3], ne = header[4];
    if (!(0 < k && k < transmitted && transmitted <= n && n <= 32768 &&
          0 < nr && nr <= n && 2*nr <= ne && ne <= max_degree*nr))
        throw std::runtime_error("Invalid graph dimensions");
    Graph g{n,k,transmitted,std::vector<int>(nr+1),std::vector<int>(ne)};
    receive(g.offsets.data(), g.offsets.size());
    receive(g.variables.data(), g.variables.size());
    if (g.offsets.front() != 0 || g.offsets.back() != ne)
        throw std::runtime_error("Invalid graph offsets");
    for (int i = 0; i < nr; ++i)
        if (g.offsets[i+1] - g.offsets[i] < 2 || g.offsets[i+1] - g.offsets[i] > max_degree)
            throw std::runtime_error("Invalid check degree");
    for (int col : g.variables)
        if (col < 0 || col >= n) throw std::runtime_error("Invalid graph column");
    return g;
}

void symbol_messages(const Graph& graph, const Config& config, int width,
                     const std::vector<float>& metrics, const std::vector<float>& constraints,
                     bool initial, std::vector<float>& channel, std::vector<float>& beliefs) {
    int nc = 1 << width, extra = graph.n - graph.transmitted;
    for (int start = 0, symbol = 0; start < graph.transmitted; start += width, ++symbol) {
        int count = std::min(width, graph.transmitted-start);
        int variable[5];
        float prior[5];
        float values[32], subset[32];
        subset[0] = 0;
        for (int j = 0; j < count; ++j) {
            int tx = start+j;
            variable[j] = tx < graph.k ? tx : tx+extra;
            int v = variable[j];
            prior[j] = initial ? 0.f : config.prior_weight *
                std::clamp(beliefs[v]-channel[v], -22.f, 22.f) + constraints[v];
            for (int i = 0; i < (1<<j); ++i) subset[i+(1<<j)] = subset[i]-prior[j];
        }
        for (int i = 0; i < nc; ++i)
            values[i] = config.scale*metrics[symbol*nc+i]+subset[i&((1<<count)-1)];
        for (int j = 0; j < count; ++j) {
            float zero=-1.e8f, one=-1.e8f;
            for (int i = 0; i < nc; ++i) {
                float& lp = i&(1<<j) ? one : zero;
                lp = log_add(lp, values[i]);
            }
            int v = variable[j];
            float target = std::clamp(zero-one-prior[j], -40.f, 40.f)+constraints[v];
            float delta = (initial ? 1.f : config.damp)*(target-channel[v]);
            channel[v] += delta;
            beliefs[v] += delta;
        }
    }
}

void process(const Graph& graph) {
    int request[6];
    float settings[4];
    receive(request, 6);
    receive(settings, 4);
    int width = request[0], iterations = request[1], period = request[2], flags = request[3];
    bool known_padding = (request[5]&1)!=0, report_extrinsic = (request[5]&2)!=0;
    if (width < 0 || width > 5 || iterations < 1 || iterations > 400 || period < 0 ||
        (width == 0 && (period != 0 || report_extrinsic)))
        throw std::runtime_error("Invalid decoder settings");
    Config config{iterations,period,flags>>1,(flags&1)!=0,settings[0],settings[1],
                  settings[2],settings[3],0,static_cast<uint32_t>(request[4])};
    std::vector<float> beliefs(graph.n), channel(graph.n), constraints(graph.n), metrics;
    if (width) {
        metrics.resize(((graph.transmitted+width-1)/width)*(1<<width));
        receive(metrics.data(), metrics.size());
        if (known_padding) receive(constraints.data(), constraints.size());
        symbol_messages(graph, config, width, metrics, constraints, true, channel, beliefs);
    } else {
        receive(beliefs.data(), beliefs.size());
    }
    int best = syndrome(graph, beliefs), best_step = 0;
    std::vector<float> best_beliefs = beliefs, messages(graph.variables.size());
    std::vector<float> best_extrinsic(report_extrinsic ? graph.transmitted : 0);
    std::vector<int> schedule(graph.offsets.size()-1);
    std::iota(schedule.begin(), schedule.end(), 0);
    std::mt19937 rng(config.seed);
    if (config.shuffle) std::shuffle(schedule.begin(), schedule.end(), rng);
    for (int i = 1; i <= iterations && best; ++i) {
        if (config.shuffle == 2) std::shuffle(schedule.begin(), schedule.end(), rng);
        for (int row : schedule) decode_check(graph, config, row, beliefs, messages);
        int left = syndrome(graph, beliefs);
        if (left < best) {
            best = left;
            best_step = i;
            best_beliefs = beliefs;
            for (int tx = 0; tx < static_cast<int>(best_extrinsic.size()); ++tx) {
                int v = tx < graph.k ? tx : tx+graph.n-graph.transmitted;
                best_extrinsic[tx] = beliefs[v]-channel[v];
            }
        }
        if (best && period && i%period == 0)
            symbol_messages(graph, config, width, metrics, constraints, false, channel, beliefs);
    }
    int reply[2] = {best,best_step};
    send(reply, 2);
    if (!best) {
        std::vector<unsigned char> bits(graph.transmitted);
        for (int i = 0; i < graph.transmitted; ++i)
            bits[i] = best_beliefs[i < graph.k ? i : i+graph.n-graph.transmitted] < 0;
        send(bits.data(), bits.size());
    } else if (report_extrinsic) {
        send(best_extrinsic.data(), best_extrinsic.size());
    }
    std::cout.flush();
}

int main() try {
#if defined(_WIN32) || defined(__CYGWIN__)
    setmode(0, O_BINARY);
    setmode(1, O_BINARY);
#endif
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    std::unordered_map<int,Graph> graphs;
    int command[2];
    while (std::cin.read(reinterpret_cast<char*>(command), sizeof(command))) {
        if (command[0] == 1) {
            graphs.insert_or_assign(command[1], receive_graph());
        } else if (command[0] == 2) {
            process(graphs.at(command[1]));
        } else {
            throw std::runtime_error("Invalid decoder command");
        }
    }
    return 0;
} catch (const std::exception& e) {
    std::cerr << e.what() << '\n';
    return 2;
}
