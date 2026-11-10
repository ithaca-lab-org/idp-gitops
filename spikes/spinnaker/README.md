# Spinnaker spike (throwaway, ADR 0011)

Goal: answer the open points of `idp-infra/docs/adr/0011-tenant-delivery-with-spinnaker.md` with numbers. Nothing here is synced by the root app: you apply one Application by hand and delete it afterwards. The agent does not run any of this.

What is installed: upstream `spinnaker-kustomize` at release `spinnaker-release-2026.4.1` (images pinned to tag `2026.4.1`), in namespace `spinnaker`, with MySQL and Redis in the cluster. Igor, Fiat, Keel and Kayenta are scaled to 0. Upstream's `cluster-admin` binding for Clouddriver is removed; its only access is the Role in `spikes/spinnaker-app` (namespace `spike-app`: deployments, services; read on replicasets, pods, events).

**Known spike-only weaknesses (never promote as is):** MySQL password `testing123` and Gate's `admin` password are upstream defaults (public); no TLS; no ingress (reach Deck and Gate with `kubectl port-forward` only); images by tag, not digest.

## Run (you)

1. Do not merge this PR. Run `make up` as usual (Argo CD reads the branch `spike/spinnaker-minimal` directly once the Application exists).
2. `kubectl apply -f spikes/spinnaker/application.yaml` (from a checkout of the branch), then watch: `kubectl -n spinnaker get pods -w`.
3. Fill in the table below and paste it back. Then `kubectl delete -f spikes/spinnaker/application.yaml`, `make down`.

## Measure and check

| # | What | How | Record |
|---|---|---|---|
| 1 | Nodes before and after | `kubectl get nodes` (did the autoscaler add one?) | count, time to add |
| 2 | Time from apply to all pods Ready | `kubectl -n spinnaker get pods` | minutes; which pods restart |
| 3 | Real memory | `kubectl top pods -n spinnaker` and `kubectl top nodes` once idle | per pod MiB, node % |
| 4 | Pods that fail and why | `kubectl -n spinnaker logs deploy/<svc> --tail=50` | first error line |
| 5 | Config keys accepted | clouddriver log: account `spike` loaded? gate log: api-tokens on? front50: service account `idp-controller`? | yes/no each |
| 6 | Restricted Role | `kubectl auth can-i create deployments -n spike-app --as=system:serviceaccount:spinnaker:clouddriver` must be yes; same for `-n default`, `create httproutes.gateway.networking.k8s.io -n spike-app`, `get nodes`, `create secrets -n spike-app` must all be no | yes/no each |
| 7 | Clouddriver without cluster-admin | clouddriver log: any `forbidden` lines (cluster-scoped reads such as CRDs or namespaces)? | the exact verbs and resources |
| 8 | Rosco Kustomize version | `kubectl -n spinnaker exec deploy/rosco -- kustomize version` | version |
| 9 | Gate machine auth | port-forward `svc/gate 8084`; log in with the basic `admin` account; mint an API token for `idp-controller` (Gate `POST /api-tokens`, see the comments in upstream `overlays/config/files/gate-local.yml`); call `GET /applications` with the header `X-Spinnaker-Token` | works / error |
| 10 | Pipeline end to end | In Deck (port-forward `svc/deck 9000`): create application `spikeapp`; pipeline stage 1 Bake (Manifest) renderer `KUSTOMIZE`, input artifact type `git/repo`, repo `https://github.com/ithaca-lab-org/idp-gitops`, branch `spike/spinnaker-minimal`, context dir `spikes/sample-app/deploy/base`, output name `base`; stage 2 Deploy (Manifest) from the baked artifact, account `spike`, namespace `spike-app`. Run it. | bake ok? deploy ok? `kubectl -n spike-app get deploy,svc` |
| 11 | Isolation | Edit the Deploy stage to target namespace `default` or a `Role` object: it must fail | failed how |
| 12 | Echo/Pub/Sub trigger (optional, skip if time is short) | only if you want to test point 4 of the ADR | notes |

If a pod will not start, paste the first error and stop: the point of the spike is to learn what 2026.4.1 really needs.

## Cleanup

`kubectl delete -f spikes/spinnaker/application.yaml`, then `make down`. The MySQL PersistentVolumeClaim can leave a Persistent Disk behind when the cluster is destroyed: check `gcloud compute disks list --filter="name~pvc"` afterwards and delete orphans by hand (the agent does not).
