# 17 · V2: Scheduled Database Backups

| | |
|---|---|
| **Objective** | Daily, dated, restorable copy of the application database |
| **Where** | lan, as root |
| **Before** | Stage 14 |
| **After** | Dump every night at 02:00 from db2, 7-day retention, files readable by root only |

Replication protects against a server failure, not against an error: a `DROP TABLE` reaches db2 within milliseconds. A backup is a frozen copy to go back in time.

---

## 1. Script

[`configs/lan/backup/backup-db.sh`](../configs/lan/backup/backup-db.sh) → `/usr/local/sbin/backup-db.sh`
```bash
#!/bin/bash
set -euo pipefail
umask 077
D=/opt/lab/backups
mkdir -p "$D"
F="$D/dvwa-$(date +%F-%H%M).sql"
trap 'rm -f "$F"' ERR
docker exec db2 sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --databases dvwa' > "$F"
find "$D" -name 'dvwa-*.sql' -mtime +7 -delete
```
```bash
chmod 700 /usr/local/sbin/backup-db.sh
```
| Element | Role |
|---|---|
| `docker exec db2` | Dump from the replica: no load on the active database |
| `umask 077` | Directory and files created `700` / `600` from the start |
| `trap … ERR` | A failed dump is deleted, never kept as a partial file |
| `MYSQL_PWD` | Password not visible in the process list |
| `--single-transaction` | Consistent snapshot without locking InnoDB tables |
| `-mtime +7 -delete` | Rotation: 7 days kept |

## 2. systemd service and timer

[`backup-db.service`](../configs/lan/backup/backup-db.service), [`backup-db.timer`](../configs/lan/backup/backup-db.timer) → `/etc/systemd/system/`
```bash
systemctl daemon-reload && systemctl enable --now backup-db.timer && systemctl start backup-db.service
```
- `Type=oneshot`: a task that ends, not a daemon.
- `OnCalendar=*-*-* 02:00:00`, `Persistent=true`: runs at the next boot if the VM was off at 02:00.

---

## Tests (lan)

| Command | Expected |
|---|---|
| `systemctl list-timers backup-db.timer` | `NEXT` = next 02:00 |
| `ls -lh /opt/lab/backups` | `dvwa-YYYY-MM-DD-HHMM.sql`, `-rw-------` |
| `grep -c "INSERT INTO" /opt/lab/backups/*.sql` | > 0 |
| `journalctl -u backup-db.service -n 5` | `Finished` / `Deactivated successfully` |

Restore (maintenance window, into the active database, here db1; the change replicates to db2):
```bash
docker exec -i db1 sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < /opt/lab/backups/dvwa-<date>.sql
```

## ⚠️ Notes

- Backups stay on the lan VM and are not encrypted (see stage 18).
- The dump uses the MariaDB `root` account; a dedicated read-only backup user is planned.
- `backups/` is excluded from Git.
