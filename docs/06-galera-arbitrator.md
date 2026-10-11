# 06 · Galera Arbitrator (garbd) on app1

| | |
|---|---|
| **Objective** | Give the two-node cluster a third vote, so that it keeps running when one database node fails |
| **Where** | app1 (arbitrator), db1 and db2 (firewall already open in stage 04), as root |
| **Before** | Stages 04 and 05 |
| **After** | `wsrep_cluster_size = 3`; the loss of any one of db1, db2, app1 leaves a majority (2 of 3) |

---

## Why an arbitrator

Galera only accepts writes in a **primary component**, a group holding more than half of the votes.

| Members | One node lost | Result |
|---|---|---|
| db1 + db2 (2 votes) | 1 of 2 left = 50 % | No majority: the survivor stops accepting queries (split-brain protection) |
| db1 + db2 + garbd (3 votes) | 2 of 3 left = 67 % | Majority: the service continues |

`garbd` is a Galera member that votes and receives the replication stream but **stores no data**: no disk, no MariaDB, a few MB of RAM.

| Placement | Decision |
|---|---|
| On a database node | Rejected: losing that VM would remove 2 votes of 3 |
| On a WAF node | Rejected: the WAF nodes are in the DMZ; the data network stays unreachable from them |
| On app1 | Chosen: already on net-data, independent from db1 and db2 |

---

## 1. Configuration (app1)

The `galera` package was installed in stage 05. [`configs/app/garb`](../configs/app/garb) → `/etc/sysconfig/garb`
```
GALERA_NODES="10.0.3.2:4567 10.0.3.3:4567"
GALERA_GROUP="lab_cluster"
```
- `GALERA_NODES`: the database nodes to contact.
- `GALERA_GROUP`: must match `wsrep_cluster_name` (stage 04).

## 2. Firewall (app1)

```bash
for d in 10.0.3.2 10.0.3.3; do firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$d port port=4567 protocol=tcp accept"; done
firewall-cmd --reload
```
The database nodes open connections back to the arbitrator. On db1 and db2, 4567/tcp from `10.0.3.5` was opened in stage 04.

## 3. Start

```bash
systemctl enable --now garbd
systemctl is-active garbd
```
⚠️ On RHEL the service is **`garbd`**; the configuration file is `/etc/sysconfig/garb` (no `d`).

---

## Tests

| On | Command | Expected |
|---|---|---|
| db1 | `mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"` | `3` |
| app1 | `journalctl -u garbd --no-pager \| tail -5` | Joined the group, state `SYNCED` |
| app1 | `poweroff`, then on db1 the same query | `2`, `wsrep_cluster_status = Primary`: service continues |
| app1 | Power on, wait ~1 min | `3` again (garbd enabled at boot) |

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| `Unit garb.service not found` | Wrong service name | `garbd` |
| Cluster stays at 2 after app1 boots | 4567/tcp blocked on app1 or on a database node | Check the rich rules on both sides |
