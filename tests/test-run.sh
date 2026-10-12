#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_ROOT=$(mktemp -d /tmp/ha-meshrik-run-tests.XXXXXX)
ACTIVE_PIDS=()

cleanup() {
    local pid
    for pid in "${ACTIVE_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    if [ "${KEEP_TEST_TMP:-false}" = true ]; then
        echo "Kept test files in $TMP_ROOT" >&2
    else
        rm -rf -- "$TMP_ROOT"
    fi
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    [ -f "$1" ] || fail "expected file $1"
}

assert_no_file() {
    [ ! -e "$1" ] || fail "unexpected file $1"
}

wait_for_file() {
    local file=$1
    local pid=$2
    local attempt
    for ((attempt = 1; attempt <= 100; attempt++)); do
        [ -f "$file" ] && return 0
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    if [ -f "$(dirname "$file")/output.log" ]; then
        sed 's/^/  /' "$(dirname "$file")/output.log" >&2
    fi
    fail "timed out waiting for $file"
}

wait_for_log() {
    local pattern=$1
    local file=$2
    local pid=$3
    local attempt
    for ((attempt = 1; attempt <= 100; attempt++)); do
        grep -Fq "$pattern" "$file" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.05
    done
    [ ! -f "$file" ] || sed 's/^/  /' "$file" >&2
    fail "timed out waiting for '$pattern' in $file"
}

write_options() {
    local file=$1
    local auth_user=${2:-}
    local auth_pass=${3:-}
    jq -n \
        --arg auth_user "$auth_user" \
        --arg auth_pass "$auth_pass" \
        '{serial_port: "", serial_baudrate: 115200, tcp_host: "", tcp_port: 5000,
          ble_address: "", ble_pin: "", log_level: "INFO", disable_bots: false,
          basic_auth_username: $auth_user, basic_auth_password: $auth_pass,
          enable_message_poll_fallback: false,
          force_channel_slot_reconfigure: false, skip_post_connect_sync: false}' \
        > "$file"
}

make_fake_tools() {
    local directory=$1
    mkdir -p "$directory"

    apply_uv="$directory/uv"
    apply_curl="$directory/curl"

    # The generated scripts must expand these variables when they run.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        'if [ "${FAKE_UV_MODE:-serve}" = exit ]; then exit "${FAKE_UV_STATUS:-23}"; fi' \
        'trap '\''printf terminated > "${UV_TERM_FILE}"; exit 0'\'' TERM INT' \
        'printf started > "${UV_STARTED_FILE}"' \
        'if [ -n "${CHILD_ENV_FILE:-}" ]; then env | sort > "${CHILD_ENV_FILE}"; fi' \
        'if [ -n "${STARTUP_ENV_FILE:-}" ]; then env | grep -E "^MESHCORE_(STARTUP_|PASSIVE_STARTUP|SKIP_POST_CONNECT_SYNC|LOGIN_RESPONSE_TIMEOUT_SECONDS|AUTO_REBOOT_ON_CLOCK_SKEW)" | sort > "${STARTUP_ENV_FILE}"; fi' \
        'while :; do sleep 1; done' \
        > "$apply_uv"

    # The generated scripts must expand these variables when they run.
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/bin/bash' \
        'set -euo pipefail' \
        'method=GET' \
        'url=' \
        'headers=' \
        'read_stdin=false' \
        'increment_counter() { local file=$1 value=0; [ ! -f "$file" ] || read -r value < "$file"; value=$((value + 1)); printf "%s\n" "$value" > "$file"; printf "%s\n" "$value"; }' \
        'while (($#)); do' \
        '  case "$1" in' \
        '    --request|-X) shift; method=$1 ;;' \
        '    --header|-H) shift; if [[ $1 == @* ]]; then headers+="$(cat "${1#@}")"$'\''\n'\''; else headers+="$1"$'\''\n'\''; fi ;;' \
        '    --data-binary) shift; [ "$1" = @- ] && read_stdin=true ;;' \
        '    http://*|https://*) url=$1 ;;' \
        '  esac' \
        '  shift' \
        'done' \
        'printf "%s %s\n" "$method" "$url" >> "${CURL_LOG}"' \
        'if [[ $url == "${TEST_API_BASE}"/* ]]; then' \
        '  if [ -n "${EXPECTED_API_AUTH:-}" ]; then grep -Fqx "Authorization: Basic ${EXPECTED_API_AUTH}" <<<"$headers"; fi' \
        '  case "$url" in' \
        '    */api/health)' \
        '      touch "${HEALTH_FILE}"' \
        '      [ "${HEALTH_MODE:-ok}" = ok ] || exit 22' \
        '      printf '\''{"status":"ok"}\n'\''' \
        '      ;;' \
        '    */api/fanout)' \
        '      if [ "$method" = POST ]; then' \
        '        count=$(increment_counter "${POST_COUNT_FILE}")' \
        '        $read_stdin && cat > "${POST_FILE}"' \
        '        if [ "${POST_MODE:-normal}" = race ]; then touch "${FANOUT_STATE_FILE}"; exit 22; fi' \
        '        (( count > ${POST_FAILS:-0} )) || exit 22' \
        '        touch "${FANOUT_STATE_FILE}"' \
        '        printf '\''{"id":1}\n'\''' \
        '      else' \
        '        touch "${FANOUT_GET_FILE}"' \
        '        count=$(increment_counter "${FANOUT_GET_COUNT_FILE}")' \
        '        (( count > ${FANOUT_GET_FAILS:-0} )) || exit 22' \
        '        if [ -f "${FANOUT_STATE_FILE}" ]; then printf '\''[{"type":"mqtt_ha","config":{"broker_host":"created"}}]\n'\''; else printf "%s\n" "${FANOUT_RESPONSE:-[]}"; fi' \
        '      fi' \
        '      ;;' \
        '  esac' \
        'elif [ "$url" = "${TEST_MQTT_URL}" ]; then' \
        '  touch "${SUPERVISOR_FILE}"' \
        '  count=$(increment_counter "${SUPERVISOR_COUNT_FILE}")' \
        '  grep -Fqx "Authorization: Bearer ${EXPECTED_SUPERVISOR_TOKEN}" <<<"$headers"' \
        '  [ "${SUPERVISOR_MODE:-ok}" = fail ] && exit 22' \
        '  (( count > ${SUPERVISOR_FAILS:-0} )) || exit 22' \
        '  printf "%s\n" "${MQTT_RESPONSE:-not-json}"' \
        'else' \
        '  exit 22' \
        'fi' \
        > "$apply_curl"

    chmod +x "$apply_uv" "$apply_curl"
}

start_wrapper() {
    local script=$1
    local case_dir=$2
    shift 2
    env \
        PATH="$case_dir/tools:$PATH" \
        MESHRIK_HA_OPTIONS="$case_dir/options.json" \
        MESHRIK_HA_APP_DIR="$case_dir" \
        MESHRIK_HA_API_BASE="http://meshrik.test:8000" \
        MESHRIK_HA_MQTT_URL="http://supervisor.test/services/mqtt" \
        MESHRIK_HA_READINESS_ATTEMPTS=3 \
        MESHRIK_HA_READINESS_INTERVAL=0 \
        MESHRIK_HA_MQTT_RETRY_ATTEMPTS=3 \
        MESHRIK_HA_MQTT_RETRY_INTERVAL=0 \
        MESHRIK_HA_MQTT_HELPER_STOP_FILE="$case_dir/mqtt-helper-stopped" \
        TEST_API_BASE="http://meshrik.test:8000" \
        TEST_MQTT_URL="http://supervisor.test/services/mqtt" \
        CURL_LOG="$case_dir/curl.log" \
        HEALTH_FILE="$case_dir/health" \
        FANOUT_GET_FILE="$case_dir/fanout-get" \
        POST_FILE="$case_dir/post.json" \
        POST_COUNT_FILE="$case_dir/post-count" \
        FANOUT_GET_COUNT_FILE="$case_dir/fanout-get-count" \
        FANOUT_STATE_FILE="$case_dir/fanout-state" \
        SUPERVISOR_FILE="$case_dir/supervisor" \
        SUPERVISOR_COUNT_FILE="$case_dir/supervisor-count" \
        UV_STARTED_FILE="$case_dir/uv-started" \
        CHILD_ENV_FILE="$case_dir/child-env" \
        STARTUP_ENV_FILE="$case_dir/startup-env" \
        UV_TERM_FILE="$case_dir/uv-terminated" \
        "$@" \
        bash "$script" > "$case_dir/output.log" 2>&1 &
    WRAPPER_PID=$!
    ACTIVE_PIDS+=("$WRAPPER_PID")
}

stop_wrapper() {
    local pid=$1
    local expected_status=${2:-143}
    local status
    kill -TERM "$pid"
    if wait "$pid"; then status=0; else status=$?; fi
    [ "$status" -eq "$expected_status" ] || fail "wrapper exit $status, expected $expected_status"
}

run_authenticated_tls_case() {
    local script=$1
    local label=$2
    local case_dir="$TMP_ROOT/$label"
    # Literal shell metacharacters are part of the credentials under test.
    # shellcheck disable=SC2016
    local auth_user='user"\$(); value' auth_pass='pass"\$(touch nope); value'
    # shellcheck disable=SC2016
    local mqtt_user='mqtt"\$(); user' mqtt_pass='mqtt"\$(touch nope); pass'
    local auth_value
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json" "$auth_user" "$auth_pass"
    auth_value=$(printf '%s:%s' "$auth_user" "$auth_pass" | base64 | tr -d '\n')
    mqtt_response=$(jq -cn \
        --arg username "$mqtt_user" --arg password "$mqtt_pass" \
        '{result:"ok", data:{host:"broker.local", port:8883,
          username:$username, password:$password, ssl:true}}')

    start_wrapper "$script" "$case_dir" \
        SUPERVISOR_TOKEN='supervisor-secret' \
        HASSIO_TOKEN='legacy-supervisor-secret' \
        EXPECTED_SUPERVISOR_TOKEN='supervisor-secret' \
        EXPECTED_API_AUTH="$auth_value" \
        MQTT_RESPONSE="$mqtt_response"
    wait_for_file "$case_dir/post.json" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"

    jq -e \
        --arg username "$mqtt_user" --arg password "$mqtt_pass" \
        '.type == "mqtt_ha" and .config.broker_host == "broker.local" and
         .config.broker_port == 8883 and .config.use_tls == true and
         .config.username == $username and .config.password == $password' \
        "$case_dir/post.json" >/dev/null
    assert_file "$case_dir/uv-terminated"
    assert_file "$case_dir/child-env"
    ! grep -Eq '^(SUPERVISOR_TOKEN|HASSIO_TOKEN)=' "$case_dir/child-env" || \
        fail "Supervisor credential reached the application process"
    ! grep -Fq 'supervisor-secret' "$case_dir/output.log" || fail "Supervisor token leaked"
    ! grep -Fq 'legacy-supervisor-secret' "$case_dir/output.log" || fail "legacy Supervisor token leaked"
    ! grep -Fq "$auth_pass" "$case_dir/output.log" || fail "Basic Auth password leaked"
    ! grep -Fq "$mqtt_pass" "$case_dir/output.log" || fail "MQTT password leaked"
}

run_existing_fanout_case() {
    local case_dir="$TMP_ROOT/existing"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik/run.sh" "$case_dir" \
        SUPERVISOR_TOKEN=token EXPECTED_SUPERVISOR_TOKEN=token \
        MQTT_RESPONSE='{"result":"ok","data":{"host":"broker","port":1883,"username":"new","password":"new","ssl":false}}' \
        FANOUT_RESPONSE='[{"type":"mqtt_ha","config":{"broker_host":"custom"}}]'
    wait_for_file "$case_dir/fanout-get" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    assert_no_file "$case_dir/post.json"
    grep -Fq 'preserving its current settings' "$case_dir/output.log"
}

run_invalid_responses_case() {
    local case_dir="$TMP_ROOT/invalid"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik-dev/run.sh" "$case_dir" \
        SUPERVISOR_TOKEN=token EXPECTED_SUPERVISOR_TOKEN=token \
        MQTT_RESPONSE='{"result":"ok","data":{"host":"broker","port":"not-a-number","ssl":"yes"}}'
    wait_for_log 'invalid MQTT service data' "$case_dir/output.log" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    assert_no_file "$case_dir/post.json"
    grep -Fq 'invalid MQTT service data' "$case_dir/output.log"
}

run_missing_token_case() {
    local case_dir="$TMP_ROOT/no-token"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik/run.sh" "$case_dir"
    wait_for_log 'Supervisor token is absent' "$case_dir/output.log" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    assert_no_file "$case_dir/supervisor"
    assert_no_file "$case_dir/post.json"
    grep -Fq 'Supervisor token is absent' "$case_dir/output.log"
}

run_mqtt_recovery_case() {
    local case_dir="$TMP_ROOT/mqtt-recovery"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik/run.sh" "$case_dir" \
        SUPERVISOR_TOKEN=token EXPECTED_SUPERVISOR_TOKEN=token \
        MQTT_RESPONSE='{"result":"ok","data":{"host":"recovered-broker","port":8883,"username":"user","password":"secret","ssl":true}}' \
        SUPERVISOR_FAILS=1 FANOUT_GET_FAILS=1 POST_FAILS=1 \
        MESHRIK_HA_MQTT_RETRY_ATTEMPTS=6
    wait_for_file "$case_dir/fanout-state" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    [ "$(< "$case_dir/supervisor-count")" -ge 4 ] || fail "Supervisor discovery was not retried"
    [ "$(< "$case_dir/fanout-get-count")" -ge 3 ] || fail "fanout GET was not retried"
    [ "$(< "$case_dir/post-count")" -eq 2 ] || fail "fanout POST retry count was unexpected"
    grep -Fq 'mqtt_ha fanout configured' "$case_dir/output.log"
    ! grep -Fq 'secret' "$case_dir/output.log" || fail "recovered MQTT password leaked"
}

run_mqtt_race_case() {
    local case_dir="$TMP_ROOT/mqtt-race"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik-dev/run.sh" "$case_dir" \
        SUPERVISOR_TOKEN=token EXPECTED_SUPERVISOR_TOKEN=token \
        MQTT_RESPONSE='{"result":"ok","data":{"host":"broker","port":1883,"ssl":false}}' \
        POST_MODE=race
    wait_for_log 'appeared during setup' "$case_dir/output.log" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    [ "$(< "$case_dir/post-count")" -eq 1 ] || fail "race created duplicate POST attempts"
}

run_mqtt_cancellation_case() {
    local case_dir="$TMP_ROOT/mqtt-cancellation"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik/run.sh" "$case_dir" \
        SUPERVISOR_TOKEN=token EXPECTED_SUPERVISOR_TOKEN=token \
        SUPERVISOR_MODE=fail MESHRIK_HA_MQTT_RETRY_ATTEMPTS=10 \
        MESHRIK_HA_MQTT_RETRY_INTERVAL=30
    wait_for_log 'retrying in 30s' "$case_dir/output.log" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    assert_file "$case_dir/mqtt-helper-stopped"
    assert_file "$case_dir/uv-terminated"
}

run_child_exit_case() {
    local case_dir="$TMP_ROOT/child-exit"
    local status
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    if env \
        PATH="$case_dir/tools:$PATH" \
        MESHRIK_HA_OPTIONS="$case_dir/options.json" \
        MESHRIK_HA_APP_DIR="$case_dir" \
        MESHRIK_HA_API_BASE="http://meshrik.test:8000" \
        MESHRIK_HA_READINESS_ATTEMPTS=3 \
        MESHRIK_HA_READINESS_INTERVAL=0 \
        TEST_API_BASE="http://meshrik.test:8000" \
        TEST_MQTT_URL="http://supervisor.test/services/mqtt" \
        CURL_LOG="$case_dir/curl.log" HEALTH_FILE="$case_dir/health" \
        FANOUT_GET_FILE="$case_dir/fanout-get" POST_FILE="$case_dir/post.json" \
        SUPERVISOR_FILE="$case_dir/supervisor" UV_STARTED_FILE="$case_dir/uv-started" \
        UV_TERM_FILE="$case_dir/uv-terminated" FAKE_UV_MODE=exit FAKE_UV_STATUS=23 \
        HEALTH_MODE=fail \
        bash "$ROOT/meshrik-dev/run.sh" > "$case_dir/output.log" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 23 ] || fail "child exit status was $status"
    grep -Fq 'exited before becoming ready (status 23)' "$case_dir/output.log"
}

run_readiness_timeout_case() {
    local case_dir="$TMP_ROOT/readiness-timeout"
    local status
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    if env \
        PATH="$case_dir/tools:$PATH" \
        MESHRIK_HA_OPTIONS="$case_dir/options.json" \
        MESHRIK_HA_APP_DIR="$case_dir" \
        MESHRIK_HA_API_BASE="http://meshrik.test:8000" \
        MESHRIK_HA_READINESS_ATTEMPTS=2 \
        MESHRIK_HA_READINESS_INTERVAL=0 \
        TEST_API_BASE="http://meshrik.test:8000" \
        TEST_MQTT_URL="http://supervisor.test/services/mqtt" \
        CURL_LOG="$case_dir/curl.log" HEALTH_FILE="$case_dir/health" \
        FANOUT_GET_FILE="$case_dir/fanout-get" POST_FILE="$case_dir/post.json" \
        SUPERVISOR_FILE="$case_dir/supervisor" UV_STARTED_FILE="$case_dir/uv-started" \
        UV_TERM_FILE="$case_dir/uv-terminated" HEALTH_MODE=fail \
        bash "$ROOT/meshrik/run.sh" > "$case_dir/output.log" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq 1 ] || fail "readiness timeout status was $status"
    assert_file "$case_dir/uv-terminated"
    grep -Fq 'did not become ready after 2 attempts' "$case_dir/output.log"
}

# Validate policy propagation without a radio or real MQTT service.
run_startup_policy_cases() {
    local case_dir="$TMP_ROOT/startup-policy"
    mkdir -p "$case_dir"
    make_fake_tools "$case_dir/tools"
    write_options "$case_dir/options.json"
    # Enable exactly two state-changing permissions to verify independent opt-ins.
    jq '. + {startup_policy:"full", startup_send_advertisement:true,
        startup_sync_clock:true, login_response_timeout_seconds:17}' \
        "$case_dir/options.json" > "$case_dir/opt.new"
    mv "$case_dir/opt.new" "$case_dir/options.json"
    start_wrapper "$ROOT/meshrik/run.sh" "$case_dir" \
        SUPERVISOR_TOKEN='' \
        MQTT_RESPONSE='not-json'
    wait_for_file "$case_dir/startup-env" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    grep -Fxq 'MESHCORE_STARTUP_POLICY=full' "$case_dir/startup-env"
    grep -Fxq 'MESHCORE_STARTUP_SEND_ADVERTISEMENT=true' "$case_dir/startup-env"
    grep -Fxq 'MESHCORE_STARTUP_SYNC_CLOCK=true' "$case_dir/startup-env"
    grep -Fxq 'MESHCORE_STARTUP_CLEAR_CHANNEL_SLOTS=false' "$case_dir/startup-env"
    grep -Fxq 'MESHCORE_STARTUP_ALLOW_PERIODIC_OFFLOAD=false' "$case_dir/startup-env"
    grep -Fxq 'MESHCORE_LOGIN_RESPONSE_TIMEOUT_SECONDS=17' "$case_dir/startup-env"

    local old_dir="$TMP_ROOT/legacy-options"
    mkdir -p "$old_dir"
    make_fake_tools "$old_dir/tools"
    write_options "$old_dir/options.json"
    # The saved options from the previous wrapper have no startup_* fields.
    start_wrapper "$ROOT/meshrik-dev/run.sh" "$old_dir" SUPERVISOR_TOKEN=''
    wait_for_file "$old_dir/startup-env" "$WRAPPER_PID"
    stop_wrapper "$WRAPPER_PID"
    grep -Fxq 'MESHCORE_STARTUP_POLICY=sync' "$old_dir/startup-env"
    grep -Fxq 'MESHCORE_STARTUP_CLEAR_CHANNEL_SLOTS=false' "$old_dir/startup-env"
    grep -Fxq 'MESHCORE_STARTUP_SEND_ADVERTISEMENT=false' "$old_dir/startup-env"

    local invalid_dir="$TMP_ROOT/invalid-policy"
    mkdir -p "$invalid_dir"
    make_fake_tools "$invalid_dir/tools"
    write_options "$invalid_dir/options.json"
    jq '.startup_policy="unsafe"' "$invalid_dir/options.json" > "$invalid_dir/new"
    mv "$invalid_dir/new" "$invalid_dir/options.json"
    local status
    if env MESHRIK_HA_OPTIONS="$invalid_dir/options.json" MESHRIK_HA_APP_DIR="$invalid_dir" \
        bash "$ROOT/meshrik/run.sh" > "$invalid_dir/output.log" 2>&1; then
        status=0
    else
        status=$?
    fi
    [ "$status" -ne 0 ] || fail "invalid startup policy was accepted"
    grep -Fq 'Invalid startup_policy' "$invalid_dir/output.log"
}

cmp -s "$ROOT/meshrik/run.sh" "$ROOT/meshrik-dev/run.sh" || \
    fail "stable and Bleeding Edge startup scripts have drifted"

run_authenticated_tls_case "$ROOT/meshrik/run.sh" stable-auth-tls
run_authenticated_tls_case "$ROOT/meshrik-dev/run.sh" dev-auth-tls
run_existing_fanout_case
run_invalid_responses_case
run_missing_token_case
run_mqtt_recovery_case
run_mqtt_race_case
run_mqtt_cancellation_case
run_child_exit_case
run_readiness_timeout_case
run_startup_policy_cases

echo "All startup wrapper tests passed."
