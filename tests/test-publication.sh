#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/ha-meshrik-publication-tests.XXXXXX)
trap 'rm -rf -- "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin"

# Read-only network simulation for source and wrapper manifests.
cat >"$TMP_ROOT/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"{{json .Image}}"* ]]; then
  jq -cn --arg sha "$SOURCE_SHA" '{"linux/amd64":{config:{Labels:{"org.opencontainers.image.revision":$sha}}},"linux/arm64":{config:{Labels:{"org.opencontainers.image.revision":$sha}}}}'
else
  digest=$SOURCE_DIGEST
  architectures='["amd64","arm64"]'
  if [[ "$*" == *@sha256:* ]]; then
    digest=$WRAPPER_DIGEST
    if [[ "${WRAPPER_MANIFEST_MODE:-valid}" == missing ]]; then
      exit 1
    elif [[ "${WRAPPER_MANIFEST_MODE:-valid}" == single-arch ]]; then
      architectures='["amd64"]'
    fi
  fi
  jq -cn --arg digest "$digest" --argjson architectures "$architectures" \
    '{digest:$digest, manifests:[$architectures[] | {platform:{os:"linux",architecture:.}}]}'
fi
DOCKER
cat >"$TMP_ROOT/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *releases/latest*) jq -cn --arg version "${RELEASE_VERSION:-3.17.1}" \
    '{tag_name:("v"+$version), html_url:("https://github.com/Bjorkan/MESHRIK/releases/tag/v"+$version),draft:false,prerelease:false}' ;;
  *commits/*) if [[ "$*" == *"--jq"* ]]; then printf '%s\n' "$SOURCE_SHA"; else printf '{}\n'; fi ;;
  *compare/*) printf '%s\n' "${COMPARE_STATUS:-ahead}" ;;
  *) printf 'Unexpected gh mock argument: %s\n' "$*" >&2; exit 1 ;;
esac
GH
chmod +x "$TMP_ROOT/bin/docker" "$TMP_ROOT/bin/gh"

run_case() {
	local channel=$1 mode=$2 expected_publish=$3
	local script lock manifest expected old_image source_sha source_digest wrapper_digest
	if [[ "$channel" == stable ]]; then
		script="$ROOT/.github/scripts/resolve-stable-release.sh"
		manifest="$ROOT/meshrik/source-lock.json"
		expected='ghcr.io/bjorkan/ha-meshrik/meshrik-app'
		old_image='ghcr.io/bjorkan/ha-meshrik/remoteterm-app'
	else
		script="$ROOT/.github/scripts/resolve-edge-publication.sh"
		manifest="$ROOT/meshrik-dev/source-lock.json"
		expected='ghcr.io/bjorkan/ha-meshrik/meshrik-app-dev'
		old_image='ghcr.io/bjorkan/ha-meshrik/remoteterm-app-dev'
	fi
	lock="$TMP_ROOT/${channel}-${mode}.json"
	case "$mode" in
	current) jq --arg image "$expected" '.wrapper_image=$image' "$manifest" >"$lock" ;;
	legacy) jq --arg image "$old_image" '.wrapper_image=$image' "$manifest" >"$lock" ;;
	renamed) jq '.wrapper_image="ghcr.io/example/another-package"' "$manifest" >"$lock" ;;
	missing-digest) jq --arg image "$expected" '.wrapper_image=$image | del(.wrapper_digest)' "$manifest" >"$lock" ;;
	missing-multiarch) jq --arg image "$expected" '.wrapper_image=$image' "$manifest" >"$lock" ;;
	source-change)
		cp "$manifest" "$lock"
		;;
	*)
		echo "Unknown mode: $mode" >&2
		exit 1
		;;
	esac
	source_sha=$(jq -r '.source_sha' "$lock")
	source_digest=$(jq -r '.source_digest' "$lock")
	wrapper_digest=$(jq -r '.wrapper_digest // "sha256:missing"' "$lock")
	release_version=$(jq -r '.source_version // "3.17.1"' "$lock")
	compare_status=ahead
	wrapper_manifest_mode=valid
	if [[ "$mode" == missing-multiarch ]]; then
		wrapper_manifest_mode=single-arch
	elif [[ "$mode" == source-change ]]; then
		source_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
		source_digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
		release_version=3.17.2
	fi
	local output="$TMP_ROOT/${channel}-${mode}.out"
	PATH="$TMP_ROOT/bin:$PATH" SOURCE_SHA="$source_sha" SOURCE_DIGEST="$source_digest" \
		WRAPPER_DIGEST="$wrapper_digest" GITHUB_RUN_NUMBER=245 \
		RELEASE_VERSION="$release_version" COMPARE_STATUS="$compare_status" \
		WRAPPER_MANIFEST_MODE="$wrapper_manifest_mode" \
		SOURCE_LOCK_FILE="$lock" GITHUB_OUTPUT="$output" bash "$script" >"$output.log"
	grep -Fxq "needs_publish=${expected_publish}" "$output"
	echo "${channel} (${mode}): OK"
}

run_rejected_edge_case() {
	local mode=$1 source_sha=$2 compare_status=${3:-ahead}
	local lock="$TMP_ROOT/edge-${mode}.json"
	local output="$TMP_ROOT/edge-${mode}.out"
	cp "$ROOT/meshrik-dev/source-lock.json" "$lock"
	if PATH="$TMP_ROOT/bin:$PATH" SOURCE_SHA="$source_sha" \
		SOURCE_DIGEST=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
		WRAPPER_DIGEST=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
		COMPARE_STATUS="$compare_status" GITHUB_RUN_NUMBER=245 \
		SOURCE_LOCK_FILE="$lock" GITHUB_OUTPUT="$output" \
		bash "$ROOT/.github/scripts/resolve-edge-publication.sh" >"$output.log" 2>&1; then
		echo "Expected edge ${mode} to be rejected" >&2
		exit 1
	fi
	echo "edge (${mode}, rejected): OK"
}

for channel in stable edge; do
	run_case "$channel" legacy true
	run_case "$channel" current false
	run_case "$channel" missing-digest true
	run_case "$channel" source-change true
	run_case "$channel" missing-multiarch true
	run_case "$channel" renamed true
done

run_rejected_edge_case invalid-sha not-a-valid-sha
run_rejected_edge_case reordered aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa behind

echo 'All release resolver fixture tests passed.'
