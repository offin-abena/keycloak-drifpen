#!/bin/bash
set -euo pipefail

# Shared MySQL with Laravel — Keycloak creates its own tables; does not wipe users.
: "${KC_DB:=mysql}"
: "${KC_DB_URL:?KC_DB_URL required}"
: "${KC_DB_USERNAME:?KC_DB_USERNAME required}"
: "${KC_DB_PASSWORD:?KC_DB_PASSWORD required}"
: "${KEYCLOAK_ADMIN:?KEYCLOAK_ADMIN required}"
: "${KEYCLOAK_ADMIN_PASSWORD:?KEYCLOAK_ADMIN_PASSWORD required}"
: "${PORT:=8080}"

KC_HOME="${KC_HOME:-$(cd "$(dirname "$0")" && pwd)}"
export PATH="${KC_HOME}/bin:${PATH}"

export KC_HTTP_PORT="${PORT}"
export KC_DB KC_DB_URL KC_DB_USERNAME KC_DB_PASSWORD
export KC_DB_POOL_INITIAL_SIZE="${KC_DB_POOL_INITIAL_SIZE:-2}"
export KC_DB_POOL_MAX_SIZE="${KC_DB_POOL_MAX_SIZE:-5}"
export KC_HEALTH_ENABLED="${KC_HEALTH_ENABLED:-true}"
export KC_HTTP_ENABLED="${KC_HTTP_ENABLED:-true}"
export KC_HOSTNAME_STRICT="${KC_HOSTNAME_STRICT:-false}"
export KC_PROXY_HEADERS="${KC_PROXY_HEADERS:-xforwarded}"

kc.sh build --db=mysql >/tmp/kc-build.log 2>&1 || { cat /tmp/kc-build.log; exit 1; }

# legacy-observability-interface: /health/ready on $PORT (Railway has no :9000 proxy)
kc.sh start --optimized --http-port="${PORT}" --legacy-observability-interface=true &
KC_PID=$!

bootstrap() {
  local base="http://127.0.0.1:${PORT}"
  for _ in $(seq 1 90); do
    if kcadm.sh config credentials \
      --server "${base}" \
      --realm master \
      --user "${KEYCLOAK_ADMIN}" \
      --password "${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done

  if [[ "${DRIFPEN_KC_BOOTSTRAP:-true}" != "true" ]]; then
    return 0
  fi

  kcadm.sh config credentials \
    --server "${base}" \
    --realm master \
    --user "${KEYCLOAK_ADMIN}" \
    --password "${KEYCLOAK_ADMIN_PASSWORD}" || return 0

  if ! kcadm.sh get realms/drifpen >/dev/null 2>&1; then
    kcadm.sh create realms \
      -s realm=drifpen \
      -s enabled=true \
      -s registrationAllowed=false \
      -s loginWithEmailAllowed=true \
      -s duplicateEmailsAllowed=false \
      -s bruteForceProtected=true
  fi

  local client_uuid
  client_uuid=$(kcadm.sh get clients -r drifpen -q clientId=drifpen-web-bff --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
  if [[ -z "${client_uuid}" || "${client_uuid}" == "id" ]]; then
    kcadm.sh create clients -r drifpen \
      -s clientId=drifpen-web-bff \
      -s enabled=true \
      -s publicClient=false \
      -s secret="${KEYCLOAK_CLIENT_SECRET:-change-me}" \
      -s directAccessGrantsEnabled=true \
      -s standardFlowEnabled=false \
      -s serviceAccountsEnabled=false \
      -s 'redirectUris=["https://drifpen.com/*","http://localhost:3000/*"]' \
      -s 'webOrigins=["https://drifpen.com","http://localhost:3000"]'
  fi

  local fed_id
  fed_id=$(kcadm.sh get components -r drifpen -q name=drifpen-mysql-users --fields id --format csv --noquotes 2>/dev/null | head -1 || true)
  if [[ -z "${fed_id}" || "${fed_id}" == "id" ]]; then
    kcadm.sh create components -r drifpen \
      -s name=drifpen-mysql-users \
      -s providerId=drifpen-mysql-users \
      -s providerType=org.keycloak.storage.UserStorageProvider \
      -s 'config.jdbcUrl=["'"${SPI_JDBC_URL:-$KC_DB_URL}"'"]' \
      -s 'config.dbUser=["'"${SPI_DB_USERNAME:-$KC_DB_USERNAME}"'"]' \
      -s 'config.dbPassword=["'"${SPI_DB_PASSWORD:-$KC_DB_PASSWORD}"'"]' \
      -s 'config.poolSize=["5"]' \
      -s 'config.importEnabled=["false"]' \
      -s 'config.priority=["0"]'
  fi
}

bootstrap || true
wait "${KC_PID}"
