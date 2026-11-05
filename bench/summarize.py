#!/usr/bin/env python3
import json
import re
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def main():
    base = Path(__file__).resolve().parent
    results_dir = base / "results"
    if not results_dir.is_dir():
        print("results/ directory not found")
        return

    pattern = re.compile(r"^c(\d+)-in(\d+)$")
    cells = {}
    for p in results_dir.glob("*.json"):
        m = pattern.match(p.stem)
        if m:
            conc = int(m.group(1))
            in_len = int(m.group(2))
            try:
                with open(p, "r") as f:
                    data = json.load(f)
                cells[(conc, in_len)] = data
            except Exception:
                pass

    if not cells:
        print("No valid cell JSON files found")
        return

    # Build rows sorted by input_len then concurrency
    rows = []
    for (conc, in_len), d in cells.items():
        rows.append((in_len, conc, d))
    rows.sort(key=lambda x: (x[0], x[1]))

    # Prompt label helper
    def prompt_label(in_len):
        if in_len == 1024:
            return "1k"
        elif in_len == 8192:
            return "8k"
        elif in_len == 32768:
            return "32k"
        else:
            return f"{in_len}"

    # Markdown table
    header = "| Prompt | Conc | Reqs | TTFT p50 ms | TTFT p95 ms | TPOT p50 ms | TPOT p95 ms | Out tok/s | Req/s | Mean W | Peak W | Tok/J |"
    sep = "|---|---|---|---|---|---|---|---|---|---|---|---|"
    print(header)
    print(sep)
    for in_len, conc, d in rows:
        prompt = prompt_label(in_len)
        conc_s = str(conc)
        reqs = f"{d.get('completed', 0)}/{d.get('num_requests', 0)}"
        ttft_p50 = f"{d.get('ttft_p50_ms', 0):.0f}"
        ttft_p95 = f"{d.get('ttft_p95_ms', 0):.0f}"
        tpot_p50 = f"{d.get('tpot_p50_ms', 0):.1f}"
        tpot_p95 = f"{d.get('tpot_p95_ms', 0):.1f}"
        out_tok_s = f"{d.get('output_tok_s', 0):.1f}"
        req_s = f"{d.get('request_throughput', 0):.2f}"
        mean_w = f"{d.get('mean_watts', 0):.0f}"
        peak_w = f"{d.get('peak_watts', 0):.0f}"
        tok_j = f"{d.get('tokens_per_joule', 0):.3f}"
        print(f"| {prompt} | {conc_s} | {reqs} | {ttft_p50} | {ttft_p95} | {tpot_p50} | {tpot_p95} | {out_tok_s} | {req_s} | {mean_w} | {peak_w} | {tok_j} |")

    # Group by input_len for plotting
    input_lens = sorted(set(in_len for in_len, _, _ in rows))
    concs = sorted(set(conc for _, conc, _ in rows))

    # Plot 1: Output tokens/s vs concurrency
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for in_len in input_lens:
        xs = []
        ys = []
        for conc in concs:
            if (conc, in_len) in cells:
                d = cells[(conc, in_len)]
                xs.append(conc)
                ys.append(d.get("output_tok_s", 0))
        if xs:
            ax.plot(xs, ys, marker="o", label=prompt_label(in_len))
    ax.set_xscale("log", base=2)
    ax.set_xticks(concs)
    ax.set_xticklabels([str(c) for c in concs])
    ax.set_xlabel("Concurrency")
    ax.set_ylabel("Output tokens/s")
    ax.set_title("Output tokens/s vs concurrency")
    ax.grid(True)
    ax.legend()
    fig.tight_layout()
    png1 = results_dir / "throughput.png"
    fig.savefig(png1, dpi=150)
    plt.close(fig)

    # Plot 2: Tokens per joule vs concurrency
    fig, ax = plt.subplots(figsize=(7, 4.5))
    for in_len in input_lens:
        xs = []
        ys = []
        for conc in concs:
            if (conc, in_len) in cells:
                d = cells[(conc, in_len)]
                xs.append(conc)
                ys.append(d.get("tokens_per_joule", 0))
        if xs:
            ax.plot(xs, ys, marker="o", label=prompt_label(in_len))
    ax.set_xscale("log", base=2)
    ax.set_xticks(concs)
    ax.set_xticklabels([str(c) for c in concs])
    ax.set_xlabel("Concurrency")
    ax.set_ylabel("Tokens per joule")
    ax.set_title("Output tokens per joule vs concurrency")
    ax.grid(True)
    ax.legend()
    fig.tight_layout()
    png2 = results_dir / "efficiency.png"
    fig.savefig(png2, dpi=150)
    plt.close(fig)

    print(str(png1))
    print(str(png2))

if __name__ == "__main__":
    main()
