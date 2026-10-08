#!/bin/bash

set -euo pipefail
cd /opt/lab

REPL_PW=$(grep -oP "IDENTIFIED BY '\K[^']+" init/db1-repl.sql | head -1)
log() { echo "[$(date +%T)] $*"; }
sql() { docker exec -i "$1" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N' <<< "$2"; }
etat() { curl -s "http://10.0.3.4:8404/stats;csv" | awk -F, -v s="$1" '$1=="mariadb" && $2==s {print $18}'; }
active() { docker exec app1 php -r '$c = new mysqli("db", "dvwa", getenv("DB_PASSWORD"), "dvwa"); echo $c->query("SELECT @@server_id")->fetch_row()[0] == 1 ? "db1" : "db2";'; }

# 0. Controles
[ "$(etat db1)" = "UP" ] || { log "db1 n'est pas UP dans HAProxy : abandon"; exit 1; }
if [ "$(active)" = "db1" ] && docker exec -i db2 sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G"' | grep "Master_Host: 10.0.3.2" >/dev/null; then
    log "Deja dans l'etat normal (db1 principale, db2 replique) : rien a faire"; exit 0
fi

trap 'log "ERREUR : db2 repasse en ecriture"; sql db2 "SET GLOBAL read_only=OFF;"' ERR

# 1. db1 copie db2 (rattrapage), si ce n'est pas deja le cas
if ! docker exec -i db1 sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G"' | grep "Master_Host: 10.0.3.3" >/dev/null; then
    log "1/6 db1 devient la copie de db2 pour rattraper son retard"
    sql db2 "STOP SLAVE; RESET SLAVE ALL;"
    sql db1 "STOP SLAVE; RESET SLAVE ALL; SET GLOBAL gtid_slave_pos=@@gtid_binlog_pos; CHANGE MASTER TO MASTER_HOST='10.0.3.3', MASTER_USER='repl', MASTER_PASSWORD='$REPL_PW', MASTER_USE_GTID=slave_pos, MASTER_CONNECT_RETRY=10; START SLAVE;"
else
    log "1/6 db1 copie deja db2"
fi

# 2. Gel des ecritures sur db2 (quelques secondes)
log "2/6 gel des ecritures sur db2"
sql db2 "SET GLOBAL read_only=ON;"

# 3. Attendre que db1 ait exactement rattrape db2
log "3/6 attente du rattrapage de db1"
for i in $(seq 1 60); do
    cible=$(sql db2 "SELECT @@gtid_binlog_pos;")
    actuel=$(sql db1 "SELECT @@gtid_slave_pos;")
    [ "$cible" = "$actuel" ] && break
    sleep 1
done
[ "$cible" = "$actuel" ] || { log "db1 n'a pas rattrape db2 en 60 s : abandon"; false; }
log "    db1 = db2 = $cible"

# 4. db1 redevient principale
log "4/6 db1 redevient principale"
sql db1 "STOP SLAVE; RESET SLAVE ALL;"

# 5. HAProxy revient sur db1 (le redemarrage vide sa memoire)
log "5/6 HAProxy revient sur db1"
docker compose restart haproxy >/dev/null 2>&1
for i in $(seq 1 30); do [ "$(etat db1)" = "UP" ] && [ "$(active)" = "db1" ] && break; sleep 1; done
[ "$(active)" = "db1" ] || { log "HAProxy n'est pas revenu sur db1"; false; }

# 6. db2 redevient la replique de db1, puis accepte de nouveau les ecritures (pour une future bascule)
log "6/6 db2 redevient la replique de db1"
sql db2 "SET GLOBAL gtid_slave_pos=@@gtid_binlog_pos; CHANGE MASTER TO MASTER_HOST='10.0.3.2', MASTER_USER='repl', MASTER_PASSWORD='$REPL_PW', MASTER_USE_GTID=slave_pos, MASTER_CONNECT_RETRY=10; START SLAVE; SET GLOBAL read_only=OFF;"
trap - ERR

sleep 3
docker exec -i db2 sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW SLAVE STATUS\G"' | grep -E "Slave_IO_Running|Slave_SQL_Running:|Last_SQL_Error:"
log "Termine : base active = $(active)"
