# 18 · Known Limitations and Next Steps

State at the end of V2 (tag `v2.0`).

## What is highly available

| Layer | Redundancy | Failover | Validated test |
|---|---|---|---|
| Edge (WAF / LB / TLS) | waf1 + waf2, VIP `192.168.80.100` | Automatic, ~3 s (VRRP + WAF health check) | Power off waf1 |
| Applications | app1 + app2, separate VLANs | Automatic, ~6 s (nginx `max_fails`) | `docker stop app1` |
| Database | db1 + db2, GTID replication, HAProxy | Automatic, ~4 s; failback planned (stage 15) | `docker stop db1` |

## Limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | ⚠️ **app1, app2, db1, db2 and HAProxy run on a single VM (`lan`)** | Shutting down `lan` (`halt`) stops the whole service: **single point of failure**, found during evaluation |
| 2 | Asynchronous replication | The last transactions can be lost if db1 fails abruptly (RPO > 0) |
| 3 | Failback to db1 is manual | Operator action required (`retour-db1.sh`) |
| 4 | Sessions are local to each application | Session affinity (`hash $remote_addr`) instead of round robin; a client is logged out if its app fails |
| 5 | Backups on the same VM, not encrypted, MariaDB `root` account | No protection if the `lan` VM is lost |
| 6 | Docker-published ports bypass firewalld | 80/443 filtering relies on Docker, not on the host firewall |
| 7 | Lab CA without revocation list | `--ssl-no-revoke` needed for Windows curl |
| 8 | Switch log stored in the browser only | No central history (server logs are per node) |

## Planned improvements (V3)

| Limitation | Improvement |
|---|---|
| 1 | Split `lan` into **lan1** (app1 + db1) and **lan2** (app2 + db2); `net-data` becomes a VMware network between them; one HAProxy per host with a `peers` section so both share the active-database choice (no split-brain) |
| 4 | Shared sessions (Redis), then round robin |
| 5 | Dedicated backup user, encrypted dumps (`age`/`gpg`), off-host copy |
| 6 | Filtering in the `DOCKER-USER` chain |
| 8 | Centralised logging and monitoring (Wazuh) |
| — | Ansible playbooks to rebuild the whole lab |

V3 acceptance test: `halt` on lan1, then on lan2: the dashboard shows the switch and the site stays available.
