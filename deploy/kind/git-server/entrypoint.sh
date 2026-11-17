#!/bin/sh
set -eu
mkdir -p /run /srv/git
chown nginx:nginx /run /srv/git
spawn-fcgi -s /run/fcgiwrap.socket -u nginx -g nginx -M 0660 -F 1 -- /usr/bin/fcgiwrap
exec nginx -g "daemon off;"
