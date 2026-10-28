# Vault (Phase 1b)

Self-hosted Vault for developer secrets, delivered to namespaces by the Vault Secrets Operator (VSO).
Design: `IDP_NOTES.md` section 10. Vault is rebuilt empty on every `make up` (single node, Raft on a
1 GiB PVC, no snapshots yet), so everything below runs on every fresh cluster.

| Piece | Where | Wave |
|---|---|---|
| Vault server (chart 0.34.1, Vault 2.0.4), NetworkPolicies, `vault-config` Job | `apps/vault.yaml`, `platform/vault/values.yaml`, this directory | 7 |
| VSO (chart 1.6.2) | `apps/vault-secrets-operator.yaml`, `platform/vault-secrets-operator/values.yaml` | 8 |
| Tailscale Ingress `vault-admin` | `apps/vault-admin-access.yaml`, `workloads/vault-admin-access` | 10 |
| Demo: Secret `vault-demo/hello` | `apps/vault-demo.yaml`, `workloads/vault-demo` | 10 |

## Flow on a fresh cluster

1. Argo CD installs Vault. The pod starts sealed and uninitialized; the readiness probe still
   reports Ready (`sealedcode=204&uninitcode=204`), so the app is Healthy and nothing waits on it.
2. `make up` in `idp-infra` runs `scripts/bootstrap-secrets.sh`: `kubectl exec` into `vault-0`,
   `vault operator init` (recovery keys go to Secret Manager, never to Git). Vault unseals itself
   through Cloud KMS (`seal "gcpckms"`, key ring `idp`, key `vault-unseal`, Workload Identity as
   `vault@`). The script then issues a short-lived **bootstrap token** (orphan, 30 min TTL, not
   renewable, no default policy, policy `vault-bootstrap`) and stores only that token in the Secret
   `vault/vault-bootstrap` (key `token`).
3. The `vault-config` PostSync Job (`config-job.yaml`) waits for Vault to be unsealed and for the
   Secret (20 min each at most), then with the bootstrap token: enables the `file` audit device to
   stdout (Cloud Logging), mounts kv-v2 at `kv/`, writes `kv/vault-demo/hello`
   (`message=hello from vault`), writes policy `vso-demo` (read `kv/data/vault-demo/hello` only),
   enables Kubernetes auth (Vault's own ServiceAccount does the TokenReview, via the chart's
   `system:auth-delegator` binding) with role `vso-demo` bound to ServiceAccount
   `vault-demo/vault-demo` (audience `vault`), makes the `kubernetes/` auth mount visible on the
   login page (the completion mark), and **revokes its own token** (`vault token revoke -self`).
   A second container then deletes `vault/vault-bootstrap` (RBAC: get/delete on that one Secret).
   Every call stays inside policy `vault-bootstrap`; the Job avoids `vault audit list` (needs
   `sudo` on `sys/audit`) and `vault token lookup` (needs the default policy).
4. VSO logs in as `vault-demo/vault-demo` and keeps `vault-demo/hello` in sync (every 60 s).

No privileged token is left afterwards. For admin work, generate a short-lived root token with
the recovery keys (`vault operator generate-root`, idp-infra `docs/vault.md`), use it, and revoke it.

## Re-runs and failures

- Argo CD re-runs the Job on every sync of the `vault` app. When the bootstrap Secret is gone (or
  its token is dead) and the completion mark is present, it exits 0 and changes nothing.
- It never exits 0 while Vault is unconfigured, so the Secret is never deleted before
  configuration finished.
- **Token expired or Job started late:** the bootstrap token lives 30 min. If it is expired or
  revoked and Vault is not configured, the Job fails at once with instructions; it does not wait.
  Fix: re-run `./scripts/bootstrap-secrets.sh` in idp-infra (it issues a fresh bootstrap token),
  then sync the `vault` app in Argo CD (PostSync hooks only run on a sync). If no token can be
  issued, use `vault operator generate-root` with the recovery keys.
- **No Secret within 20 min** of Vault being unsealed, or Vault still sealed after 20 min: the
  Job fails with the same instructions (`activeDeadlineSeconds` 50 min is only a backstop).

## Security notes

- **Pre-init window:** until `vault operator init` runs, `sys/init` is unauthenticated: any pod
  allowed to reach port 8200 could initialize Vault first and hold its keys. The NetworkPolicy
  limits who can reach it, and the idp-infra script detects front-running by checking that the
  Secret Manager `vault-recovery-keys` version it wrote is newer than `vault-0`'s creation time;
  if not, treat the Vault as compromised and rebuild it.
- **Tailnet exposure:** `vault-admin` puts the UI and API on the tailnet (Tailscale ACLs for
  `tag:k8s` decide who reaches it). Vault still requires a token; the `kubernetes/` auth mount is
  listed on the login page (completion mark), which reveals only that the method exists.
- **VSO scope:** the VSO controller's ClusterRole can create, read, update and delete Secrets,
  request ServiceAccount tokens, and patch Deployments/StatefulSets/DaemonSets (rollout restarts)
  in every namespace. What it may read from Vault is still limited per namespace by the Vault
  role bound to that namespace's ServiceAccount.
- **Plain HTTP listener** inside the cluster until TLS from a cert-manager in-cluster CA lands
  (TODO, ADR); traffic is limited by the NetworkPolicies but not encrypted (the namespaces are
  not in the ambient mesh).

## Network

`networkpolicy.yaml`: default-deny ingress; port 8200 only from VSO (namespace
`vault-secrets-operator`), from the Tailscale proxy pods of the `vault-admin` Ingress (namespace
`tailscale`, labels `tailscale.com/parent-resource=vault-admin`, `parent-resource-ns=vault`,
`parent-resource-type=ingress`, set by the operator on proxy pods) and from the `vault-config`
Job pods; 8201 only between Vault servers (unused with one replica). `kubectl exec` used by the
bootstrap goes through the API server and the kubelet, not the pod network.

## Known limits (follow-ups)

- Listener is plain HTTP inside the cluster (see security notes).
- Single node on a Spot VM: a preemption means a few minutes without Vault. VSO keeps the last
  synced Secrets, so running pods are unaffected; Vault unseals itself on restart through KMS.
- No Raft snapshots: all Vault data is lost on `make down` by design for now.
