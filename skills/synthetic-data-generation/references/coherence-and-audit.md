# Coherence across records and time, and the independent audit

## Coherence across records and time

When the same entity appears in many records (a person in many events, an account in many transactions, a machine in many log lines), each record can look fine on its own while the records contradict each other. Build the generator so that these contradictions can't happen:

- **Time-varying state is a function, not a stored value.** Anything that changes over time (age, size, balance, rank, wear, inventory) comes from one function `state_at(entity, t)`, and every consumer calls it. Never freeze it into a field while later steps still read it. Export is the last step and is read-only: it writes derived copies and never mutates the state the generator uses.
- **Conditions that change state live inside the state function.** If a period changes an attribute (a promotion, a pregnancy, an outage, a sale), apply the change in `state_at`, not in the one code path that generates the most typical event. Otherwise the same entity has two different values at the same moment.
- **Fields bound by a relation are sampled together.** Low and high, start and end, parts and total, or two readings that must stay a set distance apart: sample one and derive the other, and clamp the relation, not each field separately.
- **Shared resources have capacity.** A person, room, vehicle or account can't be in two places or two events at once. Schedule with a calendar per resource instead of drawing times independently, and do the same for the entities the events are about.
- **Statuses come from history.** Flags like first or repeat, new or returning, active or lapsed are computed from the records already generated, never drawn at random. Codes, labels and prices that encode a status are derived from that same flag.
- **Canned text must be valid in every context it can be sampled into.** Vocabulary and template fragments go straight into seeds and outputs, so a fragment with a conditional caveat ("if over 1 year old", "where applicable") is a bug. Split it into variants tagged with their context.

Write each rule that applies as a checkable **invariant** in `coherence.md` and in `spec.invariants`, e.g. "an entity's attribute X at time t is identical in every record at t" or "no resource has overlapping events". The audit checks them.

## The independent audit

The validator you write next to the generator shares the generator's blind spots: it checks the rules you thought of while you wrote the code, and the bug is usually in a rule you didn't think of. So audit independently.

**Who writes it.** Write `audit.py` from `coherence.md`, the spec and the data, not from the generator code. Ideally a fresh sub-agent (or a separate headless call on a strong model) writes and runs it, seeing only those three inputs. It reports each finding with a count and an example.

**What it checks.** Every invariant, plus these classes, which catch most bugs:
- *Format*: column counts, encodings, empty-value rates per field, one representation per type (booleans, dates, units).
- *Keys*: unique IDs, and every reference resolves.
- *Relations between fields*: the relations from the coherence rules hold in every row.
- *Trajectories*: per entity, attributes change over time at a plausible rate and in the right direction. Things that should grow do, and things that should stay constant do.
- *Same-time consistency*: one entity, one moment, one value.
- *Capacity*: no overlapping events per resource or per entity.
- *Status vs history*: each status matches the records before it.
- *Distributions per subgroup*: compare medians and percentiles within each stratum (age band, region, category) with a known reference. A global range check passes data that's wrong inside every stratum.

**Triage.** Classify every finding as a real bug, an audit false positive, or rare but real (record its rate in `coherence.md`). Fix real bugs in the generator, not in a filter, then regenerate and re-audit.

**Gate.** When workers generate from code-made seeds (S3 over structured records, S5 over generated data), they copy the seeds' errors into their output. Pass the audit before the pilot and the run, because a seed bug found afterwards means regenerating text. Run the audit again on the final data, since filtering and rebalancing can break invariants.
