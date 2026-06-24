# PetClinic Helm chart

Replaces the raw `k8s/` manifests for the 7 application services + ALB ingress with one
values-driven chart. Eureka discovery + Spring Cloud Config are kept (per the decision in
MEMORY.md). Prometheus/Grafana/Zipkin are intentionally **out of scope** here (see below).

## What this fixes vs the raw manifests
- **One image tag, not seven.** `global.imageTag` drives every service. The old `sed`
  pipeline only matched `:latest`, so `config-server:4.0.2` and `customers-service:4.0.1`
  were silently frozen. That whole class of bug is gone.
- **Uniform tracing.** `commonEnv` injects `MANAGEMENT_TRACING_EXPORT_ZIPKIN_ENDPOINT=http://zipkin:9411/...`
  into every service, so all of them export spans — not just the two that had the `docker`
  profile. (This supersedes the config-repo endpoint fix for the cluster; keep that fix
  for docker-compose parity.)
- **Consistent labels, resources, probes** across services, overridable per service.

## Layout
```
helm/petclinic/
  Chart.yaml
  values.yaml
  templates/
    _helpers.tpl
    namespace.yaml       # only if global.createNamespace=true
    deployment.yaml      # ranges over .Values.services
    service.yaml         # ranges over .Values.services
    ingress.yaml         # ALB ingress
helm/argocd-application.yaml
```

## Prerequisites (unchanged from today)
- The `ecr-secret` image-pull Secret must already exist in the `petclinic` namespace.
  This chart does NOT create it (it's a credential). Keep managing it as you do now.
- AWS Load Balancer Controller installed (it is) for the ingress to provision an ALB.

## Validate BEFORE applying (I could not run helm here)
```bash
helm lint helm/petclinic
helm template petclinic helm/petclinic -n petclinic | less   # eyeball the rendered YAML
```

## Try it without touching Argo CD (optional dry run)
```bash
# render against the live cluster without installing
helm template petclinic helm/petclinic -n petclinic | kubectl apply --dry-run=server -f -
```

## Install via Helm (interim, before Argo CD)
```bash
helm upgrade --install petclinic helm/petclinic -n petclinic --create-namespace \
  --set global.imageTag=<git-sha>
```

## Or via Argo CD (target GitOps model)
1. Install Argo CD in the cluster.
2. Commit the chart to the app repo at `helm/petclinic`.
3. `kubectl apply -f helm/argocd-application.yaml -n argocd`.
4. CI's job shrinks to: build → push to ECR → set `global.imageTag` (commit to values.yaml
   or pass as an Argo parameter). Argo CD syncs. **No more `kubectl apply` from CI.**

## What changes in deploy.yml
Once on Argo CD, delete the `Update kubeconfig`, `Update Kubernetes Manifests` (the sed),
`Deploy to Kubernetes`, and `Wait for Rollout` steps. Keep build + push, then bump the tag.

## Autoscaling + disruption budgets (HPA/PDB)
The four stateless services (customers, vets, visits, api-gateway) have `hpa` and
`pdb` enabled in values.yaml (min 2 / max 4 / 70% CPU). config-server,
discovery-server, and admin-server stay at fixed single replicas (Eureka/Config
are singletons — don't autoscale them here).

**Prerequisite: metrics-server** (HPA reads CPU from it). The cluster doesn't have
it yet — install once:
```bash
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system
kubectl top nodes      # should return numbers once it's up
```
Without metrics-server the HPAs show `<unknown>/70%` targets and won't scale.

**Argo CD note:** when `hpa.enabled`, the Deployment omits `replicas` and the HPA
owns it. The Application sets `ignoreDifferences` on `apps/Deployment /spec/replicas`
so selfHeal doesn't fight the autoscaler. (Re-apply the Application after pulling
this change: `kubectl apply -f helm/argocd-application.yaml -n argocd`.)

## Still TODO (deliberately not in this chart)
- Observability: move Prometheus/Grafana to the community `kube-prometheus-stack`; run Zipkin
  as its own small release.
- NetworkPolicies — add carefully (default-deny + explicit allows) so you don't cut service-to-service traffic.
- genai-service: no manifest today; add a service block here if/when you deploy it.
