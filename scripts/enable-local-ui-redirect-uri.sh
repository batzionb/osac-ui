#!/usr/bin/env bash
# Patch the Keycloak osac-ui client so local dev (pnpm dev on localhost:5173) can complete OIDC login.
#
# Usage:
#   export KUBECONFIG=~/envs/asaf-sno2/kubeconfig
#   ./scripts/enable-local-ui-redirect-uri.sh
#   ./scripts/enable-local-ui-redirect-uri.sh --namespace osac-laptop-sno --dry-run
#   ./scripts/enable-local-ui-redirect-uri.sh --verify-only
set -euo pipefail

KEYCLOAK_NS="${KEYCLOAK_NS:-keycloak}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-osac}"
CLIENT_ID="${CLIENT_ID:-osac-ui}"
LOCAL_ORIGIN="${LOCAL_ORIGIN:-http://localhost:5173}"
KEYCLOAK_USERNAME="${KEYCLOAK_USERNAME:-}"
KEYCLOAK_PASSWORD="${KEYCLOAK_PASSWORD:-}"
OSAC_NAMESPACE=""
DRY_RUN=false
VERIFY_ONLY=false

usage() {
  cat <<'EOF'
Enable local osac-ui OIDC login by adding localhost redirect URIs to the Keycloak osac-ui client.

Options:
  --namespace <ns>         OSAC namespace (auto-detected from osac-ui route if omitted)
  --keycloak-namespace <ns> Keycloak namespace (default: keycloak)
  --local-origin <url>     Local dev origin (default: http://localhost:5173)
  --keycloak-username <u>  Keycloak admin username (default: admin)
  --keycloak-password <p>  Keycloak admin password (tries this, then admin, then k8s secret)
  --dry-run                Print planned changes without applying
  --verify-only            Exit 0 if localhost redirect URIs are already configured
  -h, --help               Show this help

Requires: kubectl or oc, curl, jq
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      OSAC_NAMESPACE="${2:-}"
      shift 2
      ;;
    --keycloak-namespace)
      KEYCLOAK_NS="${2:-}"
      shift 2
      ;;
    --local-origin)
      LOCAL_ORIGIN="${2:-}"
      shift 2
      ;;
    --keycloak-username)
      KEYCLOAK_USERNAME="${2:-}"
      shift 2
      ;;
    --keycloak-password)
      KEYCLOAK_PASSWORD="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if command -v kubectl >/dev/null 2>&1; then
  KUBE_CMD=(kubectl)
elif command -v oc >/dev/null 2>&1; then
  KUBE_CMD=(oc)
else
  echo "ERROR: kubectl or oc is required" >&2
  exit 1
fi

LOCAL_ORIGIN="${LOCAL_ORIGIN%/}"
LOCAL_CALLBACK="${LOCAL_ORIGIN}/callback"
LOCAL_REDIRECT_WILDCARD="${LOCAL_ORIGIN}/*"

# Also allow 127.0.0.1 when origin uses localhost (common alternate).
ALT_ORIGIN=""
ALT_CALLBACK=""
ALT_REDIRECT_WILDCARD=""
if [[ "${LOCAL_ORIGIN}" == http://localhost:* ]]; then
  ALT_ORIGIN="http://127.0.0.1:${LOCAL_ORIGIN##http://localhost:}"
  ALT_CALLBACK="${ALT_ORIGIN}/callback"
  ALT_REDIRECT_WILDCARD="${ALT_ORIGIN}/*"
fi

discover_osac_namespace() {
  if [[ -n "${OSAC_NAMESPACE}" ]]; then
    echo "${OSAC_NAMESPACE}"
    return
  fi

  local ns
  ns="$("${KUBE_CMD[@]}" get route osac-ui -A -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || true)"
  if [[ -z "${ns}" ]]; then
    echo "ERROR: Could not find osac-ui route. Pass --namespace." >&2
    exit 1
  fi
  echo "${ns}"
}

discover_ui_route_host() {
  local ns="$1"
  "${KUBE_CMD[@]}" get route osac-ui -n "${ns}" -o jsonpath='{.spec.host}' 2>/dev/null || true
}

discover_keycloak_url() {
  local host
  host="$("${KUBE_CMD[@]}" get route keycloak -n "${KEYCLOAK_NS}" -o jsonpath='{.spec.host}' 2>/dev/null || true)"
  if [[ -z "${host}" ]]; then
    echo "ERROR: Could not find Keycloak route in namespace ${KEYCLOAK_NS}" >&2
    exit 1
  fi
  echo "https://${host}"
}

try_keycloak_token() {
  local kc_url="$1" username="$2" password="$3"
  curl -sk "${kc_url}/realms/master/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=${username}" \
    -d "password=${password}" | jq -r '.access_token // empty'
}

get_keycloak_admin_token() {
  local kc_url="$1"
  local token password
  local username="${KEYCLOAK_USERNAME:-admin}"

  if [[ -n "${KEYCLOAK_PASSWORD}" ]]; then
    token="$(try_keycloak_token "${kc_url}" "${username}" "${KEYCLOAK_PASSWORD}")"
    if [[ -n "${token}" && "${token}" != "null" ]]; then
      echo "${token}"
      return
    fi
    echo "ERROR: Could not obtain Keycloak admin token with provided credentials" >&2
    exit 1
  fi

  token="$(try_keycloak_token "${kc_url}" "${username}" "admin")"
  if [[ -n "${token}" && "${token}" != "null" ]]; then
    echo "${token}"
    return
  fi

  password="$("${KUBE_CMD[@]}" get secret keycloak-initial-admin -n "${KEYCLOAK_NS}" \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)"
  if [[ -z "${password}" ]]; then
    echo "ERROR: Could not obtain Keycloak admin token (tried ${username}/admin and keycloak-initial-admin secret)" >&2
    exit 1
  fi

  token="$(try_keycloak_token "${kc_url}" "${username}" "${password}")"
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    echo "ERROR: Could not obtain Keycloak admin token" >&2
    exit 1
  fi
  echo "${token}"
}

get_client_internal_id() {
  local kc_url="$1" token="$2"
  curl -sk -H "Authorization: Bearer ${token}" \
    "${kc_url}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${CLIENT_ID}" | jq -r '.[0].id // empty'
}

has_local_redirect_uri() {
  local redirect_uris_json="$1"
  local uri
  for uri in "${LOCAL_CALLBACK}" "${LOCAL_REDIRECT_WILDCARD}" "${ALT_CALLBACK}" "${ALT_REDIRECT_WILDCARD}"; do
    [[ -z "${uri}" ]] && continue
    if echo "${redirect_uris_json}" | jq -e --arg u "${uri}" 'index($u) != null' >/dev/null; then
      return 0
    fi
  done
  return 1
}

merge_redirect_uris() {
  local current_json="$1"
  local uris_json='[]'

  uris_json="$(echo "${current_json}" | jq -c '.redirectUris // []')"
  for uri in "${LOCAL_CALLBACK}" "${LOCAL_REDIRECT_WILDCARD}" "${ALT_CALLBACK}" "${ALT_REDIRECT_WILDCARD}"; do
    [[ -z "${uri}" ]] && continue
    uris_json="$(jq -cn --argjson existing "${uris_json}" --arg uri "${uri}" \
      '$existing + [$uri] | unique')"
  done
  echo "${uris_json}"
}

OSAC_NAMESPACE="$(discover_osac_namespace)"
UI_HOST="$(discover_ui_route_host "${OSAC_NAMESPACE}")"
KC_URL="$(discover_keycloak_url)"

echo "OSAC namespace:    ${OSAC_NAMESPACE}"
echo "UI route:          ${UI_HOST:-<not found>}"
echo "Keycloak:          ${KC_URL}"
echo "Realm / client:    ${KEYCLOAK_REALM} / ${CLIENT_ID}"
echo "Local redirect:    ${LOCAL_CALLBACK}"

KC_ADMIN_TOKEN="$(get_keycloak_admin_token "${KC_URL}")"
CLIENT_INTERNAL_ID="$(get_client_internal_id "${KC_URL}" "${KC_ADMIN_TOKEN}")"

if [[ -z "${CLIENT_INTERNAL_ID}" ]]; then
  if [[ -z "${UI_HOST}" ]]; then
    echo "ERROR: Keycloak client ${CLIENT_ID} not found and osac-ui route is missing — cannot create client" >&2
    exit 1
  fi

  DEPLOYED_ORIGIN="https://${UI_HOST}"
  CREATE_PAYLOAD="$(jq -cn \
    --arg clientId "${CLIENT_ID}" \
    --arg rootUrl "${DEPLOYED_ORIGIN}" \
    --arg deployedCallback "${DEPLOYED_ORIGIN}/callback" \
    --arg deployedWildcard "${DEPLOYED_ORIGIN}/*" \
    --arg localCallback "${LOCAL_CALLBACK}" \
    --arg localWildcard "${LOCAL_REDIRECT_WILDCARD}" \
    --arg altCallback "${ALT_CALLBACK}" \
    --arg altWildcard "${ALT_REDIRECT_WILDCARD}" \
    '{
      clientId: $clientId,
      name: "OSAC UI",
      publicClient: true,
      directAccessGrantsEnabled: false,
      standardFlowEnabled: true,
      rootUrl: $rootUrl,
      redirectUris: ([$deployedCallback, $deployedWildcard, $localCallback, $localWildcard, $altCallback, $altWildcard] | map(select(length > 0)) | unique),
      webOrigins: ["+"],
      protocol: "openid-connect",
      enabled: true,
      attributes: {
        "pkce.code.challenge.method": "S256"
      }
    }')"

  if [[ "${VERIFY_ONLY}" == true ]]; then
    echo "VERIFY FAILED: ${CLIENT_ID} client does not exist"
    exit 1
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    echo "DRY RUN: would create Keycloak client:"
    echo "${CREATE_PAYLOAD}" | jq .
    exit 0
  fi

  curl -sk -f -X POST \
    -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    "${KC_URL}/admin/realms/${KEYCLOAK_REALM}/clients" \
    -d "${CREATE_PAYLOAD}" >/dev/null
  echo "Created Keycloak client ${CLIENT_ID}"
  exit 0
fi

CURRENT_CLIENT="$(curl -sk -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
  "${KC_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${CLIENT_INTERNAL_ID}")"

CURRENT_REDIRECTS="$(echo "${CURRENT_CLIENT}" | jq -c '.redirectUris // []')"
if has_local_redirect_uri "${CURRENT_REDIRECTS}"; then
  echo "Local redirect URIs already configured:"
  echo "${CURRENT_REDIRECTS}" | jq .
  if [[ "${VERIFY_ONLY}" == true ]]; then
    exit 0
  fi
  if [[ "${DRY_RUN}" == true ]]; then
    echo "DRY RUN: no changes needed"
    exit 0
  fi
  echo "Nothing to do."
  exit 0
fi

NEW_REDIRECTS="$(merge_redirect_uris "${CURRENT_CLIENT}")"
UPDATE_PAYLOAD="$(echo "${CURRENT_CLIENT}" | jq --argjson redirects "${NEW_REDIRECTS}" '.redirectUris = $redirects | del(.id, .access)')"

if [[ "${VERIFY_ONLY}" == true ]]; then
  echo "VERIFY FAILED: localhost redirect URIs missing"
  echo "Current redirectUris:"
  echo "${CURRENT_REDIRECTS}" | jq .
  exit 1
fi

echo "Planned redirectUris:"
echo "${NEW_REDIRECTS}" | jq .

if [[ "${DRY_RUN}" == true ]]; then
  echo "DRY RUN: no changes applied"
  exit 0
fi

curl -sk -f -X PUT \
  -H "Authorization: Bearer ${KC_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  "${KC_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${CLIENT_INTERNAL_ID}" \
  -d "${UPDATE_PAYLOAD}" >/dev/null

echo "Updated Keycloak client ${CLIENT_ID} (${CLIENT_INTERNAL_ID})"
echo "Retry login at ${LOCAL_ORIGIN}"
