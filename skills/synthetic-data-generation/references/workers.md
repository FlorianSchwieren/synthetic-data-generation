# Workers

A worker is one call to a cheaper model through the same subscription. This file has the headless command for each common agent and the rules that apply to all of them.

## Rules for every agent

- **Check the installed CLI first.** Run its `--help` before writing `worker.sh`, because flags change between versions. Then run one real call on a pilot shard and inspect the raw output before starting a loop.
- **Pin the exact model ID.** List the agent's models, pick the smallest one that passes the pilot, and write its full ID into the spec. An alias like "the fast model" can move to a newer model in the middle of a run that spans days. Record the model each call actually used (most agents report it in their JSON output) and check it on every shard.
- **Give workers no tools.** A worker only reads its prompt and writes text. Use the agent's read-only mode, or run with no tool permissions, so a worker can't touch files or run commands.
- **Send the prompt through a file.** Write each call's full prompt (instructions plus the seed batch) to `calls/shard-XXXX.txt` and pass it in as shown below. Long prompts on the command line can hit the shell's argument-length limit.
- **Capture output to a temporary file and rename it only when complete,** so a killed worker never leaves a partial shard that looks finished.
- **Capture usage and errors.** Prefer the agent's JSON output mode: it usually includes the model, token usage and an error flag. Save those to `logs/shard-XXXX.usage.json`.
- **Detect usage limits by exit code and message.** Each agent words its limit errors differently. In the pilot, note what a limit error looks like, if you can see one, and match it precisely. A loose pattern such as "rate" also matches text like "heart rate".
- **Pack many items into each call.** Every call has a fixed overhead (system prompt and setup), so batch 100–300 short items or 5–20 long ones per call, tuned in the pilot.
- **Ask for JSONL only**, one line per seed, with the seed ID in each line, and strip any Markdown code fences before validating.

## Headless commands

Replace `<model-id>` with the pinned model ID. Each command reads the prompt from `calls/shard-0042.txt` and writes to a temporary file.

### Claude Code

```
claude -p --model <model-id> --tools "" --no-session-persistence --output-format json \
  < calls/shard-0042.txt > raw/shard-0042.tmp
```

- The JSON has the text in `result`, usage in `usage` and `modelUsage`, and `is_error` for failures.
- `--system-prompt "<one line>"` replaces the default system prompt, which reduces per-call overhead.
- Sub-agents: use the Agent tool with a model override, or define `.claude/agents/datagen-worker.md` with `model:` set.

### OpenAI Codex CLI

```
codex exec -m <model-id> -s read-only --skip-git-repo-check --ephemeral --json \
  -o raw/shard-0042.tmp - < calls/shard-0042.txt > logs/shard-0042.events.jsonl
```

- `-` reads the prompt from stdin. `-o` writes only the final message, which is the JSONL you want. `--json` streams events, including usage, to stdout.
- `-p` is **not** a prompt flag in Codex: it selects a config profile.
- Don't pass a prompt argument while stdin is open: with an inherited stdin, Codex can wait for input forever. Always redirect from a file as above.
- `--ignore-user-config` skips the user's `config.toml`, which keeps runs reproducible. Authentication still works.

### Google Gemini CLI

```
gemini -m <model-id> --output-format json \
  -p "Follow the instructions in the input above." < calls/shard-0042.txt > raw/shard-0042.tmp
```

- Piped input is combined with the `-p` text. The JSON has the text in `response` and usage in `stats`. An `error` key appears only on failure.
- Gemini CLI may refuse to run headless in a folder it doesn't trust. Trust the job folder once interactively before starting the loop.
- Workers get no tool approvals headless, so they can't change files.

### GitHub Copilot CLI

```
copilot -p "$(cat calls/shard-0042.txt)" -s --model <model-id> --no-ask-user > raw/shard-0042.tmp
```

- `-s` prints only the response. Without `--allow-tool`, the worker can't use tools.
- Copilot ignores piped input when `-p` is given, so the prompt goes in as the argument. Keep each call's prompt well under the shell's argument limit (about 1 MB on macOS and Linux), and split the shard if needed.
- Copilot meters premium requests per call, and each model has a multiplier. Larger batches per call are much cheaper.

### Cursor CLI

```
agent -p "$(cat calls/shard-0042.txt)" --model <model-id> --mode ask --output-format json > raw/shard-0042.tmp
```

- `--mode ask` is read-only. In print mode the agent otherwise has full tool access.
- The same argument-length limit as for Copilot applies.
- Inspect one JSON output in the pilot to find the fields that hold the text and the usage.

### Other agents

Any agent with a non-interactive mode works. You need a way to (1) pass a long prompt from a file, (2) choose the model, (3) disable tools, and (4) get the response on stdout or in a file, ideally as JSON with usage. If the agent has no headless mode, use its sub-agents for small jobs and tell the user that large jobs need a headless-capable agent.

## Sub-agents

If the agent can spawn sub-agents with a cheaper model, use them for pilots, judging and small jobs. Each sub-agent writes its shard with the file tool and returns one line. Sub-agent results return into your context, so keep the one-line rule strict. For anything above a few hundred calls, use headless mode.
