# 10 · W4: Duplicating the WAF on waf2

| | |
|---|---|
| **Objective** | Make waf2 strictly identical to waf1: configuration, certificate **and** key (the lab CA stays on waf1) |
| **Where** | waf1 → waf2 |
| **Before** | Stages 07 to 09 on waf1; CA installed on the host (stage 09); image `owasp/modsecurity-crs:nginx` present on waf2 |
| **After** | waf2 filters and distributes like waf1, with the same TLS identity |

Why the **same** certificate: both WAF nodes will share the VIP (W5). With two different certificates, the client would see the site's identity change at every failover.

Why the same configuration works: nginx targets **addresses** (10.0.1.2, 10.0.2.2); each VM finds its own interface through its routing table (on waf2, front2 = ens161, not ens256: irrelevant).

---

## Method: pack, send, unpack

```
waf1: /opt/waf ──tar──► /tmp/waf.tar.gz ══scp (SSH, encrypted)══► waf2: /tmp/waf.tar.gz ──tar -x──► /opt/waf
```
- `/opt`: location of applications installed outside system packages.
- `/tmp`: temporary staging area, writable by every account. Required because the transfer arrives on waf2 with a non-root account, which cannot write to `/opt`.

⚠️ After stage 13 (firewall), SSH between the nodes is refused: copy through the admin host instead, then compare `sha256sum` on both nodes.

## 1. Pack (waf1, root)

```bash
tar -czpf /tmp/waf.tar.gz -C /opt waf && chmod 600 /tmp/waf.tar.gz && tar -tzvf /tmp/waf.tar.gz
```
| Option | Role |
|---|---|
| `-c` / `-x` / `-t` | Create / extract / list |
| `-z` | gzip compression |
| `-p` | Preserves **permissions** (key in 600) |
| `-f <file>` | Archive name |
| `-C /opt waf` | Moves into `/opt` and packs `waf/` (relative paths) |
| `-v` | Details: permissions, owner, size |
| `chmod 600` | The archive contains the **private key** |

Only `/opt/waf` is packed: `/root/lab-ca` (and `ca.key`) never leaves waf1.

**Expected**: `waf/certs/latifa.key` in `-rw-------` with `101/ssh_keys`. This is normal: gid 101 is named `ssh_keys` on waf1; only the **numbers** matter.

## 2. Send (waf1)

```bash
scp /tmp/waf.tar.gz <user>@192.168.80.12:/tmp/
```
`yes` on the first connection (waf2's fingerprint), then the account password. Expected: `100%`.

## 3. Unpack (waf2, root)

```bash
tar -xzpf /tmp/waf.tar.gz -C /opt --numeric-owner && ls -ln /opt/waf /opt/waf/certs
```
- `--numeric-owner`: restores the **exact** uid/gid (101) without going through waf2's names.
- **Expected**: `latifa.key` in `-rw-------` `101 101`.

## 4. Start (waf2)

```bash
cd /opt/waf && docker compose up -d && docker compose ps
```
Expected: `(healthy)`.

## 5. Clean up (waf1 **and** waf2)

```bash
rm -f /tmp/waf.tar.gz
```
No copy of the private key must be left behind.

---

## Tests

| Test | Where | Command | Expected |
|---|---|---|---|
| Identical files | waf1 then waf2 | `sha256sum /opt/waf/docker-compose.yml /opt/waf/nginx/default.conf.template /opt/waf/certs/latifa.crt /opt/waf/certs/latifa.key` | **4 identical hashes** on both nodes |
| Same certificate served | waf1 | `for ip in 192.168.80.11 192.168.80.12; do echo -n "$ip  "; openssl s_client -connect $ip:443 </dev/null 2>/dev/null \| openssl x509 -noout -fingerprint -sha256; done` | **identical fingerprints** |
| Trusted certificate | host | `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" --resolve www.latifa.test:443:192.168.80.12 https://www.latifa.test/login.php` | `200` |
| HTTP redirected | host | `curl.exe -sI http://192.168.80.12/login.php \| Select-String "^HTTP\|^location"` | `301` |
| Injection | host | `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" --resolve www.latifa.test:443:192.168.80.12 "https://www.latifa.test/login.php?id=1'%20OR%20'1'='1"` | `403` |
| waf2 reaches both apps | host + lan | `curl.exe -sS --ssl-no-revoke -o NUL -D - --resolve www.latifa.test:443:192.168.80.12 https://www.latifa.test/login.php \| Select-String "x-backend"`; `docker stop app1`; run again; `docker start app1` | `10.0.1.2:80` → `10.0.1.2:80, 10.0.2.2:80` → `10.0.1.2:80` |
| Path to app2 | waf1 / waf2 | `ip route get 10.0.2.2` | waf1: `dev ens256 src 10.0.2.3` · waf2: `dev ens161 src 10.0.2.4` |
| Which node answered | waf1 and waf2 | `docker compose logs -f --tail 0 waf` in two windows, then curl to .12 | only **waf2**'s window reacts |

`--resolve` sends the name to waf2 for one command only, without editing the `hosts` file.

During the app1 outage, the double attempt (`10.0.1.2:80, 10.0.2.2:80`) appears several times: app1 is only removed after **3 failures** (`max_fails=3`).

Snapshots **`waf1-w4-ok`**, **`waf2-w4-ok`**.

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| `curl.exe: command not found` on a VM | Windows command typed in Linux | PowerShell on the host; on Linux: `curl` |
| `ssh root@…` refused | Direct root SSH disabled | `<user>@…`, then `su -` |
| `tar: … Cannot open: File exists` on waf2 | Extraction run as the normal account (`$` prompt) | `su -` (`#` prompt), then extract again |
