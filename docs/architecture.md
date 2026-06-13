# Architecture — KubeRelease Platform

## Overview

KubeRelease Platform is a Helm-based deployment framework. It standardizes how services are packaged, configured, and deployed across Kubernetes environments. The architecture has three layers: the source layer (Git), the delivery layer (GitHub Actions + Helm), and the runtime layer (Kubernetes).

---

## Layer 1 — Source

```
kuberelease-platform/
├── helm/commerce-api/        ← Helm chart (templates + values)
├── applications/commerce-api/ ← Container source (Dockerfile, nginx.conf)
└── .github/workflows/        ← Pipeline definition
```

The chart and the application source live in the same repository. This means a single PR can change both the application code and its deployment configuration atomically.

---

## Layer 2 — Delivery

```
GitHub Actions
    │
    ├── helm lint          → validates chart schema and YAML syntax
    ├── helm template      → renders manifests, catches template errors
    └── helm upgrade --install
            ├── commerce-api-dev   (namespace: commerce-dev)
            ├── commerce-api-stage (namespace: commerce-stage)
            └── commerce-api-prod  (namespace: commerce-prod)
```

Each environment is a separate named Helm release. The same chart is deployed three times with different values files. Promotion is sequential and each stage uses `--atomic` so failures trigger automatic rollback.

---

## Layer 3 — Runtime (per environment)

```
Namespace: commerce-{dev|stage|prod}
    │
    ├── ServiceAccount         commerce-api
    │
    ├── ConfigMap              commerce-api-config
    │       └── APP_ENV, LOG_LEVEL, CACHE_TTL_SECONDS, ...
    │
    ├── Secret                 commerce-api-secret
    │       └── DATABASE_URL, API_KEY, JWT_SECRET
    │
    ├── Deployment             commerce-api
    │       └── Pod (× replicaCount)
    │               ├── envFrom: configMapRef  → commerce-api-config
    │               ├── envFrom: secretRef     → commerce-api-secret
    │               ├── livenessProbe  GET /healthz
    │               ├── readinessProbe GET /ready
    │               └── volumeMounts:
    │                       /tmp, /var/cache/nginx, /var/run  (emptyDir)
    │
    ├── HorizontalPodAutoscaler  commerce-api
    │       └── scaleTargetRef: Deployment/commerce-api
    │           minReplicas / maxReplicas / CPU+Memory targets
    │
    ├── Service                commerce-api  (ClusterIP → port 80 → 8080)
    │
    └── Ingress                commerce-api
            └── host → Service/commerce-api → Pod:8080
```

---

## Namespace Isolation

Each environment runs in a dedicated namespace. This provides:

- **RBAC isolation** — dev teams can be granted `edit` on `commerce-dev` without any access to `commerce-prod`
- **Resource quota isolation** — LimitRanges and ResourceQuotas can be applied per namespace
- **Network policy isolation** — traffic between environments can be blocked at the namespace boundary

---

## Configuration Flow

```
values.yaml          (base defaults — all keys defined)
      +
values-{env}.yaml    (environment overrides — only changed keys)
      │
      ▼
helm upgrade --install
      │
      ▼
Rendered Kubernetes manifests
      │
      ├── ConfigMap  (non-sensitive config)
      └── Secret     (sensitive config — base64)
            │
            ▼
      Pod env vars (envFrom)
```

The ConfigMap and Secret checksums are annotated on the Pod spec. Helm re-computes checksums on every upgrade. If config content changes, the annotation changes, which triggers a rolling restart of the Deployment — ensuring pods always run with the latest configuration without needing a manual restart.

---

## Security Architecture

| Control | Implementation |
|---|---|
| Non-root container | `runAsUser: 1000`, `runAsNonRoot: true` |
| Read-only root filesystem | `readOnlyRootFilesystem: true` |
| Dropped capabilities | `capabilities.drop: [ALL]` |
| No privilege escalation | `allowPrivilegeEscalation: false` |
| Seccomp profile | `seccompProfile.type: RuntimeDefault` |
| No automounted SA token | `automountServiceAccountToken: false` |
| Dedicated ServiceAccount | One SA per service, not the `default` SA |
| Ingress TLS | Enforced in stage and prod via cert-manager |
| Rate limiting | NGINX ingress annotations in prod |
