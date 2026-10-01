# 02 · Template VM `golden` and Cloning

| | |
|---|---|
| **Objective** | Prepare a clean RHEL 9.5 + Docker VM, then clone it 3 times |
| **Where** | VM `golden`, then waf1, waf2, lan |
| **Before** | A RHEL 9.5 VM installed and registered (subscription-manager) |
| **After** | 3 identical VMs, each with its own unique identity |

Why a template: install and configure **only once**, the 3 machines start from the same known state (reproducibility), and time is saved.

---

## 1. Prepare `golden` (as root)

### Template contents
- RHEL 9.5, registered and up to date.
- Docker Engine with the Compose plugin, enabled at boot.
- Diagnostic tools (`tcpdump`, `dig`, `nc`, `vim`).

### Reset the identity before cloning
```bash
docker image prune -a -f
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
nmcli con delete ens160
poweroff
```
| Command | Why |
|---|---|
| `docker image prune -a -f` | Minimal template: no images (each VM pulls its own) |
| `rm -f /etc/ssh/ssh_host_*` | Otherwise the 3 clones would share the **same SSH host keys** (warnings and confusion) |
| `truncate -s 0 /etc/machine-id` | Empties the machine identifier: it is regenerated on each clone |
| `nmcli con delete ens160` | Removes the network profile inherited from the installer |

Snapshot **`golden`**.

## 2. Clone

Right-click `golden` → **Manage → Clone** → from the `golden` snapshot → **Create a full clone** (independent copy) × 3: `waf1`, `waf2`, `lan`.

The Red Hat registration is kept on the clones (deliberate choice). If `dnf` reports a certificate error on a clone:
```bash
subscription-manager clean && subscription-manager register --force
```

## 3. First boot of each clone (as root)

```bash
systemd-machine-id-setup
systemctl restart sshd
hostnamectl set-hostname waf1
```
- `systemd-machine-id-setup`: generates a new unique machine identifier.
- `systemctl restart sshd`: on restart, sshd generates new SSH host keys.
- `hostnamectl set-hostname`: `waf1`, `waf2` or `lan`.

---

## Validation (on the 3 VMs)

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
