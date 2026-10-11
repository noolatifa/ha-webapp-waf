# 15 · V3 Failover Test Campaign

| | |
|---|---|
| **Objective** | Prove that the loss of any single VM leaves the service available, without data loss and without logging users out |
| **Where** | VMware (power operations), admin host browser, db1 / db2 shells |
| **Before** | Stages 01 to 14; snapshot of the 6 VMs |
| **After** | Every single-VM failure case tested |

## Preparation

1. Snapshot all 6 VMs.
2. Browser on the admin host: DVWA logged in at `https://www.latifa.test`, dashboard open in a second tab (`/dashboard`), switch log cleared (**Effacer**).
3. Shell on db1 and db2 with this helper:
```bash
alias gal="mysql -e \"SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_cluster_status','wsrep_local_state_comment');\""
```
Normal state: `3`, `Primary`, `Synced`.

---

## Test matrix

| # | Failure | Action | Expected | Result |
|---|---|---|---|---|
| T1 | Application node serving the client | `poweroff` on it (dashboard shows which one) | ~10 s: the other node serves; **user still logged in** (stage 14) | Validated |
| T2 | Active database db1 | `poweroff` db1, write a guestbook entry (**XSS (Stored)**) | ~4 s: HAProxy on both apps switches to db2; entry stored; db2 `gal` → `2`, `Primary` | Validated |
| T2b | db1 returns | Power on db1, wait ~1 min | db1 `gal` → `3`, `Synced`; the entry written during the failure is on db1 (IST); traffic back on db1 after ~10 s | Validated |
| T3 | Standby database db2 | `poweroff` db2, write `t3` in the guestbook, power on | No visible change; db2 back `Synced` with `t3` | To run |
| T4 | Arbitrator (app1) | `poweroff` app1 | db1 `gal` → `2`, `Primary`; app2 serves; back to `3` when app1 boots | Validated |
| T5 | Abrupt loss of db1 | VMware **Power Off** (no clean shutdown) | Same as T2; db1 rejoins by itself | To run |
| T6 | Active WAF waf1 | VMware **Power Off** waf1 | ~3 s: VIP on waf2, site available; waf1 takes the VIP back when powered on (priority 150) | Validated |
| T7 | Attack | DVWA **SQL Injection**, User ID `1' OR '1'='1` | `403` from ModSecurity | Validated |

Checks for T2 / T3 (on the surviving node, then on the returning node):
```bash
gal ; mysql -e "SELECT name, comment FROM dvwa.guestbook;"
```

## Proof that the WAF is the protection

DVWA is vulnerable on purpose. From waf1, bypassing nginx, with the session cookie copied from the browser (F12 → Application → Cookies):
```bash
curl -s -b "PHPSESSID=<session id>; security=low" "http://10.0.1.2/vulnerabilities/sqli/?id=1'+OR+'1'%3D'1&Submit=Submit" | grep -o "First name: [^<]*"
```
- **Expected**: 5 `First name:` lines (all users dumped).
- The same request through `https://www.latifa.test` returns `403`.

## Out of scope: two simultaneous failures

The design tolerates **one** failure per tier. Losing db1 and db2 together, or one database node and app1 (the arbitrator) together, leaves fewer than 2 votes of 3: the remaining database node stops accepting queries to protect the data. Recovery: stage 17.
