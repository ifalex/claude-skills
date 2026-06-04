# Values documentation: PARAMETERS.md

Every generated chart ships a **`PARAMETERS.md`** — a human-readable table of every
configurable value, its description, and its default. It is produced from the
`## @param` / `## @section` metadata already written into `values.yaml` (Bitnami
convention), so the docs never drift from the values.

There are two ways to produce it. **Default to Method A** (zero dependencies, always
works). Use Method B when the user wants the canonical Bitnami tool and/or wants the
`values.schema.json` regenerated from the same metadata in one pass.

## Metadata contract (how `values.yaml` must be annotated)

```yaml
## @section Image parameters
image:
  ## @param image.registry [default: docker.io] Container image registry
  registry: docker.io
  ## @param image.repository Container image repository
  repository: nginx
  ## @param image.pullSecrets [array] Optional image pull secrets
  pullSecrets: []
```

Rules:
- `## @section <Title>` starts a new table.
- `## @param <dotted.path> [modifiers?] <description>` documents one value.
- **Placement matters:** put the `## @param` line *directly above the leaf key* it
  documents (above `registry:`, not above `image:`). Both the Bitnami tool and the
  fallback generator read the default from the next `key: value` line.
- Modifiers (comma-separable) override the shown default:
  `[array]`→`[]`, `[object]`→`{}`, `[string]`→`""`, `[nullable]`, `[default: VALUE]`.

## Method A — dependency-free generator (default)

Run this from the chart directory. It reads `values.yaml` and writes `PARAMETERS.md`.
Requires only `awk` (present on macOS and every Linux). Replace `CHARTNAME`.

```bash
chart="CHARTNAME"
{
  printf '# %s parameters\n\nThe following table lists the configurable parameters of the %s chart and their default values.\n\n## Parameters\n' "$chart" "$chart"
  awk '
    /^[ \t]*## @section/ { s=$0; sub(/^[ \t]*## @section[ \t]*/,"",s);
      printf "\n### %s\n\n| Name | Description | Value |\n| ---- | ----------- | ----- |\n", s; next }
    /^[ \t]*## @param/ { l=$0; sub(/^[ \t]*## @param[ \t]*/,"",l);
      n=l; sub(/[ \t].*/,"",n); d=l; sub(/^[^ \t]+[ \t]*/,"",d); m="";
      while (match(d,/^\[[^]]*\][ \t]*/)) { m=m substr(d,RSTART,RLENGTH); d=substr(d,RSTART+RLENGTH) }
      pn=n; pd=d; pm=m; have=1; next }
    have && /^[ \t]*[A-Za-z0-9_.-]+:/ {
      v=$0; sub(/^[ \t]*[A-Za-z0-9_.-]+:[ \t]*/,"",v); sub(/[ \t]*$/,"",v);
      if (v=="") v="{}";
      if (pm ~ /\[array\]/)  v="[]";
      if (pm ~ /\[object\]/) v="{}";
      if (pm ~ /\[string\]/) v="\"\"";
      if (match(pm,/\[default:[ \t]*[^]]*\]/)) { dd=substr(pm,RSTART,RLENGTH); sub(/\[default:[ \t]*/,"",dd); sub(/\][ \t]*$/,"",dd); v=dd }
      gsub(/\|/,"\\|",pd);
      printf "| `%s` | %s | `%s` |\n", pn, pd, v; have=0; next }
  ' values.yaml
} > PARAMETERS.md
```

Then sanity-check: open `PARAMETERS.md` and confirm there are no `{}` defaults on
scalar leaves (that means a `## @param` was placed above a parent key instead of its
leaf — move it down one line and re-run).

## Method B — Bitnami `readme-generator-for-helm` (optional, authoritative)

The canonical tool. It generates the same table **and** can (re)generate
`values.schema.json` from the same `@param` metadata, keeping both in sync.

Install (note: **since v2.8.0 it is no longer on npm** — install from source):

```bash
git clone https://github.com/bitnami/readme-generator-for-helm
npm install ./readme-generator-for-helm     # provides the `readme-generator` binary
```

Use it. The target markdown must already contain a `## Parameters` heading; the tool
injects/refreshes the table under it (`-s` is optional and writes the schema):

```bash
printf '# CHARTNAME parameters\n\n## Parameters\n' > PARAMETERS.md
readme-generator --values values.yaml --readme PARAMETERS.md --schema values.schema.json
```

`-c <config.json>` is optional (built-in defaults recognize `## @section`/`## @param`).
If the tool reports metadata/values mismatches, fix the `@param` lines until it passes
— that check is a useful lint that every value is documented.

## Where this fits in the run

Generate `PARAMETERS.md` right after `values.yaml` is finalized and before the summary,
so the file tree you report to the user already includes it. List it as a deliverable
and point the user at it as the single source for "what can I configure?".
