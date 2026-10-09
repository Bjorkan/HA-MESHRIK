#!/usr/bin/env bash
set -euo pipefail

meshrik_repository="${MESHRIK_REPOSITORY:-Bjorkan/MESHRIK}"
meshrik_image="${MESHRIK_IMAGE:-ghcr.io/bjorkan/meshrik}"
lock_file="${SOURCE_LOCK_FILE:-remoteterm/source-lock.json}"
wrapper_image="${WRAPPER_IMAGE:-ghcr.io/bjorkan/ha-meshrik/remoteterm-app}"

release_json=$(gh api "repos/${meshrik_repository}/releases/latest")
release_tag=$(jq -er '.tag_name' <<<"${release_json}")
source_version="${release_tag#v}"
source_url=$(jq -er '.html_url' <<<"${release_json}")

jq -e '.draft == false and .prerelease == false' <<<"${release_json}" >/dev/null
[[ "${source_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Unsupported stable release version: ${source_version}" >&2
  exit 1
}

source_sha=$(gh api "repos/${meshrik_repository}/commits/${release_tag}" --jq '.sha')

assert_expected() {
  local label=$1
  local expected=$2
  local actual=$3
  if [[ -n "${expected}" && "${expected}" != "${actual}" ]]; then
    echo "${label} mismatch: event=${expected}, published=${actual}" >&2
    exit 1
  fi
}

assert_expected "source version" "${PAYLOAD_SOURCE_VERSION:-}" "${source_version}"
assert_expected "source commit" "${PAYLOAD_SOURCE_SHA:-}" "${source_sha}"
assert_expected "release URL" "${PAYLOAD_SOURCE_URL:-}" "${source_url}"

manifest_json=$(docker buildx imagetools inspect \
  "${meshrik_image}:latest" --format '{{json .Manifest}}')
version_manifest_json=$(docker buildx imagetools inspect \
  "${meshrik_image}:${source_version}" --format '{{json .Manifest}}')

source_digest=$(jq -er '.digest' <<<"${manifest_json}")
version_digest=$(jq -er '.digest' <<<"${version_manifest_json}")
[[ "${source_digest}" == "${version_digest}" ]] || {
  echo "latest and ${source_version} do not identify the same published image" >&2
  exit 1
}
assert_expected "source image digest" "${PAYLOAD_IMAGE_DIGEST:-}" "${source_digest}"

jq -e '
  [.manifests[].platform | select(.os == "linux") | .architecture]
  | contains(["amd64", "arm64"])
' <<<"${manifest_json}" >/dev/null

needs_publish=true
wrapper_version="${source_version}.${GITHUB_RUN_NUMBER}"

if [[ -f "${lock_file}" ]]; then
  locked_source_version=$(jq -er '.source_version' "${lock_file}")
  locked_source_sha=$(jq -er '.source_sha' "${lock_file}")
  locked_source_digest=$(jq -er '.source_digest' "${lock_file}")

  if [[ "${locked_source_version}" == "${source_version}" &&
        "${locked_source_digest}" != "${source_digest}" ]]; then
    echo "Stable release ${source_version} changed digest after publication" >&2
    exit 1
  fi

  if [[ "${locked_source_version}" == "${source_version}" &&
        "${locked_source_sha}" == "${source_sha}" &&
        "${locked_source_digest}" == "${source_digest}" ]]; then
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
  fi
fi

write_output() {
  local key=$1
  local value=$2
  printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
}

write_output source_version "${source_version}"
write_output source_sha "${source_sha}"
write_output source_digest "${source_digest}"
write_output source_url "${source_url}"
write_output wrapper_version "${wrapper_version}"
write_output needs_publish "${needs_publish}"
