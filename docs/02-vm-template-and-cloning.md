# 02 · Template VM `golden` and Cloning

| | |
|---|---|
| **Objective** | Prepare a clean RHEL 9.5 VM, then clone it for the 6 lab VMs |
| **Where** | VM `golden`, then waf1, waf2, app1, app2, db1, db2 |
| **Before** | A RHEL 9.5 VM installed and registered (subscription-manager) |
| **After** | 6 VMs from the same base, each with its own unique identity |

Why a template: install and configure **only once**, every machine starts from the same known state (reproducibility), and time is saved.

V3 approach: `golden` is a **blank** RHEL 9.5 (no role software). Each role installs its own packages: Docker on the WAF and application nodes, MariaDB Galera on the database nodes. A role node is prepared once (app1, db1), then cloned for its twin (app2, db2).

---

## 1. Prepare `golden` (as root)

### Template contents
- RHEL 9.5, registered and up to date.
- Diagnostic tools (`tcpdump`, `dig`, `nc`, `vim`).

### Reset the identity before cloning
```bash
hostnamectl set-hostname golden
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
nmcli con delete ens160
poweroff
```
| Command | Why |
|---|---|
| `hostnamectl set-hostname golden` | Neutral name until the clone is renamed |
| `rm -f /etc/ssh/ssh_host_*` | Otherwise the clones would share the **same SSH host keys** (warnings and confusion) |
| `truncate -s 0 /etc/machine-id` | Empties the machine identifier: it is regenerated on each clone |
| `nmcli con delete ens160` | Removes the network profile inherited from the installer |

Snapshot **`golden`**.

## 2. Clone

Right-click `golden` → **Manage → Clone** → from the `golden` snapshot → **Create a full clone** (independent copy): `waf1`, `waf2`, `app1`, `db1`.

Twin nodes are cloned from a prepared role node, then given a new identity (section 3): `app2` from app1 (stage 05), `db2` from db1 **before** the Galera bootstrap (stage 04). waf2 can be rebuilt the same way from waf1 (then stage 10 settings: addresses, keepalived `BACKUP`/100, `NODE_NAME=waf2`).

The Red Hat registration is kept on the clones (deliberate choice). If `dnf` reports a certificate error on a clone:
```bash
subscription-manager clean && subscription-manager register --force
```

## 3. First boot of each clone (as root)

```bash
rm -f /etc/machine-id && systemd-machine-id-setup
rm -f /etc/ssh/ssh_host_* && ssh-keygen -A && systemctl restart sshd
hostnamectl set-hostname waf1
```
- `systemd-machine-id-setup`: generates a new unique machine identifier (the `rm` also covers a clone of a configured node).
- `ssh-keygen -A`: generates new SSH host keys.
- `hostnamectl set-hostname`: `waf1`, `waf2`, `app1`, `app2`, `db1` or `db2`.

---

## Validation (on every VM)

```bash
cat /etc/machine-id ; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub ; hostname
```
**Expected**: machine-id, SSH fingerprint and hostname **different** on each VM.

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| An old `ens160` profile holds an unexpected IP | `nmcli con delete ens160` forgotten on the template | Delete it on the clone (see 03) |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` from the host | Reused SSH keys or reassigned address | `ssh-keygen -R <ip>` on the host |
