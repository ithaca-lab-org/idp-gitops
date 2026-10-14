#!/usr/bin/env bash
# Renders the Istio charts the way Argo CD does and asserts the settings that broke a
# real cluster. Argo CD renders without the "-gke" suffix on the Kubernetes version, so
# anything the chart autodetects from it silently falls back to non-GKE defaults.
# Needs helm and network access to the Istio chart repo. Run by CI and `make render-check`.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="1.27.1" # keep in step with apps/istio-*.yaml
KUBE="v1.36.4"   # deliberately without -gke

export HELM_CACHE_HOME="${HELM_CACHE_HOME:-$(mktemp -d)}" HELM_CONFIG_HOME="${HELM_CONFIG_HOME:-$(mktemp -d)}" HELM_DATA_HOME="${HELM_DATA_HOME:-$(mktemp -d)}"
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
helm repo update istio >/dev/null

out="$(helm template istio-cni istio/cni --version "$VERSION" --kube-version "$KUBE" -n istio-system -f platform/istio/cni.yaml)"
dir="$(awk '/- name: cni-bin-dir/{getline; getline; print $2}' <<<"$out")"
if [ "$dir" != "/home/kubernetes/bin" ]; then
  echo "render-check FAIL: istio-cni would write to '${dir:-?}', expected /home/kubernetes/bin (read-only /opt/cni/bin breaks GKE nodes)" >&2
  exit 1
fi
echo "render-check ok: istio-cni bin dir is $dir"
