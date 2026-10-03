# 12 · W5: Virtual IP with keepalived

| | |
|---|---|
| **Objective** | VIP `192.168.80.100` held by one WAF node, moved on node or WAF failure |
| **Where** | waf1 and waf2 (root), host |
| **Before** | Stage 10 (both nodes identical) |
| **After** | waf1 MASTER, waf2 BACKUP; automatic failover and return |

## 1. Install (both nodes)

```bash
dnf install -y keepalived
```

## 2. Allow VRRP from the peer

waf1:
```bash
firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="10.0.1.4" protocol value="vrrp" accept' && firewall-cmd --reload
```
waf2:
```bash
firewall-cmd --permanent --zone=public --add-rich-rule='rule family="ipv4" source address="10.0.1.3" protocol value="vrrp" accept' && firewall-cmd --reload
```

## 3. WAF health check (both nodes)

```bash
mkdir -p /usr/libexec/keepalived
cat > /usr/libexec/keepalived/check_waf.sh <<'EOF'
#!/bin/bash
[ "$(docker inspect -f '{{.State.Running}} {{.State.Health.Status}}' waf 2>/dev/null)" = "true healthy" ]
EOF
chmod 700 /usr/libexec/keepalived/check_waf.sh && restorecon -Rv /usr/libexec/keepalived
/usr/libexec/keepalived/check_waf.sh; echo "code: $?"
```
**Expected**: `code: 0`. The script must stay in `/usr/libexec/keepalived/` (SELinux).

## 4. Configuration

Replace `/etc/keepalived/keepalived.conf` entirely.

waf1:
```
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_waf {
    script "/usr/libexec/keepalived/check_waf.sh"
    interval 2
    fall 2
    rise 2
}

vrrp_instance VI_WAF {
    state MASTER
    interface ens224
    virtual_router_id 51
    priority 150
    advert_int 1
    unicast_src_ip 10.0.1.3
    unicast_peer {
        10.0.1.4
    }
    virtual_ipaddress {
        192.168.80.100/24 dev ens160
    }
    track_script {
        chk_waf
    }
}
```

waf2:
```
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_waf {
    script "/usr/libexec/keepalived/check_waf.sh"
    interval 2
    fall 2
    rise 2
}

vrrp_instance VI_WAF {
    state BACKUP
    interface ens224
    virtual_router_id 51
    priority 100
    advert_int 1
    unicast_src_ip 10.0.1.4
    unicast_peer {
        10.0.1.3
    }
    virtual_ipaddress {
        192.168.80.100/24 dev ens160
    }
    track_script {
        chk_waf
    }
}
```

## 5. Start (waf1, then waf2)

```bash
keepalived -t -f /etc/keepalived/keepalived.conf && systemctl enable --now keepalived
ip -br addr show ens160
```
**Expected**: waf1 shows `192.168.80.11/24 192.168.80.100/24`; waf2 shows `192.168.80.12/24` only.

## 6. Point the name to the VIP (host)

PowerShell as administrator: in `C:\Windows\System32\drivers\etc\hosts`, replace `192.168.80.11 www.latifa.test` with:
```
192.168.80.100 www.latifa.test
```
then `ipconfig /flushdns`.

Snapshots **`waf1-w5-ok`**, **`waf2-w5-ok`**.

## Tests

Host loop during the tests:
```
while ($true) { curl.exe -sS --ssl-no-revoke --max-time 2 -o NUL -w "%{http_code} " https://www.latifa.test/login.php; Get-Date -Format HH:mm:ss; Start-Sleep 1 }
```

| Action | Expected |
|---|---|
| `systemctl stop keepalived` on waf1 | waf2 MASTER, loop stays `200` |
| `systemctl start keepalived` on waf1 | waf1 MASTER again |
| VMware power off waf1 | waf2 MASTER after ~3 s |
| VMware power on waf1 | waf1 MASTER again, no command |
| `docker compose -f /opt/waf/docker-compose.yml stop waf` on waf1 | waf1 FAULT, waf2 MASTER (`start` to revert) |

Follow the state on waf2 with `journalctl -u keepalived -f`.

## ⚠️ Notes

- Do not keep the package sample: `vrrp_strict` blocks the VIP, `virtual_server` duplicates nginx.
- Both nodes MASTER = VRRP blocked or peer addresses not swapped.
- After a configuration change: `systemctl reload keepalived` (a restart releases the VIP).