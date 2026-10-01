# 07 · W1: nginx as a Load Balancer

| | |
|---|---|
| **Objective** | waf1 distributes traffic between app1 and app2, removes a failed app, keeps each client on the same app |
| **Where** | waf1, as root, in `/opt/waf` |
| **Before** | Stage 05 (app1 and app2 answer from waf1); image `owasp/modsecurity-crs:nginx` available |
| **After** | `waf` container `(healthy)`, failover and sticky sessions validated. ModSecurity still **disabled** |

---

## The image used

`owasp/modsecurity-crs:nginx` = nginx + ModSecurity v3 + OWASP Core Rule Set, maintained by the OWASP project.
Documentation: https://github.com/coreruleset/modsecurity-crs-docker — what matters here:

| Characteristic | Consequence |
|---|---|
| nginx runs as an **unprivileged user** (uid 101) | It listens on **8080 / 8443** (impossible below 1024) → publish `80:8080` and `443:8443` |
| Configuration **generated from templates** at startup | Mount our file in `/etc/nginx/templates/conf.d/…template`, otherwise it is overwritten |
| Built-in healthcheck | Queries `https://localhost:8443/healthz` → an 8443 `server` block is **required** |
| Self-signed certificate generated on first start | `/etc/nginx/conf/server.crt` and `.key` (replaced in W3) |

---

## 1. Files

```bash
mkdir -p /opt/waf/nginx && cd /opt/waf
```

`/opt/waf/docker-compose.yml`:
```yaml
name: wafconf

services:
  waf:
    image: owasp/modsecurity-crs:nginx
    restart: unless-stopped
    environment:
      MODSEC_RULE_ENGINE: "Off"
    ports:
      - "80:8080"
      - "443:8443"
    volumes:
      - ./nginx/default.conf.template:/etc/nginx/templates/conf.d/default.conf.template:ro,z
```
- Service named `waf` (generic): **identical on waf1 and waf2**, same commands everywhere.
- `"Off"` **in quotes**: without them, YAML reads `Off` as the boolean `false`.

`/opt/waf/nginx/default.conf.template` (W1 version):
```nginx
upstream apps {
    server 10.0.1.2:80 max_fails=3 fail_timeout=10s;
    server 10.0.2.2:80 max_fails=3 fail_timeout=10s;
}

server {
    listen 8080;
    location / {
        proxy_pass http://apps;
        proxy_set_header Host            $host;
        proxy_set_header X-Real-IP       $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        add_header X-Backend $upstream_addr always;
        include includes/location_common.conf;
    }
}

server {
    listen 8443 ssl;
    ssl_certificate     /etc/nginx/conf/server.crt;
    ssl_certificate_key /etc/nginx/conf/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://apps;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        add_header X-Backend $upstream_addr always;
        include includes/location_common.conf;
    }
}
```
| Directive | Role |
|---|---|
| `upstream apps` | The group of servers behind the load balancer |
| `max_fails=3 fail_timeout=10s` | After 3 failures, the app is removed for 10 s, then retried (automatic reintegration) |
| `proxy_pass http://apps` | Forwards the request to the group |
| `X-Real-IP`, `X-Forwarded-For` | The app sees the client's real IP, not the WAF's |
| `X-Forwarded-Proto https` | The app knows the client arrived over HTTPS |
| `add_header X-Backend $upstream_addr always` | Shows which app answered. ⚠️ **Test aid**: exposes internal addresses, to be removed in W7 |
| `include includes/location_common.conf` | Common settings provided by the image |
| `ssl_protocols TLSv1.2 TLSv1.3` | Rejects SSLv3, TLS 1.0 and 1.1 |

Without `hash` (see §3), distribution is **round-robin**: each request goes alternately to app1, then app2.

## 2. Start

```bash
docker compose up -d && docker compose exec waf nginx -t && docker compose ps
```
- `nginx -t`: checks the syntax of the generated configuration.
- **Expected**: `syntax is ok`, then `(healthy)` after a few seconds.

**Tests from the host (PowerShell)**:
```
1..4 | ForEach-Object { curl.exe -s -o NUL -D - http://192.168.80.11/login.php | Select-String "x-backend" }
```
- `-D -` displays the headers; `Select-String` keeps the `X-Backend` line.
- **Expected**: alternating `10.0.1.2:80` / `10.0.2.2:80`.

**Failover**: on lan `docker stop app1`, run the command again → `10.0.2.2:80`, sometimes `10.0.1.2:80, 10.0.2.2:80` (attempt on app1, failure, retry on app2 **with no error for the client**). Then `docker start app1`, wait ~15 s → app1 reintegrated.

---

## 3. Sticky sessions

**The round-robin problem**: the DVWA session is stored **in the app**. If the next click lands on the other app, that app does not know the session → back to the login page on every click.

Add as the first line of `upstream apps`:
```nginx
    hash $remote_addr consistent;
```
then `docker compose restart waf` (or `up -d --force-recreate`).

- `hash $remote_addr`: the client's **full IP address** always selects the same app. The order of arrival does not matter.
- `consistent`: if an app fails, **only its clients** are moved; the others stay where they are.
- Why not `ip_hash`: it only uses the **first 3 octets** → every `192.168.80.x` client would land on the same app.

**Test**: from the host, always the same app (here `10.0.1.2`); from waf1 (`curl -s -o /dev/null -D - http://192.168.80.11/login.php | grep -i x-backend`), always the other one (here `10.0.2.2`).

| Situation | Site available | Session preserved |
|---|---|---|
| 2 apps up, with `hash` | Yes | Yes |
| 2 apps up, without `hash` | Yes | No: logged out on every click |
| app1 fails → its clients move to app2 | Yes | No: one re-login |
| Clients already on app2 | Yes | Yes |
| app1 comes back → its clients return to it | Yes | No: one re-login |

> HA guarantees **availability**, not **session continuity**. V2: shared sessions (Redis or shared volume).

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| Container `unhealthy` (exit code 7) | The healthcheck targets 8443, only 8080 was configured | Add the 8443 ssl `server` block |
| Configuration ignored | File mounted in `conf.d` instead of `templates/` | Mount in `/etc/nginx/templates/conf.d/` |
| `MODSEC_RULE_ENGINE` misread | YAML boolean | Quotes |
