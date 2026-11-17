# ADR-002: Keep VM disks on each node's local storage, with redundancy in the services

Accepted on Nov 17, 2026, by Daniel Faktor.

## Context

Core services are moving onto the Proxmox cluster: DNS (a Technitium pair, replacing the Pi-hole) and the reverse proxy (Nginx Proxy Manager). The Raspberry Pis stay for Docker and container workloads.

The three nodes, moltres, zapdos and articuno, each have 8 cores, 32 GB of RAM, one NVMe drive (256, 256 and 512 GB) that holds both Proxmox and the `local-lvm` VM storage, and one 1 GbE port. Cluster traffic (corosync), VM traffic and management all share that port.

The NAS has shared storage, but its disks are too loud to run all day, so VM disks don't go there. Kubernetes comes later and will want replicated volumes for pods.

The constraints:
- No new hardware: no second disk or second network port per node.
- DNS keeps working when one node is down.
- The cluster heartbeat stays healthy under load.
- Everything is rebuilt from code.

## Decision

1. VM disks live on each node's `local-lvm`. There is no shared or pooled storage under the VMs.
2. The services provide the redundancy. Two Technitium VMs run on different nodes and sync zones between them. The reverse proxy is one VM, restored from its nightly vzdump backup if its node fails.
3. Because `local-lvm` isn't shared, each node has its own copy of the Debian 13 template (moltres 9000, zapdos 9001, articuno 9002), built by `terraform/templates/build-debian13.sh`. The Terraform module clones the copy on the node it targets.
4. Every VM runs the QEMU guest agent, installed on first boot by a cloud-init vendor-data snippet, because the Debian cloud image doesn't include it. The agent lets vzdump freeze the filesystems for a consistent backup, and lets Proxmox shut VMs down cleanly.
5. Longhorn arrives with Kubernetes, inside the Kubernetes VMs, for pod volumes only.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Ceph across the three nodes | The Proxmox way to get one pooled volume. It needs a spare disk per node, and these hold the OS. Every write crosses the single 1 GbE port three times, shared with corosync, and rebalancing after a node reboot can starve the heartbeat. |
| Longhorn for VM disks | Longhorn runs inside Kubernetes and serves only Kubernetes volumes. Proxmox can't put VM disks on it. |
| NFS on the NAS | Shared storage that would allow live migration, but the disks would have to spin all day, and the NAS becomes a single point of failure for every VM. |
| ZFS on each node, with replication and Proxmox HA | Lets a VM restart on another node with recent data. It means reinstalling the nodes with ZFS root. That is cheapest while the cluster is empty, but nothing needs it yet. |

## Consequences

### Good
- VMs get the full speed of the local NVMe drive.
- Storage adds no traffic to the single network port, so nothing competes with corosync.
- Nothing new to run or monitor: no storage cluster, no quorum for disks.
- DNS survives the loss of any one node, because the second Technitium VM is on another node.

### Costs and trade-offs
- When a node fails, its VMs stay down until the node returns or the VMs are restored from backup elsewhere. The reverse proxy is down for that time.
- Moving a VM between nodes copies its whole disk over the 1 GbE port. There is no quick live migration.
- Core DNS and the reverse proxy now depend on the cluster, where the Pis used to be independent. The gateway, as the third DNS server, covers a total cluster outage.
- Templates must be built on every node, and kept in step when rebuilt.
- A VM's first boot takes about a minute and needs internet access, because cloud-init installs the guest agent.

### Revisit when
- A service must keep running through a node failure without a restore: move to ZFS replication and Proxmox HA.
- Nodes gain a second disk and a faster or second network port: Ceph becomes reasonable.
