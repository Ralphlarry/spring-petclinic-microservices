# Argo CD bootstrap (petclinic on EKS)

Installs Argo CD, then has it adopt the already-running petclinic app via the
Helm chart in `helm/petclinic`. Order matters — do the steps top to bottom.

## 0. Prereqs
- `kubectl` pointed at `petclinic-prod`, `helm` installed.
- The petclinic app is currently running (deployed by raw `kubectl apply`).
- The repo is public, so Argo CD needs no git credentials.

## 1. Install Argo CD
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm search repo argo/argo-cd --versions | head     # confirm 9.7.x exists

helm upgrade --install argocd argo/argo-cd \
  -n argocd --create-namespace \
  --version 9.7.0 \
  -f argocd/values.yaml

kubectl -n argocd rollout status deploy/argocd-server
```

## 2. Log in to the UI
```bash
# initial admin password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo

# no ingress yet → port-forward:
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080  (user: admin)
```
Change the admin password after first login, then delete the bootstrap secret:
`kubectl -n argocd delete secret argocd-initial-admin-secret`.

## 3. Register the app (MANUAL sync first)
```bash
kubectl apply -f helm/argocd-application.yaml -n argocd
```
In the UI the `petclinic` Application appears **OutOfSync** (expected — the
running objects were made by raw manifests; the chart adds labels and the image
tag knob). Review the diff, then click **Sync** once.

> Expect a one-time rolling restart of all 7 services during this first sync
> (label + image-tag reconciliation). The app stays up (rolling, not recreate).

Set the image tag so the chart matches what you intend to run:
- easiest: leave `global.imageTag: latest` (the manifests already use `:latest`), or
- pin to the SHA your last deploy pushed via the Application `helm.parameters`.

## 4. Hand deploys over to GitOps (only after a clean manual sync)
1. In `helm/argocd-application.yaml`, uncomment the `automated` block (prune + selfHeal). Re-apply.
2. Stop CI from running `kubectl apply`: replace `.github/workflows/deploy.yml`
   with `helm/ci/deploy-gitops.yml` (build → push → bump `values.yaml` imageTag → commit).
   Argo CD then syncs every change. **Do not run both** — they will fight over the objects.

## 5. (Optional) Expose the UI on a hostname
Set `server.ingress.enabled: true` in `argocd/values.yaml`, supply an ACM cert
ARN for `argocd.ralphnetwork.online`, add the DNS record, and `helm upgrade`.
Until then, `port-forward` is fine.

## Rollback / safety
- Manual sync is the safety net: nothing changes in-cluster until you click Sync.
- To detach Argo CD without deleting the app: delete the Application with
  `kubectl -n argocd delete application petclinic --cascade=orphan`.
