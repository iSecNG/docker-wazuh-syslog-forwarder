FROM ubuntu:22.04

ARG WAZUH_VERSION=4.14.7

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    rsyslog \
    ca-certificates \
    procps \
  && rm -rf /var/lib/apt/lists/*

RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
    | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
    https://packages.wazuh.com/4.x/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list

RUN apt-get update \
  && WAZUH_MANAGER="placeholder" apt-get install -y --no-install-recommends \
    wazuh-agent=${WAZUH_VERSION}-1 \
  && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/wazuh.list

COPY config/rsyslog.conf /etc/rsyslog.conf
COPY config/rsyslog.d/remote.conf /etc/rsyslog.d/remote.conf
COPY config/ossec.conf /var/ossec/etc/ossec.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN mkdir -p /var/log/remote && chown syslog:adm /var/log/remote

EXPOSE 514/udp 514/tcp

VOLUME ["/var/log/remote"]

ENTRYPOINT ["/entrypoint.sh"]
