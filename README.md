# claude-skills

A collection of personal [Agent Skills](https://agentskills.io) for AI coding agents.
Each skill is a self-contained `SKILL.md` (plus optional reference files) that works
with **Claude Code** and **GitHub Copilot CLI** — same format, two hosts.

This repo is the **source of truth**. You edit skills here, then deploy them into
your agent's skills directory with [`deploy.sh`](#install).

## Skills

| Skill | What it does |
|-------|--------------|
| [`helm-chart-creator`](skills/helm-chart-creator/) | Interviews you, then generates a production-grade, self-contained Helm chart (Bitnami conventions inlined — no OCI dependency) with security hardening, multi-environment values (dev/uat/prod), a `values.schema.json`, and validates the output with `kube-linter` + `kube-score`. Built for non-experts: every question has a default, an example, and explain-on-demand. The interview is a **blocking gate** — it never assumes defaults silently. Also runs an **improve mode** that audits and hardens an *existing* chart without changing its structure, presenting a proposal list first. Output is **deterministic** (templates copied verbatim) with a [test harness](skills/helm-chart-creator/tests/) to verify it. |
| [`helm-chart-token-optimized`](skills/helm-chart-token-optimized/) | **Token-lean, deterministic sibling** of `helm-chart-creator` — same production-grade output, but generation runs through a bundled `scaffold.sh` so template bodies never pass through the model's context (~40K tokens/chart saved). Short **tiered interview** (essentials first, full list on demand), confirmed once; same blocking gate and improve mode. Output is **byte-identical** for identical answers (`cp`+`sed`, not model text). **Every environment (dev/uat/prod) passes `kube-score` with 0 CRITICAL and `kube-linter` clean out of the box** — identical security posture across envs (non-root UID ≥10000, NetworkPolicy on, always-pull, ephemeral-storage, replica-safe PDB); only scale/resources differ. Ships a **no-model [test suite](skills/helm-chart-token-optimized/tests/)** (`run-all.sh`): determinism, placeholder/defaults parity, schema lint, and a kube-linter/kube-score quality gate. |

## Install

Clone the repo, then deploy with the script. By default it publishes **all** skills
to Claude Code; use `--target` to choose where they go.

```bash
git clone git@github.com:ifalex/claude-skills.git
cd claude-skills

./deploy.sh                       # all skills  -> Claude Code (~/.claude/skills)
./deploy.sh helm-chart-creator    # one skill   -> Claude Code
./deploy.sh --target copilot      # all skills  -> Copilot CLI (~/.copilot/skills)
./deploy.sh --target all          # all skills  -> both hosts
./deploy.sh --dry-run             # preview, change nothing
```

Re-run `deploy.sh` whenever you pull updates. It replaces the deployed copy with
the repo version (your edits live in the repo, not in the agent's skills folder).

### Manual install (no script)

A skill is just a directory containing `SKILL.md`. Copy it into the right place:

| Host | Personal (all projects) | Project-scoped |
|------|-------------------------|----------------|
| **Claude Code** | `~/.claude/skills/<name>/` | `.claude/skills/<name>/` |
| **GitHub Copilot CLI** | `~/.copilot/skills/<name>/` | `.github/skills/<name>/` |

```bash
# Claude Code (personal)
cp -R skills/helm-chart-creator ~/.claude/skills/

# GitHub Copilot CLI (personal)
cp -R skills/helm-chart-creator ~/.copilot/skills/
```

> Copilot CLI also reads `~/.claude/skills/` and `~/.agents/skills/` for personal
> skills, so a single Claude Code install is often picked up by both. The
> `~/.copilot/skills/` path above is the canonical Copilot location.

## Usage

Both hosts use the skill's `description` for automatic discovery — just describe the
task and the skill triggers. You can also call it explicitly:

- **Claude Code:** `Create a Helm chart for my service` (auto), or invoke the
  `helm-chart-creator` skill directly.
- **Copilot CLI:** `Use the /helm-chart-creator skill to chart my service`
  (a leading `/` plus the skill name selects it).
- **Improve an existing chart:** point it at a directory that already contains a
  `Chart.yaml` (e.g. `Harden my existing chart in ./charts/api`). It audits the
  chart, shows a proposal list grouped by severity, asks only the questions it
  can't answer from the chart, and applies fixes in place without restructuring.

**Two flavours of the Helm chart skill:** `helm-chart-creator` (v1) writes the
templates through the conversation; `helm-chart-token-optimized` (v2) hands a
small answer file to a bundled `scaffold.sh` that renders on disk, so it uses far
fewer tokens and is byte-deterministic — pick v2 for minimal token usage or
CI-repeatable generation.

Verify what's installed:

```bash
ls ~/.claude/skills/      # Claude Code personal skills
ls ~/.copilot/skills/     # Copilot CLI personal skills
```

## Repo layout

```
claude-skills/
├── README.md
├── deploy.sh                       # copy skills -> agent skills dir(s)
└── skills/
    ├── helm-chart-creator/         # v1: writes templates through the conversation
    │   ├── SKILL.md                # orchestration: interview gate, create/improve modes, quality gates
    │   ├── reference/              # loaded on demand by the agent
    │   │   ├── explanations.md     # question catalog + "what is X" explainers
    │   │   ├── improve-existing.md # improve-mode audit checklist + proposal format
    │   │   ├── values-and-schema.md
    │   │   ├── quality-gates.md
    │   │   └── templates/          # every chart file (CHARTNAME placeholder)
    │   └── tests/                  # platform-neutral determinism harness
    │       ├── compare-charts.sh   # diff two charts; PASS if ≥95% identical
    │       ├── run-determinism.sh  # run a scenario N times on any agent CLI, then compare
    │       └── scenario-a.*        # fixed interview answers (prompt + human-readable)
    └── helm-chart-token-optimized/ # v2: renders on disk via scaffold.sh (token-lean, deterministic)
        ├── SKILL.md                # tiered interview, --plan confirm, scaffold-based generation
        ├── scaffold.sh             # deterministic cp+sed generator (templates never enter context)
        ├── answers.example.env     # fill-in answer file (the only thing passed through context)
        ├── reference/              # explanations, improve-existing, values-and-schema, quality-gates, templates/
        ├── docs/further-proposals.md
        └── tests/                  # no-model guard suite (run-all.sh)
            ├── run-scaffold-determinism.sh # scaffold twice, byte-compare (+ render overlays)
            ├── check-placeholder-parity.sh # %%X%% in tmpl <-> `add X` in scaffold.sh
            ├── check-defaults-parity.sh    # answers.example.env keys <-> scaffold.sh vars
            ├── lint-all-features.sh         # all toggles on; helm lint vs values.schema.json
            ├── check-kube-quality.sh        # kube-linter clean + kube-score 0 CRITICAL (uat/prod)
            └── check-deployed-sync.sh       # deployed copy vs repo (drift guard)
```

## Adding a new skill

1. Create `skills/<name>/SKILL.md` (see the
   [Agent Skills spec](https://agentskills.io/specification) for frontmatter).
2. Keep `SKILL.md` lean; put heavy reference material in sibling files it links to.
3. `./deploy.sh <name>` to publish, then test it in your agent.

## License

MIT — see [LICENSE](LICENSE) if present, otherwise use freely.
