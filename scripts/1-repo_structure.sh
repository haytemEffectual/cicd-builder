#!/bin/bash
########################################################################################
## creating a private repo with default branch 'main' locally and remotely on GitHub  ##
## first this                                                                         ##       
##       1- will create the remote repo                                               ##
##       2- Clone it locally                                                          ##    
##       3- Build the basic structure                                                 ## 
##       4- Push it to remote                                                         ##           
########################################################################################
set -e 
. scripts/0-variables.sh
echo "## 1- Putting on initial repo folder structure and creating a remote repo ######"
echo "#####..... Creating remote repo !!!"
echo "Repository Name: "$OWNER/$REPO""
gh repo create "$OWNER/$REPO" --private --description "Terraform Repo" 
echo "#####..... Cloaning the repo"
echo " cloning https://github.com/$OWNER/$REPO.git"
git clone "https://github.com/$OWNER/$REPO.git"
echo "changing dir to "/$REPO""
cd "$REPO"
echo "#####..... building the basic structure" 
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
echo "#####..... checking the current dir structure"
#tree -a -L 2
pwd
echo "$(pwd)"
echo "#####..... pushing to remote repo"
git add .
git commit -m "init: terraform skeleton"
git push -u origin main
echo "###### Repo structure created and pushed to remote ######"