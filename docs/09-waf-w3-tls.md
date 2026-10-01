# 09 · W3: TLS Certificate `www.latifa.com`

| | |
|---|---|
| **Objective** | Replace the image's generic certificate with a certificate issued for the service name |
| **Where** | waf1, `/opt/waf` |
| **Before** | Stage 08 |
| **After** | The WAF presents `CN=www.latifa.com` over HTTPS; filtering still active |

---

## Key notions

> **The private key proves. The certificate presents. TLS encrypts.**

| Element | Role | Visibility |
|---|---|---|
| **TLS** (successor of SSL) | Protocol that encrypts the connection and authenticates the **server** | — |
| **Private key** (`.key`) | The only one able to decrypt what is encrypted with the public key; proves identity | **Secret**, on the server |
| **Certificate** (`.crt`) | Server name, dates, **public key**, issuer's signature | **Public**, sent to every client |
| **Self-signed** | Signed by its own key: encrypts just as well, but no authority vouches for it → browser warning | — |
| **`hosts` file** (client side, end of V1) | **Find** the server: `www.latifa.com` → VIP | On each client |

- TLS only authenticates the server (not the client: that would be mTLS).
- TLS **authorises no one**: access control is the job of the firewall and the WAF.
- **TLS termination on the WAF**: required so that ModSecurity can **read** the request.
- The image's certificate is **replaced**, not edited: the name is part of the **signed** data.

---

## 1. Create the key and the certificate

```bash
cd /opt/waf && mkdir certs
openssl req -x509 -newkey rsa:2048 -nodes -keyout certs/latifa.key -out certs/latifa.crt -days 365 -subj "/CN=www.latifa.com" -addext "subjectAltName=DNS:www.latifa.com"
```
| Option | Role |
|---|---|
| `req -x509` | Directly produces a **self-signed** certificate |
| `-newkey rsa:2048` | New 2048-bit RSA private key |
| `-nodes` | Key without a passphrase (otherwise nginx cannot start unattended) |
| `-keyout` / `-out` | Key file / certificate file |
| `-days 365` | One-year validity |
| `-subj "/CN=…"` | Server name (Common Name) |
| `-addext "subjectAltName=DNS:…"` | Name in the **SAN**, the only field read by modern browsers |

The `.+++…*` output = openssl searching for the key's prime numbers (random, expected).

**Verification**:
```bash
ls -l certs
openssl x509 -in certs/latifa.crt -noout -subject -dates -ext subjectAltName
```
- `latifa.crt` in `-rw-r--r--` (public), `latifa.key` in `-rw-------` (secret) — openssl protects the key on its own.
- `subject=CN=www.latifa.com`, one-year validity (dates in GMT), `DNS:www.latifa.com`.

## 2. Give the key to nginx (least privilege)

```bash
docker compose exec waf id
chown 101:101 certs/latifa.key
ls -ln certs
```
- nginx runs as **uid 101** inside the container.
- A Docker volume keeps the owner **numbers**: uid 101 on waf1 = uid 101 (nginx) in the container.
- The key stays in **600**: readable by nginx only (root can always read everything).
- `ls -ln`: displays the numbers (`101 101`) instead of the names.

## 3. Mount and use

`docker-compose.yml`, under `volumes:`:
```yaml
      - ./certs:/etc/nginx/certs:ro,z
```
`nginx/default.conf.template`, in the `listen 8443 ssl` block:
```nginx
    ssl_certificate     /etc/nginx/certs/latifa.crt;
    ssl_certificate_key /etc/nginx/certs/latifa.key;
```
```bash
docker compose up -d && docker compose ps
```

---

## Tests

Certificate **actually served** (waf1):
```bash
openssl s_client -connect 127.0.0.1:443 </dev/null 2>/dev/null | openssl x509 -noout -subject
```
- `s_client` acts as a TLS client · `</dev/null` ends the connection · `2>/dev/null` hides technical messages.
- **Expected**: `subject=CN=www.latifa.com`.

Host:
```
curl.exe -k -s -o NUL -w "%{http_code}\n" "https://192.168.80.11/login.php"
curl.exe -k -s -o NUL -w "%{http_code}\n" "https://192.168.80.11/login.php?id=1'%20OR%20'1'='1"
```
`-k`: accepts the self-signed certificate. **Expected**: `200` then `403`.

Snapshot **`waf1-w3-ok`**.

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| The name appears as `[www.latifa.com](https://…)` | Rich-text copy and paste turned the domain into a link | Check at the source: `openssl x509 … -subject \| grep -c "("` → `0` |
| `No such file or directory` on creation | Run from inside `certs/` (path `certs/certs/…`) | `cd ..` |
| nginx cannot read the key | Key `root:root` in 600, nginx as uid 101 | `chown 101:101` |
| Browser warning | Self-signed | Accepted (lab) · option: lab CA installed on the clients |
