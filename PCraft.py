###########################################################################################
## start.py: Main script to setup GitHub repo with Terraform CI/CD using GitHub Actions  ##
## Before running this script,                                                           ##
##  1- Make sure to have AWS CLI and GitHub CLI installed                                ##
##  2- Authenticate to AWS CLI and GitHub CLI                                            ##
## This script reads variables from scripts/0-variables.sh or prompts user for input     ##
## It then offers a menu to perform various setup steps including:                       ##
##       1- Creating repo structure and remote repo                                      ##
##       2- Setting up TF backend in AWS (S3 + DDB) and IAM roles                        ##
##       3- Configuring GitHub repo variables and secrets                                ##
##       4- Creating GitHub Actions workflows for CI/CD                                  ##
##       5- Applying branch protection rules to main branch                              ##
########################################################################################### 

import re
import os   
import subprocess
from pathlib import Path

 
class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'
    
# for name, value in vars(bcolors).items():
#     if not name.startswith('_'):
#         print(f"{name}: {value} ==> Sample Text{bcolors.ENDC}")

def run_step_1(myrepo_path, gh_owner, repo):
    print(f'{bcolors.OKBLUE}####### 1- Creating repo structure and remote repo {gh_owner}/{repo} #######{bcolors.ENDC}')
    subprocess.run(["bash", os.path.join(myrepo_path, "scripts/1-repo_structure.sh")], check=True)

def run_step_2(myrepo_path):
    print(f'{bcolors.OKBLUE}####### 2- Setting TF backend structure (S3 + DDB), IAM permissions, and OIDC role in AWS #######{bcolors.ENDC}')
    subprocess.run(["bash", os.path.join(myrepo_path, "scripts/2-bootstrap_tf_aws.sh")], check=True)

def run_step_3(myrepo_path):
    print(f'{bcolors.OKBLUE}####### 3- Configuring GitHub variables and secrets #######{bcolors.ENDC}')
    subprocess.run(["bash", os.path.join(myrepo_path, "scripts/3-set_gh_variables.sh")], check=True)

def run_step_4(myrepo_path):
    print(f'{bcolors.OKBLUE}####### 4- Creating cicd gh actions workflows #######{bcolors.ENDC}')
    subprocess.run(["bash", os.path.join(myrepo_path, "scripts/4-workflow_ci.sh")], check=True)

def run_step_5(myrepo_path):
    print(f'{bcolors.OKBLUE}####### 5- Configuring main branch protection rules #######{bcolors.ENDC}')
    input(f"{bcolors.WARNING}This would require to upgrade to GH plus or change this repo to PUBLIC. Press [Enter] to continue...{bcolors.ENDC}")
    subprocess.run(["bash", os.path.join(myrepo_path, "scripts/5-protect_main.sh")], check=True)

def run_step_6(myrepo_path):
    print(f'{bcolors.WARNING}####### Undoing step 2: destroying TF backend (S3 + DDB) and IAM role in AWS #######{bcolors.ENDC}')
    subprocess.run(["bash", os.path.join(myrepo_path, "scripts/undo_bootstrap.sh")], check=True)
    
def read_variables(file_path):
    """Read variables from a shell script file and return as dictionary"""
    try:
        with open(file_path, 'r') as f:
            content = f.read()

        pattern = r'^\s*([A-Z_][A-Z0-9_]*)="([^"]*)"'
        matches = re.findall(pattern, content, re.MULTILINE)

        return dict(matches)
    
    except FileNotFoundError:
        print(f"Warning: File {file_path} not found")
        return {}

myrepo_path = os.getcwd()

# Read variables from shell script
shell_vars = read_variables(os.path.join(myrepo_path, "scripts/0-variables.sh"))

# Use shell script values if available, otherwise prompt for input
GH_OWNER = shell_vars.get('GH_OWNER', '') or input("what is GitHub Owner name? ")
REPO = shell_vars.get('REPO', '') or input("what is the Repo name? ")
AWS_ACCOUNT_ID = shell_vars.get('AWS_ACCOUNT_ID', '') or input("what is the AWS Account ID? ")
AWS_REGION = shell_vars.get('AWS_REGION', '') or input("what is the AWS Region? ")
TF_BACKEND_S3_KEY = shell_vars.get('TF_BACKEND_S3_KEY', '') or input("what is the TF Backend S3 Key? ")
# VPC_CIDR = shell_vars.get('VPC_CIDR', '') or input("what is the VPC CIDR? ")   # TODO: uncomment and prompt for VPC_CIDR if the VPC is needed to be created via TF
TF_BACKEND_S3_BUCKET = f"{REPO}-tfstate-{AWS_ACCOUNT_ID}-{AWS_REGION}".lower()
TF_BACKEND_DDB_TABLE = f"{REPO}-tf-locks".lower()
OIDC_PROVIDER_ARN= f"arn:aws:iam::{AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
ROLE_NAME= f"{REPO}-gha-oidc-role"
ROLE_ARN= f"arn:aws:iam::{AWS_ACCOUNT_ID}:role/{ROLE_NAME}"

# Export all variables to environment
all_vars = {
    'GH_OWNER': GH_OWNER,
    'REPO': REPO,
    'AWS_ACCOUNT_ID': AWS_ACCOUNT_ID,
    'AWS_REGION': AWS_REGION,
    'TF_BACKEND_S3_KEY': TF_BACKEND_S3_KEY,
    # 'VPC_CIDR': VPC_CIDR,  # TODO: uncomment and set VPC_CIDR if the VPC is needed to be created via TF
    'TF_BACKEND_S3_BUCKET': TF_BACKEND_S3_BUCKET,
    'TF_BACKEND_DDB_TABLE': TF_BACKEND_DDB_TABLE,
    'OIDC_PROVIDER_ARN': OIDC_PROVIDER_ARN,
    'ROLE_NAME': ROLE_NAME,
    'ROLE_ARN': ROLE_ARN
}

print("Setting environment variables:")
for key, value in all_vars.items():
    os.environ[key] = value
    print(f"{key} = {os.environ.get(key)}")

options = ["Building basic repo structure",
           "Setting TF backend structure (S3 + DDB), IAM permissions, and OIDC role in AWS",
           "Configuring GitHub variables and secrets", 
           "Creating cicd gh actions workflows", 
           "Configuring main branch protection rules", 
           "Undo step 2, and destroy TF backend (S3 + DDB) and IAM role in AWS",
           "All of the above",
           "Exit"
        ]
print("Select an option:")

while True:
    os.system("clear") 
    os.chdir(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
    
    # Display menu as a table
    print("┌────┬────────────────────────────────────────────────────────────────────────────────────┐")
    print("│ #  │ Configuration Step                                                                 │")
    print("├────┼────────────────────────────────────────────────────────────────────────────────────┤")
    for i, option in enumerate(options, 1):
        print(f"│ {i}  │ {option:<80}   │")
    print("└────┴────────────────────────────────────────────────────────────────────────────────────┘")
    
    choice= input("Enter the configuration step number you want to apply: ")
    if choice.isdigit() and 1 <= int(choice) <= len(options):
        selected_option = options[int(choice) - 1]
        print(selected_option + " . . . working on it!")
        match int(choice):
            case 1:
                run_step_1(myrepo_path, GH_OWNER, REPO)
            case 2:
                run_step_2(myrepo_path)
            case 3:
                run_step_3(myrepo_path)
            case 4:
                run_step_4(myrepo_path)
            case 5:
                run_step_5(myrepo_path)
            case 6:
                run_step_6(myrepo_path)
            case 7:
                print(f'{bcolors.OKGREEN}####### Performing all steps 1 to 5 #######{bcolors.ENDC}')
                run_step_1(myrepo_path, GH_OWNER, REPO)
                run_step_2(myrepo_path)
                run_step_3(myrepo_path)
                run_step_4(myrepo_path)
                run_step_5(myrepo_path)
                print(f"{bcolors.OKGREEN}####### DONE!!! . . . your repo is all set! #######{bcolors.ENDC}")
                input(f"{bcolors.ENDC} press enter to continue. This would require to upgrade to GH plus or change this repo to PUBLIC. Press [Enter] to continue...")
            case 8:
                print("Exiting...")
                break   
            
    else:
        print(f"{bcolors.FAIL}Invalid choice. Please run the script again and select a valid option.{bcolors.ENDC}") 
        exit(0)