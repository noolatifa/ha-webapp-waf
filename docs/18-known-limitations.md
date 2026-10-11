# 18 · Known Limitations and Next Steps

State at the end of V3 (tag `v3.0`). V2 (single LAN VM) is preserved in the tag `v2.0` and the branch `single-point-of-failure-lan`.

## What is highly available

| Layer | Redundancy | Failover | Validated test (stage 15) |
|---|---|---|---|
| Edge (WAF / LB / TLS) | waf1 + waf2, VIP `192.168.80.100` | Automatic, ~3 s (VRRP + WAF health check) | Power off waf1 |
| Applications | app1 + app2, separate VMs and VLANs | Automatic, ~10 s (nginx `max_fails`) | Power off the serving app |
| Sessions | Stored in Galera, read by both apps | Transparent: the user stays logged in | Power off the serving app |
| Database | db1 + db2 Galera (synchronous), garbd on app1 | Automatic, ~4 s (local HAProxy); automatic return to db1 | Power off db1 |

## V2 limitations solved by V3

| V2 limitation | V3 |
|---|---|
| Single LAN VM: `halt` stopped the service | 4 VMs (app1, app2, db1, db2); any one can fail |
| Asynchronous replication (RPO > 0) | Synchronous Galera replication (RPO = 0) |
| Manual failback to db1 (`retour-db1.sh`) | Automatic: a returning node catches up (IST), then HAProxy uses it again |
| Sessions local to each app: logout on app failure | Shared sessions (stage 14) |
| Docker-published ports bypassed firewalld | DVWA uses the host network: firewalld filters port 80 |

## Limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | Cold start after a **complete** shutdown needs a manual bootstrap | Operator action (stage 17); by design, to avoid starting from stale data |
| 2 | One failure per tier | Two simultaneous failures (db1 + db2, or one database node + app1) stop the database tier |
| 3 | No TLS on SQL and Galera traffic | Mitigated: net-data is an isolated segment reachable only by app and db nodes |
| 4 | HAProxy `mysql-check` tests the login, not the Galera state | A node that accepts logins but is not yet `Synced` could receive traffic; mitigated by `rise 5` (~10 s) |
| 5 | Session handler without locking, one write per request | Fine for the lab; Redis or a locking handler at scale |
| 6 | Database backups not yet adapted to Galera | V2 backup timer removed; no scheduled dump in V3 yet |
| 7 | NAT adapters still attached to app and db VMs; SSH open on the LAN VMs | Build convenience; to be removed for production hardening |
| 8 | Lab CA without revocation list | `--ssl-no-revoke` needed for Windows curl |
| 9 | Switch log stored in the browser only | No central history (server logs are per node) |

## Next steps

| Limitation | Improvement |
|---|---|
| 1 | Boot script: join if a cluster exists, bootstrap only with `safe_to_bootstrap: 1` |
| 3 | TLS for MariaDB clients and Galera replication |
| 4 | HTTP health check reporting `wsrep_local_state = 4` (Synced) for HAProxy |
| 6 | Dump from db2 with a dedicated read-only user, encrypted (`age`/`gpg`), copied off-host |
| 7 | Remove NAT adapters, SSH from the admin host only (as on the WAF nodes) |
| 9 | Centralised logging and monitoring (Wazuh) |
| — | Round robin instead of `hash $remote_addr` (possible now that sessions are shared) |
| — | Ansible playbooks to rebuild the whole lab |
