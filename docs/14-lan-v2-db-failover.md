# 14 · V2: Automatic Database Failover with HAProxy

| | |
|---|---|
| **Objective** | Applications reach the database through a generic SQL proxy; if db1 fails, traffic moves to db2 automatically, with no change in the application |
| **Where** | lan, as root, in `/opt/lab` |
| **Before** | Stage 06 (db1 → db2 GTID replication) |
| **After** | `db` = HAProxy (10.0.3.4); db1 active, db2 standby; failover in ~4 s; no automatic failback |

---

## Principle

```
app1 / app2 ──► db (HAProxy 10.0.3.4:3306) ──► db1 (active)
                                            └─► db2 (backup, used only if db1 is DOWN)
```
- The name `db` moves from db1 to HAProxy: applications keep `DB_SERVER: db`, **no code change**.
- HAProxy is engine-agnostic (TCP); only the health check is MariaDB-specific (`mysql-check`).
- Once on db2, HAProxy **stays** on db2 even when db1 comes back: db1 has missed writes. The return is a planned operation (stage 15).

---

## 1. Users created by the init script

`/opt/lab/init/db1-repl.sql` (final content):
```sql
CREATE USER IF NOT EXISTS 'repl'@'10.0.3.3' IDENTIFIED BY '<replication password>';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'10.0.3.3';
RESET MASTER;
CREATE USER 'haproxy_check'@'10.0.3.4';
CREATE USER 'repl'@'10.0.3.2' IDENTIFIED BY '<replication password>';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'10.0.3.2';
```
| Line | Role |
|---|---|
| `haproxy_check@10.0.3.4` | Passwordless account with no privilege, used only by the health check, only from HAProxy |
| `repl@10.0.3.2` | Lets db1 replicate **from** db2 during the switchback (stage 15) |
| After `RESET MASTER` | These users are written to the binlog, so they are replicated to db2 as well |

---

## 2. Compose changes (`/opt/lab/docker-compose.yml`)

db1: remove `aliases: [db]` and set:
```yaml
    command: --server-id=1 --log-bin=mysql-bin --binlog-format=ROW --log-slave-updates
```
db2: remove `--read-only=ON` and set:
```yaml
    command: --server-id=2 --log-bin=mysql-bin --binlog-format=ROW --log-slave-updates
```
| Change | Reason |
|---|---|
| `--log-bin` on db2 | db2 must be able to act as a source after a failover |
| `--log-slave-updates` | Replicated changes are also written to the local binlog (GTID continuity in both directions) |
| No `read-only` on db2 | After failover, db2 must accept writes without a manual promotion |

New service:
```yaml
  haproxy:
    image: haproxy:lts
    container_name: haproxy
    restart: unless-stopped
    depends_on: [db1, db2]
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro,z
    networks:
      net-data:
        ipv4_address: 10.0.3.4
        aliases: [db]
```
Full file: [`configs/lan/docker-compose.yml`](../configs/lan/docker-compose.yml).

---

## 3. HAProxy configuration

```bash
mkdir -p /opt/lab/haproxy
```
`/opt/lab/haproxy/haproxy.cfg`:
```
global
    log stdout format raw local0

defaults
    mode tcp
    log global
    timeout connect 3s
    timeout client 1h
    timeout server 1h

listen mariadb
    bind *:3306
    option mysql-check user haproxy_check post-41
    option redispatch
    stick-table type ip size 2 nopurge
    stick on dst
    server db1 10.0.3.2:3306 check inter 2s fall 2 rise 2 on-marked-down shutdown-sessions
    server db2 10.0.3.3:3306 check inter 2s fall 2 rise 10 backup on-marked-down shutdown-sessions

listen stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 2s
```
| Directive | Role |
|---|---|
| `mysql-check user haproxy_check post-41` | Real MariaDB login handshake, not just an open port |
| `inter 2s fall 2` | Server marked DOWN after 2 failed checks (~4 s) |
| `backup` | db2 receives traffic only when db1 is DOWN |
| `rise 10` on db2 | db2 must be healthy for 20 s at startup: avoids a race where db2 is chosen before db1 is ready |
| `stick-table … size 2 nopurge` + `stick on dst` | Remembers the server in use: when db1 comes back, traffic **stays** on db2 (no automatic failback). `size 1` does not work |
| `on-marked-down shutdown-sessions` | Open connections to a failed server are cut, so clients reconnect to the other one |
| `listen stats` (:8404) | Status page and CSV, internal network only (used by the dashboard, stage 16) |

```bash
chmod 644 /opt/lab/haproxy/haproxy.cfg
```

---

## 4. Rebuild (empty databases required)

```bash
cd /opt/lab
docker compose config --quiet && echo "syntax OK" && docker compose down -v && docker compose up -d && sleep 30 && docker compose ps
```
⚠️ `down -v` erases the data so that the init scripts run again.

Then create the DVWA tables: browser `https://www.latifa.test/setup.php` → **Create / Reset Database**.

Snapshot **`lan-v2-db-ok`**.

---

## Tests (lan)

Helper commands for this session:
```bash
alias st='curl -s "http://10.0.3.4:8404/stats;csv" | cut -d, -f2,18 | grep -E "db1|db2"'
alias quidb='docker exec app1 php -r '"'"'$c = new mysqli("db", "dvwa", getenv("DB_PASSWORD"), "dvwa"); echo $c->query("SELECT @@server_id")->fetch_row()[0] == 1 ? "db1\n" : "db2\n";'"'"''
```
- `st`: state of db1 and db2 as seen by HAProxy (column 18 of the CSV).
- `quidb`: which database actually answers the application (`@@server_id`).

| Action | Expected |
|---|---|
| `st ; quidb` | `db1,UP` `db2,UP` · `db1` |
| `docker exec db2 sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "SHOW SLAVE STATUS\G"' \| grep -E "Running:\|Behind"` | `Yes`, `Yes`, `0` |
| `docker stop db1 ; sleep 6 ; st ; quidb` | `db1,DOWN` · `db2`; DVWA still works |
| `docker start db1 ; sleep 10 ; st ; quidb` | `db1,UP` · **`db2`** (no automatic failback) |
| Return to db1 | Stage 15 |

## ⚠️ Notes

- After any change to `haproxy.cfg`: `docker compose restart haproxy` (single-file bind mount; it also clears the stick table).
- db2 has no `read-only`: never point an application directly at `10.0.3.3`.
- Failover is automatic, failback is manual by design.
