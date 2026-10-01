# 04 · LAN: net-data and db1 (iterations 1 to 3)

| | |
|---|---|
| **Objective** | Build the foundation of the LAN: the database network and a persistent db1, with a least-privilege `dvwa` database |
| **Where** | lan, as root, in `/opt/lab` |
| **Before** | Stage 03; images available |
| **After** | db1 (10.0.3.2) running, `dvwa` database + `dvwa` user, persistent data |

Why start with the database: the applications **depend** on it (DVWA without a database displays an error). The foundation is built and tested first, then the upper layers are added.

---

## 0. Preparation

```bash
mkdir -p /opt/lab && cd /opt/lab
printf 'DB_ROOT_PASSWORD=<root password>\nDB_APP_PASSWORD=<dvwa password>\n' > .env && chmod 600 .env
```
- `.env`: read automatically by Docker Compose; the Compose file only contains `${…}` references, **never a clear-text password**. `chmod 600`: readable by root only. Two distinct passwords (least privilege).

---

## Iteration 1: net-data + minimal db1

`docker-compose.yml`:
```yaml
name: labha

networks:
  net-data:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-netdata
    internal: true
    ipam:
      config:
        - subnet: 10.0.3.0/28

services:
  db1:
    image: mariadb:11
    container_name: db1
    environment:
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
    networks:
      net-data:
        ipv4_address: 10.0.3.2
```
| Element | Role |
|---|---|
| `name: labha` | Project name (prefix of networks and volumes: `labha_net-data`) |
| `driver: bridge` | Virtual switch **inside** the lan VM |
| `com.docker.network.bridge.name` | Readable name `br-netdata` instead of a random identifier |
| `internal: true` | No route outside the VM: a compromised database cannot exfiltrate anything |
| `subnet: 10.0.3.0/28` | 7 planned hosts (gateway, db1, db2, HAProxy, app1, app2, backup) → /29 (6) too small → /28 (14) |

```bash
docker compose config --quiet && echo "syntax OK" && docker compose up -d && docker compose ps
```
**Test**: `docker compose logs db1 | grep "ready for connections"` → one line.

---

## Iteration 2: named volume + automatic restart

In `db1`, add:
```yaml
    restart: unless-stopped
    volumes:
      - db1-data:/var/lib/mysql
```
And at the end of the file (no indentation):
```yaml
volumes:
  db1-data:
```
- `restart: unless-stopped`: restarts after a crash or a reboot, unless deliberately stopped.
- Named volume: the database files live **outside the container**. Without it, Docker creates an anonymous volume, lost when the container is recreated.

**Persistence test**:
```bash
docker exec -it db1 mariadb -uroot -p -e "CREATE DATABASE witness;"
docker compose down && docker compose up -d
docker exec -it db1 mariadb -uroot -p -e "SHOW DATABASES;"
docker exec -it db1 mariadb -uroot -p -e "DROP DATABASE witness;"
```
`down` **without** `-v` keeps the volumes → the `witness` database is still present after the container is recreated. Wait ~10 s after `up -d` before testing.

---

## Iteration 3: `dvwa` database and user (least privilege)

In the `environment` of `db1`, add:
```yaml
      MARIADB_DATABASE: dvwa
      MARIADB_USER: dvwa
      MARIADB_PASSWORD: ${DB_APP_PASSWORD}
```
These variables only apply **to an empty database** → start from scratch:
```bash
docker compose down -v && docker compose up -d
```
⚠️ `-v` **deletes the volumes, and therefore the data**.

**Tests**:
```bash
docker exec -it db1 mariadb -udvwa -p -e "SELECT CURRENT_USER(); SHOW DATABASES;"
docker exec -it db1 mariadb -udvwa -p -e "USE mysql;"
docker exec -it db1 mariadb -uroot -p -e "SHOW GRANTS FOR 'dvwa'@'%';"
```
| Expected | What it proves |
|---|---|
| `dvwa` only sees `dvwa` and `information_schema` | Limited scope |
| `USE mysql` → `Access denied` | No access to system tables |
| `GRANT ALL PRIVILEGES ON dvwa.*` | Privileges on its own database only |

---

## State of the `db1` service at the end of this stage

```yaml
  db1:
    image: mariadb:11
    container_name: db1
    restart: unless-stopped
    environment:
      MARIADB_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MARIADB_DATABASE: dvwa
      MARIADB_USER: dvwa
      MARIADB_PASSWORD: ${DB_APP_PASSWORD}
    volumes:
      - db1-data:/var/lib/mysql
    networks:
      net-data:
        ipv4_address: 10.0.3.2
```
(The `db` alias, the binary log and the replication script are added in 05 and 06.)

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| The `dvwa` user does not exist | Database already initialised before the variables were added | `docker compose down -v` |
| The command seems to hang | `-p` combined with `\| grep` hides "Enter password:" | Do not combine them |
| `br-netdata` visible in `ip a` on lan | Expected: visible ≠ exposed. No `ens…` interface is attached to it | — |
