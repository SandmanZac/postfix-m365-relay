#!/bin/sh
# Postfix relay -> Exchange Online (Microsoft 365) via an inbound connector.
#
# Configuration comes from environment variables (docker run -e, compose
# `environment:` / `env_file:`), and optionally from a shell-style file
# mounted at /config/relay.env.
#
#   RELAY_DOMAIN   (required) An accepted domain in your M365 tenant, e.g. contoso.com.
#                  Used to derive the smart host contoso-com.mail.protection.outlook.com
#   M365_HOST      (optional) Override the derived smart host
#   POSTFIX_<NAME> Any main.cf parameter. The name after POSTFIX_ is lowercased, so
#                  POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS -> smtpd_recipient_restrictions
set -eu

if [ -f /config/relay.env ]; then
  echo "entrypoint: loading /config/relay.env"
  set -a
  # shellcheck disable=SC1091
  . /config/relay.env
  set +a
fi

: "${RELAY_DOMAIN:?RELAY_DOMAIN is required (your M365 accepted domain, e.g. contoso.com)}"

M365_HOST="${M365_HOST:-$(printf '%s' "$RELAY_DOMAIN" | tr '.' '-').mail.protection.outlook.com}"

# ---- Defaults (each can be overridden by setting the same POSTFIX_* variable) ----
export POSTFIX_MYHOSTNAME="${POSTFIX_MYHOSTNAME:-$(hostname)}"
export POSTFIX_RELAYHOST="${POSTFIX_RELAYHOST:-[${M365_HOST}]:25}"
export POSTFIX_MYNETWORKS="${POSTFIX_MYNETWORKS:-127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}"
export POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS="${POSTFIX_SMTPD_RECIPIENT_RESTRICTIONS:-permit_mynetworks,reject_unauth_destination}"
export POSTFIX_SMTP_TLS_SECURITY_LEVEL="${POSTFIX_SMTP_TLS_SECURITY_LEVEL:-encrypt}"
export POSTFIX_SMTP_TLS_CAFILE="${POSTFIX_SMTP_TLS_CAFILE:-/etc/ssl/certs/ca-certificates.crt}"
export POSTFIX_SMTP_TLS_LOGLEVEL="${POSTFIX_SMTP_TLS_LOGLEVEL:-1}"
export POSTFIX_INET_INTERFACES="${POSTFIX_INET_INTERFACES:-all}"
export POSTFIX_INET_PROTOCOLS="${POSTFIX_INET_PROTOCOLS:-ipv4}"
export POSTFIX_MESSAGE_SIZE_LIMIT="${POSTFIX_MESSAGE_SIZE_LIMIT:-36700160}"
export POSTFIX_MAILLOG_FILE="${POSTFIX_MAILLOG_FILE:-/dev/stdout}"

# ---- Fixed settings: this is a pure relay, no local delivery ----
postconf -e \
  "mydestination=" \
  "local_transport=error:local delivery is disabled" \
  "alias_maps=" \
  "alias_database=" \
  "smtpd_banner=\$myhostname ESMTP"

# ---- Apply every POSTFIX_* variable as a main.cf parameter ----
env | grep '^POSTFIX_' | while IFS='=' read -r key value; do
  name=$(printf '%s' "${key#POSTFIX_}" | tr 'A-Z' 'a-z')
  echo "entrypoint: ${name} = ${value}"
  postconf -e "${name}=${value}"
done || true

postfix set-permissions >/dev/null 2>&1 || true
postfix check

echo "entrypoint: effective non-default configuration:"
postconf -n

exec postfix start-fg
