# lights-out-lab

A WordPress blog served from a three-node Kubernetes cluster in my homelab and published through Amazon CloudFront. It stays online when the lab goes dark.

The blog is the vehicle; the platform under it is the project. It shows a hybrid edge with no inbound ports at home, automatic failover to AWS, infrastructure built from code and GitOps, and an AWS Organization with guardrails, for about $8 a month. Later, an AI copilot will propose fixes as pull requests and act only after I approve them.

> Status: early. The design and the AWS guardrails are in place. The cluster and the public blog come next.

## How it works

```mermaid
flowchart LR
    accTitle: Request path and failover
    accDescr: Readers reach CloudFront, which forwards to a small EC2 relay. The home router keeps an outbound IPsec tunnel to the relay, so requests reach the Kubernetes cluster with no inbound ports open at home. If the homelab fails, CloudFront serves a static mirror from S3.
    R[Readers] --> CF[CloudFront]
    CF --> RL[EC2 relay]
    RL <-->|"IPsec, dialed from home"| K8s["Homelab Kubernetes<br/>WordPress + MariaDB"]
    CF -.->|failover| S3[(S3 static mirror)]
```

- Readers only ever talk to CloudFront. It is the one public entry point.
- The home router dials out to a small relay in AWS over IPsec, so nothing at home accepts inbound connections.
- If the homelab errors or times out, CloudFront serves a static mirror of the site from S3.

## What's in this repo

| Path | Purpose |
| --- | --- |
| `docs/` | Design doc, architecture decision records, AWS guardrails |
| `terraform/` | Proxmox VM module and Debian 13 templates; the AWS edge (planned) |
| `ansible/` | Node configuration and kubeadm (planned) |
| `kubernetes/` | Argo CD applications (planned) |
| `copilot/` | The AI copilot and its evals (planned) |

## Learn more

- [Design](docs/design.md): why it is shaped this way, and where the boundaries are
- [Decisions](docs/adr/): one record per significant decision
- [AWS guardrails](docs/aws-guardrails.md): account layout and organization policies
- Build logs and deep dives: [blog.danielfaktor.com](https://blog.danielfaktor.com), once the blog is live
