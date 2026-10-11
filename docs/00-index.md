# High-Availability Web Application Behind an Open-Source WAF

Lab build of a highly available web application protected by a web application firewall, on VMware Workstation, RHEL 9.5 and Docker Compose.

**Stack:** nginx, ModSecurity v3, OWASP Core Rule Set, keepalived, HAProxy, MariaDB Galera, DVWA.
**Status:** V3 completed. No single VM failure stops the service (6 VMs, tested in [stage 15](15-failover-tests.md)). V2 (single LAN VM) is kept in the tag `v2.0` and the branch `single-point-of-failure-lan`.

![Architecture](images/architecture.svg)

---

## Documentation

| File | Content |
|---|---|
| [01-vmware-networks](01-vmware-networks.md) | Virtual networks and VM adapters |
| [02-vm-template-and-cloning](02-vm-template-and-cloning.md) | Blank template VM and clones |
| [03-vm-networking](03-vm-networking.md) | Interface identification, addressing, link tests |
| [04-db-galera-cluster](04-db-galera-cluster.md) | db1, db2: MariaDB Galera cluster, least-privilege users |
| [05-app-nodes](05-app-nodes.md) | app1, app2: DVWA and local HAProxy SQL proxy |
| [06-galera-arbitrator](06-galera-arbitrator.md) | garbd on app1: third vote, quorum |
| [07-waf-w1-load-balancer](07-waf-w1-load-balancer.md) | Reverse proxy and load balancer |
| [08-waf-w2-modsecurity](08-waf-w2-modsecurity.md) | ModSecurity and OWASP CRS |
| [09-waf-w3-tls](09-waf-w3-tls.md) | Secure HTTPS: lab CA, trusted certificate, hardening |
| [10-waf-w4-second-node](10-waf-w4-second-node.md) | Second WAF node |
| [11-connectivity-tests](11-connectivity-tests.md) | Full test matrix |
| [12-waf-w5-vip-keepalived](12-waf-w5-vip-keepalived.md) | Virtual IP, VRRP failover, WAF health check |
| [13-waf-w6-firewall](13-waf-w6-firewall.md) | Host firewall on the WAF nodes |
| [14-shared-sessions](14-shared-sessions.md) | PHP sessions stored in Galera: no logout on application failure |
| [15-failover-tests](15-failover-tests.md) | V3 failover test campaign |
| [16-ha-dashboard](16-ha-dashboard.md) | Live high-availability dashboard |
| [17-cluster-cold-start](17-cluster-cold-start.md) | Full shutdown and restart of the Galera cluster |
| [18-known-limitations](18-known-limitations.md) | Limitations and next steps |

Real configuration files: [`configs/`](../configs/) (`waf/`, `app/`, `db/`). Secrets are replaced by placeholders (`env.example`, `<dvwa password>`).

## Addressing plan

| Network | Subnet | Hosts |
|---|---|---|
| WAN (host-only) | 192.168.80.0/24 | host .254, waf1 .11, waf2 .12, VIP .100 |
| front1 | 10.0.1.0/29 | app1 .2, waf1 .3, waf2 .4 |
| front2 | 10.0.2.0/29 | app2 .2, waf1 .3, waf2 .4 |
| net-data | 10.0.3.0/28 | db1 .2, db2 .3, app1 .5, app2 .6 |
| NAT (temporary) | 192.168.x.0/24 | build only |

## Key design decisions

| Decision | Rationale |
|---|---|
| No proxy or DNS VM in front of the WAF cluster | Would be a single point of failure |
| VRRP in unicast over front1 | VRRP is not strongly authenticated; kept off the client network |
| One VLAN per application, separate data network | Segmentation; the database nodes are attached to net-data only |
| One VM per role (app1, app2, db1, db2) | Any single VM can fail; V2 ran all of them on one VM |
| MariaDB Galera, synchronous | No data loss on failure (RPO = 0), automatic catch-up of a returning node |
| No virtual IP on the database tier | Each application reaches the cluster through its own local HAProxy: no shared proxy to fail |
| Writes on db1, db2 as backup | No write conflicts between Galera nodes |
| Arbitrator `garbd` on app1 | Third vote for quorum, no data stored; not on a database node (2 votes lost at once) nor on a WAF (DMZ kept off net-data) |
| PHP sessions in Galera | Users stay logged in when their application node fails; no change to DVWA |
| DVWA on the host network | firewalld filters port 80 (only the WAF nodes); no Docker NAT rules |
| HTTPS only, certificate signed by an internal CA | Trusted padlock without a public domain; HTTP redirected, HSTS |
| Domain `latifa.test` | Reserved by RFC 2606, never resolvable on the Internet |
| keepalived tracks the WAF container health | VIP released when nginx fails, not only when the VM fails |
| SSH to the WAF nodes from the admin host only | Smaller attack surface |
| `hash $remote_addr consistent` load balancing | Stable client-to-application mapping; round robin possible since sessions are shared |
| Dashboard on the WAF, admin host only | High availability visible live without exposing internals to clients |
| DVWA as the protected application | Deliberately vulnerable, backed by MariaDB |

## Roadmap

- **V1 (done):** WAF/LB cluster with virtual IP, two application instances, replicated database.
- **V2 (done, tag `v2.0`):** SQL proxy with automatic failover, planned switchback, dashboard, scheduled backups. Single LAN VM.
- **V3 (done, tag `v3.0`):** 6 VMs, Galera cluster with arbitrator, local SQL proxies, shared sessions, full failover campaign.
- **Next:** automatic cold start, TLS on the data network, Galera-aware health check, encrypted off-host backups, Wazuh monitoring, Ansible automation.
