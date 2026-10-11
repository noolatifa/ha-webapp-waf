# 04 · Database: MariaDB Galera Cluster (db1, db2)

| | |
|---|---|
| **Objective** | Two database VMs in a synchronous multi-master cluster, reachable only from the application nodes |
| **Where** | db1, then db2, as root |
| **Before** | Stage 03: db1 `10.0.3.2` and db2 `10.0.3.3` on net-data, NAT adapter still attached |
| **After** | `wsrep_cluster_size = 2` (3 once the arbitrator is added, stage 06), `dvwa` database and least-privilege users |

Why Galera: every commit is certified on both nodes before it is acknowledged. No data is lost when a node fails (RPO = 0), both nodes accept writes, and a returning node catches up by itself. There is no virtual IP on the database tier: each application reaches the cluster through its own local HAProxy (stage 05).

⚠️ Clone db2 from db1 **before** section 3 (bootstrap). A node cloned after the cluster was initialised carries the same Galera state (`grastate.dat`, cluster UUID) and must be wiped.

---

## 1. Packages and SELinux (db1)

```bash
dnf install -y mariadb-server-galera rsync policycoreutils-python-utils
semanage port -l | grep mysqld_port_t
```
| Element | Role |
|---|---|
| `mariadb-server-galera` | MariaDB 10.5 + Galera 26.4 provider (RHEL AppStream) |
| `rsync` | Full state transfer (SST) to a joining node |
| `semanage port -l` | **Expected**: `mysqld_port_t … 1186, 3306, 63132-63164, 4444, 4567, 4568`: the Galera ports are already allowed by SELinux |

| Port | Use |
|---|---|
| 3306/tcp | SQL, from the application nodes |
| 4567/tcp+udp | Group communication (nodes and arbitrator) |
| 4568/tcp | Incremental state transfer (IST) |
| 4444/tcp | Full state transfer (SST) |

## 2. Galera configuration (db1)

[`configs/db/galera-db1.cnf`](../configs/db/galera-db1.cnf) → `/etc/my.cnf.d/galera.cnf`
```ini
[mysqld]
binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2
bind-address=10.0.3.2
server_id=1
wsrep_on=ON
wsrep_provider=/usr/lib64/galera/libgalera_smm.so
wsrep_cluster_name=lab_cluster
wsrep_cluster_address=gcomm://10.0.3.2,10.0.3.3
wsrep_node_name=db1
wsrep_node_address=10.0.3.2
wsrep_sst_method=rsync
```
| Directive | Role |
|---|---|
| `binlog_format=ROW`, `InnoDB`, `innodb_autoinc_lock_mode=2` | Required by Galera (row-based write sets, transactional engine, no auto-increment table lock) |
| `bind-address` | Listens on net-data only |
| `server_id` | 1 on db1, 2 on db2: lets the dashboard show which node answers |
| `wsrep_cluster_address` | The two database nodes; the arbitrator connects to them (stage 06) |
| `wsrep_sst_method=rsync` | Simple SST, no extra account needed |

## 3. Firewall (db1)

```bash
for a in 10.0.3.5 10.0.3.6; do firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$a port port=3306 protocol=tcp accept"; done
for p in 4567/tcp 4567/udp 4568/tcp 4444/tcp; do firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=10.0.3.3 port port=${p%/*} protocol=${p#*/} accept"; done
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.0.3.5 port port=4567 protocol=tcp accept'
firewall-cmd --reload && firewall-cmd --list-rich-rules
```
- 3306 only from app1 (`.5`) and app2 (`.6`).
- Galera ports only from the peer database node.
- 4567/tcp from app1: the arbitrator (stage 06).
- `${p%/*}` / `${p#*/}`: port and protocol split from `4567/tcp`.

Snapshot **`db1-pre-galera`**, then clone db2 (section 5) **before** going further.

## 4. Bootstrap the cluster and create the users (db1)

```bash
galera_new_cluster
systemctl enable mariadb
mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```
- `galera_new_cluster`: starts MariaDB as the **first** node of a new cluster. Run it **once**, on one node only (see stage 17 for restarts).
- `systemctl enable mariadb`: start at boot (joins an existing cluster).
- **Expected**: `wsrep_cluster_size 1`.

Users ([`configs/db/init-db.sql`](../configs/db/init-db.sql)), in `mysql` as root (socket authentication, no password):
```sql
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER 'dvwa'@'10.0.3.5' IDENTIFIED BY '<dvwa password>';
CREATE USER 'dvwa'@'10.0.3.6' IDENTIFIED BY '<dvwa password>';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'10.0.3.5', 'dvwa'@'10.0.3.6';
CREATE USER 'haproxy_check'@'10.0.3.5';
CREATE USER 'haproxy_check'@'10.0.3.6';
```
| User | Scope |
|---|---|
| `dvwa@10.0.3.5`, `@10.0.3.6` | The `dvwa` database only, only from the two application nodes |
| `haproxy_check` | No password, no privilege: used only by the HAProxy health check (login handshake) |

## 5. db2

Full clone of db1 (snapshot `db1-pre-galera`), then new identity (stage 02) and:
```bash
hostnamectl set-hostname db2
nmcli con mod data ipv4.addresses 10.0.3.3/28 && nmcli con up data
sed -i -e 's/^bind-address=.*/bind-address=10.0.3.3/' -e 's/^server_id=.*/server_id=2/' \
       -e 's/^wsrep_node_name=.*/wsrep_node_name=db2/' -e 's/^wsrep_node_address=.*/wsrep_node_address=10.0.3.3/' /etc/my.cnf.d/galera.cnf
```
Result: [`configs/db/galera-db2.cnf`](../configs/db/galera-db2.cnf). Firewall: same rules as db1, with the Galera ports open from `10.0.3.2` instead of `10.0.3.3`:
```bash
for p in 4567/tcp 4567/udp 4568/tcp 4444/tcp; do
  firewall-cmd --permanent --remove-rich-rule="rule family=ipv4 source address=10.0.3.3 port port=${p%/*} protocol=${p#*/} accept"
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=10.0.3.2 port port=${p%/*} protocol=${p#*/} accept"
done
firewall-cmd --reload
```
Join the cluster (full state transfer from db1):
```bash
systemctl enable --now mariadb
```

---

## Tests

| On | Command | Expected |
|---|---|---|
| db1, db2 | `mysql -e "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_local_state_comment','wsrep_cluster_status');"` | `2`, `Synced`, `Primary` |
| db2 | `mysql -e "SELECT User, Host FROM mysql.user WHERE User IN ('dvwa','haproxy_check');"` | The 4 accounts created on db1 (replicated) |
| db1 | `mysql -e "CREATE DATABASE witness;"` then on db2 `mysql -e "SHOW DATABASES LIKE 'witness';"` then `DROP DATABASE witness;` | Visible on db2 immediately |

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| db2 does not join, `grastate.dat` with the same UUID as db1 | Cloned after the bootstrap | Stop MariaDB on db2, `rm -rf /var/lib/mysql/*`, `systemctl start mariadb` (full SST) |
| SST hangs | 4444/tcp blocked or `rsync` missing | Firewall rule from the peer, `dnf install rsync` |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` on the host | New SSH host keys on the clone | `ssh-keygen -R <ip>` on the host |
