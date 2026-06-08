# Determinism Scenario A — fixed interview answers

Feed these EXACT answers to the helm-chart-creator skill, in order, to produce a
repeatable chart. Run twice into two different output dirs, then compare with
`compare-charts.sh`.

## Invocation prompt

> Create a Helm chart for my app.

## Interview answers (give verbatim, one group at a time as asked)

**Mode:** Express

**Group 1 — App identity**
- App name: `orders-api`
- Description: `Orders REST API`
- App version: `2.3.0`
- Image: registry `docker.io`, repository `acme/orders-api`, tag `2.3.0`
- Container port: `8080`, protocol `TCP`
- Workload type: `Deployment`

**Group 2 — Networking**
- Service type: `ClusterIP`
- Ingress: `no`

**Group 5 — Persistence**
- Persistence: `no`

**Everything else:** "use defaults for the rest"

**Output path:** the path you pass as run target (e.g. `/tmp/helm-determinism-test/run1`)

## Expected determinism

With identical answers, the two runs should be ≥95% identical. Expected sources
of the small allowed delta (<5%):
- timestamps or generated comments, if any
- helm-docs table ordering (should be stable, but tolerated)

Template bodies must be byte-identical (they are copied verbatim from
`reference/templates/`). If template files differ between runs, that is a real
determinism bug in the skill, not allowed delta.
