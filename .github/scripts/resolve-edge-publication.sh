#!/usr/bin/env bash
set -euo pipefail

meshrik_repository="${MESHRIK_REPOSITORY:-Bjorkan/MESHRIK}"
meshrik_image="${MESHRIK_IMAGE:-ghcr.io/bjorkan/meshrik}"
lock_file="${SOURCE_LOCK_FILE:-meshrik-dev/source-lock.json}"
wrapper_image="${WRAPPER_IMAGE:-ghcr.io/bjorkan/ha-meshrik/meshrik-app-dev}"

manifest_json=$(docker buildx imagetools inspect \
  "${meshrik_image}:edge" --format '{{json .Manifest}}')
image_json=$(docker buildx imagetools inspect \
  "${meshrik_image}:edge" --format '{{json .Image}}')

source_digest=$(jq -er '.digest' <<<"${manifest_json}")
amd64_sha=$(jq -er '.["linux/amd64"].config.Labels["org.opencontainers.image.revision"]' \
  <<<"${image_json}")
arm64_sha=$(jq -er '.["linux/arm64"].config.Labels["org.opencontainers.image.revision"]' \
  <<<"${image_json}")
[[ "${amd64_sha}" == "${arm64_sha}" ]] || {
  echo "Edge architectures carry different source revisions" >&2
  exit 1
}
source_sha="${amd64_sha}"
[[ "${source_sha}" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Invalid OCI source revision: ${source_sha}" >&2
  exit 1
}
source_url="https://github.com/${meshrik_repository}/commit/${source_sha}"

jq -e '
  [.manifests[].platform | select(.os == "linux") | .architecture]
  | contains(["amd64", "arm64"])
' <<<"${manifest_json}" >/dev/null
gh api "repos/${meshrik_repository}/commits/${source_sha}" --silent

assert_expected() {
  local label=$1
  local expected=$2
  local actual=$3
  if [[ -n "${expected}" && "${expected}" != "${actual}" ]]; then
    echo "${label} mismatch: event=${expected}, published=${actual}" >&2
    exit 1
  fi
}

assert_expected "source commit" "${PAYLOAD_SOURCE_SHA:-}" "${source_sha}"
assert_expected "source image digest" "${PAYLOAD_IMAGE_DIGEST:-}" "${source_digest}"
assert_expected "source URL" "${PAYLOAD_SOURCE_URL:-}" "${source_url}"

needs_publish=true
wrapper_version="$(date -u +%Y.%m.%d).${GITHUB_RUN_NUMBER}"

if [[ -f "${lock_file}" ]]; then
  locked_source_sha=$(jq -er '.source_sha' "${lock_file}")
  locked_source_digest=$(jq -er '.source_digest' "${lock_file}")

  if [[ "${locked_source_digest}" == "${source_digest}" ]]; then
    [[ "${locked_source_sha}" == "${source_sha}" ]] || {
      echo "One edge digest maps to conflicting source commits" >&2
      exit 1
    }
    locked_wrapper_image=$(jq -er '.wrapper_image' "${lock_file}")
    if [[ "${locked_wrapper_image}" == "${wrapper_image}" ]]; then
      wrapper_version=$(jq -er '.wrapper_version' "${lock_file}")
      wrapper_digest=$(jq -er '.wrapper_digest' "${lock_file}")
      wrapper_manifest=$(docker buildx imagetools inspect \
        "${wrapper_image}@${wrapper_digest}" --format '{{json .Manifest}}')
      jq -e --arg digest "${wrapper_digest}" '
      .digest == $digest and
      ([.manifests[].platform | select(.os == "linux") | .architecture]
        | contains(["amd64", "arm64"]))
      ' <<<"${wrapper_manifest}" >/dev/null
      needs_publish=false
    else
      echo "Wrapper registry renamed; publish a new edge image before updating its lock."
    fi
  elif [[ "${locked_source_sha}" != "${source_sha}" ]]; then
    comparison=$(gh api \
      "repos/${meshrik_repository}/compare/${locked_source_sha}...${source_sha}" \
      --jq '.status')
    [[ "${comparison}" == "ahead" ]] || {
      echo "Refusing non-descendant edge commit ${source_sha} (${comparison})" >&2
      exit 1
    }
  fi
fi

write_output() {
  local key=$1
  local value=$2
  printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
}

write_output source_sha "${source_sha}"
write_output source_digest "${source_digest}"
write_output source_url "${source_url}"
write_output wrapper_version "${wrapper_version}"
write_output needs_publish "${needs_publish}"
