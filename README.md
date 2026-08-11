# Automated AWS DevSecOps Pipeline 🛡️🚀

## Project Overview

Manual infrastructure deployment can introduce configuration inconsistencies and security issues if infrastructure changes are not validated before deployment.

This project demonstrates an automated AWS DevSecOps pipeline using GitHub Actions, Checkov, Docker, Amazon ECR, and Terraform. Infrastructure code is scanned for security misconfigurations before the workflow proceeds to the AWS deployment stages.

## The Architecture

![DevSecOps Pipeline Architecture](devsecops-pipeline-architecture.png)

## The Solution

The GitHub Actions workflow is triggered when code is pushed to the `main` branch.

1. **Code Checkout:** GitHub Actions checks out the repository on a GitHub-hosted runner.
2. **Security Gate:** Checkov scans the Terraform configuration for security and compliance misconfigurations.
3. **AWS Authentication:** If the security scan succeeds, the workflow configures AWS credentials using GitHub Actions secrets.
4. **Container Build:** Docker builds the application container image.
5. **Container Registry:** The image is pushed to Amazon Elastic Container Registry (ECR).
6. **Terraform Initialization:** Terraform initializes the working directory.
7. **Workspace Selection:** Terraform selects or creates a workspace based on the Git branch.
8. **Infrastructure Deployment:** Terraform applies the infrastructure configuration automatically.

Because Checkov is configured with `soft_fail: false`, a failed security scan stops the job before the AWS authentication, container publishing, and Terraform deployment steps execute.

## Core Technologies

- **Cloud Provider:** AWS
- **Infrastructure as Code:** Terraform
- **CI/CD:** GitHub Actions
- **Security Scanning:** Checkov
- **Containers:** Docker
- **Container Registry:** Amazon ECR
- **AWS Authentication:** GitHub Actions Secrets

## Simulated Case Study: Infrastructure Misconfiguration Blocked by Checkov

**Situation:** A Terraform configuration contains a security misconfiguration that violates a Checkov policy check.

**Task:** Prevent infrastructure that fails the security scan from proceeding through the automated deployment pipeline.

**Action:** The GitHub Actions workflow runs Checkov against the Terraform configuration before the AWS deployment stages. Checkov is configured with `soft_fail: false`, causing the workflow to fail when a policy violation is detected.

**Result:** The simulated security issue is detected before the deployment stages execute, demonstrating how automated infrastructure-as-code scanning can provide a shift-left security gate.

## Security Considerations

The repository excludes Terraform state files, variable files that may contain secrets, private key files, and local Terraform working directories through `.gitignore`.

AWS credentials used by the workflow are referenced through GitHub Actions secrets rather than stored directly in the workflow file.

## Potential Improvements

Future improvements could include:

- Replace long-lived AWS access keys with GitHub Actions OIDC and short-lived AWS credentials
- Add `terraform fmt` and `terraform validate` checks
- Generate and review a Terraform plan before applying changes
- Pin GitHub Actions to specific versions or commit SHAs
- Use immutable Docker image tags instead of only `latest`
- Store Terraform state in a remote backend with locking
- Add container image vulnerability scanning
- Add pull-request validation before changes reach `main`
- Add a manual approval gate for production deployments