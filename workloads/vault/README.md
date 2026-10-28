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
2. `make up` in `idp-infra` runs the Vault bootstrap script: `kubectl exec` into `vault-0`,
   `vault operator init` (recovery keys go to Secret Manager, never to Git), and creates the Secret
   `vault/vault-bootstrap` (key `root-token`). Vault unseals itself through Cloud KMS
   (`seal "gcpckms"`, key ring `idp`, key `vault-unseal`, Workload Identity as `vault@`).
3. The `vault-config` PostSync Job (`config-job.yaml`) waits for Vault to be unsealed and for the
   Secret, then with the root token: enables the `file` audit device to stdout (Cloud Logging),
   mounts kv-v2 at `kv/`, writes `kv/vault-demo/hello` (`message=hello from vault`), writes policy
   `vso-demo` (read `kv/data/vault-demo/hello` only), enables Kubernetes auth (Vault's own
   ServiceAccount does the TokenReview, via the chart's `system:auth-delegator` binding) with role
   `vso-demo` bound to ServiceAccount `vault-demo/vault-demo` (audience `vault`), makes the
   `kubernetes/` auth mount visible on the login page (the completion mark), and **revokes the root
   token**. A second container then deletes `vault/vault-bootstrap` (RBAC: get/delete on that one
   Secret by name).
4. VSO logs in as `vault-demo/vault-demo` and keeps `vault-demo/hello` in sync (every 60 s).

There is no root token afterwards. For admin work, generate a short-lived one with the recovery
keys (`vault operator generate-root`), use it, and revoke it.

## Re-runs and failures

- Argo CD re-runs the Job on every sync of the `vault` app. When the bootstrap Secret is gone and
  the completion mark is present it exits 0 and changes nothing.
- It never exits 0 while Vault is unconfigured and no token is visible, so the Secret is never
  deleted before configuration finished. If `make up` never creates the Secret, the Job fails after
  1 h (`activeDeadlineSeconds`) and the app shows a failed sync: run the bootstrap script, then
  sync the `vault` app again.
- If the token in the Secret is no longer valid and Vault is not configured (for example the
  bootstrap was half done), the Job fails on purpose: rebuild, or generate a root token with the
  recovery keys and recreate `vault/vault-bootstrap`.

## Network

`networkpolicy.yaml`: default-deny ingress; port 8200 only from the `vault-secrets-operator` and
`tailscale` namespaces and from the `vault-config` Job pods; 8201 only between Vault servers
(unused with one replica). `kubectl exec` used by the bootstrap goes through the API server and
the kubelet, not the pod network. The namespace is not in the ambient mesh.

## Known limits (follow-ups)

- Listener is plain HTTP inside the cluster. TODO: TLS from a cert-manager in-cluster CA (ADR).
- Single node on a Spot VM: a preemption means a few minutes without Vault. VSO keeps the last
  synced Secrets, so running pods are unaffected; Vault unseals itself on restart through KMS.
- No Raft snapshots: all Vault data is lost on `make down` by design for now.
