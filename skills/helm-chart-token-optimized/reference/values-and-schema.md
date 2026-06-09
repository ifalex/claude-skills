# values.yaml Structure & Schema

> **Single source of truth:** the canonical `values.yaml` is
> `reference/templates/values.yaml.tmpl` and the canonical schema is
> `reference/templates/values.schema.json`. `scaffold.sh` renders from them.
> **Read those files for the full structure** — this doc only records the
> *conventions* (section order, helm-docs comments, schema coverage) so it can't
> drift out of sync with the templates. When hand-editing or in the no-shell
> fallback, copy from the template and apply the rules below.

## Section order (follow exactly — Bitnami convention)

Emit `## @section <Title>` dividers in this order (this is the order in
`values.yaml.tmpl`):

1. Global parameters
2. Common parameters
3. Image parameters
4. Workload parameters
5. Scheduling
6. Security
7. Container ports / resources / probes
8. Traffic exposure
9. Persistence
10. RBAC / ServiceAccount
11. Autoscaling / Disruption
12. Network policy
13. Metrics
14. ConfigMap (app config)
15. Extra deploy

It's fine to keep disabled-feature sections in `values.yaml` as documented
toggles (Bitnami does). Adjust default values to the user's answers — but never
reorder or rename keys.

## helm-docs `# --` comments

Document each value with a **helm-docs `# -- <description>` comment on the line
directly above its leaf key** — this is what generates the `README.md` values
table (see `helm-docs.md`). Example:

```yaml
## @section Image parameters
image:
  # -- Container image registry
  registry: docker.io
  # -- Container image repository
  repository: <repo>
  # -- (string) Image tag, defaults to chart appVersion
  tag: "<tag>"
```

Rules:

- Use `# -- (type) ...` hints on empty values (e.g. `# -- (string)` above `tag: ""`).
- Use `# @default -- ...` to override the shown default in the table.
- Use `# @ignored` to hide a value from the table.
- Do **not** put a `# --` on a *parent* key unless you want the whole block
  documented as one row — it suppresses the nested leaves. Comment only the
  leaves you want shown.

`values.yaml.tmpl` already carries these comments on the documented leaves; if
you add a key, add its `# --` line too.

## values.schema.json

The canonical schema is `reference/templates/values.schema.json` (JSON Schema
draft-07). Rules when extending it:

- **Minimum coverage:** `image`, `service`, `ingress`, `resources`,
  `replicaCount`, `persistence`, `autoscaling`. A new top-level value that users
  set should get a matching property so `helm lint` validates it.
- **Keep it permissive:** do **not** set `additionalProperties: false` at the
  root — charts evolve and over-strict schemas reject valid overrides.
- **Enums for closed sets:** `service.type`, `image.pullPolicy`,
  `persistence.accessModes` — constrain to the valid Kubernetes values.
- Keep the schema and `values.yaml.tmpl` in step: a value added to one should be
  reflected in the other. The all-features lint test
  (`tests/lint-all-features.sh`) exercises this by running `helm lint` with every
  toggle enabled.
