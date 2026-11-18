# ADR-004: Run the Technitium DNS pair as Proxmox OCI containers

## Context

The lab's only filtering DNS resolver is a Pi-hole on a Raspberry Pi Zero 2 W (192.168.10.4). When it goes down, clients fall back to the gateway and lose filtering. [ADR-002](0002-node-local-vm-storage.md) moved DNS onto the Proxmox cluster as two Technitium servers on different nodes, with the redundancy in the service rather than the storage.

Technitium ships for Linux in two ways: an install script and tarball from `download.technitium.com`, and the `technitium/dns-server` image on Docker Hub. `technitium.com` is one server on a DigitalOcean address that geolocates to India. The UDR7's Region Blocking blocks India in both directions, and Region Blocking is evaluated before zone-based firewall policies, so an allow policy for that address has no effect. The flow log showed every attempt dropped by Region Blocking, including after an allow policy was added.

Proxmox VE 9.1 added OCI image support: Proxmox pulls an image from a registry and runs it as an LXC application container, with no Docker engine and no VM. The cluster runs 9.2.26, where application containers are still a technology preview. The bpg/proxmox provider supports this through `proxmox_oci_image` and `proxmox_virtual_environment_container`.

The constraints:
- Filtering keeps working when one node is down.
- Region Blocking stays a single global list, with no per-country exceptions.
- Everything is rebuilt from code, with secrets kept out of the repo.

## Decision

1. Technitium runs from the official `docker.io/technitium/dns-server` image, pinned to a version tag (15.6.2), as unprivileged Proxmox OCI containers. `terraform/dns` pulls the image on each node and creates the containers. Upgrading means bumping the tag and applying.
2. dns1 (CT 100, 192.168.20.2) runs on moltres and dns2 (CT 101, 192.168.20.3) on zapdos, both on Lab-VMs (VLAN 20), with 2 cores, 2 GB of RAM and a 4 GB disk each. Proxmox sets the static address from outside the container (`host-managed`), because the image has no network tools.
3. Technitium's built-in clustering keeps the pair in step. dns1 is the primary and dns2 the secondary. The cluster domain is `home.arpa`, the name reserved for home networks (RFC 8375), so it can never collide with a public zone. The nodes are `dns1.home.arpa` and `dns2.home.arpa`. Clustering replicates settings, blocklists, allowed and blocked entries, and zones.
4. Upstream is Cloudflare over DNS-over-TLS (1.1.1.1 and 1.0.0.1 on port 853). Port 853 is blocked from Lab-VMs to stop clients bypassing the filter, so one allow rule lets only the two DNS servers reach those two addresses on 853. Until that rule exists, the pair forwards over DNS-over-HTTPS to the same Cloudflare addresses.
5. Blocking uses three HaGeZi lists in adblock format from jsDelivr, refreshed every 24 hours, answering NXDOMAIN:
   - Pro, the balance HaGeZi recommends for a mixed household.
   - Threat Intelligence Feeds, Medium, for malware, phishing and command-and-control domains. The full feed has about 2.2 million entries, too many for the containers' memory.
   - Encrypted DNS (DoH), so browsers and apps can't bypass the filter with their own resolver.
   There is no allowlist at first. Entries get added when something breaks.
6. `danielfaktor.net` is a conditional forwarder zone with one local record: the apex answers 192.168.0.1. Every other name in the zone, including the `*` record for the reverse proxy, resolves through Cloudflare as it does publicly. A primary zone would hide every public record not copied into it.
7. A nightly vzdump job (`dns-nightly`, 03:00) backs up both containers to the NAS share `snorlax-proxmox`, keeping 7. The job writes its temporary files to local `/var/tmp`, because the NFS share refuses writes from an unprivileged container's mapped user.
8. The Terraform role gains `Sys.AccessNetwork`, which Proxmox requires before a node pulls an image from a registry.

This replaces the "two Technitium VMs" part of ADR-002. The reasoning there about node-local storage still holds.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Native install in two Debian VMs | Technitium's download server is blocked by Region Blocking, and a firewall policy can't make an exception. |
| Remove India from Region Blocking and block it with zone policies instead | Works, but India would sit outside the global list in one policy per zone, and any new zone would have to remember it. Making that change to install one program is a poor trade. |
| Docker inside a VM | Adds a guest kernel and a container engine to run one process. |
| Primary/secondary zone transfer instead of clustering | Copies zones only. Blocklists and settings would have to be kept in step by hand. |

## Consequences

### Good
- No VM and no Docker engine: each server is one process in an LXC container, about 100 MB to back up.
- Either node can go down and the other keeps resolving and filtering. Tested by stopping dns1.
- Region Blocking stays one global list.
- Upgrades are a tag change in Terraform.

### Costs and trade-offs
- OCI application containers are a technology preview in Proxmox VE. If they misbehave, the fallback is a Debian LXC system container running the same release.
- Terraform ignores the containers' environment variables and console settings, because Proxmox fills them in from the image. The `DNS_SERVER_DOMAIN` variable didn't survive, so the server names are set through Technitium's API instead.
- Replacing a container wipes its configuration. A rebuilt secondary rejoins the cluster to resync. A rebuilt primary is restored from vzdump.
- Joining the cluster needs the primary's admin password, so it is a manual step in the web UI.
- Technitium's own update check can't reach its server. That is harmless, because updates come from Docker Hub.
- When a container is replaced at the same IP, the gateway can keep the old MAC address for several minutes, and the new container is unreachable until that entry expires.

### Revisit when
- Proxmox VE marks application containers as stable, or a release breaks them.
- Technitium moves its downloads off the blocked address.
- The containers need more memory than 2 GB, for example for the full Threat Intelligence Feeds.
