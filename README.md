# idp-gitops

Argo CD app-of-apps for the ithaca Internal Developer Platform. Terraform in [`idp-infra`](https://github.com/ithaca-lab-org/idp-infra) installs Argo CD on the GKE cluster and creates one **root Application** pointing at `apps/` here. Everything else is installed from this repo by Argo CD, in sync-wave order.

| Path | Purpose |
|---|---|
| `apps/` | One `Application` per add-on, ordered by `argocd.argoproj.io/sync-wave` |
| `platform/<name>/values.yaml` | Helm values for each add-on (referenced from its Application) |
| `scripts/check.sh` | Structural checks: sync-wave present, values file exists, chart version pinned |

## Sync waves

| Wave | Add-on | Status |
|---|---|---|
| 1 | cert-manager | in repo |
| 2 | Istio ambient + ingress gateway, Tailscale operator | planned |
| 3 | echo test app with a Let's Encrypt certificate | planned |

## How a change reaches the cluster

PR to `main` -> checks pass -> squash merge -> Argo CD syncs (automated, prune, self-heal). There is no manual deploy step. See `CLAUDE.md` for the working rules.

## Repo hygiene

Same set as `idp-infra`: protected `main` (ruleset as code), conventional commits, SHA-pinned least-privilege workflows, zizmor + CodeQL, dependency review, OpenSSF Scorecard, gitleaks, release-please.
