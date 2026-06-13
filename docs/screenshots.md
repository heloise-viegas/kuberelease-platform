# Screenshots and Diagrams

## Application Landing Page

The `commerce-api` container serves a status page at `/` that displays:
- Service operational status
- Deployed version badge
- Available API endpoints
- Deploy timestamp (refreshed on each pod start — useful for confirming rolling restarts in dev)

Screenshot path: `docs/assets/commerce-api-status-page.png`

---

## GitHub Actions Pipeline

The CI/CD pipeline runs three sequential stages after the lint-and-validate gate:

```
lint-and-validate
    │
    ├── helm lint (base + 3 env values files)
    └── helm template (dry-run per environment)
            │
        deploy-dev ──────────────────────────────── (auto)
            │
        deploy-stage ────────────────────────────── (auto, after dev)
            │
        deploy-prod ─────────────────────────────── (manual approval required)
```

Screenshot path: `docs/assets/github-actions-pipeline.png`

---

## Helm Release History

After several deploys, `helm history commerce-api-prod` produces output similar to:

```
REVISION  UPDATED                   STATUS      CHART                DESCRIPTION
1         2024-01-15 09:12:34 UTC   superseded  commerce-api-1.0.0  Install complete
2         2024-01-20 14:30:11 UTC   superseded  commerce-api-1.0.0  Upgrade: image tag 2.1.0
3         2024-01-28 11:05:44 UTC   superseded  commerce-api-1.1.0  Upgrade: added HPA
4         2024-02-01 16:22:09 UTC   failed      commerce-api-1.2.0  Upgrade failed (--atomic rollback)
5         2024-02-01 16:22:45 UTC   superseded  commerce-api-1.1.0  Rollback to 3
6         2024-02-05 10:14:30 UTC   deployed    commerce-api-1.2.1  Upgrade complete
```

Revision 4 shows a failed deploy that was automatically rolled back to revision 3 by `--atomic`. Revision 5 is the rollback record. Revision 6 is the corrected deploy.

---

## Kubernetes Resource Tree

After a successful production deploy, the namespace contains:

```
namespace: commerce-prod
├── serviceaccount/commerce-api-prod
├── configmap/commerce-api-prod-config
├── secret/commerce-api-prod-secret
├── deployment/commerce-api-prod
│   └── replicaset/commerce-api-prod-<hash>
│       ├── pod/commerce-api-prod-<hash>-<id>
│       ├── pod/commerce-api-prod-<hash>-<id>
│       ├── pod/commerce-api-prod-<hash>-<id>
│       ├── pod/commerce-api-prod-<hash>-<id>
│       └── pod/commerce-api-prod-<hash>-<id>
├── horizontalpodautoscaler/commerce-api-prod
├── service/commerce-api-prod
└── ingress/commerce-api-prod
```

---

## HPA Scaling Activity

Under load, the HPA scales up pods. `kubectl get hpa -n commerce-prod -w`:

```
NAME               REFERENCE                       TARGETS          MINPODS  MAXPODS  REPLICAS
commerce-api-prod  Deployment/commerce-api-prod    68%/65%, 40%/75%    5       20        5
commerce-api-prod  Deployment/commerce-api-prod    82%/65%, 55%/75%    5       20        8
commerce-api-prod  Deployment/commerce-api-prod    71%/65%, 48%/75%    5       20        9
commerce-api-prod  Deployment/commerce-api-prod    58%/65%, 41%/75%    5       20        9
commerce-api-prod  Deployment/commerce-api-prod    42%/65%, 31%/75%    5       20        7
commerce-api-prod  Deployment/commerce-api-prod    35%/65%, 28%/75%    5       20        5
```

Scale-down uses a 300-second stabilization window (see `hpa.yaml`) to avoid oscillation.
