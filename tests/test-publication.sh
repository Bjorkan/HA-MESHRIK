#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/ha-meshrik-publication-tests.XXXXXX)
trap 'rm -rf -- "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin"

# Read-only network simulation: verify the resolver detects a registry package
# rename even when the upstream image and revision are unchanged.
cat > "$TMP_ROOT/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"{{json .Image}}"* ]]; then
  jq -cn --arg sha "$SOURCE_SHA" '{"linux/amd64":{config:{Labels:{"org.opencontainers.image.revision":$sha}}},"linux/arm64":{config:{Labels:{"org.opencontainers.image.revision":$sha}}}}'
else
  digest=$SOURCE_DIGEST
  if [[ "$*" == *@sha256:* ]]; then
    digest=$WRAPPER_DIGEST
  fi
  jq -cn --arg digest "$digest" '{digest:$digest,manifests:[{platform:{os:"linux",architecture:"amd64"}},{platform:{os:"linux",architecture:"arm64"}}]}'
fi
DOCKER
cat > "$TMP_ROOT/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *releases/latest*) jq -cn '{tag_name:"v3.17.1", html_url:"https://github.com/Bjorkan/MESHRIK/releases/tag/v3.17.1",draft:false,prerelease:false}' ;;
  *commits/*) if [[ "$*" == *"--jq"* ]]; then printf '%s\n' "$SOURCE_SHA"; else printf '{}\n'; fi ;;
  *compare/*) printf 'ahead\n' ;;
  *) printf 'Unexpected gh mock argument: %s\n' "$*" >&2; exit 1 ;;
esac
GH
chmod +x "$TMP_ROOT/bin/docker" "$TMP_ROOT/bin/gh"

run_case() {
  local channel=$1 mode=$2 script lock manifest expected
  if [[ "$channel" == stable ]]; then
    script="$ROOT/.github/scripts/resolve-stable-release.sh"
    manifest="$ROOT/meshrik/source-lock.json"
    expected='ghcr.io/bjorkan/ha-meshrik/meshrik-app'
  else
    script="$ROOT/.github/scripts/resolve-edge-publication.sh"
    manifest="$ROOT/meshrik-dev/source-lock.json"
    expected='ghcr.io/bjorkan/ha-meshrik/meshrik-app-dev'
  fi
  lock="$TMP_ROOT/${channel}-${mode}.json"
  if [[ "$mode" == migrated ]]; then
    jq --arg image "$expected" '.wrapper_image=$image' "$manifest" > "$lock"
  else
    cp "$manifest" "$lock"
  fi
  local source_sha source_digest wrapper_digest
  source_sha=$(jq -r '.source_sha' "$lock")
  source_digest=$(jq -r '.source_digest' "$lock")
  wrapper_digest=$(jq -r '.wrapper_digest' "$lock")
  local output="$TMP_ROOT/${channel}-${mode}.out"
  PATH="$TMP_ROOT/bin:$PATH" SOURCE_SHA="$source_sha" SOURCE_DIGEST="$source_digest" \
    WRAPPER_DIGEST="$wrapper_digest" GITHUB_RUN_NUMBER=245 \
    SOURCE_LOCK_FILE="$lock" GITHUB_OUTPUT="$output" bash "$script" > "$output.log"
  if [[ "$mode" == legacy ]]; then
    grep -Fxq 'needs_publish=true' "$output"
    ! grep -q 'needs_publish=false' "$output"
  else
    grep -Fxq 'needs_publish=false' "$output"
  fi
  echo "${channel} (${mode} lock): OK"
}

run_case stable legacy
run_case edge legacy
run_case stable migrated
run_case edge migrated

echo 'All release resolver migration tests passed.'
