# Vault (Phase 1b)

Self-hosted Vault for developer secrets, delivered to namespaces by the Vault Secrets Operator (VSO).
Design: `IDP_NOTES.md` section 10. Vault is rebuilt empty on every `make up` (single node, Raft on a
1 GiB PVC, no snapshots yet), so everything below runs on every fresh cluster.

| Piece | Where | Wave |
|---|---|---|
| Vault server (chart 0.34.1, Vault 2.0.4), NetworkPolicies, `vault-config` Job | `apps/vault.yaml`, `platform/vault/values.yaml`, this directory | 7 |
| VSO (chart 1.6.2) | `apps/vault-secrets-operator.yaml`, `platform/vault-secrets-operator/values.yaml`, shared VaultConnection `idp-vault` in `workloads/vault-secrets-operator` | 8 |
| Tailscale Ingress `vault-admin` | `apps/vault-admin-access.yaml`, `workloads/vault-admin-access` | 10 |
| Demo: Secret `vault-demo/hello` | `apps/vault-demo.yaml`, `workloads/vault-demo` | 10 |

## Flow on a fresh cluster

1. Argo CD installs Vault. The pod starts sealed and uninitialized; the readiness probe still
   reports Ready (`sealedcode=204&uninitcode=204`), so the app is Healthy and nothing waits on it.
2. `make up` in `idp-infra` runs `scripts/bootstrap-secrets.sh`: `kubectl exec` into `vault-0`,
   `vault operator init` (recovery keys go to Secret Manager, never to Git). Vault unseals itself
   through Cloud KMS (`seal "gcpckms"`, key ring `idp`, key `vault-unseal`, Workload Identity as
   `vault-server@`). The script then issues a short-lived **bootstrap token** (orphan, 30 min TTL, not
   renewable, no default policy, policy `vault-bootstrap`) and stores only that token in the Secret
   `vault/vault-bootstrap` (key `token`).
3. The `vault-config` PostSync Job (`config-job.yaml`) waits for Vault to be unsealed and for the
   Secret (20 min each at most), then with the bootstrap token: enables the `file` audit device to
   stdout (Cloud Logging), mounts kv-v2 at `kv/`, writes `kv/vault-demo/hello`
   (`message=hello from vault`), writes policy `vso-demo` (read `kv/data/vault-demo/hello` only),
   enables Kubernetes auth (Vault's own ServiceAccount does the TokenReview, via the chart's
   `system:auth-delegator` binding) with role `vso-demo` bound to ServiceAccount
   `vault-demo/vault-demo` (audience `vault`), writes the per-namespace policies `ns-reader` and
   `ns-purge` and the roles `ns-reader` and `idp-operator-purge` (see "Per-namespace access"),
   makes the `kubernetes/` auth mount visible on the
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
- Every step is a create-or-overwrite (`enable` tolerates "already in use"), so a retry after a
  partial run is safe. Steps added to the Job later (like the per-namespace policies and roles)
  reach only a Vault configured from scratch: an already configured Vault is not touched. That is
  fine because Vault is rebuilt empty on every `make up`; on a long-lived cluster apply them with a
  short-lived root token (`vault operator generate-root`) or rebuild.
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

## Per-namespace access

Tenant secrets live at `kv/<namespace>/...` (KV v2: data at `kv/data/<namespace>/...`). The
idp-operator creates **no Vault objects per namespace**: the `vault-config` Job writes two
policies and two roles once, and the namespace is enforced by an identity template.

**Policy `ns-reader`** (`<ACC>` is the accessor of the `kubernetes/` auth mount, e.g.
`auth_kubernetes_1a2b3c4d`, read by the Job at run time from `vault auth list`):

```hcl
path "kv/data/{{identity.entity.aliases.<ACC>.metadata.service_account_namespace}}/*" {
  capabilities = ["read"]
}
path "kv/metadata/{{identity.entity.aliases.<ACC>.metadata.service_account_namespace}}/*" {
  capabilities = ["read", "list"]
}
path "kv/data//*" { capabilities = ["deny"] }
path "kv/metadata//*" { capabilities = ["deny"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/renew-self" { capabilities = ["update"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
```

**Role `ns-reader`** (auth/kubernetes): `bound_service_account_names=vault-reader`,
`bound_service_account_namespaces=*`, `alias_name_source=serviceaccount_uid` (the default),
`audience=vault`, `token_policies=ns-reader`, `token_no_default_policy=true`, `token_ttl=10m`,
`token_max_ttl=1h`.

**Policy `ns-purge`** and **role `idp-operator-purge`** (bound to `idp-system/idp-operator`,
audience `vault`, `token_no_default_policy=true`, ttl 5m, max 15m): when a TeamNamespace is
deleted, the operator walks `kv/metadata/<ns>/` with LIST and removes each key with
`DELETE kv/metadata/<ns>/<key>` (KV v2: the key, all its versions and its metadata). It can
never read a secret value: no `read`, no `kv/data`, and no `kv/destroy` (that only destroys
selected versions; deleting the metadata already removes everything).

```hcl
path "kv/metadata/*" { capabilities = ["list", "delete"] }
path "kv/metadata/" { capabilities = ["deny"] }
path "kv/metadata/vault*" { capabilities = ["deny"] }
path "kv/metadata/idp-system/*" { capabilities = ["deny"] }
path "kv/metadata/argocd/*" { capabilities = ["deny"] }
path "kv/metadata/identity/*" { capabilities = ["deny"] }
path "kv/metadata/cert-manager/*" { capabilities = ["deny"] }
path "kv/metadata/tailscale/*" { capabilities = ["deny"] }
path "kv/metadata/default/*" { capabilities = ["deny"] }
path "kv/metadata/echo/*" { capabilities = ["deny"] }
path "kv/metadata/istio-*" { capabilities = ["deny"] }
path "kv/metadata/kube-*" { capabilities = ["deny"] }
path "kv/metadata/gke-*" { capabilities = ["deny"] }
path "auth/token/lookup-self" { capabilities = ["read"] }
path "auth/token/renew-self" { capabilities = ["update"] }
path "auth/token/revoke-self" { capabilities = ["update"] }
```

The deny rules limit a stolen or misused operator token: it cannot enumerate tenants (no LIST
of the root) and cannot wipe platform namespaces. The list is the reserved names and prefixes
of idp-portal `api/internal/orders/orders.go` plus `vault*` (vault, vault-demo,
vault-secrets-operator, reserved in the operator too); keep them in sync. How Vault 2.0.4
matches them (`vault/acl.go`, `AllowOperation`):

- A path without `*`/`+` is an **exact** rule and is checked first. `kv/metadata/` matches only
  `LIST kv/metadata/` (for LIST Vault also tries the path without its trailing slash,
  `kv/metadata`, which matches nothing). `LIST kv/metadata/team-a/` is looked up as
  `kv/metadata/team-a/` and `kv/metadata/team-a`, so the root deny never covers a tenant.
- A trailing `*` is a **prefix** rule; `*` anywhere else is a literal character, which is why
  the prefixes are written `istio-*`, not `istio-*/*`. When several prefix rules match, the most
  specific (longest) wins, so `kv/metadata/vault*` and `kv/metadata/idp-system/*` beat
  `kv/metadata/*`. For LIST with a trailing slash Vault also prefers a deny that is at least as
  specific as the winning allow.
- Result: `LIST kv/metadata/team-a/` and `DELETE kv/metadata/team-a/<key>` match only
  `kv/metadata/*` (allowed); `LIST kv/metadata/` and anything under `vault*`, `idp-system/`,
  `istio-`... is denied. Not covered (and harmless): a root-level *key* literally named after a
  platform namespace, e.g. `kv/metadata/argocd` without a slash; nothing writes keys at the root.
- `vault*` also matches tenant names starting with `vault`; the operator reserves that prefix.

The operator logs in with its own ServiceAccount token, audience `vault`, mounted by
`workloads/idp-operator/idp-operator.yaml` at `/var/run/secrets/vault/token`
(`POST auth/kubernetes/login`, `role=idp-operator-purge`, `jwt=<file content>`, re-read the file
for each login: the kubelet rotates it).

### How the template keeps a tenant inside its namespace

- Kubernetes auth puts `service_account_namespace` (also `service_account_name`,
  `service_account_uid`, `service_account_secret_name`) into the **entity alias metadata** on
  every login (vault-plugin-auth-kubernetes v0.24.1, bundled in Vault 2.0.4, `path_login.go`).
  The value comes from the TokenReview result, not from the client, and these keys are reserved:
  SA annotations can never override them (and `use_annotations_as_alias_metadata` stays off).
- The template addresses the alias by mount accessor, so `alias_name_source` does not matter:
  with the default `serviceaccount_uid` each ServiceAccount gets its own alias and entity, and
  the metadata is still on it. A ServiceAccount deleted and recreated gets a new entity (harmless).
- If the template cannot be resolved (no entity, no alias on that mount, missing key), Vault
  **drops that path rule** (`parsePaths` in `vault/policy.go`): the token gets nothing, not
  `kv/data/*`. Vault also rejects a substituted value containing `*` or `+`. A key present with an
  empty value would render `kv/data//*`; Kubernetes namespaces are never empty, and the two deny
  rules make that path useless anyway.
- Namespace names are DNS labels (`[a-z0-9-]`, max 63): no `/`, `.`, `*` or `+`, so a tenant
  cannot escape its own prefix (`kv/data/team-a/*` does not match `kv/data/team-ab/...`).

### Why `bound_service_account_namespaces=*` is acceptable

The role only lets a ServiceAccount named `vault-reader` log in; what it can read is decided by
the template, i.e. by the namespace of that ServiceAccount. A namespace is the tenant boundary
(its admins already hold every Secret VSO writes there), so one role for all namespaces gives no
tenant more than its own `kv/<ns>/`.

What it implies:

- **Whoever can create a ServiceAccount called `vault-reader` (or a TokenRequest for it) in a
  namespace can read all of that namespace's Vault secrets**, also `kv/<ns>/` for namespaces that
  are not tenants (`kv/vault/`, `kv/idp-system/`, `kv/vault-demo/`...). Keep platform namespaces'
  ServiceAccount and `serviceaccounts/token` rights with the platform, and never write platform
  secrets under `kv/<platform-namespace>/`.
- Tenant admins can read every secret of their namespace from Vault directly, not only through
  VSO. That matches the Secret-level access they already have.
- Hardening later: `bound_service_account_namespace_selector` (a label only TeamNamespaces carry)
  instead of `*`; it needs Vault's ServiceAccount to be allowed to read Namespaces.

### What the operator creates in a tenant namespace

A ServiceAccount `vault-reader` (`automountServiceAccountToken: false`; VSO requests its tokens)
and this VaultAuth. The shared VaultConnection `vault-secrets-operator/idp-vault` comes from
`workloads/vault-secrets-operator` (VSO app). VSO resolves `<namespace>/<name>` refs for
VaultConnections in any namespace without an allow-list; `allowedNamespaces` on the VaultAuth is
only for secrets in *other* namespaces referencing it, so it stays unset. VSO always logs in as
the ServiceAccount in the **secret's** namespace, so even a cross-namespace reference cannot read
another tenant's path.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-reader
  namespace: <ns>
spec:
  vaultConnectionRef: vault-secrets-operator/idp-vault
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: ns-reader
    serviceAccount: vault-reader
    audiences: [vault]
    tokenExpirationSeconds: 600
```

Worked example: a secret written at `kv/payments-team/orders-api/stripe` (portal Secrets page)
becomes the Kubernetes Secret `payments-team/orders-api-stripe`:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: orders-api-stripe
  namespace: payments-team
spec:
  vaultAuthRef: vault-reader
  mount: kv
  type: kv-v2
  path: payments-team/orders-api/stripe # must start with the namespace itself
  refreshAfter: 60s
  destination:
    name: orders-api-stripe
    create: true
```

A `path` under another namespace fails with 403 in the VaultStaticSecret status.

**Who creates VaultStaticSecrets today:** the platform (a cluster admin, or a manifest synced by
Argo CD), not the tenant. The VSO chart does not aggregate its CRDs into the built-in
`view`/`edit`/`admin` ClusterRoles, so a tenant namespace admin cannot create them. Tenant
self-service comes later, either through the portal Secrets page (the operator creates the
VaultStaticSecret, `IDP_NOTES.md` 10.3) or through an RBAC addition (an aggregated ClusterRole
for `vaultstaticsecrets`); neither exists yet, and tenants get no VSO RBAC in this change.

## Network

`networkpolicy.yaml`: default-deny ingress; port 8200 only from VSO (namespace
`vault-secrets-operator`), from the idp-operator pods (namespace `idp-system`, label
`app.kubernetes.io/name=idp-operator`; idp-system has no egress policy and is not in the mesh, so
nothing else is needed on that side), from the Tailscale proxy pods of the `vault-admin` Ingress (namespace
`tailscale`, labels `tailscale.com/parent-resource=vault-admin`, `parent-resource-ns=vault`,
`parent-resource-type=ingress`, set by the operator on proxy pods) and from the `vault-config`
Job pods; 8201 only between Vault servers (unused with one replica). `kubectl exec` used by the
bootstrap goes through the API server and the kubelet, not the pod network.

## Known limits (follow-ups)

- Listener is plain HTTP inside the cluster (see security notes).
- Single node on a Spot VM: a preemption means a few minutes without Vault. VSO keeps the last
  synced Secrets, so running pods are unaffected; Vault unseals itself on restart through KMS.
- No Raft snapshots: all Vault data is lost on `make down` by design for now.
