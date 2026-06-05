# Infrastructure as Code - Multi-Frontend Deployment

This Terraform configuration deploys two frontend applications (emarket and ncdf) to AWS with a shared CloudFront distribution, S3 buckets, and GitHub Actions OIDC authentication for CI/CD.

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│          CloudFront Distribution            │
│  (emarket.com, ncdf.com + www variants)     │
└──────────────┬──────────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
       ▼                ▼
┌──────────────┐  ┌──────────────┐
│ Emarket S3   │  │ NCDF S3      │
│ Bucket       │  │ Bucket       │
└──────────────┘  └──────────────┘
       │                │
       └───────┬────────┘
               │
┌──────────────┴──────────────┐
│   GitHub OIDC Provider      │
│   (Shared between modules)  │
└─────────────────────────────┘
```

## Directory Structure

```
multifrontend-deployment/
├── main.tf                      # Root module - defines emarket, ncdf, and cloudfront modules
├── variables.tf                 # Root-level variables (account, region, environment, etc.)
├── versions.tf                  # Provider versions
├── terraform.tfstate            # State file (tracked - should move to remote backend)
├── terraform.tfstate.backup     # State backups
└── cloudfront/                  # CloudFront distribution module
    ├── main.tf                  # CloudFront resources
    ├── variables.tf             # CloudFront variables
    └── output.tf                # CloudFront outputs
└── frontend-infra/
    ├── emarket/                 # Emarket frontend module
    │   ├── main.tf              # S3, IAM, Secrets Manager resources
    │   ├── variables.tf         # Module variables
    │   └── output.tf            # Module outputs (bucket domain, OIDC provider ARN)
    └── ncdf/                    # NCDF frontend module
        ├── main.tf              # S3, IAM, Secrets Manager resources
        ├── variables.tf         # Module variables
        └── output.tf            # Module outputs
```

## Prerequisites

- Terraform >= 1.0
- AWS CLI configured with appropriate credentials
- AWS account with permissions to create:
  - S3 buckets
  - CloudFront distributions
  - IAM roles and policies
  - Secrets Manager secrets
  - OIDC providers

## Configuration

### Root Variables

All configuration is managed through root-level variables in `variables.tf`:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_account_id` | string | `956536811090` | AWS account ID |
| `aws_region` | string | `us-east-1` | AWS region for resources |
| `environment` | string | `staging` | Deployment environment (staging or production) |
| `github_org` | string | `azconcept-droid-org` | GitHub organization |
| `github_environment_names` | list(string) | `null` | GitHub environment names for OIDC |
| `create_github_oidc_provider` | bool | `true` | Create GitHub OIDC provider (emarket module only) |
| `github_oidc_thumbprint` | string | See variables.tf | GitHub Actions OIDC root CA thumbprint |

### Emarket-Specific Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `emarket_project_name` | string | `emarket-frontend` | Project name for emarket |
| `emarket_github_repo` | string | `emarket-frontend-vanilla` | GitHub repository name |
| `emarket_bucket_name` | string | `null` | Optional custom S3 bucket name |
| `emarket_secret_name` | string | `emarket-frontend-vanilla-secrets` | Secrets Manager secret name |
| `emarket_secret_id` | string | `null` | Optional Secrets Manager secret ID |

### NCDF-Specific Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ncdf_project_name` | string | `ncdf-frontend` | Project name for ncdf |
| `ncdf_github_repo` | string | `ncdf-frontend-vanilla` | GitHub repository name |
| `ncdf_bucket_name` | string | `null` | Optional custom S3 bucket name |
| `ncdf_secret_name` | string | `ncdf-frontend-vanilla-secrets` | Secrets Manager secret name |
| `ncdf_secret_id` | string | `null` | Optional Secrets Manager secret ID |

## Deployment

### Initialize Terraform

```bash
terraform init
```

### Plan Changes

```bash
terraform plan
```

### Apply Configuration

```bash
terraform apply
```

Or with auto-approval:

```bash
terraform apply -auto-approve
```

## Key Features

### 1. **Shared CloudFront Distribution**
- Single CloudFront distribution serves both emarket and ncdf
- Host-based routing using CloudFront Functions
- Automatic routing to correct S3 bucket based on domain

### 2. **GitHub Actions OIDC Integration**
- emarket module creates the GitHub OIDC provider
- ncdf module reuses the same provider (no duplication)
- Enables secure CI/CD deployments without long-lived credentials

### 3. **Independent Frontend Modules**
- Each frontend (emarket, ncdf) has:
  - Dedicated S3 bucket
  - Dedicated IAM role for GitHub Actions
  - Dedicated Secrets Manager secret
  - Separate deployment configuration

### 4. **Environment Management**
- Support for staging and production environments
- All resources tagged with environment and project name
- Easy to scale to additional environments

## Outputs

The root module exposes the following outputs:

- CloudFront distribution domain name
- CloudFront distribution ID
- Emarket S3 bucket domain
- Emarket S3 bucket name
- NCDF S3 bucket domain
- NCDF S3 bucket name

Access outputs with:

```bash
terraform output <output_name>
```

## State Management

**⚠️ Important:** The current configuration stores state locally. For production use:

1. **Move to Remote Backend** (S3 + DynamoDB recommended):
   ```hcl
   terraform {
     backend "s3" {
       bucket         = "your-terraform-state-bucket"
       key            = "iac/terraform.tfstate"
       region         = "us-east-1"
       dynamodb_table = "terraform-locks"
       encrypt        = true
     }
   }
   ```

2. **Enable State Locking** to prevent concurrent modifications

3. **Ignore local state files** (already in .gitignore)

## GitHub Actions Integration

### Emarket Repository Configuration

Add to your emarket-frontend-vanilla repository secrets:

```
AWS_ROLE_ARN: <emarket github_deploy role ARN>
AWS_SESSION_NAME: emarket-deploy
```

### NCDF Repository Configuration

Add to your ncdf-frontend-vanilla repository secrets:

```
AWS_ROLE_ARN: <ncdf github_deploy role ARN>
AWS_SESSION_NAME: ncdf-deploy
```

### Example GitHub Actions Workflow

```yaml
name: Deploy to AWS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v3
      - uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      - run: |
          npm install
          npm run build
          aws s3 sync dist/ s3://$(aws s3 ls | grep frontend | awk '{print $3}')
          aws cloudfront create-invalidation --distribution-id $CLOUDFRONT_ID --paths "/*"
```

## Common Tasks

### View Current State

```bash
terraform state list
```

### Refresh State from AWS

```bash
terraform refresh
```

### Destroy All Resources

```bash
terraform destroy
```

### Target Specific Module

```bash
terraform plan -target=module.emarket
terraform apply -target=module.emarket
```

## Troubleshooting

### OIDC Provider Already Exists Error

If you get "EntityAlreadyExists" for the OIDC provider:

```bash
# Import existing provider into state
terraform import 'module.emarket.aws_iam_openid_connect_provider.github[0]' \
  'arn:aws:iam::956536811090:oidc-provider/token.actions.githubusercontent.com'
```

### State Lock Issues

If you encounter state lock errors:

```bash
# View locks
terraform state list

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

## Security Considerations

1. **Never commit terraform.tfstate** to version control
2. **Use remote backend** for team collaboration
3. **Enable MFA** for AWS credentials
4. **Rotate OIDC thumbprints** as needed
5. **Limit IAM permissions** to what's necessary
6. **Encrypt S3 state bucket** if using remote backend
7. **Use VPC endpoints** for S3 if not public

## Support

For issues or questions:
1. Check Terraform AWS provider documentation
2. Review CloudFront distribution settings
3. Verify IAM role permissions
4. Check CloudWatch logs for application errors
