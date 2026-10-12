#!/bin/bash
set -euo pipefail

OPTIONS="${MESHRIK_HA_OPTIONS:-/data/options.json}"
APP_DIR="${MESHRIK_HA_APP_DIR:-/app}"
API_BASE="${MESHRIK_HA_API_BASE:-http://localhost:8000}"
SUPERVISOR_MQTT_URL="${MESHRIK_HA_MQTT_URL:-http://supervisor/services/mqtt}"
CURL_BIN="${MESHRIK_HA_CURL_BIN:-curl}"
PYTHON_BIN="${MESHRIK_HA_PYTHON_BIN:-${APP_DIR}/.venv/bin/python}"
READINESS_TIMEOUT_OVERRIDE="${MESHRIK_HA_READINESS_TIMEOUT:-}"
READINESS_INTERVAL="${MESHRIK_HA_READINESS_INTERVAL:-1}"
READINESS_DIAGNOSTIC_INTERVAL="${MESHRIK_HA_READINESS_DIAGNOSTIC_INTERVAL:-10}"
MONOTONIC_CLOCK_FILE="${MESHRIK_HA_MONOTONIC_CLOCK_FILE:-/proc/uptime}"
MQTT_RETRY_ATTEMPTS="${MESHRIK_HA_MQTT_RETRY_ATTEMPTS:-12}"
MQTT_RETRY_INTERVAL="${MESHRIK_HA_MQTT_RETRY_INTERVAL:-10}"

AUTH_HEADER_FILE=""
SUPERVISOR_HEADER_FILE=""
APP_PID=""
MQTT_HELPER_PID=""
RETRY_SLEEP_PID=""
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
	printf '%s\n' "$header" >"$file"
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

if [ -n "$READINESS_TIMEOUT_OVERRIDE" ]; then
	# Internal override used by wrapper tests and image diagnostics.
	READINESS_TIMEOUT=$READINESS_TIMEOUT_OVERRIDE
else
	READINESS_TIMEOUT=$(jq -r '.http_startup_timeout_seconds // 120' "$OPTIONS")
	if ! [[ "$READINESS_TIMEOUT" =~ ^[0-9]+$ ]] ||
		((READINESS_TIMEOUT < 30 || READINESS_TIMEOUT > 600)); then
		echo "http_startup_timeout_seconds must be an integer in 30..600." >&2
		exit 1
	fi
fi

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
passive | sync | full) export MESHCORE_STARTUP_POLICY="$startup_policy" ;;
*)
	echo "Invalid startup_policy (expected passive, sync or full)." >&2
	exit 1
	;;
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
	((MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS < 1 || MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS > 60)); then
	echo "login_response_timeout_seconds must be an integer in 1..60." >&2
	exit 1
fi
export MESHCORE_DATABASE_PATH="/data/meshcore.db"

AUTH_USER=$(get_str basic_auth_username)
AUTH_PASS=$(get_str basic_auth_password)
if { [ -n "$AUTH_USER" ] && [ -z "$AUTH_PASS" ]; } ||
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

if ! [[ "$MQTT_RETRY_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] ||
	! [[ "$MQTT_RETRY_INTERVAL" =~ ^[0-9]+$ ]]; then
	echo "MQTT retry attempts must be positive and interval must be non-negative." >&2
	exit 1
fi

if ! [[ "$READINESS_TIMEOUT" =~ ^[1-9][0-9]*$ ]] ||
	! [[ "$READINESS_INTERVAL" =~ ^[0-9]+$ ]] ||
	! [[ "$READINESS_DIAGNOSTIC_INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
	echo "Readiness timeout and diagnostic interval must be positive; probe interval must be non-negative." >&2
	exit 1
fi

mqtt_service_discovery() {
	local response
	if ! response=$("$CURL_BIN" "${CURL_COMMON[@]}" \
		--header "@${SUPERVISOR_HEADER_FILE}" "$SUPERVISOR_MQTT_URL" 2>/dev/null); then
		echo "Supervisor MQTT service is unavailable (optional)." >&2
		return 1
	fi
	if ! jq -e '
        .result == "ok" and
        (.data | type == "object") and
        (.data.host | type == "string" and length > 0) and
        (.data.port | type == "number" and floor == . and . >= 1 and . <= 65535) and
        (.data.username == null or (.data.username | type == "string")) and
        (.data.password == null or (.data.password | type == "string")) and
        ((.data.ssl // .data.tls // false) | type == "boolean")
    ' <<<"$response" >/dev/null 2>&1; then
		echo "Supervisor returned invalid MQTT service data." >&2
		return 1
	fi
	MQTT_HOST=$(jq -r '.data.host' <<<"$response")
	MQTT_PORT=$(jq -r '.data.port' <<<"$response")
	MQTT_USER=$(jq -r '.data.username // ""' <<<"$response")
	MQTT_PASS=$(jq -r '.data.password // ""' <<<"$response")
	MQTT_TLS=$(jq -r '.data.ssl // .data.tls // false' <<<"$response")
}

read_mqtt_fanout_count() {
	local response=$1
	MQTT_COUNT=$(jq -er '
        if type == "array" then
            [.[] | select(.type == "mqtt_ha")] | length
        else
            error("fanout response is not an array")
        end
    ' <<<"$response" 2>/dev/null) || {
		echo "MESHRIK returned invalid fanout JSON." >&2
		return 1
	}
}

reconcile_mqtt_fanout() {
	local fanout_response mqtt_payload
	mqtt_service_discovery || return 1

	if ! fanout_response=$(api_request "${API_BASE}/api/fanout" 2>/dev/null); then
		echo "Could not read MESHRIK fanout settings." >&2
		return 1
	fi
	read_mqtt_fanout_count "$fanout_response" || return 1
	if [ "$MQTT_COUNT" -gt 0 ]; then
		echo "mqtt_ha fanout already exists; preserving its current settings."
		return 0
	fi

	mqtt_payload=$(jq -n \
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
	if printf '%s' "$mqtt_payload" | api_request \
		--request POST \
		--header "Content-Type: application/json" \
		--data-binary @- \
		"${API_BASE}/api/fanout" >/dev/null 2>&1; then
		echo "mqtt_ha fanout configured; MESHRIK will publish entities to Home Assistant."
		return 0
	fi

	# A concurrent setup may have won between our GET and POST. Confirm before
	# retrying so a successful race never creates a duplicate integration.
	if fanout_response=$(api_request "${API_BASE}/api/fanout" 2>/dev/null) &&
		read_mqtt_fanout_count "$fanout_response" &&
		[ "$MQTT_COUNT" -gt 0 ]; then
		echo "mqtt_ha fanout appeared during setup; preserving its current settings."
		return 0
	fi
	echo "Could not create mqtt_ha fanout." >&2
	return 1
}

# Invoked by the MQTT helper's TERM/INT traps.
# shellcheck disable=SC2329
mqtt_helper_interrupted() {
	[ -z "$RETRY_SLEEP_PID" ] || kill -TERM "$RETRY_SLEEP_PID" 2>/dev/null || true
	[ -z "${MESHRIK_HA_MQTT_HELPER_STOP_FILE:-}" ] ||
		: >"$MESHRIK_HA_MQTT_HELPER_STOP_FILE"
	exit 0
}

mqtt_reconciliation_loop() {
	local attempt
	trap mqtt_helper_interrupted TERM INT
	for ((attempt = 1; attempt <= MQTT_RETRY_ATTEMPTS; attempt++)); do
		reconcile_mqtt_fanout && return 0
		if [ "$attempt" -lt "$MQTT_RETRY_ATTEMPTS" ]; then
			echo "MQTT auto-setup attempt ${attempt}/${MQTT_RETRY_ATTEMPTS} failed; retrying in ${MQTT_RETRY_INTERVAL}s." >&2
			sleep "$MQTT_RETRY_INTERVAL" &
			RETRY_SLEEP_PID=$!
			wait "$RETRY_SLEEP_PID" || return 0
			RETRY_SLEEP_PID=""
		fi
	done
	echo "Automatic MQTT setup stopped after ${MQTT_RETRY_ATTEMPTS} attempts; configure it in the MESHRIK UI." >&2
}

stop_mqtt_helper() {
	if [ -n "$MQTT_HELPER_PID" ]; then
		kill -TERM "$MQTT_HELPER_PID" 2>/dev/null || true
		wait "$MQTT_HELPER_PID" 2>/dev/null || true
		MQTT_HELPER_PID=""
	fi
}

wait_for_child() {
	if wait "$APP_PID"; then
		CHILD_STATUS=0
	else
		CHILD_STATUS=$?
	fi
}

# Linux exposes boot-relative uptime from a monotonic clock. Return whole
# seconds without spawning another process for every readiness probe.
read_monotonic_seconds() {
	local uptime _
	IFS=' ' read -r uptime _ <"$MONOTONIC_CLOCK_FILE"
	MONOTONIC_SECONDS=${uptime%%.*}
}

# Invoked by TERM/INT traps.
# shellcheck disable=SC2317,SC2329
forward_signal() {
	local exit_code=$1
	trap - TERM INT
	stop_mqtt_helper
	if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
		kill -TERM "$APP_PID" 2>/dev/null || true
	fi
	[ -z "$APP_PID" ] || wait "$APP_PID" 2>/dev/null || true
	exit "$exit_code"
}

cd "$APP_DIR"
# The Supervisor credential belongs to this launcher. MESHRIK executes
# operator-authored bots in its application process, so never let either the
# current or legacy token variable cross that privilege boundary.
# The image build owns dependency resolution. Starting its preinstalled Python
# directly prevents uv from mutating the environment or downloading dev tools.
env -u SUPERVISOR_TOKEN -u HASSIO_TOKEN \
	"$PYTHON_BIN" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 &
APP_PID=$!
trap 'forward_signal 143' TERM
trap 'forward_signal 130' INT

echo "Waiting up to ${READINESS_TIMEOUT}s for the MESHRIK HTTP API to start..."
READY=false
read_monotonic_seconds
readiness_started=$MONOTONIC_SECONDS
readiness_deadline=$((readiness_started + READINESS_TIMEOUT))
last_diagnostic=$((readiness_started - READINESS_DIAGNOSTIC_INTERVAL))
while :; do
	read_monotonic_seconds
	((MONOTONIC_SECONDS < readiness_deadline)) || break
	if ! kill -0 "$APP_PID" 2>/dev/null; then
		wait_for_child
		echo "MESHRIK exited before becoming ready (status ${CHILD_STATUS})." >&2
		[ "$CHILD_STATUS" -ne 0 ] || CHILD_STATUS=1
		exit "$CHILD_STATUS"
	fi

	probe_status=0
	api_request --retry 0 --max-time 2 --output /dev/null \
		"${API_BASE}/api/health" 2>/dev/null || probe_status=$?
	if [ "$probe_status" -eq 0 ]; then
		READY=true
		echo "MESHRIK HTTP API is responding; radio startup may still be initializing."
		break
	fi

	read_monotonic_seconds
	if ((MONOTONIC_SECONDS - last_diagnostic >= READINESS_DIAGNOSTIC_INTERVAL)); then
		elapsed=$((MONOTONIC_SECONDS - readiness_started))
		case "$probe_status" in
		7 | 28)
			echo "MESHRIK HTTP endpoint is not bound yet after ${elapsed}s; application startup may still be importing." >&2
			;;
		*)
			echo "MESHRIK HTTP health probe is not healthy after ${elapsed}s (curl status ${probe_status})." >&2
			;;
		esac
		last_diagnostic=$MONOTONIC_SECONDS
	fi

	((MONOTONIC_SECONDS < readiness_deadline)) || break
	sleep "$READINESS_INTERVAL"
done

if [ "$READY" != true ]; then
	echo "MESHRIK HTTP API did not become ready within ${READINESS_TIMEOUT}s; stopping the application." >&2
	kill -TERM "$APP_PID" 2>/dev/null || true
	wait "$APP_PID" 2>/dev/null || true
	exit 1
fi

if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
	SUPERVISOR_HEADER_FILE=$(make_private_header_file \
		"Authorization: Bearer ${SUPERVISOR_TOKEN}")
	mqtt_reconciliation_loop &
	MQTT_HELPER_PID=$!
else
	echo "Supervisor token is absent; skipping automatic MQTT setup."
fi

wait_for_child
stop_mqtt_helper
exit "$CHILD_STATUS"
