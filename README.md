# idp-gitops

Argo CD app-of-apps for the ithaca Internal Developer Platform. Terraform in [`idp-infra`](https://github.com/ithaca-lab-org/idp-infra) installs Argo CD on the GKE cluster and creates one **root Application** pointing at `apps/` here. Everything else is installed from this repo by Argo CD, in sync-wave order.

| Path | Purpose |
|---|---|
| `apps/` | One `Application` per add-on, ordered by `argocd.argoproj.io/sync-wave` |
| `platform/<name>/values.yaml` | Helm values for each add-on (referenced from its Application) |
| `scripts/check.sh` | Structural checks: sync-wave present, values file exists, chart version pinned |

## Sync waves

Each wave waits for the previous one to be Healthy. Gaps in the numbering are deliberate.

| Wave | Application | What it does |
|---|---|---|
| 1 | cert-manager | CRDs and controller; Workload Identity for Cloud DNS DNS-01 |
| 2 | tailscale-operator | Private tailnet access (OAuth Secret created by `make up` in idp-infra) |
| 2 | istio-prereqs | `istio-system` namespace and the GKE `system-node-critical` ResourceQuota |
| 3 | istio-base | Istio CRDs |
| 4 | istiod | Control plane, ambient profile |
| 5 | istio-cni, ztunnel | Node agents (ambient data plane) |
| 6 | ingress | Let's Encrypt issuers, wildcard certificate, ingress Gateway on the static IP |
| 7 | echo | Phase 0 test app at `https://echo.apps.ithaca-idp.com` |
| 8 | identity | `identity` namespace, lldap (LDAP) and the Keycloak Postgres; Secrets from `bootstrap-secrets.sh` |
| 9 | keycloak | Keycloak (official image, codecentric keycloakx chart), realm `ithaca` federated to lldap, `idp-portal` OIDC client |
| 10 | identity-admin-access | Tailscale Ingresses for the Keycloak admin console and lldap UI (needs MagicDNS and HTTPS certificates enabled on the tailnet) |
| 11 | portal | portal-api (Keycloak OIDC login) in `idp-system` at `https://portal.apps.ithaca-idp.com`; image from Artifact Registry, built by the idp-portal repo |

Istio 1.27.1 values are the ones proven by the ambient smoke test in `idp-infra` (`docs/smoke-ambient.md`, ADR 0002).

## Exposure

Hybrid: the public ingress carries only what end users need, admin surfaces are tailnet-only.

| Surface | Reached through | Notes |
|---|---|---|
| `https://auth.apps.ithaca-idp.com/realms/ithaca/*`, `/resources/*` | Istio ingress Gateway (HTTPRoute `keycloak-public`) | Allow-list: the admin console, `/admin`, the master realm (except the two static 3rd-party-cookie check pages the admin console iframes) and metrics have no route (404) |
| Keycloak admin console | Tailscale Ingress `keycloak-admin` | `https://keycloak-admin.<tailnet>.ts.net`, set as `KC_HOSTNAME_ADMIN` |
| lldap UI | Tailscale Ingress `lldap-admin` | `https://lldap-admin.<tailnet>.ts.net` |
| Portal (later) | Istio ingress Gateway | `portal.apps.ithaca-idp.com`, route added with the portal Deployment |

## TLS

The wildcard certificate for `*.apps.ithaca-idp.com` uses the **Let's Encrypt staging** issuer by default. Production allows only 5 duplicate certificates a week and every `make down` discards the Secret, so a few rebuilds would lock it out. Staging certificates are not trusted by browsers. For a demo, change `issuerRef.name` in `workloads/ingress/certificate.yaml` to `letsencrypt-prod`, merge, and switch back afterwards (see ADR 0006 in `idp-infra`).

## How a change reaches the cluster

PR to `main` -> checks pass -> squash merge -> Argo CD syncs (automated, prune, self-heal). There is no manual deploy step. See `CLAUDE.md` for the working rules.

## Repo hygiene

Same set as `idp-infra`: protected `main` (ruleset as code), conventional commits, SHA-pinned least-privilege workflows, zizmor + CodeQL, dependency review, OpenSSF Scorecard, gitleaks, release-please.
