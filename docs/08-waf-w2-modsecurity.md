# 08 · W2: ModSecurity + OWASP CRS

| | |
|---|---|
| **Objective** | Enable the web application firewall: detect, then block web attacks |
| **Where** | waf1, `/opt/waf`; attacks from the host |
| **Before** | Stage 07 |
| **After** | Normal traffic → 200, SQL injection → 403, alerts logged |

---

## Principle

| `MODSEC_RULE_ENGINE` mode | Behaviour |
|---|---|
| `"Off"` | No inspection |
| `"DetectionOnly"` | Inspects and **logs**, blocks nothing |
| `"On"` | Inspects, logs and **blocks** (403) |

**Progressive activation** (professional practice): `DetectionOnly` first, to check that the WAF **sees** the attacks **without disturbing** legitimate traffic; then `On`.

**Anomaly scoring (CRS)**: each triggered rule adds points (rules `942xxx` = SQL injection). If the score exceeds the threshold, rule **949110** ("Inbound Anomaly Score Exceeded") blocks. A single weak indicator is not enough → fewer false positives.

---

## W2.1: DetectionOnly

In `docker-compose.yml` (with vim: `/MODSEC`, cursor on the value, `cw`, type, `Esc`, `:wq`):
```yaml
      MODSEC_RULE_ENGINE: "DetectionOnly"
```
```bash
grep MODSEC docker-compose.yml && docker compose up -d && docker compose ps
```
Compose detects the environment change and **recreates** the container. Expected: `(healthy)`.

**Tests (host, PowerShell)**:
```
curl.exe -s -o NUL -w "%{http_code}\n" "http://192.168.80.11/login.php"
curl.exe -s -o NUL -w "%{http_code}\n" "http://192.168.80.11/login.php?id=1'%20OR%20'1'='1"
```
- `-s` silent · `-o NUL` discards the page · `-w "%{http_code}\n"` displays only the HTTP code.
- `%20` = encoded space → the injection is `1' OR '1'='1` (always-true condition).

**Expected**: `200` and `200` (nothing is blocked).

**Did the WAF see the attack? (waf1)**
```bash
docker compose logs -t waf | grep -i "sql injection"
```
- `-t`: timestamps (in **UTC**).
- **Expected**: lines with `942…` rules.

## W2.2: On

```yaml
      MODSEC_RULE_ENGINE: "On"
```
```bash
grep MODSEC docker-compose.yml && docker compose up -d && docker compose ps
```
**Tests**: same `curl.exe` → **`200`** then **`403`**.

Additional checks:
```
curl.exe -k -s -o NUL -w "%{http_code}\n" "https://192.168.80.11/login.php?id=1'%20OR%20'1'='1"
curl.exe -s -o NUL -w "%{http_code}\n" "http://192.168.80.11/login.php?q=<script>alert(1)</script>"
```
→ `403` (injection over HTTPS) and `403` (XSS).

## Live observation

Window 1 (waf1):
```bash
docker compose logs -f --tail 0 waf
```
- `-f`: follows live · `--tail 0`: without history · `Ctrl+C` to exit.

Window 2 (host): send the injection → `942…` lines then `949110` / "Access denied with code 403" appear.

Snapshot **`waf1-w2-ok`**.

---

## ⚠️ Issues / limitations

| Point | Detail |
|---|---|
| Logs lost if the container is **recreated** | Docker logs live with the container → V3: centralisation with Wazuh |
| `Off`/`On` without quotes | Read as booleans by YAML |
