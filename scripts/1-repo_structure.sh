#!/bin/bash
. scripts/0-variables.sh
# create a private repo with default branch 'main' locally and remotely on GitHub
echo "###### putting on initial repo folder structure ######"
echo "..... creating remote repo"
gh repo create "$OWNER/$REPO" --private --description "Terraform Repo" 
echo "..... cloaning the repo"
git clone "https://github.com/$OWNER/$REPO.git"
cd "$REPO"
echo "..... building the basic structure" 
cat > .gitignore <<'GIT'
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
crash.log
*.tfplan
GIT

. ../scripts/build_tf_baseline.sh
sleep 2
echo "..... checking the current dir structure"
#tree -a -L 2
pwd
echo "..... pushing to remote repo"
git add .
git commit -m "init: terraform skeleton"
git push -u origin main

