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
if ! gh repo view "$GH_OWNER/$REPO" &>/dev/null; then
    echo "❌ Repository $GH_OWNER/$REPO does not exist!"
    echo "Please run script 1-repo_structure.sh first to create the repository."
    read -p "Press [Enter] key to continue..."
    exit 0
fi
echo "## .... 5- Applying GH branch protection rules to main branch..."

echo "changing dir to "/$REPO""
cd "$REPO"
echo ">>>>>..... pushing final change to the remote repo"
git pull origin main
git add .
git commit -m "finalizing the repo structure"
git push -u origin main

# Check if main branch exists in remote
echo ">>>>>..... checking if main branch exists"
if ! git ls-remote --heads origin main | grep -q main; then
    echo "❌ Error: main branch does not exist in remote repository!"
    echo "Please ensure code has been pushed to main branch first."
    exit 1
fi

echo ">>>>>..... applying branch protection rules to main branch"
cat > protection.json <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Terraform"]
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
  "/repos/$GH_OWNER/$REPO/branches/main/protection" \
  --input protection.json
rm protection.json
echo "Branch protection rules applied to main branch."
cd ..
echo "########## Branch protection applied !!! . . . ##########"
read -p "Press [Enter] key to continue..."



