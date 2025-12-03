#!/bin/bash
################################################################
##### Protect main: PRs only, passing checks required #####
##############################################################
# 1- Settings → Branches → Add rule
# 2- Branch name pattern: main
# 3- guardrails (choose the following):
#     i-      Require a pull request before merging
#     ii-     Require approvals: set to 1 (or per policy)
#     iii-    Require status checks to pass: add terraform-ci
#     iv-     Require branches to be up to date (recommended)
#     v-      Require linear history (recommended)
#     vi-     Include administrators
#     vii-    Leave force pushes & deletions unchecked
##############################################################
echo "## .... 5- Applying GH branch protection rules to main branch..."
. scripts/0-variables.sh
cd "$REPO"
cat > protection.json <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["terraform-ci"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "require_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

gh api -X PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/$OWNER/$REPO/branches/main/protection" \
  --input protection.json
rm protection.json
echo "Branch protection rules applied to main branch."
cd ..


