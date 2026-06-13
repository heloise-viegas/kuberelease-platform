# Design Decisions

Architecture decision records (ADRs) for the KubeRelease Platform.

---

## ADR-001 — Single chart, multiple values files (vs. separate charts per environment)

**Status:** Accepted

**Context:**
Early versions of the platform maintained a separate Helm chart per environment (commerce-api-dev, commerce-api-stage, commerce-api-prod). Structural changes required updating three charts. Drift accumulated over time — dev had newer probes, prod had older label schemas.

**Decision:**
One chart. Environment differences expressed entirely as values overrides. `values.yaml` defines all valid keys with sensible defaults. `values-{env}.yaml` files override only what differs.

**Consequences:**
- Structural changes propagate to all environments from one edit
- Reviewing a PR is simpler — the template diff and the values diff are in the same commit
- `helm lint` and `helm template` can validate all three environments in CI
- The tradeoff is that a bad chart change affects all environments; CI gates on all three values files mitigate this

---

## ADR-002 — `--atomic` on all helm upgrade calls

**Status:** Accepted

**Context:**
Without `--atomic`, a failed `helm upgrade` leaves the release in a `failed` state. Resources may be partially updated. The next `helm upgrade` may succeed but operate on a cluster in an inconsistent state.

**Decision:**
All `helm upgrade --install` calls in the CI pipeline use `--atomic`. This ensures Helm automatically rolls back to the last successful revision if any resource fails to reach a ready state within the timeout.

**Consequences:**
- Deployments are either fully successful or fully reverted — no partial states
- The deploy job exits non-zero on failure, blocking environment promotion
- Timeout must be set conservatively to account for slow image pulls in cold environments

---

## ADR-003 — Secret management strategy

**Status:** Accepted (with upgrade path documented)

**Context:**
Kubernetes Secrets are base64-encoded, not encrypted. Storing secret values in `values.yaml` (even base64-encoded) and committing to Git is insecure.

**Decision:**
For this reference implementation, the `secret` block in `values.yaml` uses placeholder base64 values. The chart template supports the pattern, but production deployments must inject secrets via one of:

1. **External Secrets Operator (ESO)** — syncs secrets from AWS Secrets Manager, GCP Secret Manager, or HashiCorp Vault into Kubernetes Secrets. The chart's Secret template can be disabled (`secret: {}`) and the ESO-managed secret referenced by the same name.
2. **Sealed Secrets** — encrypts secrets using the cluster's public key. Encrypted SealedSecret manifests are safe to commit to Git.
3. **GitHub Actions secrets** — for CI/CD, `--set` flags can inject secrets at deploy time from GitHub Actions secrets without them appearing in values files.

**Consequences:**
- The chart ships with a working secret template for development
- Production secret injection requires an additional operator or CI configuration
- The `kuberelease.io/secret-source` annotation on the Secret resource documents which method is in use

---

## ADR-004 — HPA replica count and `replicaCount` alignment

**Status:** Accepted

**Context:**
When HPA is enabled, it owns `spec.replicas` on the Deployment. If `helm upgrade` sets `spec.replicas` to a value lower than the HPA's current target, the Deployment briefly scales down before the HPA corrects it, causing a transient availability gap.

**Decision:**
When `hpa.enabled: true`, the Deployment template omits the `spec.replicas` field entirely. Helm does not overwrite the replica count that the HPA currently manages. The `replicaCount` value in values files is documented as the initial replica count used only at install time (first `helm install`).

**Consequences:**
- No transient scale-down during upgrades when HPA is active
- `helm template` output will not include `spec.replicas` when HPA is enabled — reviewers should be aware of this intentional omission
- `replicaCount` in values-prod.yaml should match `hpa.minReplicas` to ensure consistency on first install

---

## ADR-005 — ConfigMap/Secret checksum annotations on pods

**Status:** Accepted

**Context:**
Kubernetes does not restart pods when a ConfigMap or Secret referenced via `envFrom` changes. If a `helm upgrade` only changes config values (not the Deployment template), pods continue running with stale environment variables.

**Decision:**
The Deployment template annotates each Pod with the SHA256 checksum of the ConfigMap and Secret templates:

```yaml
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
```

When config content changes, the annotation changes, which mutates the Pod spec, which triggers a rolling restart.

**Consequences:**
- Config changes always result in a pod restart — desired behavior
- The rolling restart respects the Deployment's `maxUnavailable: 0` strategy — zero downtime
- The checksum is computed from the template source, not the rendered output — this is sufficient because any config value change will change the rendered output which changes the template hash
