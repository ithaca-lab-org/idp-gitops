# Spinnaker spike 2 (throwaway, ADR 0011): isolation by network, runtime accounts

Builds on spike 1 (results in `idp-infra/docs/adr/0011-tenant-delivery-with-spinnaker.md`, "Spike results"). Branch `spike/spinnaker-isolation`. Nothing here is synced by the root app: the human applies one Application by hand and deletes it afterwards.

Questions this spike answers (user decision 2026-11-11: Gate is protected by the network, no Fiat, no login):
1. Does a NetworkPolicy keep every caller except the controller away from Gate and Clouddriver (which are unauthenticated here)?
2. Does Gate work for the controller with no login (`SECURITY_BASICFORM_ENABLED=false`)?
3. Can Clouddriver Kubernetes accounts be added, updated and deleted at runtime (`POST/PUT/DELETE /credentials`, poller on) without restarting Clouddriver, so a new tenant namespace needs no config change?

What differs from spike 1: Gate login off; Clouddriver credentials poller on (30 s); `networkpolicy.yaml` (default deny ingress in `spinnaker`, allow from its own pods, allow only `spike-controller/app=spike-controller` to Gate 8084 and Clouddriver 7002); namespace `spike-app-b` with the deployer Role; stand-in pods `controller-sim` (namespace `spike-controller`) and `intruder` (namespace `spike-app`).

**Spike-only weaknesses (never promote as is):** no authentication at all on Gate and Clouddriver; label-based NetworkPolicy (production would pin the controller by mesh identity, ambient AuthorizationPolicy on its SPIFFE ID); MySQL password and images as in spike 1; no ingress (port-forward only).

## Run

1. `make up` (idp-infra, main), then from a checkout of this branch: `kubectl apply -f spikes/spinnaker/application.yaml`, `kubectl -n spinnaker get pods -w`.
2. Run the checks below (the agent can run them if you ask), paste the results, then `kubectl delete -f spikes/spinnaker/application.yaml`, `make down` (it prints orphaned PVC disks; `make pv-disk-cleanup DELETE=1 MAX=n` removes them).

Shorthand: `GATE=http://gate.spinnaker:8084/api/v1`, `CD=http://clouddriver.spinnaker:7002`, `CTRL="kubectl -n spike-controller exec controller-sim --"`.

## Checks

| # | What | How | Expect |
|---|---|---|---|
| 1 | Pods Ready, Gate starts with login off | `kubectl -n spinnaker get pods`; gate log has no basic-auth setup errors | all Ready |
| 2 | Controller reaches Gate with no credentials | `$CTRL curl -s -m 8 -o /dev/null -w '%{http_code}' $GATE/credentials` | 200 |
| 3 | Controller reaches Clouddriver | `$CTRL curl -s -m 8 -o /dev/null -w '%{http_code}' $CD/health` | 200 |
| 4 | Intruder is blocked | same two calls from `kubectl -n spike-app exec intruder --` | timeout (000) |
| 5 | Intruder blocked from MySQL and Redis | `curl -m 5 mysql.spinnaker:3306`, `redis.spinnaker:6379` from `intruder` | timeout |
| 6 | Policy really enforced | repeat 4 after deleting nothing: if 4 returns 200, record it (Dataplane V2 should enforce) | blocked |
| 7 | Add an account at runtime | `$CTRL curl -s -X POST -H 'Content-Type: application/json' -d @- $CD/credentials < pipelines/account-spike-b.json` (pipe the file in), then poll `$GATE/credentials` until `spike-b` appears | seconds until it appears; Clouddriver pod unchanged (`kubectl -n spinnaker get pod -l app.kubernetes.io/name=clouddriver`) |
| 8 | Deploy through the runtime account | create app `spikeapp`, pipeline from `pipelines/deploy.json` with `__NAME__=b`, `__ACCOUNT__=spike-b`, `__NAMESPACE__=spike-app-b`, run it | deploy succeeds, `spike-web` in `spike-app-b` |
| 9 | Update the account | `PUT $CD/credentials/spike-b` with `pipelines/account-spike-b-updated.json` (adds `spike-app`); wait; run the pipeline with `__NAMESPACE__=spike-app` and account `spike-b` | works after the update, fails before |
| 10 | Delete the account | `DELETE $CD/credentials/spike-b`; poll until gone; re-run the pipeline | account gone; the run fails cleanly |
| 11 | Static account unaffected | `$GATE/credentials` still lists `spike`; spike-1 pipeline still works | yes |
| 12 | Restart fallback (ask first) | `kubectl -n spinnaker rollout restart deploy/clouddriver`, time to Ready; do runtime accounts survive (SQL)? | seconds; survive yes/no |

Ids and URLs in the API calls follow the Gate/Clouddriver source; if a call is rejected, record the status and body: the shape of the account JSON is the thing most likely to need a tweak.
