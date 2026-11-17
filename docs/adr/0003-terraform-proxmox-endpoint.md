# ADR-003: Terraform reaches the Proxmox API at the cluster's virtual IP

Accepted on Nov 17, 2026, by Daniel Faktor.

## Context

Terraform manages Proxmox VMs through the bpg/proxmox provider, which needs one API endpoint and a token.

The Proxmox web interface is published as `pve.danielfaktor.net`. That name resolves through the lab's DNS and goes through Nginx Proxy Manager. Both are moving onto this cluster ([ADR-002](0002-node-local-vm-storage.md)). If Terraform used that name, then rebuilding DNS or the proxy would need DNS and the proxy to be working.

keepalived runs a virtual IP, 192.168.10.9, that moves to a healthy node. Each node's API certificate is signed by the cluster's own certificate authority and names only that node, not the virtual IP.

The constraints:
- Terraform can rebuild DNS and the reverse proxy when they are down.
- Terraform keeps working when any one node is down.
- The API token never enters this repo.

## Decision

1. The provider endpoint is `https://192.168.10.9:8006/`, the cluster's virtual IP.
2. The provider skips TLS verification (`insecure = true`), because no certificate covers the virtual IP.
3. Terraform authenticates as the API token `terraform@pve!homelab`, whose role has only the privileges the provider documents. The secret lives in the macOS Keychain and a password manager. `terraform/env.sh` loads it into the environment and stops with an error if the lookup fails.

## Alternatives considered

| Option | Why not |
| --- | --- |
| `pve.danielfaktor.net` through the reverse proxy | Circular once DNS and the proxy run on the cluster: they can't be rebuilt while they're down. |
| One node's own address | Verifiable TLS with the cluster's certificate authority, but Terraform stops when that node is down. |
| Trust the cluster's certificate authority on the Mac | Still fails verification, because the certificates don't name the virtual IP. |
| An ACME certificate for a DNS name that points at the virtual IP | The right end state: verified TLS with no dependency on the proxy. It needs certificates issued and renewed on every node, so it comes later. |

## Consequences

### Good
- Terraform doesn't depend on any service it manages.
- The endpoint survives the loss of any one node.

### Costs and trade-offs
- With TLS verification off, a device on the path could pretend to be the API and capture the token. The traffic never leaves the home network, which keeps that exposure small, but it is real until certificates are fixed.
- Terraform now depends on keepalived holding the virtual IP.

### Revisit when
- The nodes get ACME certificates for a DNS name that resolves to the virtual IP. Then point the endpoint at that name and turn verification back on.
