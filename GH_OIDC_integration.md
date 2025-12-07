# GitHub OIDC Integration with AWS for Terraform

Complete guide to implementing secure, keyless authentication between GitHub Actions and AWS using OpenID Connect (OIDC).

---

## What is OIDC?

**OpenID Connect (OIDC)** is an identity layer on top of OAuth 2.0 that allows applications to verify user identity. In the context of GitHub Actions and AWS:

- **GitHub** acts as the **Identity Provider (IdP)** - it issues signed tokens about your workflow
- **AWS** acts as the **Relying Party (RP)** - it trusts GitHub's tokens and issues temporary credentials
- **No static credentials** are stored in GitHub - tokens are minted on-demand and expire quickly

---

## The `id-token: write` Permission

```yaml
permissions:
  id-token: write
```

### What It Does

- **Allows the workflow to request an OIDC token** from GitHub's identity service
- **Does NOT grant repository write access** - only enables token minting
- **Required for cloud authentication** via OIDC (AWS, Azure, GCP, Vault, etc.)

### Why "write" Instead of "read"?

GitHub's permission model:
- `read` - View existing tokens (but OIDC tokens don't exist until requested)
- `write` - **Request/create** a new token (required for OIDC)

**Always use `id-token: write` for OIDC authentication.**

---

## How OIDC Authentication Works

### Step-by-Step Flow

1. **Workflow starts** with `permissions: id-token: write`

2. **Action requests token**:
   ```yaml
   - uses: aws-actions/configure-aws-credentials@v4
     with:
       role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
       aws-region: us-west-2
   ```

3. **GitHub generates signed OIDC token** containing:
   - Repository name
   - Branch/PR reference
   - Workflow information
   - Expiration time (~5 minutes for the token itself)

4. **Action calls AWS STS** with:
   ```
   AssumeRoleWithWebIdentity(
     RoleArn: "arn:aws:iam::123456789012:role/my-role"
     WebIdentityToken: "eyJhbGciOiJSUzI1NiIs..."
   )
   ```

5. **AWS validates token**:
   - Verifies signature using GitHub's public keys
   - Checks trust policy conditions (repo, branch, etc.)
   - Ensures token hasn't expired

6. **AWS issues temporary credentials**:
   ```
   AWS_ACCESS_KEY_ID=ASIA...
   AWS_SECRET_ACCESS_KEY=...
   AWS_SESSION_TOKEN=...
   ```
   **Valid for ~1 hour**

7. **Terraform uses credentials** to:
   - Access S3 backend
   - Lock state in DynamoDB
   - Manage AWS resources

---

## AWS Configuration

### 1. OIDC Provider in IAM

Created by `scripts/2-bootstrap_tf_aws.sh`:

```bash
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1" \
  --client-id-list "sts.amazonaws.com"
```

**Key Components:**
- **Provider URL**: `token.actions.githubusercontent.com` (GitHub's OIDC endpoint)
- **Thumbprint**: SHA-1 fingerprint of GitHub's root CA certificate
- **Audience**: `sts.amazonaws.com` (AWS STS service)

### 2. IAM Role Trust Policy

The role's trust policy controls **who** can assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:haytemEffectual/MyTerraformProject-test:ref:refs/heads/*",
            "repo:haytemEffectual/MyTerraformProject-test:pull_request"
          ]
        }
      }
    }
  ]
}
```

#### Trust Policy Breakdown

**Principal**: Who can assume the role
```json
"Principal": {
  "Federated": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
}
```
Only OIDC tokens from GitHub can attempt to assume this role.

**Action**: What operation is allowed
```json
"Action": "sts:AssumeRoleWithWebIdentity"
```
The STS operation for assuming roles via OIDC.

**Conditions**: When the role can be assumed

**Audience Check**:
```json
"StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
}
```
Ensures the token was intended for AWS STS.

**Subject Claims** (Repository & Event):
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:OWNER/REPO:ref:refs/heads/*",
    "repo:OWNER/REPO:pull_request"
  ]
}
```

**Critical Pattern Details:**

✅ **Correct patterns:**
- `repo:owner/repo:ref:refs/heads/*` - Matches all branch pushes
- `repo:owner/repo:ref:refs/heads/main` - Matches main branch only
- `repo:owner/repo:pull_request` - Matches pull request events

❌ **Incorrect pattern:**
- `repo:owner/repo:ref:refs/pull/*` - **DOES NOT WORK**

**Why?** GitHub's OIDC token `sub` claim differs by event type:
- Push to branch: `repo:owner/repo:ref:refs/heads/branch-name`
- Pull request: `repo:owner/repo:pull_request` (literal string, no PR number)
- Environment: `repo:owner/repo:environment:prod`

---

## OIDC Token Claims

GitHub's OIDC token contains these claims:

```json
{
  "sub": "repo:haytemEffectual/MyTerraformProject-test:pull_request",
  "aud": "sts.amazonaws.com",
  "repository": "haytemEffectual/MyTerraformProject-test",
  "repository_owner": "haytemEffectual",
  "ref": "refs/heads/feature-branch",
  "sha": "abc123...",
  "workflow": "terraform-ci",
  "job_workflow_ref": "haytemEffectual/MyTerraformProject-test/.github/workflows/terraform-ci.yml@refs/heads/feature-branch",
  "iss": "https://token.actions.githubusercontent.com",
  "iat": 1701820800,
  "exp": 1701821100,
  "nbf": 1701820700
}
```

**Key Claims:**
- `sub` - Subject (who this token represents)
- `aud` - Audience (who this token is for)
- `repository` - Full repository name
- `ref` - Git reference (branch/tag)
- `sha` - Commit SHA
- `exp` - Expiration time (typically 5 minutes)

---

## Workflow Configuration

### Complete Example

```yaml
name: terraform-apply
on:
  push:
    branches: [main]

permissions:
  contents: read      # Read repository contents
  id-token: write     # Request OIDC token

concurrency:
  group: ${{ github.workflow }}-main
  cancel-in-progress: false

env:
  AWS_REGION: ${{ vars.AWS_REGION }}
  TF_BACKEND_BUCKET: ${{ vars.TF_BACKEND_BUCKET }}
  TF_BACKEND_KEY: ${{ vars.TF_BACKEND_KEY }}
  TF_BACKEND_DDB_TABLE: ${{ vars.TF_BACKEND_DDB_TABLE }}
  AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ env.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
          # Optional: specify role session name
          role-session-name: GitHubActions-${{ github.run_id }}

      - name: Verify AWS Identity
        run: aws sts get-caller-identity

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: |
          terraform init \
            -backend-config="bucket=${TF_BACKEND_BUCKET}" \
            -backend-config="key=${TF_BACKEND_KEY}" \
            -backend-config="region=${AWS_REGION}" \
            -backend-config="dynamodb_table=${TF_BACKEND_DDB_TABLE}"

      - name: Terraform Apply
        run: terraform apply -auto-approve
```

---

## Security Benefits

### 1. No Long-Lived Credentials
- **No AWS access keys in GitHub Secrets**
- **No key rotation** required
- **No risk of leaked credentials** in commit history

### 2. Fine-Grained Access Control
Trust policies can restrict by:
- **Repository**: Only specific repos can assume the role
- **Branch**: Only main branch or specific patterns
- **Event type**: Only PR events or push events
- **Environment**: Only production environment

### 3. Short-Lived Tokens
- **OIDC token**: Expires in ~5 minutes
- **AWS credentials**: Expire in ~1 hour
- **Minimal exposure window** if compromised

### 4. Auditability
- **AWS CloudTrail** logs all role assumptions
- **GitHub Actions logs** show workflow execution
- **Clear attribution** to specific workflow runs

### 5. Principle of Least Privilege
- **Separate roles** per environment/repo
- **Minimal permissions** for each role
- **No privilege escalation** possible

---

## Common Issues & Solutions

### Issue: "Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Causes:**
1. Missing `id-token: write` permission
2. Trust policy repository mismatch
3. Incorrect subject claim pattern (using `ref:refs/pull/*` instead of `pull_request`)
4. OIDC provider not created in AWS account

**Solution:**
```bash
# Verify OIDC provider exists
aws iam get-open-id-connect-provider \
  --open-id-connect-provider-arn "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com"

# Check role trust policy
aws iam get-role --role-name ROLE_NAME \
  --query 'Role.AssumeRolePolicyDocument'

# Re-run bootstrap script to update trust policy
bash scripts/2-bootstrap_tf_aws.sh
```

### Issue: Token Validation Failed

**Cause:** Thumbprint mismatch or expired

**Solution:**
```bash
# Get current thumbprint
echo | openssl s_client -servername token.actions.githubusercontent.com \
  -connect token.actions.githubusercontent.com:443 2>/dev/null | \
  openssl x509 -fingerprint -sha1 -noout | cut -d'=' -f2 | tr -d ':'

# Update OIDC provider if needed
```

### Issue: Credentials Expire During Long Runs

**Cause:** AWS credentials valid for only 1 hour

**Solution:**
- Re-authenticate mid-workflow if needed
- Split into multiple jobs
- Use longer-running compute (self-hosted runners with instance profiles)

---

## Trust Policy Patterns

### Restrict to Specific Branch
```json
"StringEquals": {
  "token.actions.githubusercontent.com:sub": "repo:owner/repo:ref:refs/heads/main"
}
```

### Allow Multiple Branches
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:owner/repo:ref:refs/heads/main",
    "repo:owner/repo:ref:refs/heads/dev"
  ]
}
```

### Require Environment
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": "repo:owner/repo:environment:production"
}
```

### Multiple Repositories (Shared Role)
```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:owner/repo1:*",
    "repo:owner/repo2:*"
  ]
}
```

---

## Comparison: OIDC vs Static Keys

| Aspect | OIDC | Static Access Keys |
|--------|------|-------------------|
| **Storage** | No credentials stored | Keys in GitHub Secrets |
| **Rotation** | Automatic (per job) | Manual (90 days recommended) |
| **Lifetime** | ~1 hour | Until manually rotated |
| **Compromise Risk** | Minimal (short-lived) | High (long-lived) |
| **Attribution** | Specific to workflow run | Generic to key user |
| **Setup Complexity** | Higher (trust policy) | Lower (just store key) |
| **Best Practice** | ✅ Recommended | ⚠️ Legacy approach |

---

## Additional Resources

- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS IAM OIDC Providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [AWS STS AssumeRoleWithWebIdentity](https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRoleWithWebIdentity.html)
- [GitHub Actions Permissions](https://docs.github.com/en/actions/using-jobs/assigning-permissions-to-jobs)

---

## Summary

✅ **OIDC enables secure, keyless authentication** from GitHub Actions to AWS

✅ **`id-token: write` is required** to mint OIDC tokens (does not grant repo access)

✅ **Trust policies control access** based on repository, branch, and event type

✅ **Use `pull_request` (not `ref:refs/pull/*`)** in subject claim patterns

✅ **Credentials are short-lived** (~1 hour) and automatically rotated

✅ **No secrets to manage or rotate** - GitHub handles token lifecycle

✅ **Fully auditable** via CloudTrail and GitHub Actions logs

This is the **recommended approach** for production Terraform workflows on AWS.
