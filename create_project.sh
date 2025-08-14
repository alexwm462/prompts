#!/bin/bash

# A script to automate the creation of a new project with Git, GitHub, and Netlify.
# This script is idempotent: it checks for existing resources before creating them.
#
# Prerequisites:
# 1. GitHub CLI ('gh') installed.
# 2. Netlify CLI ('netlify') installed and up-to-date.
# 3. A '.env' file in the same directory as this script with:
#    - GITHUB_TOKEN (Personal Access Token with 'repo' scope)
#    - NETLIFY_AUTH_TOKEN (Personal Access Token)
#    - SUPABASE_URL
#    - SUPABASE_ANON_KEY
#    - NETLIFY_ACCOUNT_ID (e.g., "alexwm462")

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
    exit 1
fi

# Check if required tokens and keys are set
if [ -z "$GITHUB_TOKEN" ] || [ -z "$NETLIFY_AUTH_TOKEN" ] || [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
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
else
    echo -e "${GREEN}Creating new GitHub repository...${NC}"
    gh repo create "$PROJECT_NAME" --private --source=. --push
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create GitHub repository.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Private GitHub repository created and initial commit pushed.${NC}"
fi

# --- Netlify Site Creation and Configuration ---

echo -e "\n${GREEN}Step 3: Checking/Creating Netlify site...${NC}"

# Idempotency Check: See if a site is already linked to this directory
NETLIFY_SITE_ID=$(netlify status | grep 'Site ID:' | awk '{print $3}' 2>/dev/null)

if [ -n "$NETLIFY_SITE_ID" ]; then
    echo -e "${YELLOW}A Netlify site is already linked to this directory (ID: $NETLIFY_SITE_ID). Skipping creation.${NC}"
    SITE_INFO=$(netlify api getSite --data "{\"site_id\":\"$NETLIFY_SITE_ID\"}")
    NETLIFY_SITE_NAME=$(echo "$SITE_INFO" | grep '"name":' | sed -e 's/.*"name": "\(.*\)".*/\1/')
else
    echo -e "${GREEN}Creating new Netlify site...${NC}"
    if [ -z "$NETLIFY_ACCOUNT_ID" ]; then
        echo -e "${RED}Error: NETLIFY_ACCOUNT_ID is not set in your .env file.${NC}"
        echo -e "${YELLOW}Please add 'NETLIFY_ACCOUNT_ID=\"your_team_slug\"' to your .env file (e.g., \"alexwm462\").${NC}"
        exit 1
    fi

    NETLIFY_SITE_NAME="alexander-minchin-$PROJECT_NAME"
    # The --repo flag is deprecated. The CLI now automatically detects the git remote in the current directory.
    netlify sites:create --name "$NETLIFY_SITE_NAME" --with-ci --account-slug "$NETLIFY_ACCOUNT_ID"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create Netlify site. Please ensure your Netlify CLI is up-to-date ('npm install -g netlify-cli').${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Netlify site created and linked to the GitHub repo.${NC}"
fi

# --- Set Netlify Environment Variables ---

echo -e "\n${GREEN}Step 4: Setting environment variables on Netlify...${NC}"
# This command is idempotent; it will create or update the variables.
netlify env:set SUPABASE_URL "$SUPABASE_URL"
netlify env:set SUPABASE_ANON_KEY "$SUPABASE_ANON_KEY"

# Set the URL for the 'develop' context
yes | netlify env:set SUPABASE_URL "$SUPABASE_DEV_URL" --context develop
yes | netlify env:set SUPABASE_ANON_KEY "$SUPABASE_DEV_ANON_KEY" --context develop

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to set environment variables on Netlify.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Supabase environment variables have been set/updated.${NC}"

# --- Completion ---

echo -e "\n${GREEN}🎉 All done! Your project '$PROJECT_NAME' is ready.${NC}"
echo -e "- Local folder: $(pwd)"
echo -e "- GitHub Repo: https://github.com/$GH_USERNAME/$PROJECT_NAME"
echo -e "- Netlify Site Console: https://app.netlify.com/sites/$NETLIFY_SITE_NAME/overview"
echo -e "- Netlify Site: https://$NETLIFY_SITE_NAME.netlify.app"
