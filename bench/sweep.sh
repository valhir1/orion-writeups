#!/usr/bin/env bash
set -euo pipefail

BENCH="${BENCH_DIR}"
RESULTS="$BENCH/results"
mkdir -p "$RESULTS"

CONTAINER="qwen38-nvfp4-tp2"
BASE_URL="http://127.0.0.1:8000"
MODEL="Qwen/Qwen3.8-27B"
TOKENIZER="/model"
ENDPOINT="/v1/completions"
OUTPUT_LEN=256
SEED=42
WARMUPS=1
TAG="${TAG:-}"

declare -a CONCURRENCIES=(1 4 16 64)
declare -a INPUT_LENS=(1024 8192 32768)

# Determine which cells to run
if [[ $# -eq 2 ]]; then
    CONCURRENCIES=("$1")
    INPUT_LENS=("$2")
elif [[ $# -eq 0 ]]; then
    :
else
    echo "Usage: bash sweep.sh [concurrency input_len]" >&2
    exit 1
fi

# Trap to clean up nvidia-smi logger
LOGGER_PID=""
cleanup() {
    if [[ -n "$LOGGER_PID" ]] && kill -0 "$LOGGER_PID" 2>/dev/null; then
        kill "$LOGGER_PID" 2>/dev/null || true
        wait "$LOGGER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

# Compute base seed once at script start
RUN_SEED_BASE="${SEED_BASE:-$(date +%s)}"

run_cell() {
    local conc="$1"
    local in_len="$2"
    local cell="c${conc}-in${in_len}"
    if [[ -n "$TAG" ]]; then
        cell="${cell}-${TAG}"
    fi

    local num_prompts
    if [[ -n "${NUM_PROMPTS:-}" ]]; then
        num_prompts="$NUM_PROMPTS"
    else
        if [[ "$conc" -eq 64 ]]; then
            num_prompts=64
        else
            num_prompts=20
        fi
    fi

    # Per-cell seed to avoid prefix cache contamination
    local cell_seed=$(( RUN_SEED_BASE + conc * 100000 + in_len ))

    local gpu_csv="$RESULTS/${cell}-gpu.csv"
    local bench_log="$RESULTS/${cell}-bench.log"
    local result_json="$RESULTS/${cell}.json"
    local cells_csv="$RESULTS/cells.csv"

    echo "=== Running cell: $cell (conc=$conc, in_len=$in_len, prompts=$num_prompts, seed=$cell_seed) ==="

    # Ensure /tmp/bench exists in container
    docker exec "$CONTAINER" mkdir -p /tmp/bench

    # Start GPU logger with timestamp
    nvidia-smi --query-gpu=timestamp,index,power.draw,temperature.gpu,clocks.sm,utilization.gpu --format=csv,nounits -lms 500 > "$gpu_csv" &
    LOGGER_PID=$!

    # Small delay to ensure logger is running
    sleep 1

    # Record start time
    local start_time
    start_time=$(date +%s.%N)

    # Run benchmark inside container
    docker exec "$CONTAINER" vllm bench serve \
        --backend vllm \
        --base-url "$BASE_URL" \
        --endpoint "$ENDPOINT" \
        --model "$MODEL" \
        --tokenizer "$TOKENIZER" \
        --dataset-name random \
        --random-input-len "$in_len" \
        --random-output-len "$OUTPUT_LEN" \
        --random-range-ratio 0 \
        --ignore-eos \
        --num-prompts "$num_prompts" \
        --max-concurrency "$conc" \
        --request-rate inf \
        --num-warmups "$WARMUPS" \
        --percentile-metrics ttft,tpot,itl,e2el \
        --metric-percentiles 50,95 \
        --save-result \
        --result-dir /tmp/bench \
        --result-filename "${cell}.json" \
        --disable-tqdm \
        --seed "$cell_seed" \
        --temperature 0 \
        > "$bench_log" 2>&1

    # Record end time
    local end_time
    end_time=$(date +%s.%N)

    # Stop GPU logger
    kill "$LOGGER_PID" 2>/dev/null || true
    wait "$LOGGER_PID" 2>/dev/null || true
    LOGGER_PID=""

    # Copy result JSON out of container
    docker cp "${CONTAINER}:/tmp/bench/${cell}.json" "$RESULTS/.tmp_${cell}.json"

    # Process results with python3
    python3 - "$RESULTS/.tmp_${cell}.json" "$gpu_csv" "$result_json" "$cells_csv" "$cell" "$conc" "$in_len" "$OUTPUT_LEN" "$num_prompts" "$start_time" "$end_time" "$cell_seed" <<'PYEOF'
import sys, json, csv, os
from datetime import datetime

tmp_json = sys.argv[1]
gpu_csv = sys.argv[2]
result_json = sys.argv[3]
cells_csv = sys.argv[4]
cell = sys.argv[5]
conc = int(sys.argv[6])
in_len = int(sys.argv[7])
out_len = int(sys.argv[8])
num_req = int(sys.argv[9])
start_time = float(sys.argv[10])
end_time = float(sys.argv[11])
seed = int(sys.argv[12])

# Read vLLM result JSON
with open(tmp_json, 'r') as f:
    data = json.load(f)

# Extract metrics (handle both median_* and p50_*)
def get_metric(d, key):
    if key in d:
        return d[key]
    # Try p50 variant
    p50_key = key.replace('median_', 'p50_')
    if p50_key in d:
        return d[p50_key]
    return None

ttft_p50 = get_metric(data, 'median_ttft_ms')
ttft_p95 = data.get('p95_ttft_ms')
tpot_p50 = get_metric(data, 'median_tpot_ms')
tpot_p95 = data.get('p95_tpot_ms')
output_tok_s = data.get('output_throughput')
req_throughput = data.get('request_throughput')
duration = data.get('duration')
completed = data.get('completed')
total_output_tokens = data.get('total_output_tokens')

# Parse GPU CSV
# Format: timestamp, index, power.draw [W], temperature.gpu, clocks.current.sm [MHz], utilization.gpu [%]
# Data rows have spaces after commas.
# Grouping: walk rows in file order; a GPU 0 row starts a new sample, the following GPU 1 row completes it.
# Use the GPU 0 row's timestamp for the window filter. Discard incomplete samples.

raw_samples = []  # list of (ts_str, power0, power1)
with open(gpu_csv, 'r') as f:
    lines = f.readlines()

# Skip header
if lines and lines[0].strip().startswith('timestamp'):
    lines = lines[1:]

i = 0
while i < len(lines):
    line = lines[i].strip()
    if not line:
        i += 1
        continue
    parts = [p.strip() for p in line.split(',')]
    if len(parts) < 6:
        i += 1
        continue
    try:
        ts_str = parts[0]
        idx = int(parts[1])
        power = float(parts[2])
    except (ValueError, IndexError):
        i += 1
        continue

    if idx == 0:
        # Start a new sample; look for the next GPU 1 row
        ts0 = ts_str
        p0 = power
        # Find next row with index 1
        j = i + 1
        found = False
        while j < len(lines):
            l2 = lines[j].strip()
            if not l2:
                j += 1
                continue
            p2 = [x.strip() for x in l2.split(',')]
            if len(p2) < 6:
                j += 1
                continue
            try:
                idx2 = int(p2[1])
                power2 = float(p2[2])
            except (ValueError, IndexError):
                j += 1
                continue
            if idx2 == 1:
                raw_samples.append((ts0, p0, power2))
                i = j + 1
                found = True
                break
            else:
                j += 1
        if not found:
            # Incomplete sample, discard
            i += 1
    else:
        # A GPU 1 row without a preceding GPU 0 row in this pass; skip
        i += 1

# Filter samples by time window [end_time - duration, end_time]
window_start = end_time - duration if duration else 0
window_end = end_time

valid_samples = []
for ts_str, p0, p1 in raw_samples:
    try:
        dt = datetime.strptime(ts_str, "%Y/%m/%d %H:%M:%S.%f")
        ts_epoch = dt.timestamp()
    except ValueError:
        continue
    if window_start <= ts_epoch <= window_end:
        valid_samples.append(p0 + p1)

if valid_samples:
    mean_watts = sum(valid_samples) / len(valid_samples)
    peak_watts = max(valid_samples)
    gpu_samples = len(valid_samples)
else:
    mean_watts = 0.0
    peak_watts = 0.0
    gpu_samples = 0

# Calculate tokens_per_joule
if mean_watts > 0 and duration and duration > 0:
    tokens_per_joule = total_output_tokens / (mean_watts * duration)
else:
    tokens_per_joule = 0.0

# Write result JSON
result = {
    'cell': cell,
    'concurrency': conc,
    'input_len': in_len,
    'output_len': out_len,
    'num_requests': num_req,
    'completed': completed,
    'duration_s': duration,
    'ttft_p50_ms': ttft_p50,
    'ttft_p95_ms': ttft_p95,
    'tpot_p50_ms': tpot_p50,
    'tpot_p95_ms': tpot_p95,
    'output_tok_s': output_tok_s,
    'request_throughput': req_throughput,
    'mean_watts': mean_watts,
    'peak_watts': peak_watts,
    'tokens_per_joule': tokens_per_joule,
    'gpu_samples': gpu_samples,
    'seed': seed,
    'start_time': start_time,
    'end_time': end_time
}

with open(result_json, 'w') as f:
    json.dump(result, f, indent=2)

# Append to cells.csv
header = ['cell', 'concurrency', 'input_len', 'output_len', 'num_requests', 'completed',
          'duration_s', 'ttft_p50_ms', 'ttft_p95_ms', 'tpot_p50_ms', 'tpot_p95_ms',
          'output_tok_s', 'request_throughput', 'mean_watts', 'peak_watts',
          'tokens_per_joule', 'gpu_samples']

write_header = not os.path.exists(cells_csv)
with open(cells_csv, 'a', newline='') as f:
    writer = csv.writer(f)
    if write_header:
        writer.writerow(header)
    writer.writerow([
        cell, conc, in_len, out_len, num_req, completed,
        duration, ttft_p50, ttft_p95, tpot_p50, tpot_p95,
        output_tok_s, req_throughput, mean_watts, peak_watts,
        tokens_per_joule, gpu_samples
    ])

# Clean up temp file
os.remove(tmp_json)
PYEOF

    echo "=== Cell $cell complete ==="
}

# Run all cells
for conc in "${CONCURRENCIES[@]}"; do
    for in_len in "${INPUT_LENS[@]}"; do
        run_cell "$conc" "$in_len"
        sleep 5
    done
done

echo "=== Sweep complete ==="
