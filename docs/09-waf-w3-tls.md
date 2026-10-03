# 09 · W3: Secure HTTPS

| | |
|---|---|
| **Objective** | HTTPS only, certificate `www.latifa.test` signed by a lab CA and trusted by the clients |
| **Where** | waf1 (root), host (PowerShell) |
| **Before** | Stage 08 |
| **After** | HTTP → 301; padlock without warning; hardened headers |

## 1. Create the lab CA (waf1)

```bash
mkdir -m 700 /root/lab-ca && cd /root/lab-ca
openssl req -x509 -newkey rsa:4096 -keyout ca.key -out ca.crt -days 1825 -subj "/CN=HA-WAF Lab Root CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
chmod 600 ca.key
```
Choose a CA passphrase (4 characters minimum); it is asked at every signature.

## 2. Create and sign the site certificate (waf1, `/root/lab-ca`)

```bash
openssl req -new -newkey rsa:2048 -nodes -keyout latifa.key -out latifa.csr -subj "/CN=www.latifa.test"
printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:www.latifa.test,IP:192.168.80.100,IP:192.168.80.11,IP:192.168.80.12\n' > latifa.ext
openssl x509 -req -in latifa.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out latifa.crt -days 365 -sha256 -extfile latifa.ext
openssl verify -CAfile ca.crt latifa.crt
```
**Expected**: `latifa.crt: OK`.

## 3. Install the certificate for nginx (waf1)

```bash
mkdir -p /opt/waf/certs
\cp /root/lab-ca/latifa.crt /root/lab-ca/latifa.key /opt/waf/certs/
chown 101:101 /opt/waf/certs/latifa.key && chmod 600 /opt/waf/certs/latifa.key
rm -f /root/lab-ca/latifa.key /root/lab-ca/latifa.crt /root/lab-ca/latifa.csr
```
`/root/lab-ca` keeps `ca.key`, `ca.crt`, `ca.srl`, `latifa.ext` (renewal).

## 4. Configure nginx (waf1, `/opt/waf`)

`docker-compose.yml`, add under `volumes:`:
```yaml
      - ./certs:/etc/nginx/certs:ro,z
```

`nginx/default.conf.template`:
```nginx
server_tokens off;

upstream apps {
    hash $remote_addr consistent;
    server 10.0.1.2:80 max_fails=3 fail_timeout=10s;
    server 10.0.2.2:80 max_fails=3 fail_timeout=10s;
}

server {
    listen 8080;
    return 301 https://$host$request_uri;
}

server {
    listen 8443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/certs/latifa.crt;
    ssl_certificate_key /etc/nginx/certs/latifa.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://apps;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        add_header X-Backend $upstream_addr always;
        add_header Strict-Transport-Security "max-age=31536000" always;
        proxy_hide_header X-Powered-By;
        proxy_cookie_flags ~ secure;
    }

    include includes/location_common.conf;
}
```
`X-Backend` is a test aid, replaced by an access log at the end of V1. Final file: [`configs/waf/nginx/default.conf.template`](../configs/waf/nginx/default.conf.template).

```bash
cd /opt/waf && docker compose up -d && sleep 10 && docker compose exec waf nginx -t && docker compose ps
```
**Expected**: `test is successful`, `(healthy)`.

## 5. Trust the CA on the host

waf1:
```bash
cp /root/lab-ca/ca.crt /tmp/ca.crt && chmod 644 /tmp/ca.crt
```
Host:
```
scp <user>@192.168.80.11:/tmp/ca.crt $HOME\Downloads\ca.crt
Import-Certificate -FilePath $HOME\Downloads\ca.crt -CertStoreLocation Cert:\CurrentUser\Root
```
Accept the Windows warning after checking the thumbprint. Then remove `/tmp/ca.crt` (waf1) and the downloaded file.

Host, PowerShell as administrator:
```
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "192.168.80.11 www.latifa.test"
```
The name points to waf1 until stage 12 (VIP).

Snapshot **`waf1-w3-ok`**.

## Tests (host)

| Command | Expected |
|---|---|
| `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" https://www.latifa.test/login.php` | `200` |
| `curl.exe -sI http://www.latifa.test/login.php` | `301`, `Location: https://…` |
| `curl.exe -sS --ssl-no-revoke -D - -o NUL https://www.latifa.test/login.php` | `Server: nginx`, `Strict-Transport-Security`, cookies `Secure`, no `X-Powered-By` |
| `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" "https://www.latifa.test/login.php?id=1'%20OR%20'1'='1"` | `403` |
| Browser `https://www.latifa.test/login.php` | Padlock, issued by `HA-WAF Lab Root CA` |

## ⚠️ Notes

- `--ssl-no-revoke`: Windows curl checks revocation, and the lab CA publishes no revocation list.
- Run `nginx -t` only after the container has started (`sleep 10`), otherwise `RESOLVER_CONFIG` errors appear.
- If the browser still shows "Not secure", restart it (`chrome://restart`).