FROM alpine:3.22

RUN apk add --no-cache git git-daemon nginx fcgiwrap spawn-fcgi \
    && mkdir -p /run /srv/git /var/log/nginx \
    && chown -R nginx:nginx /run /srv/git /var/log/nginx \
    && git config --system --add safe.directory '*'

COPY nginx.conf /etc/nginx/http.d/default.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
