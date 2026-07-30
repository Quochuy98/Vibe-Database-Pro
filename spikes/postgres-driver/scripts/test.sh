#!/bin/zsh
set -euo pipefail

readonly EX_USAGE=64
readonly EX_SOFTWARE=70
readonly EX_CONFIG=78
readonly IMAGE='postgres@sha256:b797483593b82cbea9a7ee41c88f324a90d10d9c2504d40e755d91c75456366d'
readonly OWNER_USER='dataforge_test_owner'
readonly CLIENT_USER='dataforge_test_client'
readonly WRONG_CLIENT_USER='dataforge_test_wrong_client'

if [[ "${DATAFORGE_TEST_ALLOW_DESTRUCTIVE:-}" != '1' ]]; then
    print -u2 -- 'Refusing disposable database tests: DATAFORGE_TEST_ALLOW_DESTRUCTIVE must be exactly 1.'
    exit "$EX_USAGE"
fi

if [[ "${DATAFORGE_TEST_ENVIRONMENT:-}" != 'test' ]]; then
    print -u2 -- 'Refusing disposable database tests: DATAFORGE_TEST_ENVIRONMENT must be exactly test.'
    exit "$EX_USAGE"
fi

for required_command in cargo docker openssl; do
    if ! command -v "$required_command" >/dev/null 2>&1; then
        print -u2 -- "Missing required DF-M0-002 tool: ${required_command}."
        exit "$EX_CONFIG"
    fi
done

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly SPIKE_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly INIT_SQL="${SPIKE_DIRECTORY}/fixtures/init.sql"
readonly PG_HBA="${SPIKE_DIRECTORY}/fixtures/pg_hba.conf"

if [[ ! -f "$INIT_SQL" || ! -f "$PG_HBA" ]]; then
    print -u2 -- 'The checked-in PostgreSQL fixture files are unavailable.'
    exit "$EX_CONFIG"
fi

typeset -g RUN_MARKER=''
typeset -g DATABASE=''
typeset -g CONTAINER_NAME=''
typeset -g TLS_VOLUME_NAME=''
typeset -g NETWORK_NAME=''
typeset -g TLS_PREP_CONTAINER_NAME=''
typeset -g TEMPORARY_ROOT=''
typeset -g LOG_DIRECTORY=''
typeset -g SECRET_PATTERN_FILE=''
typeset -g OWNER_PASSWORD=''
typeset -g HARNESS_PID=''
typeset -gi CONTAINER_MAY_EXIST=0
typeset -gi TLS_VOLUME_MAY_EXIST=0
typeset -gi NETWORK_MAY_EXIST=0
typeset -gi TLS_PREP_MAY_EXIST=0
typeset -gi CONTAINER_LOG_CAPTURED=0
typeset -gi LOGS_SCANNED=0

capture_container_log() {
    if (( CONTAINER_MAY_EXIST == 0 || CONTAINER_LOG_CAPTURED == 1 )); then
        return 0
    fi
    if [[ -z "$LOG_DIRECTORY" || ! -d "$LOG_DIRECTORY" ]]; then
        return 0
    fi
    if ! container_is_owned_by_run; then
        return 0
    fi
    docker logs "$CONTAINER_NAME" >"${LOG_DIRECTORY}/postgres.log" 2>&1 || true
    CONTAINER_LOG_CAPTURED=1
}

scan_captured_logs() {
    if (( LOGS_SCANNED == 1 )); then
        return 0
    fi
    if [[ -z "$LOG_DIRECTORY" || ! -d "$LOG_DIRECTORY" || \
          -z "$SECRET_PATTERN_FILE" || ! -f "$SECRET_PATTERN_FILE" ]]; then
        return 0
    fi

    typeset grep_status=0
    if LC_ALL=C grep -R -F -f "$SECRET_PATTERN_FILE" -- "$LOG_DIRECTORY" >/dev/null 2>&1; then
        print -u2 -- 'Secret-canary scan failed; captured output is suppressed.'
        return 1
    else
        grep_status=$?
    fi
    if (( grep_status != 1 )); then
        print -u2 -- 'Secret-canary scan could not inspect every captured log.'
        return 1
    fi

    if LC_ALL=C grep -R -E -e \
        '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|postgres(ql)?://|password[[:space:]]*=' \
        -- "$LOG_DIRECTORY" >/dev/null 2>&1; then
        print -u2 -- 'Sensitive-pattern scan failed; captured output is suppressed.'
        return 1
    else
        grep_status=$?
    fi
    if (( grep_status != 1 )); then
        print -u2 -- 'Sensitive-pattern scan could not inspect every captured log.'
        return 1
    fi

    LOGS_SCANNED=1
}

container_is_owned_by_run() {
    [[ -n "$CONTAINER_NAME" && -n "$RUN_MARKER" ]] || return 1
    [[ "$(docker inspect --format '{{index .Config.Labels "com.dataforge.test-run"}}' \
        "$CONTAINER_NAME" 2>/dev/null || true)" == "$RUN_MARKER" ]]
}

prep_container_is_owned_by_run() {
    [[ -n "$TLS_PREP_CONTAINER_NAME" && -n "$RUN_MARKER" ]] || return 1
    [[ "$(docker inspect --format '{{index .Config.Labels "com.dataforge.test-run"}}' \
        "$TLS_PREP_CONTAINER_NAME" 2>/dev/null || true)" == "$RUN_MARKER" ]]
}

volume_is_owned_by_run() {
    [[ -n "$TLS_VOLUME_NAME" && -n "$RUN_MARKER" ]] || return 1
    [[ "$(docker volume inspect --format '{{index .Labels "com.dataforge.test-run"}}' \
        "$TLS_VOLUME_NAME" 2>/dev/null || true)" == "$RUN_MARKER" ]]
}

network_is_owned_by_run() {
    [[ -n "$NETWORK_NAME" && -n "$RUN_MARKER" ]] || return 1
    [[ "$(docker network inspect --format '{{index .Labels "com.dataforge.test-run"}}' \
        "$NETWORK_NAME" 2>/dev/null || true)" == "$RUN_MARKER" ]]
}

cleanup() {
    typeset exit_status=$?
    trap - EXIT HUP INT TERM
    set +e

    if [[ -n "$HARNESS_PID" ]]; then
        kill -TERM "$HARNESS_PID" >/dev/null 2>&1 || true
        wait "$HARNESS_PID" >/dev/null 2>&1 || true
        HARNESS_PID=''
    fi

    capture_container_log
    if ! scan_captured_logs; then
        exit_status=$EX_SOFTWARE
    fi

    if (( TLS_PREP_MAY_EXIST == 1 )) && [[ -n "$TLS_PREP_CONTAINER_NAME" ]]; then
        if prep_container_is_owned_by_run; then
            if ! docker rm --force --volumes "$TLS_PREP_CONTAINER_NAME" >/dev/null 2>&1; then
                print -u2 -- 'Failed to remove the disposable TLS-preparation container.'
                exit_status=$EX_SOFTWARE
            fi
        elif docker inspect "$TLS_PREP_CONTAINER_NAME" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a TLS-preparation container whose disposable marker label does not match.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    if (( CONTAINER_MAY_EXIST == 1 )); then
        if container_is_owned_by_run; then
            if ! docker rm --force --volumes "$CONTAINER_NAME" >/dev/null 2>&1; then
                print -u2 -- 'Failed to remove the disposable PostgreSQL container.'
                exit_status=$EX_SOFTWARE
            fi
        elif docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a container whose disposable marker label does not match.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    if (( TLS_VOLUME_MAY_EXIST == 1 )); then
        if volume_is_owned_by_run; then
            if ! docker volume rm --force "$TLS_VOLUME_NAME" >/dev/null 2>&1; then
                print -u2 -- 'Failed to remove the disposable PostgreSQL TLS volume.'
                exit_status=$EX_SOFTWARE
            fi
        elif docker volume inspect "$TLS_VOLUME_NAME" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a volume whose disposable marker label does not match.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    if (( NETWORK_MAY_EXIST == 1 )); then
        if network_is_owned_by_run; then
            if ! docker network rm "$NETWORK_NAME" >/dev/null 2>&1; then
                print -u2 -- 'Failed to remove the disposable PostgreSQL network.'
                exit_status=$EX_SOFTWARE
            fi
        elif docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
            print -u2 -- 'Refusing to remove a network whose disposable marker label does not match.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    OWNER_PASSWORD=''
    if [[ -n "$TEMPORARY_ROOT" && -d "$TEMPORARY_ROOT" && \
          "$TEMPORARY_ROOT" == */dataforge-postgres.* ]]; then
        chmod -R u+rwX "$TEMPORARY_ROOT" >/dev/null 2>&1 || true
        rm -rf -- "$TEMPORARY_ROOT"
        if [[ -e "$TEMPORARY_ROOT" ]]; then
            print -u2 -- 'Failed to remove the disposable PostgreSQL temporary directory.'
            exit_status=$EX_SOFTWARE
        fi
    fi

    exit "$exit_status"
}

on_hangup() {
    exit 129
}

on_interrupt() {
    exit 130
}

on_terminate() {
    exit 143
}

trap cleanup EXIT
trap on_hangup HUP
trap on_interrupt INT
trap on_terminate TERM

umask 077
RUN_MARKER="$(openssl rand -hex 8)"
if [[ ${#RUN_MARKER} -ne 16 || "$RUN_MARKER" == *[^a-z0-9]* ]]; then
    print -u2 -- 'OpenSSL returned an invalid disposable run marker.'
    exit "$EX_SOFTWARE"
fi

DATABASE="dataforge_test_${RUN_MARKER}"
CONTAINER_NAME="dataforge-test-postgres-${RUN_MARKER}"
TLS_VOLUME_NAME="dataforge-test-postgres-tls-${RUN_MARKER}"
NETWORK_NAME="dataforge-test-postgres-network-${RUN_MARKER}"
TLS_PREP_CONTAINER_NAME="dataforge-test-postgres-tls-prep-${RUN_MARKER}"

typeset temporary_base="${TMPDIR:-/tmp}"
temporary_base="${temporary_base%/}"
TEMPORARY_ROOT="$(mktemp -d "${temporary_base}/dataforge-postgres.XXXXXXXX")"
chmod 0700 "$TEMPORARY_ROOT"
LOG_DIRECTORY="${TEMPORARY_ROOT}/logs"
typeset tls_directory="${TEMPORARY_ROOT}/tls"
mkdir -m 0700 "$LOG_DIRECTORY" "$tls_directory"

typeset openssl_log="${LOG_DIRECTORY}/openssl.log"
typeset docker_setup_log="${LOG_DIRECTORY}/docker-setup.log"
typeset harness_log="${LOG_DIRECTORY}/evidence.log"
SECRET_PATTERN_FILE="${TEMPORARY_ROOT}/secret-patterns"
typeset password_file="${TEMPORARY_ROOT}/postgres-password"

OWNER_PASSWORD="DF_TEST_SECRET_${RUN_MARKER}_$(openssl rand -hex 24)"
{
    print -r -- "$OWNER_PASSWORD"
    print -r -- 'DF_TEST_SECRET_'
} >"$SECRET_PATTERN_FILE"
print -rn -- "$OWNER_PASSWORD" >"$password_file"
chmod 0600 "$SECRET_PATTERN_FILE" "$password_file"

typeset ca_key="${tls_directory}/ca.key"
typeset ca_certificate="${tls_directory}/ca.crt"
typeset bad_ca_key="${tls_directory}/bad-ca.key"
typeset bad_ca_certificate="${tls_directory}/bad-ca.crt"
typeset server_key="${tls_directory}/server.key"
typeset server_request="${tls_directory}/server.csr"
typeset server_certificate="${tls_directory}/server.crt"
typeset client_key="${tls_directory}/client.key"
typeset client_request="${tls_directory}/client.csr"
typeset client_certificate="${tls_directory}/client.crt"
typeset wrong_client_key="${tls_directory}/wrong-client.key"
typeset wrong_client_request="${tls_directory}/wrong-client.csr"
typeset wrong_client_certificate="${tls_directory}/wrong-client.crt"
typeset server_extensions="${tls_directory}/server.ext"
typeset client_extensions="${tls_directory}/client.ext"

{
    print -r -- 'basicConstraints=critical,CA:FALSE'
    print -r -- 'keyUsage=critical,digitalSignature,keyEncipherment'
    print -r -- 'extendedKeyUsage=serverAuth'
    print -r -- 'subjectAltName=DNS:localhost'
} >"$server_extensions"
{
    print -r -- 'basicConstraints=critical,CA:FALSE'
    print -r -- 'keyUsage=critical,digitalSignature,keyEncipherment'
    print -r -- 'extendedKeyUsage=clientAuth'
} >"$client_extensions"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "$ca_key" >>"$openssl_log" 2>&1
openssl req -new -x509 -sha256 -days 2 -key "$ca_key" \
    -subj '/CN=DataForge DF-M0-002 Test CA' \
    -out "$ca_certificate" >>"$openssl_log" 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "$bad_ca_key" >>"$openssl_log" 2>&1
openssl req -new -x509 -sha256 -days 2 -key "$bad_ca_key" \
    -subj '/CN=DataForge DF-M0-002 Wrong Test CA' \
    -out "$bad_ca_certificate" >>"$openssl_log" 2>&1

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "$server_key" >>"$openssl_log" 2>&1
openssl req -new -sha256 -key "$server_key" -subj '/CN=localhost' \
    -out "$server_request" >>"$openssl_log" 2>&1
openssl x509 -req -sha256 -days 2 -in "$server_request" \
    -CA "$ca_certificate" -CAkey "$ca_key" -CAcreateserial \
    -extfile "$server_extensions" -out "$server_certificate" \
    >>"$openssl_log" 2>&1

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "$client_key" >>"$openssl_log" 2>&1
openssl req -new -sha256 -key "$client_key" -subj "/CN=${CLIENT_USER}" \
    -out "$client_request" >>"$openssl_log" 2>&1
openssl x509 -req -sha256 -days 2 -in "$client_request" \
    -CA "$ca_certificate" -CAkey "$ca_key" -CAserial "${tls_directory}/ca.srl" \
    -extfile "$client_extensions" -out "$client_certificate" \
    >>"$openssl_log" 2>&1

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
    -out "$wrong_client_key" >>"$openssl_log" 2>&1
openssl req -new -sha256 -key "$wrong_client_key" -subj "/CN=${WRONG_CLIENT_USER}" \
    -out "$wrong_client_request" >>"$openssl_log" 2>&1
openssl x509 -req -sha256 -days 2 -in "$wrong_client_request" \
    -CA "$ca_certificate" -CAkey "$ca_key" -CAserial "${tls_directory}/ca.srl" \
    -extfile "$client_extensions" -out "$wrong_client_certificate" \
    >>"$openssl_log" 2>&1

chmod 0600 "$ca_key" "$bad_ca_key" "$server_key" "$client_key" "$wrong_client_key"

openssl verify -CAfile "$ca_certificate" -purpose sslserver "$server_certificate" \
    >>"$openssl_log" 2>&1
openssl verify -CAfile "$ca_certificate" -purpose sslclient \
    "$client_certificate" "$wrong_client_certificate" >>"$openssl_log" 2>&1
openssl x509 -in "$server_certificate" -noout -checkhost localhost \
    >>"$openssl_log" 2>&1
if openssl verify -CAfile "$bad_ca_certificate" "$server_certificate" \
    >>"$openssl_log" 2>&1; then
    print -u2 -- 'The deliberately incorrect CA unexpectedly verified the server certificate.'
    exit "$EX_SOFTWARE"
fi
if openssl x509 -in "$server_certificate" -noout -checkip 127.0.0.1 \
    >>"$openssl_log" 2>&1; then
    print -u2 -- 'The localhost-only server certificate unexpectedly matched the loopback IP literal.'
    exit "$EX_SOFTWARE"
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    docker pull --platform linux/arm64 "$IMAGE" >>"$docker_setup_log" 2>&1
fi
if [[ "$(docker image inspect --format '{{.Architecture}}/{{.Os}}' "$IMAGE")" != 'arm64/linux' ]]; then
    print -u2 -- 'The pinned PostgreSQL fixture image is not the required linux/arm64 artifact.'
    exit "$EX_CONFIG"
fi
if ! docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$IMAGE" | \
    LC_ALL=C grep -F -x -- "$IMAGE" >/dev/null; then
    print -u2 -- 'The local PostgreSQL image does not retain the required immutable digest.'
    exit "$EX_CONFIG"
fi

TLS_VOLUME_MAY_EXIST=1
docker volume create \
    --label 'com.dataforge.disposable=true' \
    --label "com.dataforge.test-run=${RUN_MARKER}" \
    "$TLS_VOLUME_NAME" >>"$docker_setup_log" 2>&1

TLS_PREP_MAY_EXIST=1
docker run --rm --platform linux/arm64 \
    --name "$TLS_PREP_CONTAINER_NAME" \
    --label 'com.dataforge.disposable=true' \
    --label "com.dataforge.test-run=${RUN_MARKER}" \
    --mount "type=bind,source=${tls_directory},target=/input,readonly" \
    --mount "type=volume,source=${TLS_VOLUME_NAME},target=/certs" \
    --entrypoint /usr/bin/install \
    "$IMAGE" -o postgres -g postgres -m 0600 \
    /input/server.key /input/server.crt /input/ca.crt /certs/ \
    >>"$docker_setup_log" 2>&1
TLS_PREP_MAY_EXIST=0

NETWORK_MAY_EXIST=1
docker network create \
    --label 'com.dataforge.disposable=true' \
    --label "com.dataforge.test-run=${RUN_MARKER}" \
    "$NETWORK_NAME" >>"$docker_setup_log" 2>&1

CONTAINER_MAY_EXIST=1
docker run --detach --platform linux/arm64 \
    --name "$CONTAINER_NAME" \
    --label 'com.dataforge.disposable=true' \
    --label "com.dataforge.test-run=${RUN_MARKER}" \
    --network "$NETWORK_NAME" \
    --publish '127.0.0.1::5432/tcp' \
    --env "POSTGRES_USER=${OWNER_USER}" \
    --env "POSTGRES_DB=${DATABASE}" \
    --env 'POSTGRES_PASSWORD_FILE=/run/secrets/postgres-password' \
    --env 'POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=trust' \
    --mount "type=bind,source=${password_file},target=/run/secrets/postgres-password,readonly" \
    --mount "type=bind,source=${INIT_SQL},target=/docker-entrypoint-initdb.d/010-dataforge.sql,readonly" \
    --mount "type=bind,source=${PG_HBA},target=/etc/postgresql/dataforge-pg_hba.conf,readonly" \
    --mount "type=volume,source=${TLS_VOLUME_NAME},target=/var/lib/postgresql/tls,readonly" \
    "$IMAGE" \
    -c 'listen_addresses=*' \
    -c 'ssl=on' \
    -c 'ssl_min_protocol_version=TLSv1.2' \
    -c 'ssl_cert_file=/var/lib/postgresql/tls/server.crt' \
    -c 'ssl_key_file=/var/lib/postgresql/tls/server.key' \
    -c 'ssl_ca_file=/var/lib/postgresql/tls/ca.crt' \
    -c 'hba_file=/etc/postgresql/dataforge-pg_hba.conf' \
    -c 'password_encryption=scram-sha-256' \
    -c "dataforge.test_run_marker=${RUN_MARKER}" \
    >>"$docker_setup_log" 2>&1

typeset port_mapping=''
for _ in {1..30}; do
    port_mapping="$(docker port "$CONTAINER_NAME" 5432/tcp 2>/dev/null || true)"
    [[ -n "$port_mapping" ]] && break
    sleep 1
done
if [[ "$port_mapping" != 127.0.0.1:* ]]; then
    print -u2 -- 'Docker did not bind the disposable database exclusively to IPv4 loopback.'
    exit "$EX_SOFTWARE"
fi
typeset host_port="${port_mapping##*:}"
if [[ -z "$host_port" || "$host_port" == *[^0-9]* ]] || \
   (( host_port < 1024 || host_port > 65535 )); then
    print -u2 -- 'Docker returned an invalid disposable database port.'
    exit "$EX_SOFTWARE"
fi

typeset server_guard=''
for _ in {1..60}; do
    if ! docker inspect --format '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null | \
        LC_ALL=C grep -F -x 'true' >/dev/null; then
        break
    fi
    if docker logs "$CONTAINER_NAME" 2>&1 | \
        LC_ALL=C grep -F -- 'PostgreSQL init process complete; ready for start up.' >/dev/null; then
        server_guard="$(docker exec "$CONTAINER_NAME" \
            psql --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 \
            --username "$OWNER_USER" --dbname "$DATABASE" \
            --command "SELECT current_database(), current_setting('dataforge.test_run_marker', true), to_regclass('public.dataforge_transaction_probe'), EXISTS (SELECT 1 FROM pg_authid WHERE rolname = current_user AND rolpassword LIKE 'SCRAM-SHA-256\$%')" \
            2>>"$docker_setup_log" || true)"
        if [[ "$server_guard" == "${DATABASE}|${RUN_MARKER}|dataforge_transaction_probe|t" ]]; then
            break
        fi
    fi
    sleep 1
done
if [[ "$server_guard" != "${DATABASE}|${RUN_MARKER}|dataforge_transaction_probe|t" ]]; then
    print -u2 -- 'The disposable PostgreSQL server did not satisfy its server-side guard.'
    exit "$EX_SOFTWARE"
fi

(
    export DATAFORGE_TEST_ALLOW_DESTRUCTIVE='1'
    export DATAFORGE_TEST_ENVIRONMENT='test'
    export DATAFORGE_TEST_IMAGE_DIGEST="$IMAGE"
    export DATAFORGE_TEST_HOST='localhost'
    export DATAFORGE_TEST_PORT="$host_port"
    export DATAFORGE_TEST_RUN_MARKER="$RUN_MARKER"
    export DATAFORGE_TEST_DATABASE="$DATABASE"
    export DATAFORGE_TEST_CONTAINER="$CONTAINER_NAME"
    export DATAFORGE_TEST_OWNER_USER="$OWNER_USER"
    export DATAFORGE_TEST_OWNER_PASSWORD="$OWNER_PASSWORD"
    export DATAFORGE_TEST_FIXTURE_DIR="$tls_directory"
    export DATAFORGE_TEST_CA_CERT="$ca_certificate"
    export DATAFORGE_TEST_BAD_CA_CERT="$bad_ca_certificate"
    export DATAFORGE_TEST_CLIENT_CERT="$client_certificate"
    export DATAFORGE_TEST_CLIENT_KEY="$client_key"
    export DATAFORGE_TEST_WRONG_CLIENT_CERT="$wrong_client_certificate"
    export DATAFORGE_TEST_WRONG_CLIENT_KEY="$wrong_client_key"
    cd "$SPIKE_DIRECTORY"
    cargo build --locked --release --bin evidence
    /usr/bin/time -l "${SPIKE_DIRECTORY}/target/release/evidence"
) >"$harness_log" 2>&1 &
HARNESS_PID=$!

typeset harness_status=0
if wait "$HARNESS_PID"; then
    harness_status=0
else
    harness_status=$?
fi
HARNESS_PID=''

capture_container_log
if ! scan_captured_logs; then
    exit "$EX_SOFTWARE"
fi

command cat -- "$harness_log"
if (( harness_status != 0 )); then
    print -u2 -- 'DF-M0-002 evidence runner failed; PostgreSQL diagnostics remain suppressed unless reviewed in the private temp lifecycle.'
    exit "$harness_status"
fi

print -- 'DF-M0-002 disposable PostgreSQL evidence completed with secret-canary scan passed.'
