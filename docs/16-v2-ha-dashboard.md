# 16 · V2: High-Availability Dashboard

| | |
|---|---|
| **Objective** | Show live which WAF holds the VIP, which application serves the client, which database is active, and log every switch |
| **Where** | lan (`/opt/lab`), waf1 then waf2 (`/opt/waf`), as root |
| **Before** | Stages 13 and 14 |
| **After** | `https://www.latifa.test/dashboard`, admin host only, refreshed every second |

---

## Principle

| Card | Source |
|---|---|
| WAF | `/status/waf` on the VIP (active node) and on `.11` / `.12` (each node) |
| Applications | `/status/app1`, `/status/app2` (each app), `/status.php` through the load balancer (app serving the client) |
| Database | `status.php`: `SELECT @@server_id` through `db`, and HAProxy stats CSV |
| Switch log | Any state change, stored in the browser (`localStorage`, 200 entries), **Effacer** button to clear |

All dashboard routes are restricted to the admin host `192.168.80.254`.

---

## 1. Status page on the applications (lan)

```bash
mkdir -p /opt/lab/status
```
[`configs/lan/status/status.php`](../configs/lan/status/status.php) → `/opt/lab/status/status.php`, then in **app1 and app2**:
```yaml
    volumes:
      - ./status/status.php:/var/www/html/status.php:ro,z
```
```bash
chmod 644 /opt/lab/status/status.php && cd /opt/lab && docker compose up -d app1 app2
```
Test from waf1: `curl -s http://10.0.1.2/status.php` → `{"app":"app1","db_active":"db1","db":{"db1":"UP","db2":"UP"}}` (same with `10.0.2.2` → `app2`).

---

## 2. WAF nodes (waf1, then waf2)

Files from the admin host (copy through the host, see stage 13):
| Repository | Node |
|---|---|
| [`configs/waf/dashboard/index.html`](../configs/waf/dashboard/index.html) | `/opt/waf/dashboard/index.html` |
| [`configs/waf/nginx/default.conf.template`](../configs/waf/nginx/default.conf.template) | `/opt/waf/nginx/default.conf.template` |
| [`configs/waf/docker-compose.yml`](../configs/waf/docker-compose.yml) | `/opt/waf/docker-compose.yml` |

Node name (different on each node):
```bash
cd /opt/waf && echo "NODE_NAME=waf1" > .env && chmod 600 .env      # waf2 on the second node
chmod 755 dashboard && chmod 644 dashboard/index.html nginx/default.conf.template
docker compose up -d && sleep 20 && docker compose exec waf nginx -t && docker compose ps
sha256sum nginx/default.conf.template dashboard/index.html docker-compose.yml
```
**Expected**: `test is successful`, `(healthy)`, identical hashes on both nodes.

Template additions (inside the `8443` server):
| Route | Role |
|---|---|
| `location = /dashboard` | Serves `index.html`; `allow 192.168.80.254; deny all` |
| `location = /status/waf` | Returns `{"node":"${NODE_NAME}"}`; admin check with `if`, because `allow/deny` does not apply to `return` |
| `location = /status.php` | Through the `apps` upstream: the app that serves this client |
| `location = /status/app1`, `/status/app2` | Direct to each app, 2 s / 3 s timeouts |

Compose additions: `NODE_NAME: ${NODE_NAME}` and the `./dashboard:/etc/nginx/dashboard:ro,z` volume.

⚠️ Replacing a single bind-mounted file with `sed -i` keeps the old file in the container: restart the container after editing.

Snapshots **`waf1-v2-dash`**, **`waf2-v2-dash`**.

---

## Tests (admin host browser, dashboard open)

| Action | Expected on the dashboard |
|---|---|
| Open the page | waf1 active · app1 · db1 · all `UP` |
| lan: `docker stop app1` / `start` | ~6 s: app1 `DOWN`, served by app2 / back `UP` |
| lan: `docker stop db1` / `start`, then `/opt/lab/retour-db1.sh` | db1 `DOWN`, active db2 / db1 `UP`, still db2 / active db1 |
| VMware: power off waf1 / on | ~3 s: active waf2, waf1 `DOWN` / waf1 active again |
| Refresh (F5) | Switch log kept |
| Another client IP | `403` on `/dashboard` |

## ⚠️ Notes

- The switch log lives in one browser only; server-side history: `journalctl -u keepalived`, HAProxy and nginx logs.
- Load-balancing proof without exposing a header: `docker logs -f waf 2>&1 | grep --line-buffered -- "->"` on the active WAF (format `client -> upstream`).
