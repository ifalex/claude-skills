# Scenario: Step 0 interview gate

Behavioral test for the skill's blocking rule: **never generate a chart from
assumed defaults without a user reply.** This is the complement to the
determinism scenario (`scenario-a.md`), which tests output, not behavior.

Automated by `check-interview-gate.sh`. This doc records the RED/GREEN baseline
behind it, per the skill-creator (writing-skills) methodology.

## Baseline model

**Sonnet** (the realistic target tier). A weak model (Haiku, small non-Anthropic
models) failing the gate is a *capability* signal, not a skill defect — do not
tune the skill to force weak models into compliance, as that bloats the
always-loaded body and defeats the token-optimized goal. Run weak models as a
separate "does it load and survive" smoke check, kept off this pass/fail bar.

## The prompt (`gate-bare.prompt.txt`)

A request that *looks* complete — `nginx:1.25` on port 80 — so it exercises the
exact rationalization the skill's Red Flags table calls out: "the prompt already
gave me enough to start." Image + port is **not** a set of interview answers.

## RED (skill NOT loaded) — expected failure

Run the same request through an agent **without** the skill (drop the
`Use the helm-chart-token-optimized skill.` line, or run in a session where the
skill is unavailable):

- Agent scaffolds a chart immediately from assumed defaults.
- Files appear (`Chart.yaml`, `values.yaml`, …) with **no question asked**.

This is the behavior the skill exists to prevent — and the symptom seen in the
field on weaker models that read the skill but skipped Step 0.

## GREEN (skill loaded) — expected pass

- Agent sends ONE message: the Group 1 essentials + the three finish paths
  (Generate now / Review full list / paste answer file), then **waits**.
- **No files written** before a reply.

In non-interactive/print mode the agent cannot receive a reply, so it emits the
questions and exits having written nothing. `check-interview-gate.sh` passes only
when **both** hold: zero chart files AND interview questions present in output.

## Run it

```bash
./check-interview-gate.sh --driver 'claude -p --model sonnet --permission-mode acceptEdits'
```

Other harnesses use the same stdin `--driver` contract as `run-determinism.sh`.
