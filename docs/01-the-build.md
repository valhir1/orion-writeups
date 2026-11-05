# The build: a home AI server

*Summary: I built a two-GPU workstation to run my own assistant at home and ran it like a small production service.*

## Why

The goal was an always-on local assistant that could use private data, run approved tools, and keep processing on the local network by default. I called it ORION. The design goal was a harness shaped like Claude Code driving a local model. I made it reachable from a web app, a phone app, a terminal, Siri, and email.

I designed the system, made the calls, ran the hardware and operated it every day. An AI pair, mostly Claude Code with OpenAI's Codex on some backend lanes, wrote most of the code under my direction. My role was closer to tech lead and operator than to the person typing every line. I decided what to build, reviewed the work, ran the evaluations, said no, and lived with the result.

**Authorship:** I designed, built and operated the system. An AI pair, mostly Claude Code with Codex on some backend lanes, wrote most of the code under my direction. ORION, the local model that ran on this box, wrote these pages from my project notes; two Claude Opus reviewers and Codex checked them against the notes, and I edited the result.

## What

The box:

| Component | Spec |
| :--- | :--- |
| CPU | AMD Threadripper, 24 cores |
| Motherboard | TRX50 workstation board (10 GbE) |
| GPU | 2x NVIDIA RTX 5090 (32 GB each) |
| RAM | 128 GB DDR5 ECC |
| Storage | 3x 2 TB NVMe (one Gen5) |

Network storage supplied backups, while a separate small model handled low-stakes review tasks.

The software consisted of three pieces. The first was "The door," a single HTTPS process that served the clients, ran each turn, held approval cards, and ran the schedulers. The schedulers included morning brief, mail sync, and reminders. The second piece was "The brain," which used Qwen3.8-27B in NVFP4 precision via vLLM. It used tensor parallel across both 5090s and had a 262k context window. The third piece was "The tools," including shell, files, web, memory, mail, money, the NAS, and image generation. Every tool call went through a permission check first. That check used fixed rules, a policy file, and a model acting as judge. There were five modes named after Claude Code's: default, accept-edits, plan, auto, and bypass. Anything risky became a card on my phone.

## What it cost

The project included several iterations of the harness. I left purchase cost out of the write-up because it does not say anything about what the system did. The relevant number was the cost to run. Both 5090s were capped at 400 W. Capping the GPUs cost about 1% of generation speed, dropping it from 79.4 to 78.6 tokens/s. This resulted in 68 W less on average during generation. The brain idled at about 58 W, a reading taken after I stopped mixing eval runs into idle readings.

## The honest outcome

It worked: it answered from my own data, ran overnight jobs, pushed me only when something needed a decision, and survived crashes, driver bugs, and a router that wedged itself at 1 a.m. Workload measurements showed that interactive usage was light relative to background jobs and evaluations. Those turns still added up to 10.93 million input tokens, about 206k per turn, because each step of a tool loop re-sent the whole context; a single request averaged only about 3.2k prompt tokens on a quiet day. Background jobs and evaluations dwarfed my own chat. On the heaviest eval day, the brain read 68 million tokens.

The measurement that mattered more came from a bake-off. When I finally tested a newer, larger open model on the same box, it tied the 27B. When I looked at why, the limit wasn't the model; it was my harness, which had been tuned around one model's quirks.

## What I'd do differently

- I would measure usage in week two, not month five. The usage meter that told me "four turns a day" existed for weeks before I read it as a signal.
- I would keep the harness model-agnostic from day one. Prompts and request shapes tuned to one model made every comparison unfair.
