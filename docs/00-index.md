# High-Availability Web Application Behind an Open-Source WAF

Lab build of a highly available web application protected by a web application firewall, on VMware Workstation, RHEL 9.5 and Docker Compose.

**Stack:** nginx, ModSecurity v3, OWASP Core Rule Set, keepalived, DVWA, MariaDB.
**Status:** stages 01 to 10 completed and validated. Virtual IP, host firewall and clean-up in progress.

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
| [09-waf-w3-tls](09-waf-w3-tls.md) | TLS certificate |
| [10-waf-w4-second-node](10-waf-w4-second-node.md) | Second WAF node |
| [11-connectivity-tests](11-connectivity-tests.md) | Full test matrix |

## Addressing plan

| Network | Subnet | Hosts |
|---|---|---|
| WAN (host-only) | 192.168.80.0/24 | host .1, waf1 .11, waf2 .12, VIP .100 |
| front1 | 10.0.1.0/29 | app1 .2, waf1 .3, waf2 .4 |
| front2 | 10.0.2.0/29 | app2 .2, waf1 .3, waf2 .4 |
| net-data (internal) | 10.0.3.0/28 | db1 .2, db2 .3, app1 .5, app2 .6 |
| NAT (temporary) | 192.168.x.0/24 | build only |

## Key design decisions

| Decision | Rationale |
|---|---|
| No proxy or DNS VM in front of the WAF cluster | Would be a single point of failure |
| VRRP in unicast over front1 | VRRP is not strongly authenticated; kept off the client network |
| One VLAN per application, internal data network | Segmentation; the database never leaves the LAN host |
| `hash $remote_addr consistent` load balancing | Session affinity across 192.168.80.x clients |
| DVWA as the protected application | Deliberately vulnerable, backed by MariaDB |

## Roadmap

- **V1:** WAF/LB cluster with virtual IP, two application instances, replicated database.
- **V2:** SQL proxy with automatic failover, backups, shared sessions.
- **V3:** Security monitoring (Wazuh) and centralised logging.
