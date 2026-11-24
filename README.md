# Synthetic Data Generation skill

A skill for coding agents that plans and runs large-scale synthetic data generation, such as names, lists, stories, relational tables and free text, on a single agent subscription. The orchestrating agent writes the spec, prompts and scripts. Cheap worker models generate the data straight to files. Plain shell and the Python standard library do everything deterministic: sampling, validation, dedup and audits. It needs no API keys, SDKs or package installs.

## What it covers

- **Strategy choice**: retrieve, enumerate, compose from parts, seeded grids, tree expansion or transforms, picking the one that needs the fewest generated tokens.
- **Coherence**: dependent fields are sampled along a dependency graph. For data where entities persist across records, it adds rules for time-varying state, joint constraints, resource capacity and statuses derived from history.
- **Independent audit**: an audit written from the spec and coherence notes, not from the generator code. It must pass before any expensive text generation.
- **Pilot and estimate**: a stratified pilot, a choice of model tier, and a usage estimate against the subscription's limits that is re-checked once the real run starts.
- **Long unattended runs**: resumable shards, a manifest that notices stale outputs, per-item retries, a single-run lock, a stop after repeated failures, and handling of both short-window and weekly limits.
- **Post-processing at any scale**: normalization, exact and near dedup, plausibility judging, rebalancing, re-audit and a data card.

## Install

### Claude Code (plugin)

```
/plugin marketplace add FlorianSchwieren/synthetic-data-generation
/plugin install synthetic-data-generation@synthetic-data
```

Then ask for a dataset, for example "generate 100,000 realistic customer support tickets", and the skill loads when it's relevant.

### claude.ai and the Claude apps

Build the upload zip, then upload it in your claude.ai settings under skills:

```
./scripts/build-zip.sh        # writes dist/synthetic-data-generation.zip
```

### Other agents

The skill is a single `SKILL.md` file in a folder. Agents that support this format can use `plugins/synthetic-data-generation/skills/synthetic-data-generation/` directly.

## Requirements and limits

- The worked commands for headless workers use the Claude Code CLI (`claude -p`). For other agents, use their non-interactive mode, as the skill describes.
- `caffeinate` (which keeps the machine awake during long runs) is macOS-only. On other systems, use the equivalent or a server.
- Large jobs can use several usage windows. The skill estimates that first and asks before starting, but you're responsible for what your subscription allows.

## Layout

```
.claude-plugin/marketplace.json                      marketplace listing
plugins/synthetic-data-generation/
  .claude-plugin/plugin.json                         plugin metadata
  skills/synthetic-data-generation/SKILL.md          the skill
scripts/build-zip.sh                                 builds the claude.ai upload zip
```

## Changelog

### 1.0.0
- Coherence across records and time: state as a function of entity and time, joint sampling, capacity, statuses from history, context-safe canned text.
- New independent audit step, which must pass before the pilot and run.
- Long-run robustness: hashes that mark stale shards, per-item retries, atomic manifest writes, a run lock, detached runs, a stop after repeated failures, and limit-aware resume.
- Pinned model IDs, stratified pilots, re-estimation after the start, headroom for the user, and corpus-wide repetition monitoring.
- Streaming post-processing at scale.
