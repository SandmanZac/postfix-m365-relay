FROM alpine:3

RUN apk add --no-cache postfix ca-certificates tzdata

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 25
VOLUME ["/var/spool/postfix"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD postfix status >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
