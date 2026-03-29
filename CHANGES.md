# Changes

## 2026-03-26

### AWS EC2 production module

- Added an AWS EC2 production deployment path under `Production-plan/terraform-ec2`.
- Added support for two edge modes:
  - direct instance mode with Elastic IP, Route53 A record, and ACM certificate terminated inside Docker
  - optional ALB mode with Route53 ALIAS and ACM termination on the load balancer
- Added Spot instance support with persistent request and stop interruption behavior.
- Added EIP-backed direct mode so DNS remains stable without depending on instance public IPv4 assignment.
- Added exportable ACM certificate handling for direct mode and kept standard ACM integration for ALB mode.
- Added conditional nginx edge service in the rendered Docker Compose template for direct TLS termination.
- Added S3-backed runtime config delivery for the rendered `docker-compose.yml` artifact.
- Added outputs for edge mode, direct public IP, config bucket, and compose artifact location.
- Upgraded the Terraform AWS provider requirement in the EC2 module to `~> 6.0` to support exportable ACM public certificates.

### Networking and platform changes

- Added support for deploying into an existing VPC with either:
  - existing public subnet IDs, or
  - Terraform-created public subnets and Internet Gateway
- Updated EC2, ALB, and EFS resources to use effective public subnet selection.

### Operations and documentation

- Updated the EC2 module README to document direct mode, ALB mode, Spot usage, ACM behavior, and runtime config refresh.
- Added runtime certificate refresh automation for direct-instance ACM termination.
- Documented refresh and update workflows for the rendered Compose artifact.

### Notes

- Direct mode reduces fixed infrastructure cost by making the ALB optional, but exportable ACM public certificates incur ACM charges.
- ALB mode remains the more managed option for TLS termination and health-checked edge routing.