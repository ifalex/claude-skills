# Values documentation with helm-docs

Every generated chart ships a **`README.md`** containing a values table, produced by
[helm-docs](https://github.com/norwoodj/helm-docs) from `# --` annotations in
`values.yaml`. helm-docs is the chart-ecosystem standard: a single Go binary, runs in
CI/pre-commit, and keeps the docs in lock-step with the values.

This skill annotates `values.yaml` in **helm-docs convention** (`# --`), not Bitnami
`## @param`. `values.schema.json` is still hand-authored (see `values-and-schema.md`) —
helm-docs does not generate schemas.

## Install

```bash
brew install norwoodj/tap/helm-docs            # macOS
go install github.com/norwoodj/helm-docs/cmd/helm-docs@latest   # any platform with Go
# or Docker: docker run --rm -v "$(pwd):/helm-docs" -u $(id -u) jnorwood/helm-docs:latest
```

If it isn't installed and can't be added, **say so and skip** — don't hand-fake a
README values table. A correct table can always be generated later by running the tool.

## Annotation contract (how to comment values.yaml)

Put a `# --` comment **directly above the leaf key** it documents:

```yaml
# -- Number of replicas to run
replicaCount: 1

image:
  # -- Container image registry
  registry: docker.io
  # -- (string) Image tag, defaults to chart appVersion
  tag: ""
  # -- Optional image pull secrets
  # @default -- []
  pullSecrets: []
```

Rules (all verified against helm-docs v1.14.2):
- **`# -- <description>`** documents the value on the next line. Column order in the
  output is `Key | Type | Default | Description`.
- **Type hint:** `# -- (int) ...`, `# -- (string) ...` forces the Type column — useful
  for empty values (`tag: ""`) where helm-docs can't infer a meaningful type.
- **Multi-line:** continue on following `#` lines *without* the `--`.
- **`# @default -- <text>`** overrides the shown Default (e.g. for computed defaults or
  to show `[]`/`{}` cleanly).
- **`# @ignored`** hides a value from the table.
- **Leaf vs container:** by default every leaf (scalar, empty list/map) is auto-listed
  even without a comment. Putting a `# --` on a **parent** key documents the whole block
  as one row and **suppresses its nested leaves** — only do that for opaque blocks
  (e.g. `podSecurityContext`); leave parents un-commented when you want each child shown.

Keep the `## @section <Title>` divider comments in `values.yaml` for human readability
if you like — helm-docs ignores any comment that isn't `# --`/`# @...`, so they're inert.

## Generate the README

Run from the chart directory (or point at it). helm-docs writes/refreshes the `## Values`
section of `README.md` using its built-in template:

```bash
helm-docs --chart-search-root=./CHARTNAME            # writes ./CHARTNAME/README.md
helm-docs --chart-search-root=./CHARTNAME --dry-run  # preview to stdout, write nothing
```

**About `-x` (strict):** it demands that *every* key — including intermediate parents and
the nested leaves under a commented block — carry documentation, and it skips the whole
chart (listing everything) if any is missing. That's stricter than this skill's style,
which intentionally hides nested keys under commented parents (e.g. `podSecurityContext`)
and leaves some values uncommented. **Don't use `-x` as a default gate** — it will fail a
normal chart. Offer it only if the user explicitly wants 100% documentation coverage and
is prepared to comment every key.

### Custom layout (optional)

helm-docs names its output after a template file: drop a `README.md.gotmpl` in the chart
to control structure. The default (no template) is fine for most charts. Useful built-in
blocks if you template: `{{ template "chart.header" . }}`,
`{{ template "chart.description" . }}`, `{{ template "chart.valuesSection" . }}`,
`{{ template "helm-docs.versionFooter" . }}`. The library includes Sprig functions.

## Where this fits in the run

Generate the README **after `values.yaml` is finalized and annotated**, before the
summary. List `README.md` as a deliverable and point the user at it for "what can I
configure?". Eyeball the table to confirm the important values are present with
descriptions (and that nested keys you wanted shown weren't hidden by a parent comment).
