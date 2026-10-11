#!/bin/bash
set -euo pipefail

OPTIONS="${MESHRIK_HA_OPTIONS:-/data/options.json}"
APP_DIR="${MESHRIK_HA_APP_DIR:-/app}"
API_BASE="${MESHRIK_HA_API_BASE:-http://localhost:8000}"
SUPERVISOR_MQTT_URL="${MESHRIK_HA_MQTT_URL:-http://supervisor/services/mqtt}"
CURL_BIN="${MESHRIK_HA_CURL_BIN:-curl}"
UV_BIN="${MESHRIK_HA_UV_BIN:-uv}"
READINESS_ATTEMPTS="${MESHRIK_HA_READINESS_ATTEMPTS:-30}"
READINESS_INTERVAL="${MESHRIK_HA_READINESS_INTERVAL:-1}"

AUTH_HEADER_FILE=""
SUPERVISOR_HEADER_FILE=""
APP_PID=""
CHILD_STATUS=0

# Invoked by the EXIT trap.
# shellcheck disable=SC2317,SC2329
cleanup() {
    [ -z "$AUTH_HEADER_FILE" ] || rm -f -- "$AUTH_HEADER_FILE"
    [ -z "$SUPERVISOR_HEADER_FILE" ] || rm -f -- "$SUPERVISOR_HEADER_FILE"
}
trap cleanup EXIT

make_private_header_file() {
    local header=$1
    local file
    file=$(mktemp /tmp/meshrik-header.XXXXXX)
    chmod 600 "$file"
    printf '%s\n' "$header" > "$file"
    printf '%s\n' "$file"
}

get_str() {
    jq -er --arg key "$1" '.[$key] // empty | select(type == "string")' "$OPTIONS" \
        2>/dev/null || true
}

get_val() {
    jq -r --arg key "$1" \
        'if .[$key] != null then .[$key] else error("missing option: \($key)") end' \
        "$OPTIONS"
}

jq -e 'type == "object"' "$OPTIONS" >/dev/null || {
    echo "Invalid Home Assistant options JSON." >&2
    exit 1
}

# Export only non-empty connection values so MESHRIK can auto-detect serial
# devices when no explicit connection is configured.
SERIAL_PORT=$(get_str serial_port)
SERIAL_BAUDRATE=$(get_val serial_baudrate)
TCP_HOST=$(get_str tcp_host)
TCP_PORT=$(get_val tcp_port)
BLE_ADDRESS=$(get_str ble_address)
BLE_PIN=$(get_str ble_pin)

[ -z "$SERIAL_PORT" ] || export MESHCORE_SERIAL_PORT="$SERIAL_PORT"
[ -z "$SERIAL_BAUDRATE" ] || export MESHCORE_SERIAL_BAUDRATE="$SERIAL_BAUDRATE"
[ -z "$TCP_HOST" ] || export MESHCORE_TCP_HOST="$TCP_HOST"
[ -z "$TCP_PORT" ] || export MESHCORE_TCP_PORT="$TCP_PORT"
[ -z "$BLE_ADDRESS" ] || export MESHCORE_BLE_ADDRESS="$BLE_ADDRESS"
[ -z "$BLE_PIN" ] || export MESHCORE_BLE_PIN="$BLE_PIN"

MESHCORE_LOG_LEVEL=$(get_val log_level)
MESHCORE_DISABLE_BOTS=$(get_val disable_bots)
MESHCORE_ENABLE_MESSAGE_POLL_FALLBACK=$(get_val enable_message_poll_fallback)
MESHCORE_FORCE_CHANNEL_SLOT_RECONFIGURE=$(get_val force_channel_slot_reconfigure)
MESHCORE_SKIP_POST_CONNECT_SYNC=$(get_val skip_post_connect_sync)
export MESHCORE_LOG_LEVEL MESHCORE_DISABLE_BOTS
export MESHCORE_ENABLE_MESSAGE_POLL_FALLBACK MESHCORE_FORCE_CHANNEL_SLOT_RECONFIGURE
export MESHCORE_SKIP_POST_CONNECT_SYNC

# Settings introduced by MESHRIK #48/#49: handle legacy options.json that
# does not yet contain them without granting any new maintenance permissions.
# The MESHCORE_SKIP_POST_CONNECT_SYNC legacy flag intentionally overrides
# startup_policy=full to passive, as enforced by the MESHRIK settings model.
startup_policy=$(jq -r '.startup_policy // "sync"' "$OPTIONS")
case "$startup_policy" in
    passive|sync|full) export MESHCORE_STARTUP_POLICY="$startup_policy" ;;
    *) echo "Invalid startup_policy (expected passive, sync or full)." >&2; exit 1 ;;
esac

# All potentially modifying startup operations remain individually opt-in.
# Never use eval or export arbitrary user-supplied environment variable names.
MESHCORE_PASSIVE_STARTUP=$(jq -r 'if .passive_startup == null then false else .passive_startup end' "$OPTIONS")
export MESHCORE_PASSIVE_STARTUP
MESHCORE_STARTUP_EXPORT_PRIVATE_KEY=$(jq -r 'if .startup_export_private_key == null then false else .startup_export_private_key end' "$OPTIONS")
export MESHCORE_STARTUP_EXPORT_PRIVATE_KEY
MESHCORE_STARTUP_SYNC_CLOCK=$(jq -r 'if .startup_sync_clock == null then false else .startup_sync_clock end' "$OPTIONS")
export MESHCORE_STARTUP_SYNC_CLOCK
MESHCORE_STARTUP_APPLY_FLOOD_SCOPE=$(jq -r 'if .startup_apply_flood_scope == null then false else .startup_apply_flood_scope end' "$OPTIONS")
export MESHCORE_STARTUP_APPLY_FLOOD_SCOPE
MESHCORE_STARTUP_SEND_ADVERTISEMENT=$(jq -r 'if .startup_send_advertisement == null then false else .startup_send_advertisement end' "$OPTIONS")
export MESHCORE_STARTUP_SEND_ADVERTISEMENT
MESHCORE_STARTUP_DRAIN_MESSAGES=$(jq -r 'if .startup_drain_messages == null then false else .startup_drain_messages end' "$OPTIONS")
export MESHCORE_STARTUP_DRAIN_MESSAGES
MESHCORE_STARTUP_RECONCILE_CONTACTS=$(jq -r 'if .startup_reconcile_contacts == null then false else .startup_reconcile_contacts end' "$OPTIONS")
export MESHCORE_STARTUP_RECONCILE_CONTACTS
MESHCORE_STARTUP_CLEAR_CHANNEL_SLOTS=$(jq -r 'if .startup_clear_channel_slots == null then false else .startup_clear_channel_slots end' "$OPTIONS")
export MESHCORE_STARTUP_CLEAR_CHANNEL_SLOTS
MESHCORE_STARTUP_ALLOW_PERIODIC_OFFLOAD=$(jq -r 'if .startup_allow_periodic_offload == null then false else .startup_allow_periodic_offload end' "$OPTIONS")
export MESHCORE_STARTUP_ALLOW_PERIODIC_OFFLOAD
MESHCORE_STARTUP_ENABLE_TELEMETRY_COLLECTION=$(jq -r 'if .startup_enable_telemetry_collection == null then false else .startup_enable_telemetry_collection end' "$OPTIONS")
export MESHCORE_STARTUP_ENABLE_TELEMETRY_COLLECTION
MESHCORE_AUTO_REBOOT_ON_CLOCK_SKEW=$(jq -r 'if .auto_reboot_on_clock_skew == null then false else .auto_reboot_on_clock_skew end' "$OPTIONS")
export MESHCORE_AUTO_REBOOT_ON_CLOCK_SKEW
MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS=$(jq -r 'if .login_response_timeout_seconds == null then 5 else .login_response_timeout_seconds end' "$OPTIONS")
export MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS

# Validate the bounded login wait before exporting to Pydantic settings.
if ! [[ "$MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] ||
   (( MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS < 1 || MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS > 60 )); then
    echo "login_response_timeout_seconds must be an integer in 1..60." >&2
    exit 1
fi
export MESHCORE_DATABASE_PATH="/data/meshcore.db"

AUTH_USER=$(get_str basic_auth_username)
AUTH_PASS=$(get_str basic_auth_password)
if { [ -n "$AUTH_USER" ] && [ -z "$AUTH_PASS" ]; } || \
   { [ -z "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; }; then
    echo "Basic Auth username and password must either both be set or both be empty." >&2
    exit 1
fi

if [ -n "$AUTH_USER" ]; then
    export MESHCORE_BASIC_AUTH_USERNAME="$AUTH_USER"
    export MESHCORE_BASIC_AUTH_PASSWORD="$AUTH_PASS"
    auth_value=$(printf '%s:%s' "$AUTH_USER" "$AUTH_PASS" | base64 | tr -d '\n')
    AUTH_HEADER_FILE=$(make_private_header_file "Authorization: Basic ${auth_value}")
    unset auth_value
fi

CURL_COMMON=(
    --silent
    --show-error
    --fail
    --connect-timeout 2
    --max-time 5
    --retry 2
    --retry-delay 1
    --retry-connrefused
)

api_request() {
    local auth_args=()
    [ -z "$AUTH_HEADER_FILE" ] || auth_args=(--header "@${AUTH_HEADER_FILE}")
    "$CURL_BIN" "${CURL_COMMON[@]}" "${auth_args[@]}" "$@"
}

MQTT_HOST=""
MQTT_PORT="1883"
MQTT_USER=""
MQTT_PASS=""
MQTT_TLS="false"

if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    SUPERVISOR_HEADER_FILE=$(make_private_header_file \
        "Authorization: Bearer ${SUPERVISOR_TOKEN}")
    if MQTT_RESPONSE=$("$CURL_BIN" "${CURL_COMMON[@]}" \
        --header "@${SUPERVISOR_HEADER_FILE}" "$SUPERVISOR_MQTT_URL"); then
        if jq -e '
            .result == "ok" and
            (.data | type == "object") and
            (.data.host | type == "string" and length > 0) and
            (.data.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
            (.data.username == null or (.data.username | type == "string")) and
            (.data.password == null or (.data.password | type == "string")) and
            ((.data.ssl // .data.tls // false) | type == "boolean")
        ' <<<"$MQTT_RESPONSE" >/dev/null; then
            MQTT_HOST=$(jq -r '.data.host' <<<"$MQTT_RESPONSE")
            MQTT_PORT=$(jq -r '.data.port' <<<"$MQTT_RESPONSE")
            MQTT_USER=$(jq -r '.data.username // ""' <<<"$MQTT_RESPONSE")
            MQTT_PASS=$(jq -r '.data.password // ""' <<<"$MQTT_RESPONSE")
            MQTT_TLS=$(jq -r '.data.ssl // .data.tls // false' <<<"$MQTT_RESPONSE")
        else
            echo "Supervisor returned invalid MQTT service data; skipping automatic MQTT setup." >&2
        fi
    else
        echo "MQTT service is unavailable from Supervisor; skipping automatic MQTT setup." >&2
    fi
else
    echo "Supervisor token is absent; skipping automatic MQTT setup."
fi

wait_for_child() {
    if wait "$APP_PID"; then
        CHILD_STATUS=0
    else
        CHILD_STATUS=$?
    fi
}

# Invoked by TERM/INT traps.
# shellcheck disable=SC2317,SC2329
forward_signal() {
    local exit_code=$1
    trap - TERM INT
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        kill -TERM "$APP_PID" 2>/dev/null || true
    fi
    [ -z "$APP_PID" ] || wait "$APP_PID" 2>/dev/null || true
    exit "$exit_code"
}

cd "$APP_DIR"
"$UV_BIN" run uvicorn app.main:app --host 0.0.0.0 --port 8000 &
APP_PID=$!
trap 'forward_signal 143' TERM
trap 'forward_signal 130' INT

echo "Waiting for MESHRIK to start..."
READY=false
for ((attempt = 1; attempt <= READINESS_ATTEMPTS; attempt++)); do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
        wait_for_child
        echo "MESHRIK exited before becoming ready (status ${CHILD_STATUS})." >&2
        [ "$CHILD_STATUS" -ne 0 ] || CHILD_STATUS=1
        exit "$CHILD_STATUS"
    fi

    if api_request --retry 0 --max-time 2 --output /dev/null \
        "${API_BASE}/api/health" 2>/dev/null; then
        READY=true
        echo "MESHRIK HTTP API is responding; radio startup may still be initializing."
        break
    fi

    [ "$attempt" -eq "$READINESS_ATTEMPTS" ] || sleep "$READINESS_INTERVAL"
done

if [ "$READY" != true ]; then
    echo "MESHRIK did not become ready after ${READINESS_ATTEMPTS} attempts." >&2
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    exit 1
fi

if [ -n "$MQTT_HOST" ]; then
    if FANOUT_RESPONSE=$(api_request "${API_BASE}/api/fanout" 2>/dev/null); then
        if MQTT_COUNT=$(jq -er '
            if type == "array" then
                [.[] | select(.type == "mqtt_ha")] | length
            else
                error("fanout response is not an array")
            end
        ' <<<"$FANOUT_RESPONSE" 2>/dev/null); then
            if [ "$MQTT_COUNT" -eq 0 ]; then
                MQTT_PAYLOAD=$(jq -n \
                    --arg broker_host "$MQTT_HOST" \
                    --argjson broker_port "$MQTT_PORT" \
                    --arg username "$MQTT_USER" \
                    --arg password "$MQTT_PASS" \
                    --argjson use_tls "$MQTT_TLS" \
                    '{type: "mqtt_ha", name: "Home Assistant",
                      config: {broker_host: $broker_host, broker_port: $broker_port,
                        username: $username, password: $password, use_tls: $use_tls},
                      scope: {messages: "all", raw_packets: "none"}, enabled: true}')

                echo "Configuring mqtt_ha fanout against ${MQTT_HOST}:${MQTT_PORT} (TLS: ${MQTT_TLS})..."
                if printf '%s' "$MQTT_PAYLOAD" | api_request \
                    --request POST \
                    --header "Content-Type: application/json" \
                    --data-binary @- \
                    "${API_BASE}/api/fanout" >/dev/null 2>&1; then
                    echo "mqtt_ha fanout configured; MESHRIK will publish entities to Home Assistant."
                else
                    echo "Could not create mqtt_ha fanout; configure it in the MESHRIK UI." >&2
                fi
            else
                echo "mqtt_ha fanout already exists; preserving its current settings."
            fi
        else
            echo "MESHRIK returned invalid fanout JSON; automatic MQTT setup was skipped." >&2
        fi
    else
        echo "Could not read MESHRIK fanout settings; automatic MQTT setup was skipped." >&2
    fi
else
    echo "Mosquitto was not found via Supervisor; configure MQTT in the MESHRIK UI if needed."
fi

wait_for_child
exit "$CHILD_STATUS"
