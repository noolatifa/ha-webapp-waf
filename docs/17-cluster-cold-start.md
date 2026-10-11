# 17 · Full Shutdown and Cold Start of the Cluster

| | |
|---|---|
| **Objective** | Stop the whole lab and start it again without losing data |
| **Where** | All 6 VMs, as root |
| **Before** | Stages 01 to 14 |
| **After** | `wsrep_cluster_size = 3`, `Primary`, service available |

## Why a cold start needs an operator

Each Galera node records its state in `/var/lib/mysql/grastate.dat`:
```
seqno:   -1             # last committed transaction (-1 while running)
safe_to_bootstrap: 0    # 1 = this node was the last to stop cleanly
```
When **all** nodes are stopped, none of them knows at boot whether another node holds more recent transactions. Starting a new cluster from a node that is behind would discard the transactions it missed. Galera therefore never restarts a fully stopped cluster by itself: an operator starts it from the most advanced node, the one with `safe_to_bootstrap: 1`.

This only concerns a **complete** shutdown. A single node that stops and returns (stage 15) rejoins by itself.

---

## 1. Shutdown order

`poweroff` on each VM, waiting for each one to be off:

| Order | VMs | Reason |
|---|---|---|
| 1 | waf2, then waf1 | Clients stop reaching the applications |
| 2 | app2, then app1 | No more writes; garbd stops with app1 |
| 3 | db2 | |
| 4 | **db1 last** | db1 gets `safe_to_bootstrap: 1` |

## 2. Start order

1. **db1**:
   ```bash
   cat /var/lib/mysql/grastate.dat
   galera_new_cluster
   ```
   Run `galera_new_cluster` only if `safe_to_bootstrap: 1`. If db2 holds the `1`, run it on db2 instead. If neither node does (power loss), compare `seqno` after `mysqld --wsrep-recover` on both nodes, choose the highest, set `safe_to_bootstrap: 1` in its `grastate.dat`, then bootstrap it.
2. **db2**: power on; it joins at boot. If not: `systemctl restart mariadb`.
3. **app1**: power on; `garbd` joins at boot. If not: `systemctl restart garbd`.
4. **app2**, **waf1**, **waf2**: power on.
5. Check on db1:
   ```bash
   mysql -e "SHOW STATUS WHERE Variable_name IN ('wsrep_cluster_size','wsrep_cluster_status');"
   ```
   **Expected**: `3`, `Primary`.

⚠️ `galera_new_cluster` on a node while another cluster is running creates a second, separate cluster (split-brain). Run it once, on one node, only when no database node is running.

## Lab alternative: suspend

VMware **Suspend** on all 6 VMs, then **Resume** on all 6 within a short time: for Galera the cluster was never stopped, no bootstrap is needed. Check `wsrep_cluster_size` after resuming.

## Planned improvement

A boot script on db1 and db2 applying the same rule automatically: join if a cluster exists, bootstrap only if `safe_to_bootstrap: 1`, otherwise retry until the other node has started the cluster.
