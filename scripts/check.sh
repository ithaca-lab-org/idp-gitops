#!/usr/bin/env bash
# Structural checks that don't need a cluster: every Application under apps/ has a
# sync-wave, points at a values file that exists, and pins an explicit chart version.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
for f in apps/*.yaml; do
  grep -q 'argocd.argoproj.io/sync-wave' "$f" || { echo "$f: missing sync-wave annotation" >&2; fail=1; }
  grep -qE 'targetRevision: *(main|HEAD|latest|\*)$' <(grep -B3 'chart:' "$f") && { echo "$f: chart targetRevision must be pinned" >&2; fail=1; }
  for v in $(grep -oE '\$values/[^ ]+' "$f" | sed 's#^\$values/##'); do
    [ -f "$v" ] || { echo "$f: values file $v not found" >&2; fail=1; }
  done
done
[ "$fail" -eq 0 ] && echo "check ok"
exit "$fail"
