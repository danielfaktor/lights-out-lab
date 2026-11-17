# AWS guardrails

Reference for the AWS side of the platform: which accounts exist and which organization-wide policies apply. The reasoning is in the [design doc](design.md).

## Account layout

Created with AWS Builder ID sign-up, then converted to a full AWS Organization with advanced features.

| Account | Purpose |
| --- | --- |
| Management | Billing, AWS Organizations, the organization-wide CloudTrail trail, Budgets. No workloads. Root user has MFA and is kept for emergencies. |
| Identity delegated admin | IAM Identity Center administration. Created by AWS; nothing else runs here. |
| Blog platform | Everything the blog uses: the relay, CloudFront, S3, Route 53 and, later, EKS. No root credentials exist. |

All three accounts are owned by one AWS Builder ID, protected by a passkey and a TOTP device.

## Guardrails

| Control | How it's enforced | Effect |
| --- | --- | --- |
| Regions | Service control policy at the organization root | Workloads run only in us-west-2. us-east-1 allows global services (IAM, CloudFront, ACM, Route 53, Budgets) plus Lambda and CloudWatch Logs for Lambda@Edge. Every other Region is denied. |
| S3 public access | Organization S3 policy | Block Public Access is on in every account and can't be turned off locally. |
| EC2 metadata | Organization EC2 declarative policy | IMDSv2 is required and enforced; hop limit 2 for containers. |
| Audit log | Organization CloudTrail trail | Management events from every account and Region, with log file validation, kept 365 days. |
| Spend | AWS Budgets and Cost Anomaly Detection | $50 a month for the organization and $15 for the blog account, excluding credits. Daily anomaly summaries above $5 impact. |
