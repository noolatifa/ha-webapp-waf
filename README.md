# High-Availability Web Application Behind an Open-Source WAF

Lab build of a secure, highly available hosting architecture for a web application and its database: nginx + ModSecurity + OWASP Core Rule Set at the edge, keepalived virtual IP, HAProxy database failover and a live dashboard, on RHEL 9.5 and Docker Compose. DVWA and MariaDB are the test application and engine.

![Architecture](docs/images/architecture.svg)

Documentation (reproducible runbook): [docs/00-index.md](docs/00-index.md)

## Status

**V2 completed** (stages 01 to 17), tag `v2.0`:
- Edge: two WAF nodes behind a virtual IP, HTTPS only, ModSecurity + OWASP CRS, host firewall.
- Applications: two instances on separate VLANs, health-based load balancing with session affinity.
- Database: GTID replication, automatic failover through HAProxy, planned switchback script.
- Operations: live HA dashboard, daily backups.

⚠️ **Known limitation:** the application and database tier (app1, app2, db1, db2, HAProxy) runs on a single VM. Shutting it down stops the service. Details and the other limitations: [docs/18-known-limitations.md](docs/18-known-limitations.md).

## Roadmap

- **V1 (done):** WAF/LB cluster with virtual IP, two application instances, replicated database.
- **V2 (done):** SQL proxy with automatic failover, switchback, dashboard, backups.
- **V3 (next):** two LAN hosts (no single point of failure), shared sessions, `DOCKER-USER` filtering, encrypted off-host backups.
- **Later:** security monitoring (Wazuh), centralised logging, Ansible automation.
