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
       ┌───────┴────────────────┐
       │                        │
       │   Shared Resources     │
       │   (Root Module)        │
       │                        │
       ├─ GitHub OIDC Provider  │
       ├─ IAM Role              │
       │  (both repos trusted)  │
       │                        │
       └────────────────────────┘
       
       Each frontend attaches
       its own IAM policy to the
       shared role
```

## Architecture Details

### Shared Infrastructure (Root Module)

The root module creates shared infrastructure used by both frontend deployments:

1. **GitHub OIDC Provider** - Single provider trusted by AWS
   - URL: `https://token.actions.githubusercontent.com`
   - Trusts both emarket and ncdf repositories
   - Optional creation (set `create_github_oidc_provider = false` if already exists)

2. **Shared IAM Role** - Single role for GitHub Actions deployments
   - Name: `frontend-deployment-{environment}-github-deploy`
   - Trusts both emarket and ncdf repositories via StringLike condition
   - Uses repository environment subjects: `repo:{org}/{repo}:environment:*`

3. **CloudFront Distribution** - Serves both frontend applications
   - Uses host-based routing via CloudFront Functions
   - Routes to correct S3 bucket based on domain

### Independent Frontend Resources (Module Level)

Each frontend module creates independent resources:

1. **S3 Bucket** - Dedicated storage for frontend artifacts
2. **Secrets Manager Secret** - Build variables (API keys, etc.)
3. **IAM Policy** - Specific permissions for S3, Secrets, CloudFront invalidation
   - Attached to the shared root role
   - Each module's policy is independent and scoped to its bucket

This architecture ensures:
- **No OIDC provider duplication** - Single provider, no errors
- **Single IAM role management** - Easier to audit and maintain
- **Independent permissions** - Each frontend has granular access controls
- **Scalable** - Easy to add more frontends by creating new modules


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

### 2. **Consolidated IAM Architecture** ⭐
- **Single GitHub OIDC Provider** created at root level (no duplication)
- **Single Shared IAM Role** for both frontend deployments
  - Trusts both emarket and ncdf repositories
  - Simplifies IAM management and auditing
- **Independent IAM Policies** per module for granular permissions
  - Each module's policy is attached to the shared root role
  - Scoped to specific S3 bucket and resources
  - No cross-repository permission leakage

### 3. **Independent Frontend Modules**
- Each frontend (emarket, ncdf) has:
  - Dedicated S3 bucket for deployment artifacts
  - Dedicated Secrets Manager secret for build variables
  - Independent IAM policy with granular permissions
  - Separate deployment configuration

### 4. **Environment Management**
- Support for staging and production environments
- All resources tagged with environment and project name
- Easy to scale to additional environments

### 5. **CI/CD Ready**
- GitHub Actions OIDC authentication (no long-lived credentials)
- Automatic credential exchange using AWS SigV4
- Both repositories can deploy independently to their respective buckets


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

### Shared IAM Role Setup

Both repositories use the same shared IAM role for deployments:

```bash
# Get the role ARN from terraform output
terraform output github_deploy_role_arn
```

### Emarket Repository Configuration

Add to your emarket-frontend-vanilla repository secrets:

```
AWS_ROLE_ARN: <shared github_deploy_role_arn>
AWS_SESSION_NAME: emarket-deploy
AWS_ACCOUNT_ID: 956536811090
```

### NCDF Repository Configuration

Add to your ncdf-frontend-vanilla repository secrets:

```
AWS_ROLE_ARN: <shared github_deploy_role_arn>
AWS_SESSION_NAME: ncdf-deploy
AWS_ACCOUNT_ID: 956536811090
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
          role-session-name: ${{ secrets.AWS_SESSION_NAME }}
      
      - name: Build and Deploy
        run: |
          npm install
          npm run build
          
          # Determine bucket name (project-environment-account-region)
          BUCKET_NAME="${{ env.PROJECT_NAME }}-staging-956536811090-us-east-1"
          
          # Deploy to S3
          aws s3 sync dist/ s3://${BUCKET_NAME}
          
          # Invalidate CloudFront cache
          DISTRIBUTION_ID="<your-cloudfront-distribution-id>"
          aws cloudfront create-invalidation --distribution-id ${DISTRIBUTION_ID} --paths "/*"
```

**Note:** The shared role automatically grants:
- S3 permissions to each frontend's dedicated bucket
- Secrets Manager read access for build variables
- CloudFront invalidation permissions


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

### OIDC Provider Duplication Error

**Problem:** `EntityAlreadyExists: Provider with url https://token.actions.githubusercontent.com already exists`

**Causes:**
- Multiple modules trying to create the same OIDC provider
- Previous failed apply left provider in AWS but not in state

**Solutions:**

1. **Verify only root creates OIDC** - Ensure `create_github_oidc_provider = false` in module calls:
   ```hcl
   # root main.tf - OIDC provider is created here only
   resource "aws_iam_openid_connect_provider" "github" {
     count = var.create_github_oidc_provider ? 1 : 0
     # ...
   }
   ```

2. **Import existing provider into state** - If provider exists in AWS but not in state:
   ```bash
   terraform import 'aws_iam_openid_connect_provider.github' \
     'arn:aws:iam::956536811090:oidc-provider/token.actions.githubusercontent.com'
   ```

3. **Import to module state** - If using module scope:
   ```bash
   terraform import 'module.emarket.aws_iam_openid_connect_provider.github[0]' \
     'arn:aws:iam::956536811090:oidc-provider/token.actions.githubusercontent.com'
   ```

### IAM Role Not Granting Permissions

**Problem:** GitHub Actions deployment fails with permission denied

**Check:**
1. Verify role can be assumed:
   ```bash
   # Check the role exists
   aws iam get-role --role-name frontend-deployment-staging-github-deploy
   ```

2. Check the role's trust policy:
   ```bash
   aws iam get-role --role-name frontend-deployment-staging-github-deploy \
     --query 'Role.AssumeRolePolicyDocument'
   ```

3. Verify policies are attached:
   ```bash
   # List policies attached to role
   aws iam list-attached-role-policies \
     --role-name frontend-deployment-staging-github-deploy
   ```

4. Check inline policies:
   ```bash
   aws iam list-role-policies \
     --role-name frontend-deployment-staging-github-deploy
   ```

### State Lock Issues

If you encounter state lock errors:

```bash
# View locks
terraform state list

# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

### CloudFront Distribution Issues

**Problem:** Can't access frontend through CloudFront domain

1. Check distribution is deployed:
   ```bash
   terraform output cloudfront_distribution_domain_name
   ```

2. Verify S3 bucket permissions (should be private):
   ```bash
   aws s3api get-bucket-policy --bucket <bucket-name>
   ```

3. Check CloudFront origin configuration:
   ```bash
   aws cloudfront get-distribution --id <distribution-id>
   ```

### S3 Bucket Not Accepting Files

**Problem:** S3 upload permissions denied

1. Verify bucket exists:
   ```bash
   aws s3 ls | grep frontend
   ```

2. Check bucket policy allows GitHub role:
   ```bash
   aws s3api get-bucket-policy --bucket <bucket-name>
   ```

3. Verify IAM policy includes S3:PutObject:
   ```bash
   aws iam get-policy --policy-arn <policy-arn>
   aws iam get-policy-version --policy-arn <policy-arn> --version-id <version>
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
