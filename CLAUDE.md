# idp-gitops rules

Argo CD app-of-apps for the ithaca IDP. Architecture and decisions live in `../IDP_NOTES.md` (sections 5, 8, 11) and `../idp-infra/docs/adr/` (ADR 0003: GitOps with Argo CD).

- `apps/` holds one Argo CD `Application` per add-on. The root Application (created by Terraform in `idp-infra`) syncs this directory. Every Application needs a `sync-wave` annotation (order: cert-manager 1, Istio and Tailscale 2, echo app 3, then later phases).
- Helm charts come from upstream with an **explicitly pinned `targetRevision`**; values live in `platform/<name>/values.yaml` and are referenced as `$values/...` (multi-source). Never use `latest`, `main` or a range for a chart.
- **Argo CD syncs `main` automatically with prune and self-heal.** A merge is a deploy. Review diffs accordingly.
- No secrets in this repo, ever. Secrets come from External Secrets / Vault in later phases. The repo is public.
- Never run `kubectl apply/delete/patch`, `argocd app sync`, or `helm install/upgrade` against the cluster: Argo CD is the only writer. Read-only `kubectl get/describe/logs` is fine.
- The cluster is rebuilt often (`make up` / `make down` in `idp-infra`). Do not set resource finalizers on Applications and do not keep CRDs past a release (`crds.keep: false`), or teardown hangs.
- Run `make check` before finishing a change. Use conventional commits and PRs to `main`.
