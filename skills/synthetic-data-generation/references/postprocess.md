# Post-processing and the data card

## Steps (standard library only, in this order)

1. Parse and schema-validate (`json`).
2. Normalize: `unicodedata` NFC, whitespace and casing rules.
3. Exact dedup: `hashlib` on the normalized text.
4. Near dedup: for long text, shingle into word 5-grams and use a small MinHash built on `hashlib`, with banding. For short items, use normalized keys or `difflib` within buckets. Templated categories (short, formulaic items) collapse into near-duplicates first. Either add variation for them or accept their dup rate explicitly in `coherence.md`.
5. Plausibility and fact check: a judge worker checks a random sample, stratified so that small subgroups are covered, or every item if the set is small or `factuality: exact`. If the failure rate is above the threshold, go back to the generator.
6. Filter: length, language heuristics and banned terms.
7. Rebalance to the target distribution. Fill any deficit by generating only the missing slices, at most twice per slice. If a slice still falls short, report it rather than looping.
8. Re-audit: run `audit.py` on the final data, since filtering and rebalancing can break invariants.
9. Export to `final/` (JSONL or CSV), using one representation per type across all files (e.g. booleans always `true`/`false`, dates always ISO 8601).

## At scale

With millions of items, or data larger than memory, every step streams: read shard by shard and never load the whole set.
- Near dedup: write each item's MinHash band keys to bucket files on disk, sort or group each bucket, and compare only items within it.
- Audit: split records into files by entity ID first, then run the per-entity checks one file at a time.

## Data card

Write `datacard.md` with:
- the spec, the strategy and a summary of `coherence.md`
- the worker and judge model IDs, and the agent used
- counts at each stage (generated → valid → deduped → plausible → filtered → final)
- dup rate, quality score and plausibility pass rate
- the invariants and the final audit result, including accepted rare-but-real findings with their rates
- calls and usage windows actually used, compared with the estimate
- known biases and limitations
