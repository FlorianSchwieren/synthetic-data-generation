---
name: synthetic-data-generation
description: Plan and run large-scale synthetic data generation (names, lists, stories, relational tables, bulk text) with any coding agent, using cheap worker models on the user's own subscription, then audit, post-process and document the result. Works with Claude Code, Codex, Gemini CLI, GitHub Copilot CLI, Cursor and other agents that run headless.
---

# Synthetic Data Generation

This skill works with any use case and any coding agent. It needs **only the agent and its subscription**: no API keys, no SDKs and no package installs. Deterministic work (sampling, combining, dedup, validation, audits) runs in plain shell or Python using only the standard library. All state lives in files, so any agent or person can resume a job.

Read the reference files when you reach the step that needs them:
- [references/workers.md](references/workers.md): headless worker commands for each agent, sub-agents, batching
- [references/coherence-and-audit.md](references/coherence-and-audit.md): coherence across records and time, the independent audit
- [references/long-runs.md](references/long-runs.md): manifest, resuming, unattended runs, failures and limits, monitoring
- [references/postprocess.md](references/postprocess.md): post-processing in detail and at scale, the data card
- [references/examples.md](references/examples.md): worked examples

## Core rules

1. **The orchestrator plans, cheap workers generate, and files carry the data.** You (the orchestrator) write the spec, the prompts and the scripts. Workers on the cheapest adequate model write the data straight to files. Bulk data never passes through your context. A sub-agent worker reports back one line, e.g. `shard-0042: 480 items written`. A headless run reports one status line for the whole run.
2. **Every item must make sense.** Diversity without coherence is noise. Before generating, reason about what a realistic item looks like (see Coherence rule).
3. **Don't use an LLM for what code can do.** Combining, counting, sampling and deduplicating are code. Spend the subscription only on generation and judging.

## Workers

A worker is one call to a cheaper model through the same subscription, in one of two modes:
- **Headless**: a shell loop calls the agent's non-interactive mode and writes each result to a shard file. It runs outside your context, so it's resumable and can run unattended. Use it for large jobs (more than a few hundred calls).
- **Sub-agent**: a sub-agent with a cheap model override writes its shard with the file tool and returns one line. Use it for small jobs, pilots and judging, if the agent has sub-agents.

Pack many items into each call (e.g. 100–300 short items or 5–20 stories, tuned in the pilot), give workers no tools and a minimal prompt, ask for JSONL only, and **pin the exact model ID**, not an alias. The exact command for each agent, and its pitfalls, are in [references/workers.md](references/workers.md).

## Workflow

1. **Spec**: turn the request into `jobs/<job>/spec.yaml`.
2. **Strategy and coherence**: choose a strategy (S0–S5) and write `coherence.md`, including its invariants.
3. **Audit**: if code generates any data (seeds, vocabularies, structured records), audit it independently before any worker generates from it.
4. **Pilot**: run a stratified sample on the available models, review it, and pick the cheapest model that's good enough.
5. **Estimate**: estimate the usage the job needs against the plan's limits, and confirm with the user.
6. **Run**: workers generate resumable shards.
7. **Post-process**: validate, normalize, deduplicate, judge, filter, rebalance, re-audit and export.
8. **Report**: write `datacard.md`.

When resuming, always read `manifest.json` first. Don't rely on what you remember.

## 1. Spec

```yaml
job: child_stories
target: {count: 1000000, unit: item}      # or {count: 100000000, unit: word}
item_schema: {title: str, age_band: str, text: str}
factuality: plausible     # exact | plausible | free
uniqueness: near          # exact | near | none
strategy: null            # set in step 2
diversity_axes: {}        # set in step 2 (S3/S4)
dependencies: {}          # set in step 2: which fields condition which
constraints: []           # set in step 2: invalid or rare combinations, with rates
invariants: []            # set in step 2: rules across fields, records and time
audit: scripts/audit.py   # step 3: written independently of the generator
prompt_template: prompts/item.md
items_per_call: null      # tuned in pilot
worker: {agent: null, mode: headless, model: null, judge_model: null, parallel: 4}   # exact model IDs
validators: [schema, seed_facts, min_words:150, language:en]
postprocess: [normalize, dedup_exact, dedup_near, plausibility, filter, rebalance, reaudit]
quality_rubric: rubric.md # includes the plausibility threshold
output: {format: jsonl, shard_size: 100000}
usage_budget: null        # e.g. max usage windows, or max worker calls per window
rng_seed: 42
```

If the request is ambiguous about factuality, uniqueness, schema or budget, ask once. If no one is there to answer, assume sensible defaults and write them in the spec.

## 2. Strategies

| ID | Strategy | Use when | How |
|---|---|---|---|
| S0 | Retrieve | The data is factual and a source is reachable | Read or extract from the source. Use workers only to fill gaps or reformat. |
| S1 | Enumerate | The set is small, closed and factual | One worker call per partition, with JSON output. Verify with a second call or against a source. |
| S2 | Compose | N is huge and each item is a combination of parts | Workers generate component vocabularies with weights, each tagged with its context. Code samples the combinations conditionally. Usage doesn't grow with N. |
| S3 | Seeded grid | You need many rich, distinct items | Define axes and their dependencies, have code sample consistent seed tuples, and give each worker a batch of seeds. |
| S4 | Tree expansion | You need open-ended volume and broad coverage | Workers build a taxonomy (topic → subtopic → angle) down to the number of leaves you need, then generate long outputs per leaf. |
| S5 | Transform | Seed data already exists | Paraphrase, translate, restyle or augment it. |

To decide, work through these in order:
1. Factual, with a source available → **S0**.
2. Finite and small → **S1**.
3. An item can be assembled from parts whose vocabulary is much smaller than N → **S2**.
4. Large count of rich items → **S3**. If the axes aren't obvious, use S4 first to find them.
5. The target is measured in words or tokens → **S4** with long outputs.
6. You have input data to vary → **S5**.

Strategies can be combined: S4 can find the axes for S3, and S2 can supply names inside S3. Always prefer the strategy that needs the fewest generated tokens. S2 is by far the cheapest.

**Diversity rule.** At scale, LLMs collapse into the same names, plots and phrasings. Get diversity from **seeds that code samples** and puts into each worker prompt, not from "be creative". Also rotate few-shot examples at random.

## Coherence rule

Before generating anything, reason explicitly and write `coherence.md`:
- What does a realistic item look like? Which fields depend on each other? (E.g. country → language → first name and surname; age band → vocabulary and length.)
- Which combinations are invalid (always reject), and which are rare but real (allow at a set rate)?

Then:
- **Sample along the dependency graph.** Sample parent attributes first and condition the child fields on them. Never sample dependent fields independently.
- **Tag every component with its context** (e.g. each name with its locale, gender and era), so code can only combine compatible parts.
- **Model real-world mixing explicitly,** at a stated rate. Don't forbid mixing or leave it to chance.
- **When the same entity appears in many records** (a person in many events, an account in many transactions), the records must not contradict each other. Time-varying state comes from one function `state_at(entity, t)`. Related fields are sampled together. Shared resources have calendars. Statuses come from history. Canned text must fit every context it can land in. Read [references/coherence-and-audit.md](references/coherence-and-audit.md) before writing a generator for such data.
- Write each rule that applies as a checkable **invariant** in `coherence.md` and `spec.invariants`.

This applies to every strategy. In S2, parts can clash; in S3, seed tuples can contradict each other; in S4, leaves can drift off-topic; in S5, transforms can change the meaning.

## 3. Audit

The validator written next to the generator shares its blind spots. So audit independently:
- Write `audit.py` from `coherence.md`, the spec and the data, **not from the generator code**. Ideally a fresh sub-agent writes and runs it, seeing only those three inputs.
- Check every invariant, plus the standard check classes in [references/coherence-and-audit.md](references/coherence-and-audit.md): format, keys, field relations, trajectories, same-time consistency, capacity, status vs history, and distributions per subgroup against a reference.
- Triage each finding as a real bug, a false positive, or rare but real (record its rate). Fix real bugs in the generator, regenerate and re-audit.
- **Gate the expensive stage on the audit.** Workers copy seed errors into their output, so a seed bug found after the run means regenerating text.

## 4. Pilot

- Generate 200–1,000 items with the cheapest model and the next one up. Stratify the sample with about 20 items per stratum, so rare categories get checked too.
- Measure validity, exact and near-duplicate rate, quality against `quality_rubric`, truncation rate, items and output size per call, and wall time per call.
- Run a **sanity review**: a stronger model (or the user) reasons over 100 random items, flags anything unrealistic or contradictory, and names the cause. Fix the generator and repeat until the flag rate is below the threshold.
- Tune `items_per_call` up until quality, repetition or truncation gets worse.
- Choose the **cheapest model that passes**, and record its exact ID in the spec.

## 5. Estimate

There's often no per-token price, so the budget is the plan's usage limits.
- Total output tokens ≈ items × tokens per item, plus per-call overhead × calls, plus judge calls. For English, 1 word ≈ 1.33 tokens.
- Add the pilot's dup, reject and judge-failure rates, and over-generate by that margin.
- Convert the total into worker calls, wall time and usage windows, and write it to `estimate.md`.
- If the job needs more than a few usage windows, **tell the user before starting** and offer options: a smaller target, a more compact strategy (more S2, shorter items), or a long-running resumable job. Never quietly spend the whole subscription.
- The pilot estimate is rough. Re-estimate after the first 2–5% of the run, and confirm again if the total moves by more than about 25%.
- Workers share limits with the user's own use. Agree a cap per usage window with the user and keep `parallel` at a level where they can still work.

## 6. Run

Follow [references/long-runs.md](references/long-runs.md). The essentials:
- Seeds are deterministic from `rng_seed`, and every output line carries its seed ID.
- `manifest.json` records, per shard, the status, the model, and hashes of the seed shard and prompt. A hash mismatch makes the shard stale.
- Track items, not only shards: re-queue missing and invalid items up to 2 times, then send them to `rejects/`.
- Use one run at a time (a lock file), detach the run from the session, and stop after a few consecutive failures.
- On a usage limit, record which limit and when it resets, and resume then.
- Validate each shard against its seeds as it lands, and monitor repetition across the whole corpus.

## 7. Post-process

Parse and schema-validate → normalize → exact dedup → near dedup → judge a stratified sample → filter → rebalance → re-audit → export to `final/`, with one representation per type across all files. Use only the standard library, and stream at scale. Details are in [references/postprocess.md](references/postprocess.md).

## 8. Report

Write `datacard.md`: spec, strategy and coherence summary, worker model IDs, counts per stage, dup rate, quality and plausibility scores, invariants and final audit result, usage against the estimate, and known biases and limitations.

## Layout

```
jobs/<job>/spec.yaml  coherence.md  estimate.md  manifest.json  status.json  datacard.md
           prompts/  seeds/  raw/  rejects/  final/
           scripts/  run.sh  worker.sh  sample_seeds.py  validate.py  audit.py  postprocess.py
```

The scripts are driven entirely by `spec.yaml` and use only the shell and the Python standard library.
