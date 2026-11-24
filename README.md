# Synthetic Data Generation skill

A skill for coding agents that plans and runs large-scale synthetic data generation, such as names, lists, stories, relational tables and free text, on a single agent subscription. The orchestrating agent writes the spec, prompts and scripts. Cheap worker models generate the data straight to files. Plain shell and the Python standard library do everything deterministic: sampling, validation, dedup and audits. It needs no API keys, SDKs or package installs.

It follows the open [Agent Skills](https://agentskills.io) format (a folder with a `SKILL.md`), so it works with Claude Code, OpenAI Codex, Gemini CLI, GitHub Copilot, Cursor and other agents that support it.

## What it covers

- **Strategy choice**: retrieve, enumerate, compose from parts, seeded grids, tree expansion or transforms, picking the one that needs the fewest generated tokens.
- **Coherence**: dependent fields are sampled along a dependency graph. For data where entities persist across records, it adds rules for time-varying state, joint constraints, resource capacity and statuses derived from history.
- **Independent audit**: an audit written from the spec and coherence notes, not from the generator code. It must pass before any expensive text generation.
- **Pilot and estimate**: a stratified pilot, a choice of model, and a usage estimate against the subscription's limits that is re-checked once the real run starts.
- **Workers for each agent**: tested-pattern headless commands for Claude Code, Codex, Gemini CLI, Copilot CLI and Cursor CLI, with each one's pitfalls.
- **Long unattended runs**: resumable shards, a manifest that notices stale outputs, per-item retries, a single-run lock, a stop after repeated failures, and handling of both short-window and weekly limits.
- **Post-processing at any scale**: normalization, exact and near dedup, plausibility judging, rebalancing, re-audit and a data card.

## Install

### Claude Code

Add the marketplace:

```bash
/plugin marketplace add FlorianSchwieren/synthetic-data-generation
```

Then install the plugin:

```bash
/plugin install synthetic-data-generation@synthetic-data
```

### Gemini CLI

```bash
gemini extensions install https://github.com/FlorianSchwieren/synthetic-data-generation
```

### Codex, Cursor, GitHub Copilot and other agents

These agents all read skills from the shared folder `~/.agents/skills/`. Clone the repo:

```bash
git clone https://github.com/FlorianSchwieren/synthetic-data-generation.git
```

Then run the install script from inside the clone:

```bash
./synthetic-data-generation/scripts/install.sh
```

By default, it copies the skill to `~/.agents/skills/` and `~/.claude/skills/`. Options:

- `--link` symlinks instead of copying, so a `git pull` updates the skill.
- `--project DIR` installs into a repository instead of your home folder, so everyone working in that repository gets the skill.
- Targets choose agent-specific folders: `agents` (Codex, Gemini CLI, Cursor, Copilot), `claude`, `gemini`, `cursor` or `copilot`. For example, `./synthetic-data-generation/scripts/install.sh cursor` installs to `~/.cursor/skills/`.

To install by hand, copy `skills/synthetic-data-generation/` into the skills folder your agent reads.

### claude.ai and the Claude apps

Build the upload zip from inside the clone:

```bash
./synthetic-data-generation/scripts/build-zip.sh
```

Then upload `dist/synthetic-data-generation.zip` in your claude.ai settings under skills.

## Use

Ask your agent for a dataset, for example "generate 100,000 realistic customer support tickets". The skill loads when it's relevant. Large jobs can use several usage windows: the skill estimates that first and asks before starting.

## Requirements and limits

- For large jobs, the agent needs a non-interactive (headless) mode with a model option. The commands for each agent are in [`references/workers.md`](skills/synthetic-data-generation/references/workers.md). CLI flags change between versions, so the skill checks `--help` and pilots one call first.
- On Gemini CLI versions where Agent Skills are still experimental, enable them in its settings first.
- The skill keeps long runs awake with `caffeinate` on macOS and `systemd-inhibit` on Linux, or you can run them on a server.
- You're responsible for what your subscription and its terms allow.

## Layout

```
skills/synthetic-data-generation/SKILL.md            the skill (core workflow)
skills/synthetic-data-generation/references/         details, loaded when needed
.claude-plugin/marketplace.json, plugin.json         Claude Code marketplace and plugin
gemini-extension.json                                Gemini CLI extension
scripts/install.sh                                   installs for any agent
scripts/build-zip.sh                                 builds the claude.ai upload zip
LICENSE                                              MIT license
```

## License

[MIT](LICENSE): free to use, copy, modify and distribute, including commercially, as long as the copyright notice is kept.

## Changelog

### 1.1.0
- Works with any agent that supports the Agent Skills format. Adds headless worker commands for Claude Code, Codex, Gemini CLI, Copilot CLI and Cursor CLI.
- The skill is split into a short `SKILL.md` and reference files, to stay within the Agent Skills size guidance.
- Adds a Gemini CLI extension and an install script for the shared `~/.agents/skills/` folder and agent-specific folders.

### 1.0.0
- Coherence across records and time: state as a function of entity and time, joint sampling, capacity, statuses from history, context-safe canned text.
- New independent audit step, which must pass before the pilot and run.
- Long-run robustness: hashes that mark stale shards, per-item retries, atomic manifest writes, a run lock, detached runs, a stop after repeated failures, and limit-aware resume.
- Pinned model IDs, stratified pilots, re-estimation after the start, headroom for the user, and corpus-wide repetition monitoring.
- Streaming post-processing at scale.
