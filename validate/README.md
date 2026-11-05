# Hardware validation: ORION box (2026-11-04)

Start at `reports/INDEX.md`. Each part page cites the log file and line behind every verdict. Raw evidence is in `logs/`, and the full model exchange is in `model-transcript.md`.

## Result

| Part | PASS | FAIL | INFO | SKIPPED | Overall |
|---|---|---|---|---|---|
| CPU (Threadripper 9960X, 24C/48T) | 4 | 0 | 8 | 0 | PASS |
| Board + memory (TRX50-SAGE WIFI A, 4x32 GB DDR5 ECC RDIMM @ 5600) | 2 | 0 | 9 | 1 | PASS |
| GPU 0 (RTX 5090, 11:00.0) | 11 | 0 | 8 | 0 | PASS |
| GPU 1 (RTX 5090, E1:00.0) | 11 | 0 | 8 | 0 | PASS |
| nvme0 (990 EVO Plus 2TB) | 5 | 0 | 8 | 1 | PASS |
| nvme1 (9100 PRO 2TB) | 5 | 0 | 8 | 1 | PASS |
| nvme2 (990 EVO Plus 2TB) | 5 | 0 | 8 | 1 | PASS |

## What ran

`collect.sh` ran in 61 s and wrote one log per command into `logs/`:
- lscpu, free -h, dmidecode -t memory/processor/baseboard.
- `lspci -vv` per GPU, with a LnkCap/LnkSta summary.
- `nvidia-smi -q` and the CSV clock/link/temp/power query.
- `smartctl -a` on nvme0n1, nvme1n1 and nvme2n1, plus sysfs model, firmware and size.
- hwmon temperatures, dmesg filtered for edac/ecc/mce, EDAC sysfs counters, /proc/mdstat and uptime.
- A 60 s all-core CPU load: a Python loop with 48 workers, since stress-ng isn't installed. Tctl went 70 C before, 95 C max during and 95 C at the end, which is AMD's design limit under all-core load.

`report.py` reads only `logs/` and wrote `reports/` (cpu, board-memory, gpu0, gpu1, nvme0, nvme1, nvme2, INDEX).

The GPUs were serving the live vLLM model, so no GPU load was run. GPU evidence is the nvidia-smi query and the existing benchmark runs in `${BENCH_DIR}/results`, which are linked from the GPU pages and not copied.

## Sudo and skipped items

- `sudo -n` was allowed for dmidecode, smartctl and dmesg, so nothing ended up as NEEDS_SUDO.
- Skipped because the tool isn't installed (nothing was installed, by the read-only rule):
  - memtester: no memory test was run. ECC evidence is EDAC mc0 ce=0, ue=0, and no edac/ecc/mce kernel messages.
  - stress-ng: replaced by the Python CPU loop.
  - nvme-cli: SMART came from smartctl instead.
  - lm-sensors: replaced by the raw hwmon dump.
- GPU ECC, retired pages and remapped rows read N/A. These consumer cards don't report them, so they're INFO, not PASS.

## Privacy

Serial numbers and GPU UUIDs were masked at collection and kept out of the published logs and reports.

Caveat: the smartctl logs still contain each drive's "IEEE EUI-64" namespace ID. That's a device identifier, not a serial, but redact it before sharing raw logs.

## Verification (operator)

- 4 random citations, picked with `shuf` (fixed seed) from all report lines, were opened at the cited log line. All 4 verdicts match the line:
  - gpu0 HW Power Brake Slowdown "Not Active" (q.log:102)
  - gpu1 TPC Repair Pending "No" (q.log:419, inside GPU 1's section)
  - gpu0 temp 48 C (q.log:177)
  - nvme1 Error Information Log Entries 0 (smart-nvme1n1.log:61)
- Two numbers recomputed by hand:
  - nvme0 Data Units Written: 86,137,188 x 512,000 B = 44.10 TB, which matches smartctl's "[44.1 TB]".
  - DIMM total: 4 x 32 GB = 128 GiB. free reports 125 GiB, which is at least 0.95 x 128 = 121.6, so the capacity PASS holds.

## Authorship

The 27B (Qwen/Qwen3.8-27B, local) wrote both scripts through 8 rounds: 4 for collect.sh and 4 for report.py. The operator (Claude) scoped, reviewed, ran and verified them.

The operator wrote no validation code. In report.py round 3, the model sent the script in two halves because of the 4000-token reply cap. In round 4 it sent only the corrected `chk()` and `page()`. The operator joined these model outputs verbatim; the joins are recorded in the transcript.

Bugs caught in review:
- collect.sh:
  - temp files written outside validate/
  - masking cut multi-word values
  - awk `/re/i` matched every line, so every line with a colon would have been masked
  - dmesg denial was never detected
  - `continue` outside a loop wrote a false NO_MATCHES line
- report.py:
  - one NOT_INSTALLED line skipped all three SMART pages
  - DIMM part number and speed were looked up outside a 10-line window
  - uptime cited the header line
  - the CSV row was picked by position
  - INDEX counts were always 0
