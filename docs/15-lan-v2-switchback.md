# 15 · V2: Planned Switchback to db1

| | |
|---|---|
| **Objective** | After a failover, bring db1 back as the active database without losing the writes made on db2 |
| **Where** | lan, as root |
| **Before** | Stage 14; db1 restarted and `UP` in HAProxy, traffic still on db2 |
| **After** | db1 active, db2 replica of db1 again; ready for the next failover |

---

## Principle

db1 first **catches up** from db2 (GTID), writes are frozen for a few seconds, then the roles are swapped back.

| Step | Action |
|---|---|
| 0 | Checks: db1 must be `UP`; exits if the setup is already normal |
| 1 | db1 becomes a replica of db2 and catches up (`gtid_slave_pos` = its own binlog position) |
| 2 | Writes frozen on db2 (`read_only=ON`) |
| 3 | Waits until db1 has applied exactly what db2 has (`@@gtid_binlog_pos` = `@@gtid_slave_pos`, max 60 s) |
| 4 | db1 stops replicating: it is a primary again |
| 5 | `docker compose restart haproxy`: clears the stick table, traffic goes to db1 |
| 6 | db2 becomes a replica of db1 again, then `read_only=OFF` |

If any step fails after step 2, a `trap` puts db2 back in read-write: the service keeps running on db2.

---

## 1. Install the script

[`configs/lan/retour-db1.sh`](../configs/lan/retour-db1.sh) → `/opt/lab/retour-db1.sh`
```bash
chmod 700 /opt/lab/retour-db1.sh
```
- No password in the script: the replication password is read from `init/db1-repl.sql`, the root password from the container environment.
- Root only (`700`).

## 2. Run

```bash
/opt/lab/retour-db1.sh
```
**Expected**: steps `1/6` to `6/6`, then `Slave_IO_Running: Yes`, `Slave_SQL_Running: Yes`, `Termine : base active = db1`.
On a normal setup: `Deja dans l'etat normal … rien a faire`.

---

## Tests (lan, aliases from stage 14)

| Action | Expected |
|---|---|
| `docker stop db1`, insert data in DVWA (e.g. guestbook), `docker start db1` | `quidb` → `db2` |
| `/opt/lab/retour-db1.sh` | `quidb` → `db1` |
| DVWA guestbook | Entry written during the failover is still there |
| `/opt/lab/retour-db1.sh` again | `Deja dans l'etat normal` (idempotent) |

## ⚠️ Notes

- Run it during a quiet period: writes are refused for a few seconds (step 2).
- Manual by design: an automatic failback could flap between servers. A systemd timer with a stability guard is possible later.
- MariaDB-specific (GTID commands): this is the engine-specific module of an otherwise generic design.
