# Long runs

A large job runs for hours or days across several usage windows. These rules keep it correct, resumable and cheap.

## Seeds and shards

- Generate seeds deterministically from `rng_seed`. Use only seeded RNG objects, and sort before iterating over sets or hash-ordered keys, so a rebuild produces the same seeds in the same order.
- Split the seeds into shards. Each worker writes `raw/shard-XXXX.jsonl`, and every line includes its seed ID so outputs can be matched back to inputs.

## Manifest

- `manifest.json` tracks each shard's status (pending, running, done or failed), its calls and model, and the **hash of its seed shard and of the prompt** that produced it. When either hash no longer matches the current files, the shard is stale: set it back to pending. Otherwise, after a generator or prompt fix, old outputs stay marked done and get mixed into the new data.
- **Track items, not only shards.** A shard whose valid items fall short of its seeds isn't done. Re-queue its missing and invalid items, batched into new calls, up to 2 times, then send them to `rejects/`. Losses concentrate in long, hard and last-in-batch items, so dropping them silently skews the data.
- Write the manifest atomically (write a temporary file, then rename it). Make it rebuildable from `seeds/` and `raw/`, so a lost manifest only costs a rescan.
- **Allow one run at a time.** At start, take a lock file holding the run's process ID, and refuse to start while a live process holds it. Otherwise a scheduled resume and a manual start do the same shards twice.

## Running unattended

- Detach the run from the agent session, so ending the session doesn't kill it. Use `nohup`, a terminal multiplexer or the agent's background mode. On macOS, wrap it in `caffeinate -i` so the machine doesn't sleep. On Linux, use `systemd-inhibit` or run it on a server.
- The run writes a small `status.json` (done, pending and failed counts, calls, last error, time of last progress). The orchestrator reads that, not the run's log, so the log never floods its context.
- Runs are idempotent: skip shards that are done and current.

## Failures and limits

- **Stop the whole run after a few consecutive failures** of any kind, e.g. 3. An expired login, network outage or changed CLI flag otherwise fails every remaining shard in seconds.
- **Usage limits:** when a worker hits a limit, mark its shard pending, stop the loop, and record which limit was hit (short window or weekly) and when it resets. Schedule the resume for that time if the agent supports scheduled tasks; otherwise tell the user. Never retry on a fixed short interval: under a weekly limit, every retry fails again.
- Respect the cap agreed with the user: count calls per window, and pause when the cap is reached even if the agent would allow more.

## Validation and monitoring

- Validate each shard as soon as it lands, with a standard-library script.
- **Validate content against the seed, not just the format.** Every fact that appears in both the seed and the output (numbers, names, categories, attributes) must match. Workers garble and invent facts in ways a schema check can't see. Also check that outputs aren't shifted between IDs within a batch.
- **Monitor repetition across the whole corpus, not only within a shard.** Keep a running index (exact hashes, MinHash bands, and counts of the most common opening n-grams) that each new shard is checked against. Phrasing that's rare within one call can still dominate across a thousand calls.
- On every shard, also judge a small sample. If the dup rate, plausibility or the model ID drifts, pause and fix the cause.
- After the first 2–5% of the run, compare actual usage with `estimate.md`, and re-confirm with the user if the total moves by more than about 25%.
