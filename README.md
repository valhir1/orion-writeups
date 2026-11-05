# ORION: a home AI server

*Summary: four write-ups about building and operating a self-hosted AI assistant on a two-GPU workstation.*

## The pages

1. **[The build](docs/01-the-build.md)**: why I built a two-GPU server for a personal assistant, who wrote the code, and what it turned out to be good at.
2. **[Serving a 27B model on two 5090s](docs/02-serving-a-27b-on-two-5090s.md)**: vLLM tensor parallel with NVFP4, a crash loop on 0.28 and the move to 0.30, Xid 13, a watchdog that restarted a healthy server, and what "harness-handicapped" meant in my benchmarks.
3. **[Running it like production](docs/03-running-it-like-production.md)**: systemd units and timers, the watchdog, nightly Borg backups to the NAS, restore drills that boot the service from the restored copy, and the a full snapshot of the box.
4. **[Shipping a native iOS client](docs/04-shipping-a-native-ios-client.md)**: SwiftUI, hosted CI, beta delivery, APNs push, and diagnosing a release-distribution failure.

## Who wrote what

I handled the design, construction, and daily operation of the system. Most of the code was written by an AI pair under my direction. That usually meant Claude Code, with OpenAI’s Codex handling some backend lanes. The text on these pages comes from ORION, specifically the Qwen3.8-27B model that ran on the server itself. It generated the content using my project notes and a fact list I verified against those notes.

Each page then went to a review council. This group included two Claude Opus reviewers, one focused on facts and the other on voice, plus Codex. Each of the three compared the draft line by line against the checked notes and produced a fix list. ORION then applied those fixes in two additional passes. A script verified that no number appeared that was not in the notes and that section headings remained unchanged. The per-page source lists were removed before publishing because they named private notes.

The pages received a final manual review. ORION-authored commits contain model-generated drafts, while operator-authored commits contain subsequent edits. Earlier drafts by Claude served as the fact-checked base. However, ORION’s initial drafts in early November had tense issues and status errors, such as writing plans as completed tasks. That mistake is exactly why the council step exists.

## Two things the system did itself

- `bench/`: A serving-capacity and power sweep of the 27B model on two RTX 5090s. It tested 12 cells across concurrency and prompt length combinations, tracking tokens per joule. The model wrote the scripts over six prompt rounds. I found measurement bugs during the first full run. Every cell used the same seed, causing later cells to hit the prefix cache, and the concurrency-64 cells only sent five requests. The model fixed these issues. Raw results and the full model transcript are included.
- `validate/`: A read-only hardware validation report for each component. It covered the CPU, board, ECC memory, both GPUs, and three NVMe drives. Every PASS or FAIL line cites the specific log line it originated from. The model wrote this report over eight rounds, with serial numbers masked.
