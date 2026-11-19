# ADR-005: Collect router, DNS and Proxmox logs on one VM and keep them on the NAS

## Context

Each log in the lab lives only on the machine that wrote it. The UniFi gateway keeps a short rolling log, the Technitium containers keep 7 days inside a 4 GB disk that a rebuild wipes, and each Proxmox node keeps its own journal. Losing a device loses its history, and there is no one place to look when something breaks.

The router's configuration is already covered by UniFi's automatic backups, which run weekly and are stored on the console and in the UniFi cloud. This record is about logs only.

The constraints:
- No new agents or SSH access on the router or the Proxmox nodes.
- Every credential is read-only and stays out of the repo.
- The NAS disks are loud, so they must not spin all day ([ADR-002](0002-node-local-vm-storage.md)).
- Everything is rebuilt from code.

## Decision

1. One Debian VM, `logs` (VMID 102, 192.168.20.4 on articuno), with 1 core, 1 GB of RAM and 20 GB of disk, built by `terraform/logs` from the existing VM module and configured by `terraform/logs/setup-collector.sh`.
2. The router pushes its logs to the VM over UDP 514 through the System Logging / SIEM integration (Network → Integrations), with all 14 categories and raw logs. The router sends from 192.168.20.1, and rsyslog accepts syslog from that address only. It writes one file per day under `/var/log/remote` on the VM's local disk, named by the date the collector received it. Each line is stamped with the collector's receive time, because UniFi writes UTC digits with a -08:00 offset in the header. The router's own `UNIFIutcTime` field stays in every line.
3. Everything else is pulled, once a night at 03:15, over read-only API keys:
   - Technitium query logs from dns1 and dns2 through `/api/logs/download`, as the Technitium user `logs`, which can only view logs. Each server has File logging, Log All Queries and Max Log File Days 7 set in its own Settings → Logging. Clustering doesn't copy these settings, so a rebuilt server needs them set again. Files are named by UTC date, and the job takes only days before the current one.
   - Proxmox journals for moltres, zapdos and articuno through `/nodes/<node>/journal`, with the token `logs@pve!collector`. The role `LogReader` holds only `Sys.Syslog`, on `/nodes`. Privilege separation is on, so the ACL is set on both the user and the token.
   - Each pull fills in any day from the last 7 that is missing, so a missed night repairs itself.
4. The job then moves everything to the Synology share `lab-logs` on snorlax (192.168.10.5) over NFS. The share mounts on demand and unmounts after 10 minutes idle. 03:15 follows the 03:00 `dns-nightly` vzdump, so the disks are already awake. If the share isn't mounted, the job stops rather than filling the VM's disk.
5. Retention on the NAS: 365 days for router syslog and Proxmox journals, matching the CloudTrail trail; 90 days for DNS query logs, which are the largest and most private. The share has a 50 GB quota so logs can't fill the volume that holds the vzdump backups.
6. API tokens live in macOS Keychain (`technitium-logs`, `proxmox-logs`) and in `/etc/logs-backup/env` on the VM, mode 0600. curl reads URLs and headers from a pipe, so tokens never show in the process list.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Loki and Grafana | Search and dashboards, but three more services to run and upgrade. Plain files answer today's questions. |
| SSH from the collector to the router | Needs root on the gateway, and UniFi updates can wipe the authorized keys. |
| rsyslog agents on each Proxmox node | Changes every host, and the API already serves the journal. |
| Writing logs straight to the NFS share | The NAS disks would spin all day. |
| Technitium's Log Exporter app | The App Store is on technitium.com, which Region Blocking drops ([ADR-004](0004-technitium-dns-pair.md)). |

## Consequences

### Good
- One place to read every log, with up to a year of history.
- No credential on the VM can change anything. The Proxmox token was tested against a VM start and got 403.
- The router and the nodes needed no new software and no new access.

### Costs and trade-offs
- The collector reaches the Proxmox API (8006) and the NAS (NFS 2049) across zones, so Lab-VMs to Lab-Mgmt has two allow policies, each limited to source 192.168.20.4 and one destination port: "Allow log collector NFS to snorlax" and "Allow log collector to Proxmox API". They live in the UniFi controller, not in this repo.
- All Proxmox pulls go through articuno, which also runs the collector. If articuno is down, the 7-day catch-up covers it on the next run.
- Router syslog is UDP. Anything sent while the collector is down is lost.
- Anything that can spoof 192.168.20.1 on the VLAN can still write to the router's log. Other senders are dropped.
- Firewall hits only reach the log for policies that have syslog logging turned on.
- Changing the VM module's cloud-init settings, such as its DNS servers, reboots the collector and gives it new SSH host keys. Verify the new fingerprint with `qm guest exec 102 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` before trusting it.
- No alerting. A failed run shows only in `journalctl -u logs-nightly` on the VM.
- The logs exist only on snorlax. A ransomware attack or NAS failure takes them all.

### Revisit when
- The blog is public. Add a locked off-site copy (S3 Object Lock in compliance mode, Deep Archive, an upload-only key in a separate account) and VM and container snapshots.
- Searching plain files gets slow enough to matter. Consider Loki then.
- Routinely missing runs. Add alerting.
