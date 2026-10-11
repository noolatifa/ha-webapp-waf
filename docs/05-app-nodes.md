# 05 · Application Nodes (app1, app2): DVWA and Local HAProxy

| | |
|---|---|
| **Objective** | Two independent application VMs, each with DVWA and its own SQL entry point to the Galera cluster |
| **Where** | app1, then app2, as root |
| **Before** | Stages 03 and 04 (cluster `Synced`, users created) |
| **After** | DVWA answers `200` on `10.0.1.2` and `10.0.2.2`, only from the WAF nodes; each app uses db1, db2 if db1 fails |

---

## Principle

```
waf1/waf2 ──front1──► app1 (10.0.1.2) ── DVWA ──► 127.0.0.1:3306 HAProxy ──net-data──► db1 (active) / db2 (backup)
waf1/waf2 ──front2──► app2 (10.0.2.2) ── DVWA ──► 127.0.0.1:3306 HAProxy ──net-data──► db1 (active) / db2 (backup)
```
| Choice | Reason |
|---|---|
| DVWA accepts a single database host | A local proxy gives it failover without any code change |
| One HAProxy **per application node**, on `127.0.0.1` | No shared proxy, no virtual IP, no new single point of failure: if an app node fails, its proxy fails with it, and nothing else depends on it |
| db1 active, db2 `backup` | All writes on one node: no write conflicts between Galera nodes (recommended practice) |
| `network_mode: host` for DVWA | The container uses the VM's interfaces: firewalld filters port 80 (no Docker NAT rules bypassing the host firewall) |

---

## 1. Packages (app1)

```bash
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin haproxy galera
systemctl enable --now docker
docker pull ghcr.io/digininja/dvwa:latest
```
- `haproxy`: local SQL proxy (2.8, RHEL AppStream).
- `galera`: provides the arbitrator `garbd`, used on app1 only (stage 06).

## 2. HAProxy

[`configs/app/haproxy.cfg`](../configs/app/haproxy.cfg) → `/etc/haproxy/haproxy.cfg`
```
listen mariadb
    bind 127.0.0.1:3306
    option mysql-check user haproxy_check post-41
    option redispatch
    server db1 10.0.3.2:3306 check inter 2s fall 2 rise 5 on-marked-down shutdown-sessions
    server db2 10.0.3.3:3306 check inter 2s fall 2 rise 5 backup on-marked-down shutdown-sessions

listen stats
    bind 127.0.0.1:8404
    mode http
    stats enable
    stats uri /stats
```
| Directive | Role |
|---|---|
| `bind 127.0.0.1` | Reachable from the node itself only |
| `mysql-check user haproxy_check post-41` | Real MariaDB login handshake, not just an open port |
| `inter 2s fall 2` | Server marked DOWN after ~4 s |
| `rise 5` | A returning node must pass 5 checks (~10 s) before receiving traffic |
| `backup` | db2 is used only while db1 is DOWN; when db1 is back, traffic returns to it (safe: Galera nodes hold the same data) |
| `on-marked-down shutdown-sessions` | Connections to a failed node are cut, clients reconnect to the other one |
| `listen stats` | CSV status for the dashboard (stage 16) |

```bash
setsebool -P haproxy_connect_any 1
systemctl enable --now haproxy
curl -s "http://127.0.0.1:8404/stats;csv" | cut -d, -f1,2,18 | grep mariadb
```
- `haproxy_connect_any`: SELinux lets HAProxy connect to the database port and bind the stats port.
- **Expected**: `mariadb,db1,UP` and `mariadb,db2,UP`.

## 3. Firewall: HTTP from the WAF nodes only

```bash
for w in 10.0.1.3 10.0.1.4; do firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$w service name=http accept"; done
firewall-cmd --reload
```
On app2: `10.0.2.3` and `10.0.2.4`.

## 4. DVWA

```bash
mkdir -p /opt/app && cd /opt/app
read -rsp 'dvwa password: ' P && printf 'DB_APP_PASSWORD=%s\n' "$P" > .env && unset P && chmod 600 .env
```
- `read -rsp`: reads the password without echoing it (`-s`) and without interpreting backslashes (`-r`).
- ⚠️ Paste this line **alone**: in a pasted block, the next line would be read as the password.
- `.env`: read by Docker Compose, root only, never committed ([`configs/app/env.example`](../configs/app/env.example)).

Files from [`configs/app/`](../configs/app/): `docker-compose.yml` and `status.php` → `/opt/app/` (the session files are added in stage 14).
```yaml
name: app
services:
  dvwa:
    image: ghcr.io/digininja/dvwa:latest
    container_name: dvwa
    restart: unless-stopped
    network_mode: host
    environment:
      DB_SERVER: 127.0.0.1
      DB_DATABASE: dvwa
      DB_USERNAME: dvwa
      DB_PASSWORD: ${DB_APP_PASSWORD}
    volumes:
      - ./status.php:/var/www/html/status.php:ro,z
```
```bash
chmod 644 status.php
docker compose config -q && docker compose up -d && docker compose ps
```

## 5. app2

Full clone of app1, new identity (stage 02), then:
- `hostnamectl set-hostname app2`;
- front interface on **front2**, profile renamed `front2`, address `10.0.2.2/29`; net-data `10.0.3.6/28` (stage 03);
- HTTP rules from `10.0.2.3` and `10.0.2.4` instead of `10.0.1.3` / `10.0.1.4`;
- the arbitrator runs on app1 only: if app2 was cloned after stage 06, run `systemctl disable --now garbd` and remove the 4567/tcp rules from `10.0.3.2` / `10.0.3.3`.

---

## Tests

| From | Command | Expected |
|---|---|---|
| waf1 | `curl -s -o /dev/null -w '%{http_code}\n' http://10.0.1.2/login.php` (then `10.0.2.2`) | `200` |
| waf1 | `curl -s http://10.0.1.2/status.php` | `{"app":"app1","db_active":"db1","db":{"db1":"UP","db2":"UP"}}` |
| waf1 | `curl -s http://10.0.2.2/status.php` | Same with `app2` |
| host | `https://www.latifa.test/setup.php` → **Create / Reset Database** | DVWA tables created (once, replicated by Galera) |

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| `db1,DOWN` and `db2,DOWN` in the stats | SELinux denial, or `haproxy_check` user missing for this node's address | `setsebool -P haproxy_connect_any 1`; check `mysql.user` on db1 |
| DVWA unreachable from the WAF nodes | firewalld rule missing, or WAF VMs powered off | `firewall-cmd --list-rich-rules` |
| Wrong password stored in `.env` | Block pasted with the `read` line | Paste `read` alone, recreate the container with `docker compose up -d --force-recreate` |
