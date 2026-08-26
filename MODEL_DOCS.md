# GB10 Model Drive — Model Reference

**Target hardware:** Dell GB10 (128 GB unified memory, 273 GB/s, Blackwell FP4) · DGX OS · vLLM
**Constraint:** Western-origin labs only (OpenAI, NVIDIA, Mistral, Google) — no Chinese-lab models
**Prepared:** 2026-08-26 · Speeds below are single-GB10 unless noted

| Folder | Model | Disk | Params (act.) | Context | Multimodal | Role |
|---|---|---|---|---|---|---|
| `gpt-oss-120b` | gpt-oss-120b | ~63 GB | 117B (5.1B) | 128K | Text | Workhorse / code |
| `nemotron-3-super-120b-nvfp4` | Nemotron 3 Super | ~65 GB | 120B (12B) | up to 1M | Text | Long-context agent |
| `devstral-small-2-24b-fp8` | Devstral Small 2 | ~26 GB | 24B dense | 256K | Text + image | Best code writer |
| `gemma-4-26b-a4b-it-fp8` | Gemma 4 26B-A4B (FP8) | ~27 GB | 25B (3.8B) | 256K | Text + image | Summaries / vision |
| `gemma-4-26b-mtp-drafter` | Gemma 4 MTP drafter | ~1 GB | — | — | — | Speedup add-on |
| `gemma-4-26b-a4b-it-nvfp4` | Gemma 4 26B-A4B (NVFP4) | ~17 GB | 25B (3.8B) | 256K | Text + image | Co-residency copy |
| `gemma-4-e4b-it-nvfp4a16` | Gemma 4 E4B | ~10 GB | 4.5B dense | 128K | Text + image + audio | Router / triage |

**Golden rule:** copy models to internal NVMe (`/opt/models/`) before serving. Never point vLLM at this USB drive.

---

## gpt-oss-120b
**Repo:** `openai/gpt-oss-120b` · **License:** Apache 2.0 · **Lab:** OpenAI (US)

The default endpoint. A 117B mixture-of-experts model activating only 5.1B parameters
per token, which is why it decodes fast on bandwidth-limited hardware. Ships natively
in MXFP4 (~63 GB) — no separate quantization needed. Configurable reasoning effort
(low/medium/high) via system prompt.

- **Context:** 128K tokens (smallest on the drive, but sufficient for most harness turns)
- **Multimodality:** none — text only
- **Measured on GB10:** ~36 t/s single node, ~55 t/s across two nodes (vLLM TP=2)
- **Use for:** general coding via harnesses (pi / Claude Code / Warp), everyday Q&A,
  the "just works" fallback when anything else misbehaves. Most mature GB10/vLLM
  support of any model here.
- **Avoid for:** sessions that need >128K context (use Nemotron), image input.
- **Serving note:** works out-of-the-box with NVIDIA's vLLM container; enable
  `--enable-prefix-caching` for agent workloads.

---

## Nemotron 3 Super 120B-A12B (NVFP4)
**Repo:** `nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-NVFP4` · **License:** NVIDIA Open Model License (commercial OK) · **Lab:** NVIDIA (US)

The long-haul agent model. Hybrid architecture (Mamba-2 state-space layers + Latent
Mixture-of-Experts + select attention layers) — most layers keep a fixed-size state
instead of a growing KV cache, which is why a 1M-token context is actually usable.
This exact NVFP4 checkpoint is the one NVIDIA recommends for DGX Spark, and the model
was *trained* with NVFP4 quantization-aware methods, so quality loss vs BF16 is minimal.
Built-in Multi-Token Prediction gives free speculative-decoding speedups. Reasoning
traces can be toggled via a chat-template flag.

- **Context:** up to 1M tokens (default configs use 256K; raise as memory allows)
- **Multimodality:** none — text only
- **Benchmarks:** 60.5 SWE-bench Verified · RULER 91.75 at 1M tokens (vs 22.3 for gpt-oss-120b)
- **Use for:** long-running agent sessions, repo-scale context, multi-step planning,
  cross-document work — anything where the conversation outgrows 128K.
- **Avoid for:** quick lightweight tasks (Gemma tier is cheaper) — and note decode is
  moderate (~25–40 t/s expected; 12B active is the largest per-token read on the drive).

---

## Devstral Small 2 (24B, native FP8)
**Repo:** `mistralai/Devstral-Small-2-24B-Instruct-2512` · **License:** Apache 2.0 · **Lab:** Mistral (France)

The code-quality pick. 68.0 on SWE-bench Verified — the best repo-level coding score of
any Western open model that fits this hardware. Purpose-built for agentic software
engineering: exploring codebases, multi-file edits, tool use. The official repo ships
in FP8 (~26 GB); it also carries a Pixtral vision encoder, so it accepts images
(screenshots, diagrams) alongside code.

- **Context:** 256K tokens
- **Multimodality:** text + image input
- **The trade-off:** it is a *dense* model — all 24B parameters are read per token, so
  expect only ~10–15 t/s on a GB10. Quality per token is high; tokens per second are not.
- **Use for:** correctness-critical code writing, tricky bug fixes, unit-test
  generation, tasks where you'd rather wait for a right answer.
- **Avoid for:** long many-turn agent loops where latency compounds (use gpt-oss-120b),
  high-frequency light tasks.
- **Serving note:** vLLM with `--tokenizer_mode mistral`. FP8 path is the
  vLLM-recommended configuration from Mistral.

---

## Gemma 4 26B-A4B-it — FP8 Dynamic
**Repo:** `RedHatAI/gemma-4-26B-A4B-it-FP8-Dynamic` · **License:** Apache 2.0 (Gemma 4 family) · **Lab:** Google (US), quant by Red Hat AI

The high-throughput multimodal generalist. MoE with just 3.8B active parameters, so it
is fast; pair it with the MTP drafter (next entry) and it becomes the fastest model on
the drive by a wide margin. Excellent tool-call formatting and instruction following.

- **Context:** 256K tokens
- **Multimodality:** text + image input (variable aspect ratio; screenshots, UI, charts, PDFs-as-images)
- **Measured on GB10:** ~40 t/s alone · **~108 t/s single-stream / ~674 t/s aggregate
  (concurrency 8) with the MTP drafter** — best multi-user throughput on the drive
- **Use for:** PR summaries, commit messages, documentation, Jira comment drafting,
  code *review commentary*, screenshot/diagram understanding, vision sidecar for
  text-only coders.
- **DO NOT use as a primary coding model.** Google omitted SWE-bench from official
  numbers; independent estimates put it around ~17% SWE-bench Verified with known
  identifier-hallucination issues. It will format tool calls perfectly while writing
  wrong code — the worst failure mode. Route code writing to Devstral/gpt-oss/Nemotron.

---

## Gemma 4 MTP Drafter (26B-A4B-it assistant)
**Repo:** `google/gemma-4-26B-A4B-it-assistant` · **License:** Gemma license (gated repo) · **Lab:** Google (US)

Not a standalone model — a ~0.9 GB BF16 Multi-Token Prediction drafter used for
speculative decoding. Loaded alongside the 26B-A4B via vLLM's speculative-decoding
config, it multiplies throughput ~2.7x (γ=4).

- **Critical pairing rule:** works with **-it (instruct)** targets only. Pairing it
  with a *base*-variant quant reproducibly makes throughput WORSE, not better.
- **Overhead:** ~0.9 GB memory — noise on a 128 GB node.
- **Serving note:** the 108 t/s configuration currently rides a preview vLLM image
  (`vllm/vllm-openai:gemma4-cu130`). If it fights you, drop the drafter and serve the
  FP8 target plain — still ~40 t/s.

---

## Gemma 4 26B-A4B-it — NVFP4 (co-residency copy)
**Repo:** `bg-digitalservices/Gemma-4-26B-A4B-it-NVFP4` · **License:** Apache 2.0 · **Lab:** Google (US), community quant (Spark-validated)

The same model as the FP8 entry, compressed to ~16.5 GB (W4A4). Exists for one
scenario: when Gemma must share a node with another model and every GB counts —
e.g. GLM-alternative + vision-sidecar layouts, or E4B + 26B on one box with maximum
KV headroom. Quality cost of the 4-bit squeeze: ~4pp on math-style chained reasoning
(GSM8K); instruction following unaffected.

- **Context / multimodality:** same as FP8 copy (256K, text + image)
- **Measured on GB10:** ~52 t/s (vLLM, stable ≥ v0.25.1)
- **Use for:** multi-model single-node layouts. If Gemma has the node to itself,
  prefer the FP8 copy + drafter instead.
- **Serving notes:** requires the bundled `gemma4_patched.py` and
  `--moe-backend marlin`. Both documented in the repo card.

---

## Gemma 4 E4B-it — NVFP4A16 (router)
**Repo:** `coolthor/Gemma-4-E4B-it-NVFP4A16` · **License:** Apache 2.0 · **Lab:** Google (US), community quant

The triage tier. 4.5B effective parameters (8B total with Per-Layer Embeddings) in
~7.5–10 GB, running ~50 t/s. The validated pattern: E4B handles ~95% of routine agent
traffic — classification, routing, parsing tool output, one-line Jira comments — and
escalates anything hard to a bigger model. Costs almost nothing to keep resident;
fits alongside any other model on the drive.

- **Context:** 128K tokens
- **Multimodality:** text + image + audio input (the only audio-capable model on the drive)
- **Measured on GB10:** ~49.9 t/s (this exact checkpoint)
- **Use for:** orchestration/classification, request routing, quick summaries,
  tool-output parsing, cheap first-pass triage in multi-agent setups.
- **Avoid for:** anything requiring depth — it is intentionally shallow and fast.
- **Serving note:** `--quantization compressed-tensors --kv-cache-dtype fp8`.

---

## Suggested node layouts

**Two nodes, independent (default):**
- **Node A — coding:** gpt-oss-120b resident (primary harness endpoint). Swap to
  Nemotron 3 Super for long-context sessions; swap to Devstral Small 2 for
  correctness-critical work.
- **Node B — light-lift:** E4B (router, ~10 GB) + 26B-A4B FP8 + MTP drafter
  (~28 GB) resident together; ~75 GB left for KV cache. Serves summaries, docs,
  Jira, vision.

**Two nodes, clustered (TP=2 over the QSFP link):**
- gpt-oss-120b at ~55 t/s for shared heavy use. Tear down and rebuild per session.

**KV-cache budget:** every layout above keeps single-node weights ≤ ~90 GB against
~110–116 GB usable, leaving 20 GB+ for KV cache at full advertised context. The two
1M-context models (Nemotron) and hybrid/MoE designs keep KV growth small by
architecture; no context-length compromises are required at these quants.
