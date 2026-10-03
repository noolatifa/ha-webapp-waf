# 13 · W6: Host Firewall

| | |
|---|---|
| **Objective** | SSH from the admin host only; HTTP/HTTPS for clients; VRRP from the peer |
| **Where** | waf1, then waf2 (root) |
| **Before** | Stage 12 |
| **After** | SSH refused from any other source |

## 1. Find the admin address (any node)

```bash
ss -tn state established '( sport = :22 )'
```
Peer Address = host VMnet2 address, here `192.168.80.254`.

## 2. Allow SSH from the admin (each node)

```bash
firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="192.168.80.254" service name="ssh" accept' && firewall-cmd --reload
```
Open a new SSH session from the host to confirm access before step 3.

## 3. Remove the open services (each node)

```bash
firewall-cmd --permanent --zone=public --remove-service=ssh --remove-service=cockpit && firewall-cmd --reload
firewall-cmd --zone=public --list-all
```
**Expected**: `services: dhcpv6-client`, two rich rules (VRRP, admin SSH).

Snapshots **`waf1-w6-ok`**, **`waf2-w6-ok`**.

## Tests

| From | Command | Expected |
|---|---|---|
| host | `Test-NetConnection 192.168.80.11 -Port 22 \| Select-Object TcpTestSucceeded` (then `.12`) | `True` |
| waf2 | `timeout 3 bash -c '</dev/tcp/192.168.80.11/22' && echo OPEN \|\| echo CLOSED` | `CLOSED` |
| host | `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" https://www.latifa.test/login.php` | `200` |
| waf2 | `timeout 3 bash -c '</dev/tcp/10.0.1.3/443' && echo OPEN \|\| echo CLOSED` | `OPEN` (Docker) |

## ⚠️ Notes

- Keep an SSH session open during step 3; the VMware console remains available if access is lost.
- Docker-published ports (80/443) bypass firewalld; filtering them requires the `DOCKER-USER` chain (V2).
- SSH between nodes is now refused: copy files through the host.