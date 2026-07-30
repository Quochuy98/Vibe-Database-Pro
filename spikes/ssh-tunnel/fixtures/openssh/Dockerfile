FROM docker.io/library/alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

RUN apk add --no-cache openssh-server=10.3_p1-r0 \
    && adduser -D -h /home/dataforge_test -s /bin/sh dataforge_test \
    && install -d -m 0700 -o dataforge_test -g dataforge_test /home/dataforge_test/.ssh \
    && install -d -m 0700 /run/dataforge-ssh

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/sbin/dataforge-test-sshd

RUN chmod 0755 /usr/local/sbin/dataforge-test-sshd \
    && chmod 0600 /etc/ssh/sshd_config

EXPOSE 2222

ENTRYPOINT ["/usr/local/sbin/dataforge-test-sshd"]
