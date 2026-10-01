# 03 · VM Networking

| | |
|---|---|
| **Objective** | Give every interface its correct address, and prove that each link works |
| **Where** | waf1, waf2, lan (VMware console first, then SSH) |
| **Before** | Stages 01 and 02 completed |
| **After** | SSH from the host to waf1/waf2; waf1 ↔ waf2 on WAN, front1, front2; internet through NAT |

---

## 1. Principle: interface ≠ connection profile

- **Interface**: name assigned by Linux, cannot be chosen — `ens160`, `ens161`, `ens224`, `ens256`.
- **Connection profile**: NetworkManager configuration applied to an interface, with a name we choose — `wan`, `front1`, `front2`, `nat`.

```
interface ens160  ──►  profile "wan"  ──►  192.168.80.11/24
```

In `nmcli con add`: `ifname` = the interface, `con-name` = the profile name.

---

## 2. Identify the interfaces (⚠️ the order changes from one VM to another)

### Method 1: MAC address
```bash
ip -br link
```
Compare with VMware: **VM → Settings → Network Adapter X → Advanced → MAC Address**.

### Method 2: DHCP probe (to find the NAT adapter)
Only VMnet8 has a DHCP server: the interface that obtains an address is the NAT adapter.
```bash
for i in ens160 ens161 ens224 ens256; do nmcli con add type ethernet ifname $i con-name t-$i ipv4.method auto ipv4.dhcp-timeout 10 ipv6.method disabled; nmcli con up t-$i; done ; ip -br a
```
- one interface shows `successfully activated` and an address 192.168.x.y → **NAT**;
- the others: `could not be reserved` → no DHCP → WAN or fronts.
- Then: **rename** the NAT profile (`nmcli con mod t-<NAT> connection.id nat`) and delete the other `t-…` profiles.

### Resulting mapping

| VM | WAN | front1 | front2 | NAT (temporary) |
|---|---|---|---|---|
| waf1 | ens160 | ens224 | ens256 | ens161 |
| waf2 | ens160 | ens224 | **ens161** | **ens256** |
| lan | — | ens160 | ens224 | ens256 |

---

## 3. Configuration (as root)

First: `nmcli -f NAME,DEVICE con show` and delete inherited profiles (`nmcli con delete <name>`).
⚠️ **Never delete the profile carrying your SSH session**: rename it (`nmcli con mod <name> connection.id <new>`) or use the console.

### waf1
```bash
nmcli con add type ethernet ifname ens160 con-name wan    ipv4.method manual ipv4.addresses 192.168.80.11/24 ipv6.method disabled
nmcli con add type ethernet ifname ens224 con-name front1 ipv4.method manual ipv4.addresses 10.0.1.3/29 ipv6.method disabled
nmcli con add type ethernet ifname ens256 con-name front2 ipv4.method manual ipv4.addresses 10.0.2.3/29 ipv6.method disabled
nmcli con add type ethernet ifname ens161 con-name nat    ipv4.method auto ipv6.method disabled
nmcli con up wan ; nmcli con up front1 ; nmcli con up front2 ; nmcli con up nat
```

### waf2
```bash
nmcli con add type ethernet ifname ens160 con-name wan    ipv4.method manual ipv4.addresses 192.168.80.12/24 ipv6.method disabled
nmcli con add type ethernet ifname ens224 con-name front1 ipv4.method manual ipv4.addresses 10.0.1.4/29 ipv6.method disabled
nmcli con add type ethernet ifname ens161 con-name front2 ipv4.method manual ipv4.addresses 10.0.2.4/29 ipv6.method disabled
nmcli con add type ethernet ifname ens256 con-name nat    ipv4.method auto ipv6.method disabled
nmcli con up wan ; nmcli con up front1 ; nmcli con up front2 ; nmcli con up nat
```

### lan — the front interfaces have **no IP**
```bash
nmcli con add type ethernet ifname ens160 con-name front1 ipv4.method disabled ipv6.method disabled
nmcli con add type ethernet ifname ens224 con-name front2 ipv4.method disabled ipv6.method disabled
nmcli con add type ethernet ifname ens256 con-name nat    ipv4.method auto ipv6.method disabled
nmcli con up front1 ; nmcli con up front2 ; nmcli con up nat
```

| Option | Role |
|---|---|
| `ipv4.method manual` + `ipv4.addresses` | Static address |
| `ipv4.method auto` | DHCP (NAT adapter only) |
| `ipv4.method disabled` | Interface up **without an address**: parent interface of the macvlan containers, lan stays invisible on front1/front2 |
| `ipv6.method disabled` | No IPv6: reduced exposure |
| No `ipv4.gateway` on wan/front | The only default route goes through `nat` (temporary) |

Why create a profile even without an IP on lan: so that the interface is **brought up at boot** (macvlan needs an UP parent interface), and so that it never looks for DHCP.

Why these addresses in the /29s: `.0` network, `.1` gateway reserved by Docker (macvlan), `.2` the application, `.3` waf1, `.4` waf2, `.7` broadcast. Same pattern in both VLANs.

---

## 4. How two WAF nodes reach each other on front1

```
waf2 (10.0.1.4) ─ens224─► front1 switch ─ens224─► waf1 (10.0.1.3)
                                │
                       lan ens160 (parent interface, no IP)
```
1. waf2 sees that 10.0.1.3 is in **its own** network (10.0.1.0/29) → no router, direct delivery through ens224.
2. **ARP**: waf2 asks on the switch "who has 10.0.1.3?"; waf1 answers with its MAC address.
3. The ping is delivered to that MAC.

`ip neigh` displays the neighbours discovered by ARP. "Destination Host Unreachable" = nobody answered the ARP request (wrong switch, swapped interfaces).

---

## Validation

See the full matrix in `11-connectivity-tests.md` (tests 1 to 10). Minimum:

| From | Command | Expected |
|---|---|---|
| host | `ping 192.168.80.11` / `.12` then `ssh <user>@192.168.80.11` | Success |
| waf1 | `ping -c 2 10.0.1.4` and `ping -c 2 10.0.2.4` | waf2 answers on front1 and front2 |
| waf1, waf2, lan | `ping -c 2 8.8.8.8` | Internet reachable |
| waf2 | `ip route get 10.0.2.3` | `dev ens161 src 10.0.2.4` |

Wiring of lan's parent interfaces (address lent, then removed):
```bash
ip addr add 10.0.1.6/29 dev ens160
ping -c 2 10.0.1.3
ip addr del 10.0.1.6/29 dev ens160
```
(same with `10.0.2.6` on `ens224` → `10.0.2.3`). Without an address, `ping` fails with `Network is unreachable`: a source address is required.

Snapshot **`reseau-ok`** on the 3 VMs.

---

## ⚠️ Issues

| Symptom | Cause | Fix |
|---|---|---|
| `Insufficient privileges` | Not root | `su -` |
| front1 and front2 unreachable between the WAF nodes | Interfaces swapped on one VM | Test: `ip addr add 10.0.1.5/29 dev <other interface>` + ping; if it answers, move the profiles: `nmcli con mod front1 connection.interface-name <interface>` |
| NAT adapter with an unexpected address, no internet | Old inherited static profile | Delete it, recreate it as `auto` |
| Two profiles with the same name | `con add` on an already configured interface | `nmcli -f NAME,UUID,DEVICE con show` then `nmcli con delete <UUID>` |
