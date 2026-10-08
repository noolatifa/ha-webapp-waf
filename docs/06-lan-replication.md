# 06 · LAN: db2 and Replication (iteration 6)

| | |
|---|---|
| **Objective** | Add db2, a real-time copy of db1, set up **automatically** at startup |
| **Where** | lan, `/opt/lab` |
| **Before** | Stages 04 and 05 |
| **After** | db1 → db2 replicated (GTID, encrypted), db2 read-only |

---

## Principle

```
db1 (10.0.3.2) ──binary log──► db2 (10.0.3.3)
   primary: records every change        replica: reads the log and replays it
```
- **Binary log** (binlog): db1 records every change.
- **GTID**: global identifier of each transaction → db2 knows exactly where to resume after an interruption.
- ⚠️ Replication **is not a backup**: a `DROP TABLE` on db1 is replayed on db2.

---

## The path followed (6a → 6c)

| Sub-step | Content | What it showed |
|---|---|---|
| 6a | db2 added without replication | A table created on db1 is absent from db2: two independent databases |
| 6b | binlog on db1, read-only on db2 | `server_id` 1/2, `SHOW MASTER STATUS`, `@@read_only = 1` |
| 6c | Manual replication, then automated with scripts | `Yes / Yes`, data propagated |

Below: the final, reproducible version.

---

## 1. Initialisation scripts

```bash
mkdir -p /opt/lab/init
```

`/opt/lab/init/db1-repl.sql`:
```sql
CREATE USER IF NOT EXISTS 'repl'@'10.0.3.3' IDENTIFIED BY '<replication password>';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'10.0.3.3';
RESET MASTER;
```
- Dedicated account, usable **only from db2** (10.0.3.3), with **a single privilege**.
- `RESET MASTER`: clears the log after initialisation, otherwise db2 would replay the creation of the database it already has.

`/opt/lab/init/db2-repl.sql`:
```sql
CHANGE MASTER TO MASTER_HOST='10.0.3.2', MASTER_PORT=3306, MASTER_USER='repl', MASTER_PASSWORD='<replication password>', MASTER_USE_GTID=slave_pos, MASTER_CONNECT_RETRY=10;
```
- `MASTER_USE_GTID=slave_pos`: GTID-based tracking.
- `MASTER_CONNECT_RETRY=10`: retries every 10 s if db1 is not ready yet.

```bash
chmod 644 /opt/lab/init/*.sql
```
Readable by the container's `mysql` user. Limitation: the replication password is readable on the VM (production: Docker secrets).

---

## 2. Compose changes

`db1` — add:
```yaml
    command: --server-id=1 --log-bin=mysql-bin --binlog-format=ROW
```
and in its `volumes`:
```yaml
      - ./init/db1-repl.sql:/docker-entrypoint-initdb.d/10-repl.sql:ro,z
```

New `db2` service:
```yaml
  db2:
    image: mariadb:11
    container_name: db2
    command: --server-id=2 --read-only=ON
    restart: unless-stopped
    depends_on: [db1]
    environment:
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MARIADB_DATABASE: dvwa
      MARIADB_USER: dvwa
      MARIADB_PASSWORD: ${DB_APP_PASSWORD}
    volumes:
      - db2-data:/var/lib/mysql
      - ./init/db2-repl.sql:/docker-entrypoint-initdb.d/10-repl.sql:ro,z
    networks:
      net-data:
        ipv4_address: 10.0.3.3
```
And under `volumes:` at the bottom: `db2-data:`.

| Element | Role |
|---|---|
| `--server-id` | Unique identifier of each server (mandatory) |
| `--log-bin=mysql-bin` | Enables the binary log on db1 |
| `--binlog-format=ROW` | Logs the modified rows (more reliable than logging statements) |
| `--read-only=ON` | The application cannot write to db2 (root and replication can) |
| `/docker-entrypoint-initdb.d/` | Scripts executed **on the first start of an empty database** |
| `:ro,z` | Read-only + SELinux label (required on RHEL) |

---

## 3. Start (empty database required)

```bash
cd /opt/lab
docker compose config --quiet && echo "syntax OK" && docker compose down -v && docker compose up -d
```
⚠️ `down -v` erases the data: required so that the initialisation scripts run.

---

## Tests

```bash
docker exec -it db2 mariadb -uroot -p -e "SHOW SLAVE STATUS\G"
```
| Field | Expected |
|---|---|
| `Slave_IO_Running` | `Yes` (db2 reads db1's log) |
| `Slave_SQL_Running` | `Yes` (db2 replays the changes) |
| `Seconds_Behind_Master` | `0` |
| `Using_Gtid` | `Slave_Pos` |
| `Master_SSL_Allowed` | `Yes` → replication natively **encrypted** |
| `Last_IO_Error`, `Last_SQL_Error` | empty |

Propagation:
```bash
docker exec -it db1 mariadb -uroot -p -e "CREATE TABLE dvwa.witness (id INT); INSERT INTO dvwa.witness VALUES (7);"
docker exec -it db2 mariadb -uroot -p -e "SELECT * FROM dvwa.witness;"
docker exec -it db1 mariadb -uroot -p -e "DROP TABLE dvwa.witness;"
```
→ `7` visible on db2; after the `DROP`, the table also disappears from db2.

Read-only:
```bash
docker exec -it db1 mariadb -uroot -p -e "CREATE TABLE dvwa.test_ro (id INT);"
docker exec -it db2 mariadb -udvwa -p -e "INSERT INTO dvwa.test_ro VALUES (99);"
docker exec -it db1 mariadb -uroot -p -e "DROP TABLE dvwa.test_ro;"
```
→ the 2nd command fails with an error mentioning `--read-only`.

Snapshot **`lan-v1-ok`**.

---

## ⚠️ Limitations (V1)

| Limitation | Evolution |
|---|---|
| If db1 fails: **manual** failover to db2 | Done in V2: HAProxy, stage 14 (db2 `read-only` removed) |
| No backup | Done in V2: scheduled dump, stage 17 |
| `read-only` does not restrict root | Administrative rule |
