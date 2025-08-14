#!/bin/bash

# A script to automate the creation of a new project with Git, GitHub, and Netlify,
# including a 'develop' branch setup.
# This script is idempotent: it checks for existing resources before creating them.
#
# Prerequisites:
# 1. GitHub CLI ('gh') installed and authenticated.
# 2. Netlify CLI ('netlify') installed, authenticated, and up-to-date.
# 3. A '.env' file in the same directory as this script with:
#    - GITHUB_TOKEN (Personal Access Token with 'repo' scope)
#    - NETLIFY_AUTH_TOKEN (Personal Access Token)
#    - NETLIFY_ACCOUNT_ID (Your Netlify team slug, e.g., "alexwm462")
#    - SUPABASE_URL (For the 'main' branch/production)
#    - SUPABASE_ANON_KEY (For the 'main' branch/production)
#    - SUPABASE_DEV_URL (For the 'develop' branch)
#    - SUPABASE_DEV_ANON_KEY (For the 'develop' branch)

# --- Configuration and Pre-flight Checks ---

# Set colors for output messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting the project setup process...${NC}"

# Check if .env file exists and source it
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}Error: '.env' file not found.${NC}"
    echo -e "${YELLOW}Please create a .env file with the required variables.${NC}"
    exit 1
fi

# Check if required tokens and keys are set
if [ -z "$GITHUB_TOKEN" ] || [ -z "$NETLIFY_AUTH_TOKEN" ] || [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ] || [ -z "$SUPABASE_DEV_URL" ] || [ -z "$SUPABASE_DEV_ANON_KEY" ] || [ -z "$NETLIFY_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: One or more required environment variables are not set in the .env file.${NC}"
    exit 1
fi

# --- User Input ---

read -p "Enter the name for your new project: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Project name cannot be empty.${NC}"
    exit 1
fi

# --- Project Directory and Git Initialization ---

# Idempotency Check: Check if directory exists
if [ -d "$PROJECT_NAME" ]; then
    echo -e "${YELLOW}Directory '$PROJECT_NAME' already exists. Proceeding inside it.${NC}"
    cd "$PROJECT_NAME"
else
    echo -e "\n${GREEN}Step 1: Creating project directory and initializing Git...${NC}"
    mkdir "$PROJECT_NAME"
    cd "$PROJECT_NAME"
    git init -b main
    echo "# $PROJECT_NAME" > README.md
    git add README.md
    git commit -m "Initial commit"
    echo -e "${GREEN}✔ Git repository initialized locally.${NC}"
fi

# --- GitHub Repository Creation ---

echo -e "\n${GREEN}Step 2: Checking/Creating GitHub repository...${NC}"
GH_USERNAME=$(gh api user -q .login)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to authenticate with GitHub. Is your GITHUB_TOKEN valid?${NC}"
    exit 1
fi

# Idempotency Check: Check if GitHub repo already exists
if gh repo view "$GH_USERNAME/$PROJECT_NAME" >/dev/null 2>&1; then
    echo -e "${YELLOW}GitHub repository '$GH_USERNAME/$PROJECT_NAME' already exists. Skipping creation.${NC}"
    # Ensure the git remote is set correctly
    git remote add origin "https://github.com/$GH_USERNAME/$PROJECT_NAME.git" 2>/dev/null || git remote set-url origin "https://github.com/$GH_USERNAME/$PROJECT_NAME.git"
    git push origin main
else
    echo -e "${GREEN}Creating new GitHub repository...${NC}"
    gh repo create "$PROJECT_NAME" --private --source=. --push
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create GitHub repository.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Private GitHub repository created and initial commit pushed.${NC}"
fi

# --- Create and Push Develop Branch ---

echo -e "\n${GREEN}Step 3: Creating and pushing the 'develop' branch...${NC}"

# Idempotency Check: Create 'develop' branch if it doesn't exist locally
if git show-ref --verify --quiet refs/heads/develop; then
    echo -e "${YELLOW}Git branch 'develop' already exists locally. Skipping creation.${NC}"
else
    git checkout -b develop
    echo -e "${GREEN}✔ Git branch 'develop' created.${NC}"
fi

# Push the develop branch to GitHub and set it to track the remote branch
git push --set-upstream origin develop
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to push 'develop' branch to GitHub.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ 'develop' branch pushed to GitHub.${NC}"

# Switch back to the main branch for safety
git checkout main

# --- Netlify Site Creation and Configuration ---

echo -e "\n${GREEN}Step 4: Checking/Creating Netlify site...${NC}"

# Idempotency Check: See if a site is already linked to this directory
NETLIFY_SITE_ID=$(netlify status --json | jq -r '.siteData."site-id"')

if [ -n "$NETLIFY_SITE_ID" ]; then
    echo -e "${YELLOW}A Netlify site is already linked to this directory (ID: $NETLIFY_SITE_ID). Skipping creation.${NC}"
    SITE_INFO=$(netlify api getSite --data "{\"site_id\":\"$NETLIFY_SITE_ID\"}")
    NETLIFY_SITE_NAME=$(echo "$SITE_INFO" | grep '"name":' | sed -e 's/.*"name": "\(.*\)".*/\1/')
else
    echo -e "${GREEN}Creating new Netlify site...${NC}"
    NETLIFY_SITE_NAME="alexander-minchin-$PROJECT_NAME"
    # The --with-ci flag links the repo and enables continuous deployment for all branches.
    netlify sites:create --name "$NETLIFY_SITE_NAME" --with-ci --account-slug "$NETLIFY_ACCOUNT_ID"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create Netlify site. Please ensure your Netlify CLI is up-to-date ('npm install -g netlify-cli').${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Netlify site created and linked to the GitHub repo.${NC}"
    
    NETLIFY_SITE_ID=$(netlify status --json | jq -r '.siteData."site-id"')
    echo "Setting up branch deploys for site ID: $NETLIFY_SITE_ID"
    netlify api updateSite --data "{\"site_id\": \"$NETLIFY_SITE_ID\",\"body\": {\"build_settings\": {\"allowed_branches\": []}}}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to configure Netlify site for branch deploys.${NC}"
        exit 1
    fi
    echo "🎉 Success! Project '$NETLIFY_SITE_NAME' is now configured to deploy all branches from Git."
fi

# --- Set Netlify Environment Variables ---

echo -e "\n${GREEN}Step 5: Setting environment variables on Netlify...${NC}"
# These commands are idempotent; they will create or update the variables.

echo "Setting production variables (for 'main' branch)..."
netlify env:set SUPABASE_URL "$SUPABASE_URL"
netlify env:set SUPABASE_ANON_KEY "$SUPABASE_ANON_KEY"

echo "Setting variables for 'develop' branch context..."
# Use 'yes' to automatically confirm overwriting if the variables already exist.
yes | netlify env:set SUPABASE_URL "$SUPABASE_DEV_URL" --context develop
yes | netlify env:set SUPABASE_ANON_KEY "$SUPABASE_DEV_ANON_KEY" --context develop

echo "Setting variables for branch deploys..."
yes | netlify env:set SUPABASE_URL "$SUPABASE_DEV_URL" --context branch-deploy
yes | netlify env:set SUPABASE_ANON_KEY "$SUPABASE_DEV_ANON_KEY" --context branch-deploy

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to set one or more environment variables on Netlify.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Supabase environment variables have been set for all contexts.${NC}"

# --- Completion ---

echo -e "\n${GREEN}🎉 All done! Your project '$PROJECT_NAME' is ready.${NC}"
echo -e "- Local folder: $(pwd)"
echo -e "- GitHub Repo: https://github.com/$GH_USERNAME/$PROJECT_NAME"
echo -e "- Netlify Site Console: https://app.netlify.com/sites/$NETLIFY_SITE_NAME/overview"
echo -e "- Production URL (main): https://$NETLIFY_SITE_NAME.netlify.app"
echo -e "- Develop URL: https://develop--$NETLIFY_SITE_NAME.netlify.app"
