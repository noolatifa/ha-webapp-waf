# 14 · Shared PHP Sessions in Galera

| | |
|---|---|
| **Objective** | A user stays logged in when the application node serving them fails |
| **Where** | db1 (once), then app1 and app2, as root |
| **Before** | Stages 04 to 06 |
| **After** | Sessions stored in `phpsess.sessions`, replicated by Galera, readable by both application nodes; no DVWA code change |

## Problem

PHP stores sessions as files **inside each container**. nginx keeps a client on the same application (`hash $remote_addr consistent`, stage 07), but when that application fails, the other one does not know the session: the user is sent back to the login page.

## Principle

```
browser ── cookie PHPSESSID ──► app1 or app2 ── session handler ──► 127.0.0.1:3306 HAProxy ──► Galera (db1 / db2)
```
- A PHP `SessionHandlerInterface` class stores sessions in a table instead of local files.
- It is loaded before every page with `auto_prepend_file`: DVWA itself is not modified.
- Same pattern as the database session drivers of common frameworks (Laravel `database` driver, Symfony `PdoSessionHandler`).

---

## 1. Session table (db1)

[`configs/db/init-phpsess.sql`](../configs/db/init-phpsess.sql):
```bash
mysql <<'EOF'
CREATE DATABASE IF NOT EXISTS phpsess;
CREATE TABLE IF NOT EXISTS phpsess.sessions (id VARCHAR(128) NOT NULL PRIMARY KEY, data MEDIUMBLOB, ts INT UNSIGNED NOT NULL, KEY (ts)) ENGINE=InnoDB;
GRANT SELECT, INSERT, UPDATE, DELETE ON phpsess.* TO 'dvwa'@'10.0.3.5', 'dvwa'@'10.0.3.6';
EOF
mysql -e "SHOW TABLES FROM phpsess; SHOW GRANTS FOR 'dvwa'@'10.0.3.5';"
```
| Element | Role |
|---|---|
| Separate `phpsess` database | DVWA's **Create / Reset Database** drops `dvwa`; sessions are not affected |
| `id` primary key | Session identifier; a primary key is required by Galera replication |
| `ts` + index | Last access time, used to delete expired sessions |
| Existing `dvwa` user, 4 privileges | Least privilege: no `DROP`, no `CREATE`, only from the two application nodes |

## 2. Session handler (app1, then app2)

[`configs/app/session_db.php`](../configs/app/session_db.php) → `/opt/app/session_db.php` (29 lines)

| Method | Query |
|---|---|
| `open` | PDO connection to `127.0.0.1` (local HAProxy), database `phpsess`, user `dvwa`, password from the container environment (`DB_PASSWORD`): no secret in the file |
| `read` | `SELECT data FROM sessions WHERE id = ?` |
| `write` | `REPLACE INTO sessions (id, data, ts) VALUES (?, ?, ?)`: insert or update, refresh `ts` |
| `destroy` | `DELETE … WHERE id = ?` (logout) |
| `gc` | `DELETE … WHERE ts < ?`: expired sessions, called periodically by PHP |

All queries are prepared statements: the session identifier sent by the client is never concatenated into SQL.

[`configs/app/session.ini`](../configs/app/session.ini) → `/opt/app/session.ini`
```ini
auto_prepend_file=/var/www/session_db.php
```

## 3. Compose (app1, then app2)

Two volumes added to [`configs/app/docker-compose.yml`](../configs/app/docker-compose.yml):
```yaml
      - ./session_db.php:/var/www/session_db.php:ro,z
      - ./session.ini:/usr/local/etc/php/conf.d/zz-session.ini:ro,z
```
- `session_db.php` in `/var/www`: outside the web root, not reachable by URL.
- `zz-session.ini` in `conf.d`: loaded last by PHP.

```bash
cd /opt/app && chmod 644 session_db.php session.ini
docker compose config -q && docker compose up -d --force-recreate
docker exec dvwa php -l /var/www/session_db.php
docker exec dvwa php -r 'echo ini_get("auto_prepend_file"), PHP_EOL;'
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/login.php
```
**Expected**: `No syntax errors detected`, `/var/www/session_db.php`, `200`.

---

## Tests

| Step | Expected |
|---|---|
| db1: `mysql -e "SELECT id, ts, LENGTH(data) FROM phpsess.sessions;"` after the `curl` | At least one row per application node |
| Log in to DVWA through `https://www.latifa.test`; the dashboard shows which application serves the client | e.g. app1 |
| `poweroff` on that application node, wait ~10 s, open another DVWA page | Page served by the other node, **still logged in** |
| Power the node back on | Dashboard: node `UP` again |

## ⚠️ Notes

- No session locking: two simultaneous requests of the same user can overwrite each other's session changes (acceptable for DVWA; a production design would use a locking handler or Redis).
- One database write per request: suitable for this lab; at scale, a dedicated session store (Redis cluster) is preferable.
- Session data travels in clear text on net-data, like all SQL traffic (isolated segment; see stage 18).
