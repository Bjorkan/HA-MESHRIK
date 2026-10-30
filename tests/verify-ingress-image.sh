#!/usr/bin/env bash
# An upstream image must pass this before HA-MESHRIK advertises a new wrapper.
# Home Assistant strips /api/hassio_ingress/<token>/ and passes X-Ingress-Path.
set -euo pipefail

image="${1:?usage: verify-ingress-image.sh <immutable-image-ref>}"
if [[ "$image" != *@sha256:* ]]; then
  echo "Expected an immutable upstream image digest, not a mutable tag" >&2
  exit 2
fi

workdir=$(mktemp -d)
container=""
cleanup() {
  if [[ -n "$container" ]]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

echo "Checking upstream image Ingress contract (no radio writes)..."
docker pull "$image"
container=$(docker run -d --rm \
  -p 127.0.0.1::8000 \
  -e MESHCORE_DATABASE_PATH=/tmp/ingress-contract.db \
  "$image")

host_mapping=$(docker port "$container" 8000/tcp)
port=${host_mapping##*:}
if ! [[ "$port" =~ ^[0-9]+$ ]]; then
  echo "Could not determine published container HTTP test port" >&2
  exit 1
fi
base_url="http://127.0.0.1:${port}"
ready=false
for ((attempt = 0; attempt < 120; attempt++)); do
  if curl --silent --show-error --fail --max-time 3 \
    "${base_url}/api/health" >"$workdir/health.json" 2>/dev/null; then
    ready=true
    break
  fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "$container")" != true ]]; then
    echo "MESHRIK container exited before the HTTP API became ready" >&2
    docker logs "$container" 2>&1 | tail -n 60 >&2 || true
    exit 1
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "Timed out waiting for the MESHRIK HTTP API" >&2
  docker logs "$container" 2>&1 | tail -n 60 >&2 || true
  exit 1
fi

# Only synthetic tokens are used. Never print a real Ingress session prefix.
ingress_path="/api/hassio_ingress/ci-test-token"
headers=(
  -H "X-Ingress-Path: ${ingress_path}"
  -H "X-Forwarded-Proto: https"
  -H "X-Forwarded-Host: ha.example.test"
)

curl --silent --show-error --fail --max-time 10 \
  "${headers[@]}" "${base_url}/settings/radio" >"$workdir/ingress.html"
curl --silent --show-error --fail --max-time 10 \
  "${headers[@]}" "${base_url}/channel/test" >"$workdir/ingress-channel.html"
curl --silent --show-error --fail --max-time 10 \
  "${headers[@]}" "${base_url}/site.webmanifest" >"$workdir/manifest.json"
curl --silent --show-error --fail --max-time 10 \
  "${base_url}/settings/radio" >"$workdir/root.html"

grep -Fq "<base href=\"${ingress_path}/\"" "$workdir/ingress.html"
grep -Fq "<base href=\"${ingress_path}/\"" "$workdir/ingress-channel.html"
grep -Fq '<base href="/"' "$workdir/root.html"
grep -Fq 'assets/' "$workdir/ingress.html"
if grep -Eq '(src|href)="/assets/' "$workdir/ingress.html"; then
  echo "Built assets still refer to the Home Assistant origin root" >&2
  exit 1
fi
if grep -q 'rel="manifest"' "$workdir/ingress.html"; then
  echo "Ingress must not install MESHRIK as a Home Assistant origin PWA" >&2
  exit 1
fi
expected_manifest="https://ha.example.test${ingress_path}/"
jq -e --arg base "$expected_manifest" '
  .id == $base and .start_url == $base and .scope == $base and
  all(.icons[]; .src | startswith($base))
' "$workdir/manifest.json" >/dev/null

echo "Ingress HTML/deep-link/manifest contract: PASS"
