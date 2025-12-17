import re
import os   
import subprocess
from pathlib import Path

   
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
    print("#######################################################################")
    for i, option in enumerate(options, 1):
        print(f"{i}. {option}")
    print("#######################################################################")
    choice= input("Enter the configuration step number you want to apply: ")
    if choice.isdigit() and 1 <= int(choice) <= len(options):
        selected_option = options[int(choice) - 1]
        print(selected_option + " . . . working on it!")
        match int(choice):
            case 1:
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/1-repo_structure.sh")], check=True)
            case 2:
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/2-bootstrap_tf_aws.sh")], check=True)
            case 3:
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/3-set_gh_variables.sh")], check=True)
            case 4:
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/4-workflow_ci.sh")], check=True)
            case 5:
                print ("#########  Now, protecting main branch... #########")
                input ("This would require to upgrade to GH plus or change this repo to PUBLIC. Press [Enter] to continue...")
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/5-protect_main.sh")], check=True)
            case 6:
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/undo_bootstrap.sh")], check=True)
            case 7:
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/1-repo_structure.sh")], check=True)
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/2-bootstrap_tf_aws.sh")], check=True)
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/3-set_gh_variables.sh")], check=True)
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/4-workflow_ci.sh")], check=True)
                print ("#########  Now, protecting main branch... #########")
                input ("this would require to upgrade to GH plus or change this repo to PUBLIC. Press [Enter] to continue...")
                subprocess.run(["bash", os.path.join(myrepo_path, "scripts/5-protect_main.sh")], check=True)
                print("####### DONE!!! . . . your repo is all set! #######")
            case 8:
                print("Exiting...")
                break   
            
    else:
        print("Invalid choice. Please run the script again and select a valid option.") 