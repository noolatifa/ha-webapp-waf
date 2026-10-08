#!/bin/bash
set -euo pipefail
umask 077
D=/opt/lab/backups
mkdir -p "$D"
F="$D/dvwa-$(date +%F-%H%M).sql"
trap 'rm -f "$F"' ERR
docker exec db2 sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --databases dvwa' > "$F"
find "$D" -name 'dvwa-*.sql' -mtime +7 -delete
