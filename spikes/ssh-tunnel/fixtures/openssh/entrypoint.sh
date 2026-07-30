#!/bin/sh
set -eu

readonly fixture_root='/run/dataforge-fixture'
readonly runtime_root='/run/dataforge-ssh'
readonly user_home='/home/dataforge_test'

if [ ! -f "${fixture_root}/host_key" ] || [ ! -f "${fixture_root}/authorized_keys" ]; then
    printf '%s\n' 'Disposable SSH fixture is missing its runtime-generated keys.' >&2
    exit 78
fi

install -m 0600 "${fixture_root}/host_key" "${runtime_root}/host_key"
install -m 0600 -o dataforge_test -g dataforge_test \
    "${fixture_root}/authorized_keys" "${user_home}/.ssh/authorized_keys"

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
