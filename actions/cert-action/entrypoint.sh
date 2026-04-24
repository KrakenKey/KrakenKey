#!/usr/bin/env bash
set -euo pipefail

# ── 1. Mask secrets ──────────────────────────────────────────────
echo "::add-mask::${INPUT_API_KEY}"

# ── 2. Validate inputs ──────────────────────────────────────────
validate_inputs() {
  if [[ -z "${INPUT_API_KEY}" ]]; then
    echo "::error::Missing required input: api-key"
    exit 1
  fi
  if [[ ! "${INPUT_API_KEY}" =~ ^kk_ ]]; then
    echo "::error::Invalid api-key format — must start with 'kk_'"
    exit 1
  fi

  case "${INPUT_COMMAND}" in
    issue)
      if [[ -z "${INPUT_DOMAIN:-}" ]]; then
        echo "::error::Missing required input: domain (required for 'issue' command)"
        exit 1
      fi
      ;;
    renew|download)
      if [[ -z "${INPUT_CERT_ID:-}" ]]; then
        echo "::error::Missing required input: cert-id (required for '${INPUT_COMMAND}' command)"
        exit 1
      fi
      ;;
    *)
      echo "::error::Invalid command '${INPUT_COMMAND}' — must be: issue, renew, or download"
      exit 1
      ;;
  esac
}

# ── 3. Download CLI binary ───────────────────────────────────────
download_cli() {
  local version="${INPUT_CLI_VERSION}"
  local os arch binary_name download_url checksums_url

  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac

  if [[ "${version}" == "latest" ]]; then
    version=$(curl -fsSL "https://api.github.com/repos/krakenkey/cli/releases/latest" | jq -r '.tag_name')
    echo "::debug::Resolved latest CLI version: ${version}"
  fi

  binary_name="krakenkey_${version#v}_${os}_${arch}.tar.gz"
  download_url="https://github.com/krakenkey/cli/releases/download/${version}/${binary_name}"
  checksums_url="https://github.com/krakenkey/cli/releases/download/${version}/checksums.txt"

  echo "::group::Downloading krakenkey-cli ${version} (${os}/${arch})"
  curl -fsSL "${download_url}" -o "/tmp/${binary_name}"
  curl -fsSL "${checksums_url}" -o /tmp/checksums.txt

  # Verify checksum
  (cd /tmp && grep "${binary_name}" checksums.txt | sha256sum -c -)
  tar -xzf "/tmp/${binary_name}" -C /tmp krakenkey
  chmod +x /tmp/krakenkey
  echo "::endgroup::"

  export PATH="/tmp:${PATH}"
}

# ── 4. Execute command ───────────────────────────────────────────
execute_issue() {
  local args=(
    --api-url "${INPUT_API_URL}"
    --output json
    --no-color
    cert issue
    --domain "${INPUT_DOMAIN}"
    --key-type "${INPUT_KEY_TYPE}"
    --poll-interval "${INPUT_POLL_INTERVAL}"
    --poll-timeout "${INPUT_POLL_TIMEOUT}"
    --key-out "${INPUT_KEY_PATH}"
    --csr-out "${INPUT_CSR_PATH}"
    --out "${INPUT_CERT_PATH}"
  )
  [[ "${INPUT_AUTO_RENEW}" == "true" ]] && args+=(--auto-renew)
  [[ "${INPUT_WAIT}" == "true" ]] && args+=(--wait)
  [[ -n "${INPUT_SAN}" ]] && args+=(--san "${INPUT_SAN}")
  [[ -n "${INPUT_SUBJECT_ORG}" ]] && args+=(--org "${INPUT_SUBJECT_ORG}")
  [[ -n "${INPUT_SUBJECT_OU}" ]] && args+=(--ou "${INPUT_SUBJECT_OU}")
  [[ -n "${INPUT_SUBJECT_COUNTRY}" ]] && args+=(--country "${INPUT_SUBJECT_COUNTRY}")

  KK_API_KEY="${INPUT_API_KEY}" krakenkey "${args[@]}"
}

execute_renew() {
  local result wait_args=()
  [[ "${INPUT_WAIT}" == "true" ]] && wait_args+=(--wait)
  result=$(KK_API_KEY="${INPUT_API_KEY}" krakenkey \
    --api-url "${INPUT_API_URL}" \
    --output json \
    --no-color \
    cert renew "${INPUT_CERT_ID}" \
    "${wait_args[@]}" \
    --poll-interval "${INPUT_POLL_INTERVAL}" \
    --poll-timeout "${INPUT_POLL_TIMEOUT}")
  echo "${result}"

  local status
  status=$(echo "${result}" | jq -r '.status')
  if [[ "${status}" == "issued" ]]; then
    KK_API_KEY="${INPUT_API_KEY}" krakenkey \
      --api-url "${INPUT_API_URL}" \
      --output json \
      --no-color \
      cert download "${INPUT_CERT_ID}" \
      --out "${INPUT_CERT_PATH}" > /dev/null
  fi
}

execute_download() {
  KK_API_KEY="${INPUT_API_KEY}" krakenkey \
    --api-url "${INPUT_API_URL}" \
    --output json \
    --no-color \
    cert download "${INPUT_CERT_ID}" \
    --out "${INPUT_CERT_PATH}"
}

# ── 5. Parse output and set Action outputs ───────────────────────
set_outputs() {
  local result="$1"
  local cert_id status

  cert_id=$(echo "${result}" | jq -r '.id // empty')
  status=$(echo "${result}" | jq -r '.status // empty')

  {
    echo "cert-id=${cert_id}"
    echo "status=${status}"
  } >> "${GITHUB_OUTPUT}"

  if [[ "${status}" == "issued" ]]; then
    local details
    details=$(KK_API_KEY="${INPUT_API_KEY}" krakenkey \
      --api-url "${INPUT_API_URL}" \
      --output json \
      --no-color \
      cert show "${cert_id}" 2>/dev/null || true)

    if [[ -n "${details}" ]]; then
      {
        echo "domain=$(echo "${details}" | jq -r '.details.subject // empty' | sed 's/CN=//')"
        echo "sans=$(echo "${details}" | jq -r '[.details.sans[]? // empty] | join(",")' 2>/dev/null || echo "")"
        echo "issuer=$(echo "${details}" | jq -r '.details.issuer // empty')"
        echo "serial-number=$(echo "${details}" | jq -r '.details.serialNumber // empty')"
        echo "expires=$(echo "${details}" | jq -r '.details.validTo // .expiresAt // empty')"
        echo "fingerprint=$(echo "${details}" | jq -r '.details.fingerprint // empty')"
        echo "key-type=$(echo "${details}" | jq -r '.details.keyType // empty')"
        echo "key-size=$(echo "${details}" | jq -r '.details.keySize // empty')"
      } >> "${GITHUB_OUTPUT}"
    fi
  fi

  {
    echo "cert-path=$(realpath "${INPUT_CERT_PATH}" 2>/dev/null || echo "${INPUT_CERT_PATH}")"
    echo "key-path=$(realpath "${INPUT_KEY_PATH}" 2>/dev/null || echo "${INPUT_KEY_PATH}")"
    echo "csr-path=$(realpath "${INPUT_CSR_PATH}" 2>/dev/null || echo "${INPUT_CSR_PATH}")"
  } >> "${GITHUB_OUTPUT}"

  [[ -f "${INPUT_KEY_PATH}" ]] && chmod 0600 "${INPUT_KEY_PATH}"
  [[ -f "${INPUT_CERT_PATH}" ]] && chmod 0644 "${INPUT_CERT_PATH}"
}

# ── 6. Error handler ────────────────────────────────────────────
handle_error() {
  local exit_code="$1"
  case "${exit_code}" in
    0) return 0 ;;
    2) echo "::error::Authentication failed — verify KRAKENKEY_API_KEY secret is set and valid" ;;
    3) echo "::error::Certificate or resource not found — check cert-id input" ;;
    4) echo "::error::Rate limited by KrakenKey API — wait and retry, or upgrade your plan" ;;
    5) echo "::error::Configuration error — check action inputs" ;;
    *) echo "::error::Command failed (exit code ${exit_code}) — check logs above for details" ;;
  esac
  exit "${exit_code}"
}

# ── Main ─────────────────────────────────────────────────────────
main() {
  validate_inputs
  download_cli

  local result=""
  local exit_code=0

  echo "::group::KrakenKey ${INPUT_COMMAND}"
  case "${INPUT_COMMAND}" in
    issue)    result=$(execute_issue)    || exit_code=$? ;;
    renew)    result=$(execute_renew)    || exit_code=$? ;;
    download) result=$(execute_download) || exit_code=$? ;;
  esac
  echo "::endgroup::"

  if [[ ${exit_code} -ne 0 ]]; then
    handle_error "${exit_code}"
  fi

  set_outputs "${result}"

  echo "### KrakenKey Certificate" >> "${GITHUB_STEP_SUMMARY}"
  echo "" >> "${GITHUB_STEP_SUMMARY}"
  if [[ "${INPUT_COMMAND}" == "issue" ]]; then
    {
      echo "| Field | Value |"
      echo "|-------|-------|"
      echo "| **Command** | \`${INPUT_COMMAND}\` |"
      echo "| **Domain** | \`${INPUT_DOMAIN}\` |"
      echo "| **Cert ID** | \`$(echo "${result}" | jq -r '.id // "—"')\` |"
      echo "| **Status** | \`$(echo "${result}" | jq -r '.status // "—"')\` |"
      echo "| **Key Type** | \`${INPUT_KEY_TYPE}\` |"
    } >> "${GITHUB_STEP_SUMMARY}"
  else
    {
      echo "| Field | Value |"
      echo "|-------|-------|"
      echo "| **Command** | \`${INPUT_COMMAND}\` |"
      echo "| **Cert ID** | \`${INPUT_CERT_ID}\` |"
      echo "| **Status** | \`$(echo "${result}" | jq -r '.status // "—"')\` |"
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

main "$@"
