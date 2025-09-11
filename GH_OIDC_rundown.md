# The `id-token: write` permission

```yaml
permissions:
  id-token: write
```

- The **`id-token` scope** controls whether the workflow can **request an OpenID Connect (OIDC) token** from GitHub’s identity service.

- Setting it to **`write`** means:  
  _“Yes, this job is allowed to mint a short-lived OIDC token.”_

That token isn’t stored anywhere; it’s generated **on demand** during a workflow run.

---

## Why is this needed?

Because we’re using **OIDC to authenticate to AWS** without static credentials.

Here’s what happens step by step:

1. Your workflow calls the action:

   ```yaml
   - uses: aws-actions/configure-aws-credentials@v4
   ```

2. That action says to GitHub:  
   _“Please issue me an OIDC token for this job.”_

3. GitHub only issues the token if the workflow has `id-token: write`.

4. The action sends that token to **AWS STS** (`AssumeRoleWithWebIdentity`) along with the IAM role ARN.

5. AWS validates the token against your IAM trust policy (restricted to this repo/branches).

6. AWS returns **temporary credentials** (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) that expire after ~1 hour.

7. Terraform then uses those creds to read/write the backend (S3 + DynamoDB) and to manage resources.

---

## Why “write” instead of “read”?

GitHub’s model for this permission is a little counter-intuitive:

- **`read`** would mean “the workflow can only _see_ OIDC tokens” — but there’s nothing to read; tokens must be actively minted.

- **`write`** is required to **request/create** a new token.  
  That’s why we always use `id-token: write` when we want to use OIDC to cloud providers (AWS, Azure, GCP, Vault, etc.).

---

## Security implications

- **Safer than static keys**: No long-lived AWS access keys stored in secrets. Tokens are minted per-job and expire quickly.
- **Scoped to repo/branch**: Your IAM trust policy can say _only allow OIDC tokens from repo `OWNER/REPO` and branch `main` or PRs_.
- **Short-lived**: If leaked, the token is useless after expiration (minutes).
- **Auditable**: AWS CloudTrail logs the role assumption via OIDC.

---

✅ In short:  
`id-token: write` is what **unlocks the OIDC feature** in GitHub Actions. It doesn’t let the workflow write to your repo — it only lets it **mint OIDC tokens**, which cloud providers trust to issue temporary creds.
