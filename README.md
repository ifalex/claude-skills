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
    └── helm-chart-creator/
        ├── SKILL.md                # orchestration: interview gate, create/improve modes, quality gates
        ├── reference/              # loaded on demand by the agent
        │   ├── explanations.md     # question catalog + "what is X" explainers
        │   ├── improve-existing.md # improve-mode audit checklist + proposal format
        │   ├── values-and-schema.md
        │   ├── quality-gates.md
        │   └── templates/          # every chart file (CHARTNAME placeholder)
        └── tests/                  # platform-neutral determinism harness
            ├── compare-charts.sh   # diff two charts; PASS if ≥95% identical
            ├── run-determinism.sh  # run a scenario N times on any agent CLI, then compare
            └── scenario-a.*        # fixed interview answers (prompt + human-readable)
```

## Adding a new skill

1. Create `skills/<name>/SKILL.md` (see the
   [Agent Skills spec](https://agentskills.io/specification) for frontmatter).
2. Keep `SKILL.md` lean; put heavy reference material in sibling files it links to.
3. `./deploy.sh <name>` to publish, then test it in your agent.

## License

MIT — see [LICENSE](LICENSE) if present, otherwise use freely.
