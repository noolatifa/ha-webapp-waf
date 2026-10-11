# 16 · High-Availability Dashboard

| | |
|---|---|
| **Objective** | Show live which WAF holds the VIP, which application serves the client, which database is active, and log every switch |
| **Where** | app1 and app2 (`/opt/app`), waf1 then waf2 (`/opt/waf`), as root |
| **Before** | Stages 05 and 13 |
| **After** | `https://www.latifa.test/dashboard`, admin host only, refreshed every second |

---

## Principle

| Card | Source |
|---|---|
| WAF | `/status/waf` on the VIP (active node) and on `.11` / `.12` (each node) |
| Applications | `/status/app1`, `/status/app2` (each app), `/status.php` through the load balancer (app serving the client) |
| Database | `status.php` on each app: `SELECT @@server_id` through the local HAProxy, and its stats CSV (`127.0.0.1:8404`) |
| Switch log | Any state change, stored in the browser (`localStorage`, 200 entries), **Effacer** button to clear |

All dashboard routes are restricted to the admin host `192.168.80.254`.

---

## 1. Status page on the applications (app1, app2)

[`configs/app/status.php`](../configs/app/status.php) → `/opt/app/status.php`, mounted by the Compose file of stage 05:
```yaml
    volumes:
      - ./status.php:/var/www/html/status.php:ro,z
```
- Connects to `127.0.0.1` (local HAProxy) and reads `http://127.0.0.1:8404/stats;csv`.
- `@@server_id` 1 → `db1`, 2 → `db2`.

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

V3 update of the database card text (both nodes; the `dashboard` directory is mounted, no restart needed):
```bash
sed -i 's/Aiguillage par HAProxy, réplication GTID entre db1 et db2./HAProxy local sur chaque app, cluster Galera db1 + db2 + arbitre (garbd)./' /opt/waf/dashboard/index.html
```

Snapshots **`waf1-dash`**, **`waf2-dash`**.

---

## Tests (admin host browser, dashboard open)

| Action | Expected on the dashboard |
|---|---|
| Open the page | waf1 active · app1 · db1 · all `UP` |
| `poweroff` app1 / power on | ~10 s: app1 `DOWN`, served by app2, still logged in / back `UP` |
| `poweroff` db1 / power on | ~4 s: db1 `DOWN`, active db2 / db1 `UP` and active again after ~10 s |
| VMware: power off waf1 / on | ~3 s: active waf2, waf1 `DOWN` / waf1 active again |
| Refresh (F5) | Switch log kept |
| Another client IP | `403` on `/dashboard` |

## ⚠️ Notes

- The switch log lives in one browser only; server-side history: `journalctl -u keepalived`, HAProxy and nginx logs.
- Load-balancing proof without exposing a header: `docker logs -f waf 2>&1 | grep --line-buffered -- "->"` on the active WAF (format `client -> upstream`).
