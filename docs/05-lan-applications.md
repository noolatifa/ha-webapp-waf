# 05 · LAN: front1, front2, app1 and app2 (iterations 4 and 5)

| | |
|---|---|
| **Objective** | Attach app1 to front1 and app2 to front2 (macvlan), each with access to the database through net-data |
| **Where** | lan (`/opt/lab`), tests from **waf1** |
| **Before** | Stage 04 |
| **After** | app1 10.0.1.2 and app2 10.0.2.2 reachable from the WAF nodes, DVWA answers `200 OK` |

---

## Principle: macvlan

```
waf1 ──ens224──► front1 switch ◄──lan ens160 (parent)──► app1 (10.0.1.2, its own MAC)
```
- The container is attached **directly** to lan's VMware adapter (parent interface), with its own MAC and IP address.
- It appears on front1 as a regular machine. No switch or veth is created.
- **Expected limitation**: the lan VM cannot reach its own macvlan containers → tests are run from waf1.

Difference with net-data: **bridge** = switch internal to the VM; **macvlan** = exposure on a network outside the VM.

---

## Iteration 4: front1 + app1

In `networks:`, add:
```yaml
  front1:
    driver: macvlan
    driver_opts:
      parent: ens160
    ipam:
      config:
        - subnet: 10.0.1.0/29
          gateway: 10.0.1.1
```
In `db1`, add an **alias** on net-data:
```yaml
    networks:
      net-data:
        ipv4_address: 10.0.3.2
        aliases: [db]
```
In `services:`, add:
```yaml
  app1:
    image: ghcr.io/digininja/dvwa:latest
    container_name: app1
    restart: unless-stopped
    depends_on: [db1]
    environment:
      DB_SERVER: db
      DB_DATABASE: dvwa
      DB_USERNAME: dvwa
      DB_PASSWORD: ${DB_APP_PASSWORD}
    networks:
      front1:
        ipv4_address: 10.0.1.2
      net-data:
        ipv4_address: 10.0.3.5
```
| Element | Role |
|---|---|
| `parent: ens160` | The lan interface attached to front1 (**check the mapping**, stage 03) |
| `gateway: 10.0.1.1` | Required by Docker; no machine holds it, hence .1 is reserved |
| `aliases: [db]` | The apps target the **name** `db`. In V2, this name will point to HAProxy SQL without touching the apps |
| `DB_SERVER: db` | DVWA connects to `db` |
| Two networks for app1 | front1 (WAF side) **and** net-data (database side): the app is the only path between the two |
| `10.0.3.5` | app1's own address in net-data: traceability and IP-based access control |

```bash
docker compose config --quiet && echo "syntax OK" && docker compose up -d && docker compose ps
docker network inspect labha_front1 --format '{{.Driver}} {{json .Options}}'
```
**Expected**: `macvlan {"parent":"ens160"}`.

**Tests from waf1**:
```bash
ping -c 2 10.0.1.2
curl -sI http://10.0.1.2/login.php | head -1
```
→ replies, then `HTTP/1.1 200 OK`.

---

## Iteration 5: front2 + app2

Same procedure with: network `front2` (`parent: ens224`, `10.0.2.0/29`, gateway `10.0.2.1`), service `app2` (`front2: 10.0.2.2`, `net-data: 10.0.3.6`).

```bash
docker compose up -d && docker compose ps
docker network inspect labha_front2 --format '{{json .Options}}'
```
**Expected**: 3 containers `Up`, `{"parent":"ens224"}`.

**Tests from waf1**: `ping -c 2 10.0.2.2` and `curl -sI http://10.0.2.2/login.php | head -1`.

If DVWA displays the **Setup** page on first access: log in (`admin` / `password`) then **Create / Reset Database**.

---

## Additional checks (on lan)

```bash
ip -br a | grep dm-
ip link show master br-netdata
```
- The first must display **nothing**.
- The second lists the virtual cables (veth) attached to net-data.

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| macvlan container unreachable, `dm-…` interface in `ip a` | Misspelled option (`parents` instead of `parent`): **no error displayed**, Docker creates a dummy interface | Fix it; **always verify** with `docker network inspect` |
| `ping 10.0.1.2` fails from lan | Expected macvlan limitation | Test from waf1 |
| app2 unreachable, app1 OK | Parent interfaces ens160/ens224 swapped | Check by MAC, fix `parent:` |
