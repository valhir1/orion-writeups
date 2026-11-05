# Serving a 27B model on two RTX 5090s

*Summary: keeping Qwen3.8-27B in NVFP4 serving on vLLM across two consumer Blackwell cards, through a crash loop, GPU faults and an overeager watchdog, and why my benchmarks measured my harness as much as the model.*

## The setup

I served Qwen3.8-27B on vLLM in Docker behind an OpenAI-compatible API. Three configurations worked out in sequence:

1. FP8 with tensor parallel over both cards.
2. NVFP4 on a single card, using the official NVIDIA checkpoint.
3. NVFP4 with tensor parallel over both cards.

The first layout hit about 79 tokens per second on a 400-token probe. I switched to the single-card NVFP4 layout on September 20, which ran at 71 to 73 tokens per second and passed a 12-row battery 12/12 on the first pass. I added tensor parallel across both cards on October 15, mainly for context and cache rather than speed.

The one-card layout taught me about memory headroom. At 95% GPU memory utilization, a 7.8k-token prefill ran out of memory, so I settled on 90%. I tried to keep the full 262k context on one card, but vLLM refused to start because it needed 8.33 GiB of KV cache while only 5.12 GiB was free. The container restarted 78 times during that crash loop. My fallback line in the launch script sat after an `exit 1` command, so it never ran, and the brain stayed down for about an hour. I eventually settled for 128k context on one card, but using two cards fixed the issue of long prompts evicted from cache.

With two cards, the KV cache grew to about 881k tokens. On 65k-token prompts, cold time to first token fell from 12.9 to 8.9 seconds. A long chat right after another long chat went from 13.1 seconds to 0.35 seconds because the cache no longer evicted. GPU draw while busy went from about 400 W to about 680 W, occurring roughly half the time. At 92% memory utilization, rank 0 held about 1.2 GB more memory than rank 1 and had around 160 MB free. During FlashInfer autotuning, the two ranks ran out of memory at different moments. One rank stalled while the other spun at 100% waiting on NCCL. I dropped memory utilization to 88%, then to 85% after five more startup hangs. That setting left about 750k tokens of KV cache. That cost about three hours and twenty minutes of downtime.

## Xid 13, the crash loop on vLLM 0.28, and the move to 0.30

The first Xid 13 error, an illegal memory access, hit the brain card mid-inference after 16 days of uptime. Docker's `unless-stopped` policy brought vLLM back in about 60 seconds. Seven benchmark attempts failed as "brain unreachable" after that first incident. After a burst like that, check the kernel log for Xid errors before blaming application code. On vLLM 0.28, the brain crashed four times in about 30 hours between September 25 and 28. Some crashes involved Xid 13, while others involved dying in CUDA graph replay with an `EngineDeadError`. The crash signature matched an open upstream issue for this specific model and quant on SM120 consumer Blackwell hardware. A driver update didn't help, and others' workarounds hadn't helped them.

I moved to vLLM 0.30.0 based on evidence from two parallel 14-case runs. Two parallel 14-case runs on 0.30.0 lasted about 80 minutes with zero crashes, while 0.28 kept crashing. Speed was 68 versus 72 tokens/s, close enough.

## The watchdog that restarted a healthy brain

A new watchdog probe sent "Say OK." with `max_tokens` set to 4. Qwen spent all four tokens on reasoning, so the visible content came back empty. The watchdog decided the brain was down and restarted the container. It pushed an alert while I was away, but the brain had been fine. I fixed it the same hour: probes turn thinking off, ask for 16 tokens, and count `completion_tokens >= 1` as alive. Restarts require two misses at least four minutes apart. Every new probe is tested by hand before it may act.

## What "harness-handicapped" meant

On October 31, I ran GLM-5.3-Flash on the same two cards. GLM-5.3-Flash is a larger mixture-of-experts model at 2.05 bits per weight in EXL3. It scored 15/22 on the task suite, while the 27B model scored 14 to 17 across three runs. Decode averaged 74.5 tokens per second. The run accidentally favored Qwen because my model layer knew only its request shape: GLM had thinking forced on, an effort setting mapped to high, Qwen's sampling settings, and its own reasoning stripped from history every turn. Several scoring rules matched Qwen's habits. Meanwhile one bug hurt both models: a secret-redaction regex matched `KEY` inside `sort_keys=True`, corrupting a build script in every run of one task.

An earlier comparison with Qwen3.8 Flash-Next ended with a score of 49/66 for the 27B and 46/66 for each Flash-Next build. The losses in that earlier comparison were in long tasks the prompts had been tuned on. "Harness-handicapped" means scores measured fit to the harness at least as much as model quality. When the judge corpus was run while a test battery was loading the brain, requests timed out. Timed-out requests were scored as "failed or invalid answer." On an idle brain, the same model scored 10/10 on lane idioms and 74/75 on the tightened probes. The median latency on the idle brain was 0.70 seconds. Quality runs go on a quiet box, while load runs are a separate test.

## What I'd do differently

Before every serving upgrade, I would run a few parallel long requests as a crash check. I would write the memory headroom rule into the launch script. I would test the failure path of every launch script. I would keep a known-good rollback command next to the launch script. I would build the model layer around a per-model profile before running any bake-off. The per-model profile should include sampling, thinking, and history handling. Otherwise the bake-off measures which model the harness was written for.
