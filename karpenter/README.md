# Karpenter (node autoscaling) — bootstrap

Why: HPA scales pods, but pods can only run if there are nodes. The cluster is a
fixed 2-node group with no autoscaler, so an HPA scale-up would leave pods
**Pending**. Karpenter watches for Pending pods and launches right-sized nodes,
then consolidates when idle.

Stack fit: your EKS already runs the **pod-identity agent**, so Karpenter's
controller gets its IAM via a Pod Identity association (no IRSA annotation).

## Order of operations

### 1. Terraform (infra repo, branch feature/bootstrap-backend)
The submodule + tags are already wired (`environments/prod/karpenter.tf`, plus
`karpenter.sh/discovery` tags on private subnets and the node security group).
```bash
cd terraform/environments/prod
terraform init      # pulls the karpenter submodule
terraform plan      # review: IAM roles, instance profile, SQS queue, access entry, tags
terraform apply
terraform output karpenter_queue_name          # note this for step 2
terraform output karpenter_node_iam_role_name  # should be petclinic-karpenter-node
```
> Reminder: the ALB-policy import (from the earlier IAM fix) is still pending —
> handle that in the same apply or it'll error on the existing policy.

### 2. Install the Karpenter controller (Helm, OCI chart)
```bash
# find the latest v1.x:
helm show chart oci://public.ecr.aws/karpenter/karpenter | grep version

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.X.Y" \                         # pin the version you found above
  -n kube-system \
  --set settings.clusterName=petclinic-prod \
  --set settings.interruptionQueue=<karpenter_queue_name from step 1> \
  --set controller.resources.requests.cpu=0.5 \
  --set controller.resources.requests.memory=512Mi \
  --wait
```
The chart's default service account is `karpenter` in `kube-system` — that matches
the Pod Identity association Terraform created. No SA annotation needed.

### 3. Apply the NodePool + EC2NodeClass
```bash
kubectl apply -f karpenter/ec2nodeclass.yaml
kubectl apply -f karpenter/nodepool.yaml
```
(Or, to keep it GitOps, add a second Argo CD Application pointing at `karpenter/`.)

### 4. Trigger a scale event
Push the HPA chart changes, re-apply the Application, sync. The four stateless
services go to 2 replicas; if they don't fit on the existing nodes, Karpenter
provisions one. Watch it:
```bash
kubectl get nodes -w
kubectl logs -f -n kube-system deploy/karpenter
kubectl get pods -n petclinic -o wide        # confirm nothing stuck Pending
```

## Notes / caveats
- Keep the existing managed node group — Karpenter's own controller runs on it.
- This is untested against your cluster (drafted offline). `terraform plan` and a
  dry `kubectl apply --dry-run=server` are your gates.
- API versions here are Karpenter **v1** (`karpenter.sh/v1`, `karpenter.k8s.aws/v1`).
  If you pin an older controller, adjust the manifests.
- Cost guard: NodePool `limits` cap total cpu/memory; `consolidateAfter` removes
  idle nodes. Add `spot` to capacity-type for cheaper bursts.
