# 11 · Connectivity Test Matrix

HTTPS tests use the name `www.latifa.test` (host `hosts` file, pointing to the VIP `192.168.80.100` from stage 12) and the lab CA installed on the host (stage 09). Failover tests: stage 12. Firewall tests: stage 13.

To be re-run after every network change. "From" = the machine on which the command is typed.

## Address reminder

| Machine | WAN (VMnet2) | front1 | front2 | net-data | NAT (temporary) |
|---|---|---|---|---|---|
| host | 192.168.80.254 | — | — | — | 192.168.x.1 |
| waf1 | .80.11 · ens160 | 10.0.1.3 · ens224 | 10.0.2.3 · ens256 | — | ens161 |
| waf2 | .80.12 · ens160 | 10.0.1.4 · ens224 | 10.0.2.4 · ens256 | — | ens161 |
| app1 | — | 10.0.1.2 · ens224 | — | 10.0.3.5 · ens256 | ens160 |
| app2 | — | — | 10.0.2.2 · ens224 | 10.0.3.6 · ens256 | ens160 |
| db1 / db2 | — | — | — | 10.0.3.2 / 10.0.3.3 · ens160 | ens224 |

## Tests that must succeed

| # | From | To | Command | Expected |
|---|---|---|---|---|
| 1 | host | waf1 (WAN) | `ping 192.168.80.11` | replies |
| 2 | host | waf2 (WAN) | `ping 192.168.80.12` | replies |
| 3 | host | waf1 (SSH) | `ssh <user>@192.168.80.11` | login (admin host only after stage 13) |
| 4 | host | waf2 (SSH) | `ssh <user>@192.168.80.12` | login (admin host only after stage 13) |
| 5 | waf1 | waf2 (WAN) | `ping -c 2 192.168.80.12` | replies |
| 6 | waf1 | waf2 (front1) | `ping -c 2 10.0.1.4` | replies |
| 7 | waf1 | waf2 (front2) | `ping -c 2 10.0.2.4` | replies |
| 8 | waf2 | waf1 (front1) | `ping -c 2 10.0.1.3` | replies |
| 9 | waf2 | waf1 (front2) | `ping -c 2 10.0.2.3` | replies |
| 10 | every VM | internet (NAT, temporary) | `ping -c 2 8.8.8.8` | replies |
| 11 | waf1, waf2 | app1 | `ping -c 2 10.0.1.2` | replies |
| 12 | waf1, waf2 | app2 | `ping -c 2 10.0.2.2` | replies |
| 13 | waf1, waf2 | DVWA app1 | `curl -sI http://10.0.1.2/login.php \| head -1` | `HTTP/1.1 200 OK` |
| 14 | waf1, waf2 | DVWA app2 | `curl -sI http://10.0.2.2/login.php \| head -1` | `HTTP/1.1 200 OK` |
| 15 | host | WAF + apps, trusted HTTPS | `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" https://www.latifa.test/login.php` (through the VIP; per node: `--resolve www.latifa.test:443:192.168.80.11`, then `.12`) | `200` |
| 15b | host | HTTP redirected | `curl.exe -sI http://192.168.80.11/login.php \| Select-String "^HTTP"` (then .12) | `301` |
| 16 | db1 | Galera cluster | `mysql -e "SHOW STATUS LIKE 'wsrep_cluster_size';"` | `3` |
| 16b | app1, app2 | Local SQL proxy | `curl -s "http://127.0.0.1:8404/stats;csv" \| cut -d, -f1,2,18 \| grep mariadb` | `db1,UP` `db2,UP` |

## Tests that must fail (proof of segmentation)

| # | From | To | Command | Why |
|---|---|---|---|---|
| 17 | host | app1 | `ping 10.0.1.2` | The host is not on front1: it only sees the WAF nodes |
| 18 | waf1 | db1 | `ping -c 2 -W 1 10.0.3.2` | The WAF nodes are not on net-data |
| 19 | waf1 | app1 on net-data | `ping -c 2 -W 1 10.0.3.5` | Same reason |
| 20 | app1 | app2 through the fronts | `ping -c 2 -W 1 10.0.2.2` | app1 is not on front2: separate VLANs |
| 21 | host | app1 HTTP, not through a WAF | `curl.exe -m 3 http://10.0.1.2/` | No route; on front1, firewalld accepts HTTP from `10.0.1.3`/`.4` only |
| 22 | waf1 | db1 SQL | `timeout 2 bash -c "</dev/tcp/10.0.3.2/3306" && echo OPEN \|\| echo CLOSED` | `CLOSED` |
| 23 | host | WAF + injection | `curl.exe -sS --ssl-no-revoke -o NUL -w "%{http_code}\n" "https://www.latifa.test/login.php?id=1'%20OR%20'1'='1"` | `403`: the WAF blocks |

## ⚠️ Known limitation

| # | From | To | Command | Result |
|---|---|---|---|---|
| 24 | app1 | app2 through net-data | `timeout 2 bash -c "</dev/tcp/10.0.3.6/80" && echo OPEN \|\| echo CLOSED` | `CLOSED`: app2's firewalld accepts HTTP from the WAF nodes only (V1: `OPEN`) |

## Which way each packet goes

| On | Command | Expected |
|---|---|---|
| waf1 | `ip route get 10.0.2.2` | `dev ens256 src 10.0.2.3` |
| waf2 | `ip route get 10.0.2.2` | `dev ens256 src 10.0.2.4` |
| waf1 | `ip route get 8.8.8.8` | `via 192.168.x.2 dev ens161` |

## Reading a failure

| Symptom | Probable cause |
|---|---|
| 1 and 2 fail | Host VMnet2 adapter missing / not at .80.254 (`ipconfig`) |
| 6 and 7 both fail | Front interfaces swapped on one VM |
| "Destination Host Unreachable" | No ARP reply: wrong switch or swapped interfaces |
| 10 fails on a single VM | `nat` profile (no `default via 192.168.x.2` in `ip route`) |
| 11 or 12 fails | Application VM off, front interface on the wrong segment, or firewalld rule missing |
| 16 below 3 | A database node or garbd is down; full restart: stage 17 |
