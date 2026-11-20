# Homelab network

![Homelab network: zones, VLANs, physical links and service flows](./homelab-network.png)

## Networks

| Network | VLAN | Subnet | Firewall zone | What lives there |
| --- | --- | --- | --- | --- |
| Default | 1 | 192.168.0.0/24 | Internal | Laptops, phones, printer, media devices |
| Lab-Infra | 10 | 192.168.10.0/24 | Lab-Mgmt | Proxmox nodes and VIP, NAS, Raspberry Pis, AP and switch management |
| Lab-VMs | 20 | 192.168.20.0/24 | Lab-VMs | Guests built by `terraform/`: the DNS pair and the log collector |
| Work | 30 | 192.168.30.0/24 | Work | A work laptop |
| IoT | 40 | 192.168.40.0/24 | IoT | Smart-home devices, on a 2.4 GHz-only SSID |

The gateway is `.1` on every VLAN. Infrastructure gets its address from a UniFi DHCP reservation, except the Proxmox nodes and their guests, which Proxmox sets itself. In Lab-Infra, addresses follow the switch ports: `.5` NAS, `.6`–`.8` Proxmox, `.9` the cluster VIP, `.10`–`.15` the Pis on ports 1–6.

## Who can talk to whom

Traffic between zones is denied unless a policy allows it, and replies to allowed traffic always pass.

- **Internal** reaches every zone except Work.
- **Lab-Mgmt** reaches Lab-VMs. Lab-VMs reaches Lab-Mgmt only through two policies for the log collector: NFS to the NAS and the Proxmox API ([ADR-005](../adr/0005-lab-log-collection.md)).
- **IoT** and **Work** get the internet and DNS on the Technitium pair, nothing else.
- **VPN** (UniFi Teleport clients) reaches Internal, Lab-Mgmt and Lab-VMs.
- IoT, Work and Lab-VMs can't reach the router's admin ports. IoT and Lab-VMs can't use DNS-over-TLS, except the DNS pair talking to Cloudflare.
- No port forwards, UPnP off. IPS runs in block mode, and Region Blocking applies to every network before any zone policy.

## Services and flows

- **DNS.** Every network hands out dns1 and dns2 as DNS 1 and 2 and its own gateway as DNS 3. The pair runs as Proxmox OCI containers on two different nodes, filters with blocklists, and forwards to Cloudflare over DNS-over-TLS ([ADR-004](../adr/0004-technitium-dns-pair.md)).
- **Internal HTTPS.** A DNS-only Cloudflare record points `*.danielfaktor.net` at nidoking. Nginx Proxy Manager there holds a wildcard Let's Encrypt certificate and proxies `pve` to the cluster VIP, `nas` to the Synology, and `dns` to dns1 with dns2 as a backup.
- **Proxmox.** Three nodes, each with one NVMe disk and one 1 GbE link trunked for VLANs 10 and 20. Guests live on node-local storage, and redundancy comes from the services ([ADR-002](../adr/0002-node-local-vm-storage.md)). Terraform and browsers use the keepalived VIP ([ADR-003](../adr/0003-terraform-proxmox-endpoint.md)). A nightly vzdump job backs the DNS containers up to the NAS.
- **Logs.** The router sends syslog to `logs`. Each night the collector pulls the DNS query logs and the Proxmox journals, then moves everything to the NAS over NFS ([ADR-005](../adr/0005-lab-log-collection.md)).
- **Remote access.** UniFi Teleport only. Clients land in the VPN zone.
