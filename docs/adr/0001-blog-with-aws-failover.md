# ADR-001: Serve the blog from the homelab, with failover to a static copy in AWS

## Context

blog.danielfaktor.com needs to be public. The blog is also the proof of a platform project, so where it runs is part of the point: it should run on the Kubernetes cluster in my homelab, not on a hosting service.

A homelab is not a reliable origin. Power, updates, hardware swaps and my own experiments will take it down, sometimes for hours. The home connection sits behind double NAT, so port forwarding is not practical, and I don't want the home network listening on the internet at all.

The home router is a UniFi gateway with a zone firewall and intrusion prevention. Anything that enters the lab from outside should pass through it, not around it.

The constraints:
- Readers should get pages when the homelab is down.
- Nothing at home accepts inbound connections.
- Traffic from AWS enters the lab through the router's firewall.
- The always-on AWS cost stays under $15 a month.
- Everything is built from code and can be rebuilt.
- The design should use the AWS services I'm building skills in.

## Decision

1. WordPress runs on the homelab cluster and is the primary origin for every request.
2. CloudFront is the only public entry point. It reaches the cluster through a relay: one t4g.nano instance in us-west-2 running Caddy. The relay accepts web traffic only from CloudFront and checks a secret origin header.
3. The home router dials out to the relay over site-to-site IPsec. The relay has a fixed address; the home side doesn't need one. The tunnel ends on the router, so its traffic crosses the zone firewall, and rules let it reach only the cluster Gateway's virtual IP on port 443.
4. A static mirror in S3 is the failover origin. A job in the cluster crawls the sitemap and page assets and syncs them to a private bucket. A CloudFront origin group switches to the mirror on 500, 502, 503 or 504, or when the relay doesn't connect within 3 seconds or respond within 10.
5. Pages carry `stale-if-error`, so CloudFront keeps serving cached pages through short outages before failover is needed.
6. The public site is read-only. Comments are off and admin paths return 403 at the edge, because CloudFront fails over only GET, HEAD and OPTIONS requests.
7. `blog.danielfaktor.com` is delegated from Cloudflare to Route 53. The parent domain stays on Cloudflare. The delegated zone holds the CloudFront alias, ACM certificate validation, and cert-manager's DNS-01 records.
8. CloudFront stays on pay-as-you-go pricing. The flat-rate plans include origin failover only at the Premium tier, and pay-as-you-go is free up to 1 TB and 10 million requests a month.

## Alternatives considered

| Option | Why not |
| --- | --- |
| Port forwarding with dynamic DNS | Impractical behind double NAT, exposes the home IP, and offers no failover. |
| AWS Site-to-Site VPN with an internal load balancer as a CloudFront VPC origin | No server to patch, and good hybrid-networking practice. But it costs about $55 to $60 a month against about $8, and AWS needs a static public address at home. The load balancer also adds no failover: CloudFront's origin group does that either way. |
| A VPN client on a host inside the lab, not on the router | Works behind any NAT with no router setup, but the traffic would arrive behind the router's firewall. Kept as the fallback, confined to the VM network, if IPsec proves unreliable through double NAT. |
| Cloudflare Tunnel | Free and simple, but it doesn't serve a copy of the site when the origin is down, and it builds no AWS experience. |
| Host the blog in AWS (Lightsail, ECS or EKS) | Reliable, but costs more, and the homelab platform stops being the thing readers use. |
| Static site generator on S3, no WordPress | Simplest and cheapest, but leaves nothing for the platform to run and operate. |

## Consequences

### Good
- Readers see the site during homelab outages, for every page in the sitemap.
- No inbound ports at home; the home IP never appears in DNS and can change without breaking the tunnel.
- Traffic from AWS is held to one destination and one port by the same firewall that guards the rest of the lab.
- About $8 a month always on, mostly the relay's instance and public IPv4 address.
- The failover can be tested on purpose by stopping WordPress, cutting the tunnel or powering off the cluster. A planned game day does exactly that.

### Costs and trade-offs
- No comments, now or later, unless a separate service handles them.
- The mirror can lag. A post published while the lab is down doesn't exist until the lab returns, and edits appear in the mirror only after the next sync.
- IPsec through double NAT is unproven here. The router dials out, which should pass through, but it needs testing. The fallback is a WireGuard client on a VM in the isolated VM network, dialing the same relay.
- The tunnel is a door into the lab, so it stays narrow: one source, one destination, one port, and a pre-shared key that never enters this repo.
- There is one server to patch. The relay is the only always-on instance; it is rebuilt from code, not maintained by hand.
- Lambda@Edge runs twice on a failover (once per origin), so the function has to check which origin it's handling.
- There are more moving parts than plain hosting. The relay, the tunnel and its firewall rules, the sync job and the origin group all need monitoring. SLO probes will cover the public URL and the origin separately.
- Lambda@Edge needs Lambda and CloudWatch Logs allowed in us-east-1, so the organization's Region policy carries that exception.
