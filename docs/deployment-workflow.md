# Deployment Workflow

## Standard Deployment (CI/CD path)

All production deployments go through the GitHub Actions pipeline. Direct `helm upgrade` against production is not permitted outside of incident response.

```
1. Engineer opens PR against main
         │
2. PR review + approval
         │
3. Merge to main
         │
4. GitHub Actions: lint-and-validate job
   ├── helm lint (base + all env values files)
   └── helm template (dry-run render per environment)
         │
         ├── FAIL → pipeline stops, no deployment
         │
5. deploy-dev job
   └── helm upgrade --install commerce-api-dev
       --values values-dev.yaml --atomic --timeout 8m
         │
         ├── FAIL → automatic rollback (--atomic), pipeline stops
         │
6. deploy-stage job (requires deploy-dev success)
   └── helm upgrade --install commerce-api-stage
       --values values-stage.yaml --atomic --timeout 8m
         │
         ├── FAIL → automatic rollback, pipeline stops
         │
         └── (GitHub environment protection: manual approval required)
         │
7. deploy-prod job (requires deploy-stage success + approver)
   └── helm upgrade --install commerce-api-prod
       --values values-prod.yaml --atomic --timeout 5m
         │
         ├── FAIL → automatic rollback, smoke test alert
         │
8. Smoke test: GET /healthz → expect HTTP 200
         │
         └── FAIL → helm rollback triggered, PagerDuty alert
```

---

## Manual Deployment (break-glass / incident response)

Use only when the CI/CD pipeline is unavailable or a hotfix must bypass the pipeline queue.

```bash
# Authenticate to the target cluster
export KUBECONFIG=/path/to/prod-kubeconfig

# Inspect current state before making changes
helm status commerce-api-prod --namespace commerce-prod
helm history commerce-api-prod --namespace commerce-prod

# Deploy a specific image tag (e.g., a hotfix build)
helm upgrade --install commerce-api-prod ./helm/commerce-api \
  --values ./helm/commerce-api/values-prod.yaml \
  --namespace commerce-prod \
  --atomic \
  --timeout 5m \
  --set image.tag=hotfix-2.4.2 \
  --description "Manual hotfix deploy by $(whoami) - incident INC-1234"

# Verify
kubectl rollout status deployment/commerce-api-prod \
  --namespace commerce-prod
```

Manual deploys must be documented in the incident report.

---

## Rollback Procedure

### Automatic (CI/CD)
When `--atomic` is set and a deploy fails, Helm automatically rolls back to the last successful revision. No manual intervention required.

### Manual rollback
```bash
# Step 1: Identify the last known good revision
helm history commerce-api-prod --namespace commerce-prod

# REVISION  STATUS      CHART               DESCRIPTION
# 1         superseded  commerce-api-1.0.0  Install complete
# 2         superseded  commerce-api-1.1.0  Upgrade complete
# 3         failed      commerce-api-1.2.0  Upgrade failed
# 4         deployed    commerce-api-1.1.0  Rollback to 2  ← after --atomic

# Step 2: Roll back to a specific revision
helm rollback commerce-api-prod 2 --namespace commerce-prod

# Step 3: Confirm
kubectl rollout status deployment/commerce-api-prod \
  --namespace commerce-prod
helm history commerce-api-prod --namespace commerce-prod
```

---

## Environment Promotion Matrix

| From | To | Gate | Approver |
|---|---|---|---|
| commit | dev | `helm lint` passes | automated |
| dev | stage | dev deploy succeeds | automated |
| stage | prod | stage deploy succeeds + manual approval | Platform Engineer or Service Owner |

---

## Deployment Checklist (pre-production)

- [ ] `helm lint` passes with no warnings
- [ ] `helm template` output reviewed for unexpected changes
- [ ] Image tag pinned (not `latest`) for traceability
- [ ] Resource requests/limits reviewed against staging load test results
- [ ] HPA minReplicas matches `replicaCount` in values-prod.yaml
- [ ] TLS secret exists in the namespace
- [ ] Downstream services notified if API contract changed
