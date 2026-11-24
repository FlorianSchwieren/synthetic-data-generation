---
name: "synthetic-data-generation"
description: "Plan and run large-scale LLM synthetic data generation (lists, names, stories, bulk text) on a single agent subscription with cheap worker models, then store, post-process and document it."
---

# Synthetic Data Generation

This skill works with any use case and any coding agent. It needs **only the agent and its subscription**: no API keys, no SDKs and no package installs. Deterministic work (sampling, combining, dedup, validation) runs in plain shell or Python using only the standard library. All state lives in files, so any agent or person can resume a job.

## Core rules

1. **The orchestrator plans, cheap workers generate, and files carry the data.** You (the orchestrator) write the spec, the prompts and the scripts. Workers on the cheapest adequate model tier write the data straight to files. Bulk data never passes through the orchestrator's context. A sub-agent worker reports back only a one-line summary, e.g. `shard-0042: 480 items written`. A headless run reports one status line for the whole run, never one line per shard.
2. **Every item must make sense.** Diversity without coherence is noise. Before generating, always reason about what a realistic item looks like (see Coherence rule).
3. **Don't use an LLM for what code can do.** Combining, counting, sampling and deduplicating are code. Spend the subscription only on generation and judging.

## Workers

A worker is a call to a cheaper model tier through the same subscription. Use whichever of the two modes the agent supports, and prefer headless mode for large jobs.

| Mode | How | Best for |
|---|---|---|
| Headless CLI | A shell loop calls the agent's non-interactive mode with a cheap model and redirects stdout to a shard file. It runs outside your context, so it's resumable and can run unattended. | Large jobs (more than a few hundred calls) |
| Sub-agent | Spawn a sub-agent with a cheap model override. It writes its shard with the file tool and returns only the summary line. | Small and medium jobs, pilots, judging |

Agent mapping (check the current CLI help, since flags change):
- **Claude Code**: headless is `claude -p "<prompt>" --model haiku > raw/shard-0042.jsonl`. For sub-agents, use the Agent/Task tool with the model set to haiku, or define a `datagen-worker` agent with `model: haiku`.
- **Other agents** (Codex CLI, Gemini CLI, …): use their equivalent non-interactive command, or their sub-agent feature with a smaller model.

Each worker call has a fixed overhead (system prompt and tools), so:
- **Pack many items into each call**: e.g. 100–300 short items or 5–20 stories. Tune this in the pilot.
- Give workers no tools, or as few as possible, and a minimal prompt, if the agent allows it.
- Ask for JSONL output only, with no prose, so the output can be validated directly.
- **Pin the exact model ID**, not an alias like `haiku`. An alias can move to a newer model partway through a run that spans days, and the output style changes with it. Record the model each call actually used and check it on every shard.

## Workflow

1. **Spec**: turn the request into `jobs/<job>/spec.yaml`.
2. **Strategy and coherence**: classify the job, choose a strategy (S0–S5), and write `coherence.md`, including its invariants.
3. **Audit**: if code generates any data (seeds, vocabularies, structured records), audit it independently before any worker generates from it.
4. **Pilot**: run a small sample on the available model tiers, do a sanity review, and pick the cheapest tier that's good enough.
5. **Estimate**: estimate the tokens and usage windows the job needs, compare them with the plan's limits, and confirm with the user.
6. **Run**: workers generate resumable shards.
7. **Post-process**: validate, normalize, deduplicate, check plausibility, filter, rebalance, re-audit and export.
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
invariants: []            # set in step 2: rules across fields, records and time (see Coherence rule)
audit: scripts/audit.py   # step 3: written independently of the generator
prompt_template: prompts/item.md
items_per_call: null      # tuned in pilot
worker: {mode: headless, model: null, judge_model: null, parallel: 4}   # exact model IDs, not aliases
validators: [schema, min_words:150, language:en]
postprocess: [normalize, dedup_exact, dedup_near, plausibility, filter, rebalance]
quality_rubric: rubric.md # includes the plausibility threshold
output: {format: jsonl, shard_size: 100000}
usage_budget: null        # e.g. max usage windows or max worker calls
rng_seed: 42
```

If the request is ambiguous about factuality, uniqueness, schema or budget, ask once. If no one is there to answer, assume sensible defaults and write them in the spec.

## 2. Strategies

| ID | Strategy | Use when | How |
|---|---|---|---|
| S0 | Retrieve | The data is factual and a source file or page is reachable | Read or extract from the source. Use workers only to fill gaps or reformat. |
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

Strategies can be combined. For example, S4 can find the axes for S3, and S2 can supply character names inside S3. On a subscription, always prefer the strategy that needs the fewest generated tokens. S2 is by far the cheapest.

**Diversity rule.** At scale, LLMs collapse into the same names, plots and phrasings. Get diversity from **seeds that code samples** and puts into each worker prompt, not from "be creative". Also rotate few-shot examples at random.

## Coherence rule

Before generating anything, reason explicitly and write `coherence.md`:
- What does a realistic item look like? Which fields depend on each other? (Examples: country → language → first name and surname; age band → vocabulary, plot complexity and length.)
- Which combinations are invalid (always reject), and which are rare but real (allow at a set rate)?

Then:
- **Sample along the dependency graph.** Sample parent attributes first and condition the child fields on them. Never sample dependent fields independently.
- **Tag every component with its context** (e.g. each name with its locale, gender and era), so code can only combine compatible parts.
- **Model real-world mixing explicitly.** For example, give some share of people in Germany a Turkish surname, at a stated rate. Don't forbid mixing or leave it to chance.
- **Judge plausibility.** A worker on a stronger tier reasons over random samples and returns pass/fail with a reason. When failures form a pattern, fix the generator (vocabulary, dependencies or constraints), not just the filter.

This applies to every strategy. In S2, parts can clash; in S3, seed tuples can contradict each other; in S4, leaves can drift off-topic; in S5, transforms can change the meaning.

### Coherence across records and time

When the same entity appears in many records (a person in many events, an account in many transactions, a machine in many log lines), each record can look fine on its own while the records contradict each other. Build the generator so that these contradictions can't happen:
- **Time-varying state is a function, not a stored value.** Anything that changes over time (age, size, balance, rank, wear, inventory) comes from one function `state_at(entity, t)`, and every consumer calls it. Never freeze it into a field while later steps still read it. Export is the last step and is read-only: it writes derived copies and never mutates the state the generator uses.
- **Conditions that change state live inside the state function.** If a period changes an attribute (a promotion, a pregnancy, an outage, a sale), apply the change in `state_at`, not in the one code path that generates the most typical event. Otherwise the same entity has two different values at the same moment.
- **Fields bound by a relation are sampled together.** Low and high, start and end, parts and total, or two readings that must stay a set distance apart: sample one and derive the other, and clamp the relation, not each field separately.
- **Shared resources have capacity.** A person, room, vehicle or account can't be in two places or two events at once. Schedule with a calendar per resource instead of drawing times independently, and do the same for the entities the events are about.
- **Statuses come from history.** Flags like first or repeat, new or returning, active or lapsed are computed from the records already generated, never drawn at random. Codes, labels and prices that encode a status are derived from that same flag.
- **Canned text must be valid in every context it can be sampled into.** Vocabulary and template fragments go straight into seeds and outputs, so a fragment with a conditional caveat ("if over 1 year old", "where applicable") is a bug. Split it into variants tagged with their context.

Write each of these rules that applies as a checkable **invariant** in `coherence.md` and in `spec.invariants`, e.g. "an entity's attribute X at time t is identical in every record at t" or "no resource has overlapping events". The audit checks them.

## 3. Audit

The validator you write next to the generator shares the generator's blind spots: it checks the rules you thought of while you wrote the code, and the bug is usually in a rule you didn't think of. So audit independently:
- **Write `audit.py` from `coherence.md`, the spec and the data, not from the generator code.** Ideally a fresh sub-agent writes and runs it, seeing only those three inputs. It reports each finding with a count and an example.
- **Check every invariant**, plus these classes, which catch most bugs:
  - *format*: column counts, encodings, empty-value rates per field, one representation per type (booleans, dates, units)
  - *keys*: unique IDs, and every reference resolves
  - *relations between fields*: the relations from the Coherence rule hold in every row
  - *trajectories*: per entity, attributes change over time at a plausible rate and in the right direction (things that should grow do, things that should stay constant do)
  - *same-time consistency*: one entity, one moment, one value
  - *capacity*: no overlapping events per resource or per entity
  - *status vs history*: each status matches the records before it
  - *distributions per subgroup*: compare medians and percentiles within each stratum (age band, region, category) with a known reference. A global range check passes data that's wrong inside every stratum.
- **Triage every finding** as a real bug, an audit false positive, or rare but real (record its rate in `coherence.md`). Fix real bugs in the generator, then regenerate and re-audit.
- **Gate the expensive stage on the audit.** When workers generate from code-made seeds (S3 over structured records, S5 over generated data), they copy the seeds' errors into their output. Pass the audit before the pilot and the run, because a seed bug found afterwards means regenerating text.

## 4. Pilot

- Generate 200–1,000 items using the cheapest tier and the next tier up. Stratify the sample, with a minimum of about 20 items per stratum, so that rare categories get checked too. A proportional sample leaves them with a handful of items.
- Measure:
  - validity rate
  - exact and near-duplicate rate
  - quality against `quality_rubric`
  - truncation rate
  - items and output size per call
  - wall time per call
- Run a **sanity review**. A stronger-tier worker (or the user) reasons over 100 random items, flags anything unrealistic or contradictory, and names the cause. Fix the generator and repeat until the flag rate is below the threshold.
- Tune `items_per_call` up until quality, repetition or truncation gets worse.
- Choose the **cheapest tier that passes**. Record it in the spec.

## 5. Estimate

There's no per-token price, so the budget is the plan's usage limits.
- Total output tokens ≈ items × tokens per item, plus the per-call overhead × number of calls, plus the judge calls. For English, 1 word ≈ 1.33 tokens.
- Add expected losses from the pilot's dup, reject and plausibility-failure rates, and over-generate by that margin.
- Use the pilot's throughput to convert the total into worker calls, wall time and an estimated number of usage windows.
- Write the result to `estimate.md`. If the job needs more than a few usage windows, **tell the user before starting** and offer options: a smaller target, a more compact strategy (more S2, shorter items), or a long-running resumable job. Never quietly spend the whole subscription.
- **Treat the pilot estimate as rough.** A pilot moves the usage meter by a few points at most, so extrapolating from it multiplies its error by the scale-up factor. Re-estimate from the real run after its first 2–5% and confirm again if the total changes by more than about 25%.
- **Leave headroom for the user.** Workers draw on the same limits as the user's own interactive use. Agree a cap with the user, such as a share of each window or a number of calls per window, and keep `parallel` at a level where they can still work.

## 6. Run

**Seeds and shards**
- Generate seeds deterministically from `rng_seed`. Use only seeded RNG objects, and sort before iterating over sets or hash-ordered keys, so that a rebuild produces the same seeds in the same order.
- Split the seeds into shards. Each worker writes `raw/shard-XXXX.jsonl`, and every line includes its seed ID so outputs can be matched back to inputs.

**Manifest**
- `manifest.json` tracks each shard's status (pending, running, done or failed), its calls and model, and the **hash of its seed shard and of the prompt** that produced it. When either hash no longer matches the current files, the shard is stale: set it back to pending. Otherwise, after a generator or prompt fix, old outputs stay marked done and get mixed into the new data.
- **Track items, not only shards.** A shard whose valid items fall short of its seeds isn't done. Re-queue its missing and invalid items, batched into new calls, up to 2 times, then send them to `rejects/`. Losses concentrate in long, hard and last-in-batch items, so dropping them silently skews the data.
- Write the manifest atomically (write a temporary file, then rename it). Make it rebuildable from `seeds/` and `raw/`, so a lost manifest only costs a rescan.
- **Allow one run at a time.** Take a lock file holding the run's process ID at start, and refuse to start while a live process holds it. Otherwise a scheduled resume and a manual start do the same shards twice.

**Running unattended**
- Detach the run from the agent session so that ending the session doesn't kill it. Use `nohup`, a terminal multiplexer or the agent's background mode, and on macOS wrap it in `caffeinate -i` so the machine doesn't sleep.
- The run writes a small `status.json` (done, pending and failed counts, calls, last error, time of last progress). The orchestrator reads that, not the run's log.
- Runs are idempotent: skip shards that are done and current.

**Failures and limits**
- **Stop the whole run after a few consecutive failures** of any kind, e.g. 3. An expired login, network outage or changed CLI flag otherwise fails every remaining shard in seconds.
- **Usage limits:** when a worker hits a limit, mark its shard pending, stop the loop, and record which limit was hit (short window or weekly) and when it resets. Schedule the resume for that reset time if the agent supports scheduled tasks; otherwise tell the user. Never retry on a fixed short interval: a weekly limit makes every retry fail again.
- Write outputs to a temporary file and rename it when complete, so a killed worker never leaves a partial shard that looks finished.

**Validation and monitoring**
- Validate each shard as soon as it lands, with a standard-library script.
- **Validate content against the seed, not just the format.** Every fact that appears in both the seed and the output (numbers, names, categories, attributes) must match. Workers garble and invent facts in ways a schema check can't see. Also check that outputs aren't shifted between IDs within a batch.
- **Monitor repetition across the whole corpus, not only within a shard.** Keep a running index (exact hashes, MinHash bands, and counts of the most common opening n-grams) that each new shard is checked against. Phrasing that is rare within a call can still dominate across a thousand calls.
- On every shard, also judge a small sample. If the dup rate, plausibility or the model ID drifts, pause and fix the cause.

## 7. Post-process (standard library only, in this order)

1. Parse and schema-validate (`json`).
2. Normalize: `unicodedata` NFC, whitespace and casing rules.
3. Exact dedup: `hashlib` on the normalized text.
4. Near dedup: for long text, shingle into word 5-grams and use a small MinHash built on `hashlib` with banding. For short items, use normalized keys or `difflib` within buckets. Templated categories (short, formulaic items) collapse into near-duplicates first. Either add variation for them or accept their dup rate explicitly in `coherence.md`.
5. Plausibility and fact check: a judge worker checks a random sample, stratified so that small subgroups are covered, or every item if the set is small or `factuality: exact`. If the failure rate is above the threshold, go back to the generator.
6. Filter: length, language heuristics and banned terms.
7. Rebalance to the target distribution. Fill any deficit by generating only the missing slices.
8. Re-audit: run `audit.py` on the final data, since filtering and rebalancing can break invariants.
9. Export to `final/` (JSONL or CSV), using one representation per type across all files.

**At scale** (millions of items, or data larger than memory), every step streams: read shard by shard and never load the whole set. For near dedup, write each item's MinHash band keys to bucket files on disk, sort or group each bucket, and compare only items within it. Run the audit's checks per entity by first splitting records into files by entity ID. Run rebalancing deficit fills at most twice per slice; if a slice still falls short, report it rather than looping.

## 8. Report

Write `datacard.md` with:
- the spec, the strategy and a summary of `coherence.md`
- the worker model
- counts at each stage (generated → valid → deduped → plausible → filtered → final)
- dup rate, quality score and plausibility pass rate
- the invariants and the final audit result, including accepted rare-but-real findings with their rates
- calls and usage windows actually used compared with the estimate
- known biases and limitations

## Layout

```
jobs/<job>/spec.yaml  coherence.md  estimate.md  manifest.json  status.json  datacard.md
           prompts/  seeds/  raw/  rejects/  final/
           scripts/  run.sh  sample_seeds.py  validate.py  audit.py  postprocess.py
```

The scripts are driven entirely by `spec.yaml` and use only the shell and the Python standard library.

## Worked examples

- **50 cities per country**: S1. One worker call per batch of about 10 countries (~20 calls), returning JSON with names and populations. A second worker verifies that each city exists and belongs to its country. Some countries have fewer than 50 cities, so allow fewer and flag them rather than accepting invented ones.
- **10M names**: S2 with conditioning. About 100 worker calls produce per-locale first names (tagged by gender, era and frequency) and surnames (tagged by origin). For each person, code samples country → name origin (mostly local, plus a mixing rate) → gender → birth decade, then picks a first name and surname that fit. Generating the 10M takes seconds and uses no subscription. A judge checks a sample. If the names must be unique, make the combination space at least 10× N.
- **1M children's stories**: S3. Axes are age band, theme, setting, protagonist, conflict, moral, tone and length, with dependencies (e.g. age band limits themes and length). Names come from S2. That's about 0.7B output tokens, so expect many usage windows. Estimate first and agree on the scope with the user.
- **Relational dataset with text** (e.g. customers, orders and support tickets over two years): S2 for the tables and S3 for the text, with each record as the seed. A customer's tier, balance and address come from `state_at(customer, t)`. Support agents get calendars, so no agent works two tickets at once. "First order" is computed from order history. A fresh sub-agent audits the tables from `coherence.md` before any ticket text is generated, and each ticket is checked against the facts in its record.
- **100M words**: S4. Build a taxonomy of about 20 domains × 50 subtopics × 50 angles, with long outputs per call. That's about 133M output tokens, so run it as a long, resumable, rate-limited job and confirm the scope first.