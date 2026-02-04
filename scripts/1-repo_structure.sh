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
echo "###################################################################################"
echo "##### 1- Putting on initial repo folder structure and creating a remote repo ######"
echo "###################################################################################"
echo ">>>>>..... Creating remote repo !!!"
echo "Repository Name: $GH_OWNER/$REPO"
echo "Debug: GH_OWNER='$GH_OWNER' REPO='$REPO'"
if [[ -z "$GH_OWNER" || -z "$REPO" ]]; then
    echo "❌ Error: GH_OWNER or REPO variables are not set!"
    echo "Please run 'source scripts/0-variables.sh' or set them manually."
    exit 1
fi
# Check if repository already exists
if gh repo view "$GH_OWNER/$REPO" &>/dev/null; then
    echo "⚠️  Repository $GH_OWNER/$REPO already exists!"
    # Clone or navigate to it if not already present locally
    if [[ ! -d "$REPO" ]]; then
        echo ">>>>>..... Cloning existing repo..."
        gh repo clone "$GH_OWNER/$REPO"
    fi
    echo ">>>>>..... Changing to repo directory..."
    cd "$REPO"
    read -p "Press [Enter] key to continue..."
    exit 0
fi
gh repo create "$GH_OWNER/$REPO" --private --description "Terraform Repo"
echo ">>>>>..... Cloning the repo!!!"
echo " cloning https://github.com/$GH_OWNER/$REPO.git"
gh repo clone "$GH_OWNER/$REPO"
echo "changing dir to /$REPO"
cd "$REPO"
echo ">>>>>..... building the basic structure!!!" 
cat > .gitignore << 'EOF'
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.*
crash.log
*.tfplan
EOF

. ../scripts/build_tf_baseline.sh
sleep 2
echo ">>>>>..... checking the current dir structure !!!"
#tree -a -L 2
read -p " Do you want to push to remote repo now? (y/n): " confirm_push
if [[ "$confirm_push" == "y" || "$confirm_push" == "Y" ]]; then
    pwd
    echo "Current directory: $(pwd)"
    echo ">>>>>..... pushing to remote repo !!!"
    git add .
    git commit -m "init: terraform skeleton"
    git push -u origin main
else
    echo "Push to remote repo skipped."
fi      
# echo ">>>>>..... Repo structure created and pushed to remote repo !!!"
# read -p "Press [Enter] key to continue..."

