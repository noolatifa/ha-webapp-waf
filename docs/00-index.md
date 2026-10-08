# High-Availability Web Application Behind an Open-Source WAF

Lab build of a highly available web application protected by a web application firewall, on VMware Workstation, RHEL 9.5 and Docker Compose.

**Stack:** nginx, ModSecurity v3, OWASP Core Rule Set, keepalived, HAProxy, DVWA, MariaDB.
**Status:** V2 completed (stages 01 to 17). ⚠️ Known limitation: the application and database tier runs on a single VM; see [stage 18](18-known-limitations.md). V3 removes it.

![Architecture](images/architecture.svg)

---

## Documentation

| File | Content |
|---|---|
| [01-vmware-networks](01-vmware-networks.md) | Virtual networks and VM adapters |
| [02-vm-template-and-cloning](02-vm-template-and-cloning.md) | Template VM and clones |
| [03-vm-networking](03-vm-networking.md) | Interface identification, addressing, link tests |
| [04-lan-database](04-lan-database.md) | Data network, db1, persistence, least privilege |
| [05-lan-applications](05-lan-applications.md) | Front VLANs (macvlan), app1, app2 |
| [06-lan-replication](06-lan-replication.md) | db2 and GTID replication |
| [07-waf-w1-load-balancer](07-waf-w1-load-balancer.md) | Reverse proxy and load balancer |
| [08-waf-w2-modsecurity](08-waf-w2-modsecurity.md) | ModSecurity and OWASP CRS |
| [09-waf-w3-tls](09-waf-w3-tls.md) | Secure HTTPS: lab CA, trusted certificate, hardening |
| [10-waf-w4-second-node](10-waf-w4-second-node.md) | Second WAF node |
| [11-connectivity-tests](11-connectivity-tests.md) | Full test matrix |
| [12-waf-w5-vip-keepalived](12-waf-w5-vip-keepalived.md) | Virtual IP, VRRP failover, WAF health check |
| [13-waf-w6-firewall](13-waf-w6-firewall.md) | Host firewall on the WAF nodes |
| [14-lan-v2-db-failover](14-lan-v2-db-failover.md) | HAProxy SQL proxy, automatic database failover |
| [15-lan-v2-switchback](15-lan-v2-switchback.md) | Planned return to db1 without data loss |
| [16-v2-ha-dashboard](16-v2-ha-dashboard.md) | Live high-availability dashboard |
| [17-lan-v2-backups](17-lan-v2-backups.md) | Scheduled database backups |
| [18-known-limitations](18-known-limitations.md) | Limitations and planned improvements |

Real configuration files: [`configs/`](../configs/) (secrets replaced by placeholders; see `configs/lan/.env.example`).

## Addressing plan

| Network | Subnet | Hosts |
|---|---|---|
| WAN (host-only) | 192.168.80.0/24 | host .254, waf1 .11, waf2 .12, VIP .100 |
| front1 | 10.0.1.0/29 | app1 .2, waf1 .3, waf2 .4 |
| front2 | 10.0.2.0/29 | app2 .2, waf1 .3, waf2 .4 |
| net-data (internal) | 10.0.3.0/28 | db1 .2, db2 .3, HAProxy .4 (`db`), app1 .5, app2 .6 |
| NAT (temporary) | 192.168.x.0/24 | build only |

## Key design decisions

| Decision | Rationale |
|---|---|
| No proxy or DNS VM in front of the WAF cluster | Would be a single point of failure |
| VRRP in unicast over front1 | VRRP is not strongly authenticated; kept off the client network |
| One VLAN per application, internal data network | Segmentation; the database never leaves the LAN host |
| HTTPS only, certificate signed by an internal CA | Trusted padlock without a public domain; HTTP redirected, HSTS |
| Domain `latifa.test` | Reserved by RFC 2606, never resolvable on the Internet |
| keepalived tracks the WAF container health | VIP released when nginx fails, not only when the VM fails |
| SSH from the admin host only | Smaller attack surface; no SSH between nodes |
| `hash $remote_addr consistent` load balancing | Session affinity across 192.168.80.x clients |
| HAProxy as the SQL entry point (`db`) | Engine-agnostic failover, no application change |
| No automatic failback to db1 | db1 may have missed writes; return is a planned, scripted operation |
| Backups taken from the replica | No load on the active database |
| Dashboard on the WAF, admin host only | High availability visible live without exposing internals to clients |
| DVWA as the protected application | Deliberately vulnerable, backed by MariaDB |

## Roadmap

- **V1 (done):** WAF/LB cluster with virtual IP, two application instances, replicated database.
- **V2 (done):** SQL proxy with automatic failover, planned switchback, dashboard, scheduled backups.
- **V3 (next):** two LAN hosts (no single point of failure), shared sessions, `DOCKER-USER` filtering, encrypted off-host backups.
- **Later:** security monitoring (Wazuh), centralised logging, Ansible automation.
