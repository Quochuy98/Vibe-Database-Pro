#!/bin/zsh
set -euo pipefail

readonly EX_USAGE=64
readonly EX_SOFTWARE=70
readonly EX_CONFIG=78
readonly FIXTURE_USER='dataforge_test'

if [[ "${DATAFORGE_TEST_ALLOW_DESTRUCTIVE:-}" != '1' ]]; then
    print -u2 -- 'Refusing disposable SSH tests: DATAFORGE_TEST_ALLOW_DESTRUCTIVE must be exactly 1.'
    exit "$EX_USAGE"
fi

if [[ "${DATAFORGE_TEST_ENVIRONMENT:-}" != 'test' ]]; then
    print -u2 -- 'Refusing disposable SSH tests: DATAFORGE_TEST_ENVIRONMENT must be exactly test.'
    exit "$EX_USAGE"
fi

for required_command in awk cargo docker grep nc openssl sed ssh-add ssh-agent ssh-keygen; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        print -u2 -- "Missing required DF-M0-005 tool: ${required_command}."
        exit "$EX_CONFIG"
    fi
done

if [[ ! -x /usr/bin/leaks ]]; then
    print -u2 -- 'Missing required DF-M0-005 leak-smoke tool: /usr/bin/leaks.'
    exit "$EX_CONFIG"
fi

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly SPIKE_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly FIXTURE_DIRECTORY="${SPIKE_DIRECTORY}/fixtures/openssh"
readonly ARTIFACT_DIRECTORY="${SPIKE_DIRECTORY}/artifacts/df-m0-005"
readonly RUSSH_PROBE="${SPIKE_DIRECTORY}/target/release/dataforge-russh-probe"
readonly OPENSSH_PROBE="${SPIKE_DIRECTORY}/target/release/dataforge-openssh-probe"

if [[ ! -x "$RUSSH_PROBE" || ! -x "$OPENSSH_PROBE" ]]; then
    print -u2 -- 'Release probes are unavailable; run cargo build --release --workspace first.'
    exit "$EX_CONFIG"
fi

typeset -g RUN_MARKER=''
typeset -g NETWORK_NAME=''
typeset -g BASTION_CONTAINER=''
typeset -g TARGET_CONTAINER=''
typeset -g IMAGE_TAG=''
typeset -g TEMPORARY_ROOT=''
typeset -g SECRET_PATTERN_FILE=''
typeset -g TEST_PASSWORD=''
typeset -g AGENT_PID=''
typeset -gi NETWORK_MAY_EXIST=0
typeset -gi BASTION_MAY_EXIST=0
typeset -gi TARGET_MAY_EXIST=0
typeset -gi IMAGE_MAY_EXIST=0
typeset -gi CONTAINER_LOGS_CAPTURED=0
typeset -gi OUTPUTS_SCANNED=0

container_is_owned_by_run() {
    typeset container_name="$1"
    [[ -n "$container_name" && -n "$RUN_MARKER" ]] || return 1
    [[ "$(docker inspect --format '{{index .Config.Labels "com.dataforge.test-run"}}' \
        "$container_name" 2>/dev/null || true)" == "$RUN_MARKER" ]]
}

network_is_owned_by_run() {
    [[ -n "$NETWORK_NAME" && -n "$RUN_MARKER" ]] || return 1
    [[ "$(docker network inspect --format '{{index .Labels "com.dataforge.test-run"}}' \
        "$NETWORK_NAME" 2>/dev/null || true)" == "$RUN_MARKER" ]]
}

capture_container_logs() {
    if (( CONTAINER_LOGS_CAPTURED == 1 )) || [[ -z "$TEMPORARY_ROOT" ]]; then
        return 0
    fi
    typeset log_directory="${TEMPORARY_ROOT}/logs"
    mkdir -m 0700 -p "$log_directory"
    if container_is_owned_by_run "$BASTION_CONTAINER"; then
        docker logs "$BASTION_CONTAINER" >"${log_directory}/bastion.log" 2>&1 || true
    fi
    if container_is_owned_by_run "$TARGET_CONTAINER"; then
        docker logs "$TARGET_CONTAINER" >"${log_directory}/target.log" 2>&1 || true
    fi
    CONTAINER_LOGS_CAPTURED=1
}

scan_outputs() {
    if (( OUTPUTS_SCANNED == 1 )); then
        return 0
    fi
    if [[ -z "$SECRET_PATTERN_FILE" || ! -f "$SECRET_PATTERN_FILE" ]]; then
        return 1
    fi

    typeset scan_root="${TEMPORARY_ROOT}/logs"
    typeset grep_status=0
    if LC_ALL=C grep -R -F -f "$SECRET_PATTERN_FILE" -- "$ARTIFACT_DIRECTORY" "$scan_root" \
        >/dev/null 2>&1; then
        print -u2 -- 'Secret-canary scan failed; captured output is suppressed.'
        return 1
    else
        grep_status=$?
    fi
    if (( grep_status != 1 )); then
        print -u2 -- 'Secret-canary scan could not inspect every output.'
        return 1
    fi

    if LC_ALL=C grep -R -E -e \
        '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|password[[:space:]]*=|SSH_AUTH_SOCK=' \
        -- "$ARTIFACT_DIRECTORY" "$scan_root" >/dev/null 2>&1; then
        print -u2 -- 'Sensitive-pattern scan failed; captured output is suppressed.'
        return 1
    else
        grep_status=$?
    fi
    if (( grep_status != 1 )); then
        print -u2 -- 'Sensitive-pattern scan could not inspect every output.'
        return 1
    fi

    if [[ -n "$TEST_PASSWORD" ]] && \
        /bin/ps -axo command | LC_ALL=C grep -F -q -f "$SECRET_PATTERN_FILE"; then
        print -u2 -- 'Secret-canary process-argument scan failed.'
        return 1
    fi
    OUTPUTS_SCANNED=1
}

cleanup() {
    typeset exit_status=$?
    trap - EXIT HUP INT TERM
    set +e

    capture_container_logs
    if ! scan_outputs; then
        exit_status=$EX_SOFTWARE
    fi

    if [[ -n "$AGENT_PID" ]]; then
        kill -TERM "$AGENT_PID" >/dev/null 2>&1 || true
        wait "$AGENT_PID" >/dev/null 2>&1 || true
        AGENT_PID=''
    fi

    if (( BASTION_MAY_EXIST == 1 )); then
        if container_is_owned_by_run "$BASTION_CONTAINER"; then
            docker rm --force --volumes "$BASTION_CONTAINER" >/dev/null 2>&1 || \
                exit_status=$EX_SOFTWARE
        elif docker inspect "$BASTION_CONTAINER" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a bastion container with a mismatched disposable marker.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    if (( TARGET_MAY_EXIST == 1 )); then
        if container_is_owned_by_run "$TARGET_CONTAINER"; then
            docker rm --force --volumes "$TARGET_CONTAINER" >/dev/null 2>&1 || \
                exit_status=$EX_SOFTWARE
        elif docker inspect "$TARGET_CONTAINER" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a target container with a mismatched disposable marker.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    if (( NETWORK_MAY_EXIST == 1 )); then
        if network_is_owned_by_run; then
            docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || exit_status=$EX_SOFTWARE
        elif docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a network with a mismatched disposable marker.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    if (( IMAGE_MAY_EXIST == 1 )) && [[ -n "$IMAGE_TAG" ]]; then
        docker image rm --force "$IMAGE_TAG" >/dev/null 2>&1 || exit_status=$EX_SOFTWARE
    fi

    TEST_PASSWORD=''
    if [[ -n "$TEMPORARY_ROOT" && -d "$TEMPORARY_ROOT" && \
          "$TEMPORARY_ROOT" == */dataforge-ssh.* ]]; then
        chmod -R u+rwX "$TEMPORARY_ROOT" >/dev/null 2>&1 || true
        rm -rf -- "$TEMPORARY_ROOT"
        [[ ! -e "$TEMPORARY_ROOT" ]] || exit_status=$EX_SOFTWARE
    fi

    exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

umask 077
RUN_MARKER="$(openssl rand -hex 8)"
if [[ ${#RUN_MARKER} -ne 16 || "$RUN_MARKER" == *[^a-f0-9]* ]]; then
    print -u2 -- 'OpenSSL returned an invalid disposable run marker.'
    exit "$EX_SOFTWARE"
fi

NETWORK_NAME="dataforge-test-ssh-network-${RUN_MARKER}"
BASTION_CONTAINER="dataforge-test-ssh-bastion-${RUN_MARKER}"
TARGET_CONTAINER="dataforge-test-ssh-target-${RUN_MARKER}"
IMAGE_TAG="dataforge-test-ssh-fixture:${RUN_MARKER}"

typeset temporary_base="${TMPDIR:-/tmp}"
temporary_base="${temporary_base%/}"
TEMPORARY_ROOT="$(mktemp -d "${temporary_base}/dataforge-ssh.XXXXXXXX")"
chmod 0700 "$TEMPORARY_ROOT"
mkdir -m 0700 "${TEMPORARY_ROOT}/bastion" "${TEMPORARY_ROOT}/target" \
    "${TEMPORARY_ROOT}/trust" "${TEMPORARY_ROOT}/logs"
mkdir -m 0700 -p "$ARTIFACT_DIRECTORY"

SECRET_PATTERN_FILE="${TEMPORARY_ROOT}/secret-patterns"
TEST_PASSWORD="DF_TEST_SECRET_${RUN_MARKER}_$(openssl rand -hex 24)"
{
    print -r -- "$TEST_PASSWORD"
    print -r -- 'DF_TEST_SECRET_'
} >"$SECRET_PATTERN_FILE"
chmod 0600 "$SECRET_PATTERN_FILE"

typeset client_key="${TEMPORARY_ROOT}/client_key"
typeset insecure_key="${TEMPORARY_ROOT}/client_key_insecure"
typeset bastion_host_key="${TEMPORARY_ROOT}/bastion/host_key"
typeset target_host_key="${TEMPORARY_ROOT}/target/host_key"

ssh-keygen -q -t ed25519 -N '' -C 'dataforge-test-client' -f "$client_key"
ssh-keygen -q -t ed25519 -N '' -C 'dataforge-test-bastion' -f "$bastion_host_key"
ssh-keygen -q -t ed25519 -N '' -C 'dataforge-test-target' -f "$target_host_key"
cp "$client_key" "$insecure_key"
chmod 0644 "$insecure_key"
cp "${client_key}.pub" "${TEMPORARY_ROOT}/bastion/authorized_keys"
cp "${client_key}.pub" "${TEMPORARY_ROOT}/target/authorized_keys"

docker build --platform linux/arm64 --pull \
    --label "com.dataforge.test-run=${RUN_MARKER}" \
    --tag "$IMAGE_TAG" "$FIXTURE_DIRECTORY" >"${TEMPORARY_ROOT}/logs/docker-build.log" 2>&1
IMAGE_MAY_EXIST=1

docker network create --label "com.dataforge.test-run=${RUN_MARKER}" "$NETWORK_NAME" \
    >/dev/null
NETWORK_MAY_EXIST=1

docker run --detach --name "$TARGET_CONTAINER" --network "$NETWORK_NAME" \
    --network-alias target --label "com.dataforge.test-run=${RUN_MARKER}" \
    --mount "type=bind,source=${TEMPORARY_ROOT}/target,target=/run/dataforge-fixture,readonly" \
    "$IMAGE_TAG" >/dev/null
TARGET_MAY_EXIST=1

docker run --detach --name "$BASTION_CONTAINER" --network "$NETWORK_NAME" \
    --network-alias bastion --label "com.dataforge.test-run=${RUN_MARKER}" \
    --publish '127.0.0.1::2222' \
    --mount "type=bind,source=${TEMPORARY_ROOT}/bastion,target=/run/dataforge-fixture,readonly" \
    "$IMAGE_TAG" >/dev/null
BASTION_MAY_EXIST=1

typeset bastion_port=''
for _ in {1..100}; do
    bastion_port="$(docker port "$BASTION_CONTAINER" 2222/tcp 2>/dev/null | \
        sed -n 's/^127\.0\.0\.1:\([0-9][0-9]*\)$/\1/p')"
    if [[ -n "$bastion_port" ]] && /usr/bin/nc -z 127.0.0.1 "$bastion_port" \
        >/dev/null 2>&1; then
        break
    fi
    sleep 0.05
done
if [[ -z "$bastion_port" || "$bastion_port" == *[^0-9]* ]]; then
    print -u2 -- 'Disposable bastion did not expose a valid loopback port.'
    exit "$EX_SOFTWARE"
fi

print -r -- "${FIXTURE_USER}:${TEST_PASSWORD}" | \
    docker exec --interactive "$BASTION_CONTAINER" chpasswd \
    >"${TEMPORARY_ROOT}/logs/chpasswd.log" 2>&1
print -r -- "${FIXTURE_USER}:${TEST_PASSWORD}" | \
    docker exec --interactive "$TARGET_CONTAINER" chpasswd \
    >>"${TEMPORARY_ROOT}/logs/chpasswd.log" 2>&1

typeset agent_socket="${TEMPORARY_ROOT}/agent.sock"
/usr/bin/ssh-agent -a "$agent_socket" -D >/dev/null 2>&1 &
AGENT_PID=$!
for _ in {1..100}; do
    [[ -S "$agent_socket" ]] && break
    sleep 0.02
done
if [[ ! -S "$agent_socket" ]]; then
    print -u2 -- 'Ephemeral ssh-agent socket was not created.'
    exit "$EX_SOFTWARE"
fi
SSH_AUTH_SOCK="$agent_socket" /usr/bin/ssh-add "$client_key" \
    >"${TEMPORARY_ROOT}/logs/ssh-add.log" 2>&1

typeset bastion_public="$(awk '{ print $1 " " $2 }' "${bastion_host_key}.pub")"
typeset target_public="$(awk '{ print $1 " " $2 }' "${target_host_key}.pub")"
typeset trust_directory="${TEMPORARY_ROOT}/trust"
typeset known_correct="${trust_directory}/known_correct"
typeset known_empty="${trust_directory}/known_empty"
typeset known_hashed="${trust_directory}/known_hashed"
typeset known_revoked="${trust_directory}/known_revoked"
typeset known_bastion_mismatch="${trust_directory}/known_bastion_mismatch"
typeset known_target_mismatch="${trust_directory}/known_target_mismatch"

{
    print -r -- "[127.0.0.1]:${bastion_port} ${bastion_public}"
    print -r -- "[target]:2222 ${target_public}"
} >"$known_correct"
: >"$known_empty"
cp "$known_correct" "$known_hashed"
ssh-keygen -q -H -f "$known_hashed" >/dev/null 2>&1
rm -f -- "${known_hashed}.old"
{
    print -r -- "@revoked [127.0.0.1]:${bastion_port} ${bastion_public}"
    print -r -- "[target]:2222 ${target_public}"
} >"$known_revoked"
{
    print -r -- "[127.0.0.1]:${bastion_port} ${target_public}"
    print -r -- "[target]:2222 ${target_public}"
} >"$known_bastion_mismatch"
{
    print -r -- "[127.0.0.1]:${bastion_port} ${bastion_public}"
    print -r -- "[target]:2222 ${bastion_public}"
} >"$known_target_mismatch"
chmod 0600 "$trust_directory"/*

"$OPENSSH_PROBE" >"${ARTIFACT_DIRECTORY}/openssh-static.json" \
    2>"${TEMPORARY_ROOT}/logs/openssh-probe.stderr"

typeset -a russh_probe_arguments=(
    --bastion-address "127.0.0.1:${bastion_port}"
    --bastion-host '127.0.0.1'
    --target-host 'target'
    --target-port '2222'
    --username "$FIXTURE_USER"
    --key "$client_key"
    --insecure-key "$insecure_key"
    --known-correct "$known_correct"
    --known-empty "$known_empty"
    --known-hashed "$known_hashed"
    --known-revoked "$known_revoked"
    --known-bastion-mismatch "$known_bastion_mismatch"
    --known-target-mismatch "$known_target_mismatch"
    --agent-socket "$agent_socket"
)

"$RUSSH_PROBE" "${russh_probe_arguments[@]}" \
    >"${ARTIFACT_DIRECTORY}/russh-runtime.json" \
    2>"${TEMPORARY_ROOT}/logs/russh-probe.stderr"

chmod 0600 "${ARTIFACT_DIRECTORY}/openssh-static.json" \
    "${ARTIFACT_DIRECTORY}/russh-runtime.json"

typeset leaks_log="${TEMPORARY_ROOT}/logs/russh-leaks.log"
typeset -gi leaks_exit_status=0
set +e
/usr/bin/leaks --noContent --nostacks --atExit -- \
    "$RUSSH_PROBE" "${russh_probe_arguments[@]}" >"$leaks_log" 2>&1
leaks_exit_status=$?
set -e

typeset leaks_summary
leaks_summary="$(LC_ALL=C sed -n \
    's/^Process [0-9][0-9]*: \([0-9][0-9]* leaks for [0-9][0-9]* total leaked bytes\.\)$/\1/p' \
    "$leaks_log" | tail -n 1)"
if [[ -z "$leaks_summary" ]]; then
    leaks_summary='unavailable; inspect the transient leak log for tool diagnostics'
fi
{
    print -r -- "leaks_exit_status=${leaks_exit_status}"
    print -r -- "leaks_summary=${leaks_summary}"
    print -r -- 'scope=one additional full runtime-matrix process; not a long soak or proof of zero production leaks'
} >"${ARTIFACT_DIRECTORY}/leak-smoke.txt"
chmod 0600 "${ARTIFACT_DIRECTORY}/leak-smoke.txt"

capture_container_logs
scan_outputs

print -- 'DF-M0-005 disposable SSH evidence completed; sanitized JSON is under artifacts/df-m0-005.'
