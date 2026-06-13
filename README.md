# KubeRelease Platform

**Enterprise Kubernetes Application Delivery Framework using Helm**

---

## Executive Summary

Modern engineering organizations running workloads across multiple Kubernetes environments face a common operational problem: configuration drift. When deployment manifests are maintained as environment-specific YAML files, any structural change — a new sidecar, a label policy update, a resource quota adjustment — must be propagated manually across every environment. This creates toil, introduces inconsistencies, and makes rollbacks difficult to reason about.

KubeRelease Platform solves this by providing a single, parameterized Helm chart per service, with environment-specific configuration expressed as value overrides. A CI/CD pipeline enforces lint, render, and deploy gates on every commit, ensuring that no unvalidated manifest reaches a cluster.

This framework is designed for Platform Engineering teams that need to onboard new services quickly, enforce organizational standards at the chart level, and provide application teams with a well-defined deployment contract.

---

## Architecture

```
Developer Workstation
        │
        │  git push / pull request
        ▼
GitHub Repository
        │
        │  triggers on: push to main, workflow_dispatch
        ▼
GitHub Actions Runner
        │
        ├──── helm lint          (schema & syntax validation)
        │
        ├──── helm template      (render manifests, catch template errors)
        │
        └──── helm upgrade --install  (atomic deploy with rollback on failure)
                │
                ▼
        Kubernetes Cluster
                │
                ├──── Ingress Controller
                │           │
                │           ▼
                │       Ingress Resource
                │           │
                │           ▼
                │        Service (ClusterIP / LoadBalancer)
                │           │
                │           ▼
                │       Deployment
                │           │
                │    ┌──────┴──────┐
                │    ▼             ▼
                │   Pod           Pod         ← HPA manages replica count
                │    │             │
                │    └──── ConfigMap / Secret (mounted as env or volume)
                │
                └──── ServiceAccount (RBAC identity per workload)
```

---

## Repository Structure

```
kuberelease-platform/
│
├── README.md                          # This document
├── LICENSE                            # Apache 2.0
├── .gitignore
│
├── docs/
│   ├── architecture.md                # Detailed architecture notes
│   ├── deployment-workflow.md         # Step-by-step deploy process
│   ├── design-decisions.md            # ADRs and rationale
│   └── screenshots.md                 # Diagram and UI references
│
├── .github/
│   └── workflows/
│       └── deploy-platform.yml        # CI/CD pipeline definition
│
├── helm/
│   └── commerce-api/                  # Helm chart for the commerce-api service
│       ├── Chart.yaml                 # Chart metadata and version
│       ├── values.yaml                # Default values (base configuration)
│       ├── values-dev.yaml            # Dev environment overrides
│       ├── values-stage.yaml          # Staging environment overrides
│       ├── values-prod.yaml           # Production environment overrides
│       ├── charts/                    # Subchart dependencies (empty by default)
│       └── templates/
│           ├── _helpers.tpl           # Named templates and helper functions
│           ├── deployment.yaml        # Deployment resource
│           ├── service.yaml           # Service resource
│           ├── ingress.yaml           # Ingress resource
│           ├── configmap.yaml         # Application configuration
│           ├── secret.yaml            # Sensitive configuration
│           ├── hpa.yaml               # HorizontalPodAutoscaler
│           ├── serviceaccount.yaml    # ServiceAccount + RBAC identity
│           └── NOTES.txt              # Post-install usage instructions
│
└── applications/
    └── commerce-api/
        ├── Dockerfile                 # Container image definition
        ├── nginx.conf                 # NGINX server configuration
        └── index.html                 # Application entry point
```

### Key Directory Purposes

| Path | Purpose |
|---|---|
| `helm/commerce-api/` | The canonical Helm chart. All templates live here. |
| `helm/commerce-api/values.yaml` | Base defaults — every value must have an entry here. |
| `helm/commerce-api/values-*.yaml` | Environment-specific overrides applied at deploy time. |
| `helm/commerce-api/templates/` | Go-templated Kubernetes manifests. |
| `helm/commerce-api/templates/_helpers.tpl` | Reusable named template blocks (labels, selectors, names). |
| `applications/commerce-api/` | Source code and container build assets. |
| `.github/workflows/` | GitHub Actions pipeline definitions. |

---

## Why Helm?

### Templating
Helm uses Go's `text/template` engine to render Kubernetes manifests from parameterized templates. This eliminates copy-paste across environments and lets you express variations (replica count, resource limits, image tag) as data rather than duplicated YAML.

### Packaging
A Helm chart is a versioned, portable artifact. Running `helm package ./helm/commerce-api` produces `commerce-api-1.0.0.tgz` — a self-contained bundle of all templates and default values that can be stored in a Helm repository, pulled by other teams, or archived.

### Versioning
`Chart.yaml` tracks two independent versions:
- `version`: the chart schema version — increment when templates change
- `appVersion`: the application version being deployed — updated per release

This lets the platform team evolve the chart independently from the application release cadence.

### Release Management
Every `helm upgrade --install` creates a named **release** (e.g., `commerce-api-prod`). Helm records each deploy as a numbered revision in a Kubernetes Secret, giving you a full audit trail.

### Rollback
Because Helm stores prior rendered manifests as release history, rolling back is deterministic:

```bash
helm history commerce-api-prod
helm rollback commerce-api-prod 3
```

This re-applies the exact manifests from revision 3 — no guessing, no manual YAML reconstruction.

### Environment-Specific Configuration
Rather than maintaining three separate manifest trees for dev, staging, and production, a single chart expresses all structural logic, and environment differences are isolated to `values-dev.yaml`, `values-stage.yaml`, and `values-prod.yaml`. Structural changes (adding a new probe, changing label strategy) propagate to all environments from a single edit.

---

## Multi-Environment Strategy

| Concern | Separate YAML files per environment | Single chart + values overrides |
|---|---|---|
| Structural change propagation | Manual edit in N places | One template change |
| Configuration drift | Likely over time | Prevented by design |
| Rollback | Ad hoc, error-prone | `helm rollback` |
| Auditability | Git diff across files | Helm release history |
| Onboarding new environments | Copy + modify all files | Add a `values-<env>.yaml` |
| Linting and validation | Manual or scripted | `helm lint` + `helm template` |

The values file hierarchy is:

```
values.yaml          ← base defaults (all keys defined here)
    └── values-dev.yaml     ← dev overrides
    └── values-stage.yaml   ← stage overrides
    └── values-prod.yaml    ← prod overrides
```

At deploy time, Helm merges them:

```bash
helm upgrade --install commerce-api-dev ./helm/commerce-api \
  -f ./helm/commerce-api/values-dev.yaml \
  --namespace commerce-dev
```

---

## Installation

> Prerequisites: `helm` ≥ 3.12, `kubectl` configured against a target cluster, appropriate RBAC permissions.

### Validate the chart

```bash
helm lint ./helm/commerce-api
```

Checks for YAML syntax errors, missing required values, and schema violations. Exit code is non-zero on any error — safe to use as a CI gate.

### Render manifests locally

```bash
helm template commerce-api-dev ./helm/commerce-api \
  -f ./helm/commerce-api/values-dev.yaml \
  --namespace commerce-dev
```

Renders all templates to stdout without contacting a cluster. Use this to inspect what Kubernetes objects will be created before deploying.

### Install a new release

```bash
helm install commerce-api-dev ./helm/commerce-api \
  -f ./helm/commerce-api/values-dev.yaml \
  --namespace commerce-dev \
  --create-namespace
```

Creates all resources defined in the chart. Fails (and does not partially apply) if the release already exists — use `upgrade --install` for idempotent behavior.

### Upgrade or install (idempotent)

```bash
helm upgrade --install commerce-api-prod ./helm/commerce-api \
  -f ./helm/commerce-api/values-prod.yaml \
  --namespace commerce-prod \
  --create-namespace \
  --atomic \
  --timeout 5m
```

`--atomic` rolls back automatically if any resource fails to become ready within `--timeout`. This is the recommended form for CI/CD pipelines.

### List releases

```bash
helm list --all-namespaces
```

Shows all named releases, their current revision, status, and chart version.

### Inspect release history

```bash
helm history commerce-api-prod
```

Lists every revision with timestamp, status, chart version, and the description set at deploy time.

### Roll back to a prior revision

```bash
helm rollback commerce-api-prod 3
```

Re-applies the manifests from revision 3. Helm creates a new revision entry (e.g., revision 7) that records the rollback event, preserving full audit history.

### Uninstall a release

```bash
helm uninstall commerce-api-dev --namespace commerce-dev
```

Removes all Kubernetes resources created by the release. The release history is also deleted unless `--keep-history` is passed.

---

## Packaging

### Build a distributable chart archive

```bash
helm package ./helm/commerce-api
```

Produces `commerce-api-1.0.0.tgz` in the current directory. The archive contains all templates, the `Chart.yaml`, and `values.yaml`. It does not embed environment-specific values files — those are provided at deploy time.

The version in the filename comes from the `version` field in `Chart.yaml`. Increment this on every chart change following [semver](https://semver.org/).

---

## Helm Repository

### Generate a repository index

```bash
helm repo index .
```

Scans the current directory for `.tgz` chart archives and generates `index.yaml` — the Helm repository manifest. This file maps chart names and versions to their download URLs.

Host `index.yaml` and the `.tgz` files on any static HTTP server (GitHub Pages, S3, Artifactory, Nexus) to create a private Helm repository.

### Consuming the repository

```bash
helm repo add kuberelease https://your-org.github.io/kuberelease-platform
helm repo update
helm search repo kuberelease
helm install commerce-api-prod kuberelease/commerce-api --version 1.0.0 -f values-prod.yaml
```

---

## Rollback Procedure

When a production deploy introduces a regression:

```bash
# 1. Inspect revision history
helm history commerce-api-prod --namespace commerce-prod

# Output example:
# REVISION  STATUS      CHART                 DESCRIPTION
# 1         superseded  commerce-api-1.0.0    Install complete
# 2         superseded  commerce-api-1.1.0    Upgrade complete
# 3         deployed    commerce-api-1.2.0    Upgrade complete  ← current

# 2. Roll back to last known good revision
helm rollback commerce-api-prod 2 --namespace commerce-prod

# 3. Verify
helm status commerce-api-prod --namespace commerce-prod
kubectl rollout status deployment/commerce-api --namespace commerce-prod
```

Helm will re-apply the rendered manifests from revision 2 and record a new revision 4 with status `deployed`.

---

## CI/CD Flow

```
1. Developer pushes to main or opens a PR targeting main
        │
2. GitHub Actions runner starts (ubuntu-latest)
        │
3. Checkout repository (actions/checkout)
        │
4. Install Helm (azure/setup-helm)
        │
5. helm lint ./helm/commerce-api
   → Fails pipeline on any chart error
        │
6. helm template (render per environment)
   → Catches template rendering errors before touching a cluster
        │
7. helm upgrade --install (per environment, sequentially)
   → dev  → stage  → prod
   → Each deploy uses --atomic; failure triggers automatic rollback
   → Kubeconfig injected from GitHub Actions secrets
        │
8. Post-deploy: helm status + kubectl rollout status
```

Environment promotion is sequential: a failed dev deploy blocks staging. A failed staging deploy blocks production. The pipeline never promotes a broken release.

---

## Skills Demonstrated

| Skill | Where Applied |
|---|---|
| Helm 3 chart authoring | `helm/commerce-api/` — full chart with all standard resources |
| Go template engine | `templates/_helpers.tpl`, all `.yaml` templates |
| Kubernetes resource design | Deployment, Service, Ingress, HPA, ServiceAccount, ConfigMap, Secret |
| Multi-environment config management | `values-dev/stage/prod.yaml` |
| CI/CD pipeline design | `.github/workflows/deploy-platform.yml` |
| GitHub Actions | Workflow with lint, template, and deploy stages |
| Release management | `helm history`, `helm rollback`, atomic upgrades |
| Production deployment strategies | `--atomic`, rolling update strategy, HPA |
| Secret management patterns | Kubernetes Secret with base64 encoding, sealed-secret annotation pattern |
| RBAC and workload identity | `ServiceAccount` per workload, automountServiceAccountToken control |

---

## Interview Questions

**1. What is the difference between `helm install` and `helm upgrade --install`?**
`helm install` fails if the release already exists. `helm upgrade --install` is idempotent — it installs on first run and upgrades on subsequent runs. CI/CD pipelines always use `upgrade --install`.

**2. What does `helm lint` check?**
It validates YAML syntax, required chart fields, template rendering errors, and schema compliance. It does not contact a Kubernetes cluster.

**3. What is the purpose of `_helpers.tpl`?**
It defines named templates (using `{{- define "name" -}}`) that are reused across multiple resource templates. Common uses: label sets, selector sets, full resource names, image references. This prevents duplication and ensures consistency.

**4. How does Helm store release state?**
In Kubernetes Secrets (or ConfigMaps in older versions) in the release namespace, named `sh.helm.release.v1.<release-name>.v<revision>`. Each revision stores the rendered manifests, values, and chart metadata.

**5. What does `--atomic` do in `helm upgrade`?**
If any resource fails to reach a ready state within the timeout window, Helm automatically rolls back to the previous revision and the command exits with a non-zero code. Essential for CI/CD pipelines to prevent partial broken states.

**6. What is the difference between `chart.version` and `chart.appVersion`?**
`version` is the Helm chart schema version — increment it when templates change. `appVersion` is informational and reflects the version of the application being packaged. They evolve independently.

**7. How do you pass environment-specific configuration in Helm?**
Using the `-f` flag to layer values files: `helm upgrade --install release ./chart -f values.yaml -f values-prod.yaml`. Later files take precedence over earlier ones.

**8. What is a named template in Helm and how do you invoke it?**
Defined in `_helpers.tpl` with `{{- define "chart.fullname" -}}`. Invoked in templates with `{{ include "chart.fullname" . }}`. `include` (unlike `template`) returns a string, enabling piping to functions like `indent` or `nindent`.

**9. How does the HorizontalPodAutoscaler interact with the Deployment?**
HPA monitors metrics (CPU, memory, custom) from the Metrics Server and adjusts the `spec.replicas` field on the Deployment. The Deployment's `replicaCount` in values.yaml sets the initial replica count; the HPA takes over afterwards.

**10. Why should `replicaCount` in values-prod.yaml be set to the minimum acceptable value rather than the expected steady-state value?**
HPA manages scale-out beyond the minimum. If `replicaCount` in the chart and HPA's `minReplicas` differ, a `helm upgrade` could reset replicas to the chart value, causing a brief scale-down before HPA corrects it.

**11. What is `helm template` used for?**
It renders all chart templates to stdout without deploying to a cluster. Used for local inspection, diff generation, CI validation, and feeding rendered manifests to `kubectl apply` in GitOps pipelines.

**12. How do you handle sensitive values in Helm?**
Kubernetes Secrets (base64-encoded, not encrypted). For production, use external secret management: Sealed Secrets, External Secrets Operator (ESO), Vault Agent Injector, or AWS Secrets Manager CSI driver. Never commit plaintext secrets to values files in version control.

**13. What is a Helm dependency (subchart) and when would you use one?**
Declared in `Chart.yaml` under `dependencies`. Used to bundle shared infrastructure components (PostgreSQL, Redis, cert-manager CRDs) alongside the application chart. Managed with `helm dependency update`.

**14. How do you roll back a Helm release?**
`helm rollback <release> <revision>`. Helm re-applies the stored rendered manifests from that revision and creates a new revision entry recording the rollback event.

**15. What is `helm diff` and why is it useful?**
A community plugin (`helm plugin install https://github.com/databus23/helm-diff`) that shows the diff between the current release state and what a pending upgrade would apply. Provides a human-readable change preview before deploying.

**16. What is the `lookup` function in Helm and what is its limitation?**
`lookup` queries the live cluster for existing resources during template rendering: `{{ lookup "v1" "ConfigMap" "namespace" "name" }}`. It only works during `helm upgrade/install` (not `helm template`) because it requires cluster access.

**17. How do you test a Helm chart?**
`helm test <release>` runs Pods annotated with `helm.sh/hook: test`. These pods run assertions (connectivity checks, smoke tests) and Helm reports pass/fail based on pod exit codes.

**18. What is the difference between `set` and `-f` when passing values?**
`--set key=value` overrides individual values on the command line. `-f values-prod.yaml` loads a full values file. `-f` is preferred for structured configuration; `--set` is useful for one-off overrides in scripts or CI matrix steps.

**19. How does Helm handle a failed upgrade with `--atomic`?**
It automatically calls `helm rollback` to the last successful revision, then exits non-zero. Without `--atomic`, a failed upgrade leaves the release in a `failed` state and requires manual intervention.

**20. What is `helm package` and `helm repo index` used for in an enterprise context?**
`helm package` builds a versioned `.tgz` artifact from a chart directory. `helm repo index` generates the `index.yaml` manifest for a Helm repository. Together they enable publishing charts to a private registry (GitHub Pages, Artifactory, Nexus) so other teams can pull pinned chart versions without direct Git access.
