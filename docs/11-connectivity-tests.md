# 11 · Connectivity Test Matrix (end of W4)

To be re-run after every network change. "From" = the machine on which the command is typed.

## Address reminder

| Machine | WAN (VMnet2) | front1 | front2 | NAT (temporary) |
|---|---|---|---|---|
| host | 192.168.80.1 | — | — | 192.168.x.1 |
| waf1 | .80.11 · ens160 | 10.0.1.3 · ens224 | 10.0.2.3 · ens256 | ens161 |
| waf2 | .80.12 · ens160 | 10.0.1.4 · ens224 | 10.0.2.4 · ens161 | ens256 |
| lan | — | parent ens160 | parent ens224 | ens256 · DHCP |
| app1 / app2 | — | 10.0.1.2 | 10.0.2.2 | — |
| db1 / db2 | net-data 10.0.3.2 / 10.0.3.3 (internal to lan) | | | |

## Tests that must succeed

| # | From | To | Command | Expected |
|---|---|---|---|---|
| 1 | host | waf1 (WAN) | `ping 192.168.80.11` | replies |
| 2 | host | waf2 (WAN) | `ping 192.168.80.12` | replies |
| 3 | host | waf1 (SSH) | `ssh <user>@192.168.80.11` | login |
| 4 | host | waf2 (SSH) | `ssh <user>@192.168.80.12` | login |
| 5 | waf1 | waf2 (WAN) | `ping -c 2 192.168.80.12` | replies |
| 6 | waf1 | waf2 (front1) | `ping -c 2 10.0.1.4` | replies |
| 7 | waf1 | waf2 (front2) | `ping -c 2 10.0.2.4` | replies |
| 8 | waf2 | waf1 (front1) | `ping -c 2 10.0.1.3` | replies |
| 9 | waf2 | waf1 (front2) | `ping -c 2 10.0.2.3` | replies |
| 10 | waf1, waf2, lan | internet (NAT, temporary) | `ping -c 2 8.8.8.8` | replies |
| 11 | waf1, waf2 | app1 | `ping -c 2 10.0.1.2` | replies |
| 12 | waf1, waf2 | app2 | `ping -c 2 10.0.2.2` | replies |
| 13 | waf1, waf2 | DVWA app1 | `curl -sI http://10.0.1.2/login.php \| head -1` | `HTTP/1.1 200 OK` |
| 14 | waf1, waf2 | DVWA app2 | `curl -sI http://10.0.2.2/login.php \| head -1` | `HTTP/1.1 200 OK` |
| 15 | host | WAF + apps | `curl.exe -k -s -o NUL -w "%{http_code}\n" https://192.168.80.11/login.php` (then .12) | `200` |
| 16 | lan | db2 replicates db1 | `docker exec -it db2 mariadb -uroot -p -e "SHOW SLAVE STATUS\G"` | `Yes` / `Yes` / `0` |

## Tests that must fail (proof of segmentation)

| # | From | To | Command | Why |
|---|---|---|---|---|
| 17 | host | app1 | `ping 10.0.1.2` | The host is not on front1: it only sees the WAF nodes |
| 18 | waf1 | db1 | `ping -c 2 -W 1 10.0.3.2` | net-data only exists inside lan |
| 19 | waf1 | app1 on net-data | `ping -c 2 -W 1 10.0.3.5` | Same reason |
| 20 | lan | app1 | `ping -c 2 -W 1 10.0.1.2` | Expected macvlan limitation |
| 21 | container on net-data | internet | `docker run --rm --network labha_net-data alpine ping -c 2 -W 1 8.8.8.8` | `internal: true` |
| 22 | app1 | app2 through the fronts | `docker exec app1 bash -c 'timeout 2 bash -c "</dev/tcp/10.0.2.2/80" && echo OPEN \|\| echo CLOSED'` | `CLOSED`: separate VLANs |
| 23 | host | WAF + injection | `curl.exe -k -s -o NUL -w "%{http_code}\n" "https://192.168.80.11/login.php?id=1'%20OR%20'1'='1"` | `403`: the WAF blocks |

## ⚠️ Known limitation (V1)

| # | From | To | Command | V1 result |
|---|---|---|---|---|
| 24 | app1 | app2 through net-data | `docker exec app1 bash -c 'timeout 2 bash -c "</dev/tcp/10.0.3.6/80" && echo OPEN \|\| echo CLOSED'` | `OPEN` → V2: split net-data |

## Wiring of lan's parent interfaces

```bash
ip addr add 10.0.1.6/29 dev ens160
ping -c 2 10.0.1.3
ip addr del 10.0.1.6/29 dev ens160
```
Same with `10.0.2.6` on `ens224` towards `10.0.2.3`. Always remove the address afterwards.

## Which way each packet goes

| On | Command | Expected |
|---|---|---|
| waf1 | `ip route get 10.0.2.2` | `dev ens256 src 10.0.2.3` |
| waf2 | `ip route get 10.0.2.2` | `dev ens161 src 10.0.2.4` |
| waf1 | `ip route get 8.8.8.8` | `via 192.168.x.2 dev ens161` |

## Reading a failure

| Symptom | Probable cause |
|---|---|
| 1 and 2 fail | Host VMnet2 adapter missing / not at .80.1 (`ipconfig`) |
| 6 and 7 both fail | Front interfaces swapped on one VM |
| "Destination Host Unreachable" | No ARP reply: wrong switch or swapped interfaces |
| 10 fails on a single VM | `nat` profile (no `default via 192.168.x.2` in `ip route`) |
| 11 or 12 fails | Container stopped, or macvlan `parent:` on the wrong interface |
