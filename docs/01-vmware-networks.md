# 01 · VMware Networks and VM Adapters

| | |
|---|---|
| **Objective** | Create the 4 virtual networks of the lab and attach each VM adapter |
| **Where** | VMware Workstation, on the host PC (Windows) |
| **Before** | VMware installed |
| **After** | The host has 192.168.80.254 on VMnet2; every VM adapter is attached to the right network |

---

## 1. The 4 networks and their role

| Network | VMware type | Role | Attached |
|---|---|---|---|
| **VMnet2** | Host-only | Lab WAN: client access and administration | host, waf1, waf2 (+ clients later) |
| **front1** | LAN Segment | VLAN of app1 | waf1, waf2, lan |
| **front2** | LAN Segment | VLAN of app2 | waf1, waf2, lan |
| **VMnet8** | NAT (temporary) | Internet access during the build **only** | waf1, waf2, lan |

- **Host-only**: private network between the VMs **and** the host, with no internet access.
- **LAN Segment**: private virtual switch **between VMs only**; the host is not attached.
- **NAT**: the VMs reach the internet through the host.

---

## 2. Create VMnet2

**Edit → Virtual Network Editor → Change Settings** (administrator rights), then **Add Network → VMnet2**:

| Setting | Value | Why |
|---|---|---|
| Type | Host-only | Isolated host + VM network |
| Subnet IP | `192.168.80.0` | Fixed, documented subnet, distinct from common home and campus networks |
| Subnet mask | `255.255.255.0` | /24: client access zone, room is needed |
| Use local DHCP service | **unchecked** | Addresses are static (.11, .12, .100); a DHCP server could create conflicts |
| Connect a host virtual adapter | **checked** | Creates the "VMware Network Adapter VMnet2" adapter in Windows: **without it, the host cannot reach the VMs** |

## 3. VMnet8 (NAT, temporary)

Exists by default. Check: **Use local DHCP service** is checked (the VMs' NAT adapters use DHCP).

> NAT subnet: 192.168.x.0/24 (gateway 192.168.x.2). It is assigned by VMware at installation and is only used during the build.

⚠️ Never click **Restore Defaults**: it resets every network, VMnet2 included.

## 4. LAN Segments front1 and front2

In the **Settings** of any VM → a network adapter → **LAN Segment → LAN Segments… → Add**: create `front1`, then `front2`.
Names are **case-sensitive**: `front1` and `Front1` would be two different switches.

## 5. Attach each VM's adapters

| VM | Adapter 1 | Adapter 2 | Adapter 3 | Adapter 4 |
|---|---|---|---|---|
| waf1, waf2 | Custom **VMnet2** | LAN Segment **front1** | LAN Segment **front2** | **NAT** |
| lan | LAN Segment **front1** | LAN Segment **front2** | **NAT** | — |

For each adapter: **Connected** and **Connect at power on** checked.

lan has **no** adapter on VMnet2: it belongs to the internal zone and is invisible from the WAN.

---

## Validation

In PowerShell or cmd, on the host:
```
ipconfig
```
**Expected**: a **VMware Network Adapter VMnet2** adapter with **192.168.80.254**, and a **VMnet8** adapter in 192.168.x.1.

---

## ⚠️ Issues encountered

| Symptom | Cause | Fix |
|---|---|---|
| The host cannot ping the VMs | VMnet2 host adapter missing in Windows | Check "Connect a host virtual adapter to this network" |
| Two VMs on "front1" cannot see each other | Different segment names (case, whitespace) | Exact same name everywhere |
