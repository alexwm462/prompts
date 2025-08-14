#!/bin/bash

# A script to tear down a project created by the setup script.
# This will permanently delete the local directory, the GitHub repository,
# and the Netlify site.
#
# WARNING: This action is irreversible.

# --- Configuration and Pre-flight Checks ---

# Set colors for output messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting the project teardown process...${NC}"
echo -e "${RED}WARNING: This script will permanently delete local files, a GitHub repository, and a Netlify site.${NC}"

# Check if .env file exists and source it
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}Error: '.env' file not found.${NC}"
    echo -e "${YELLOW}Please ensure you are running this script from the same directory that contains the .env file.${NC}"
    exit 1
fi

# Check if required tokens are set
if [ -z "$GITHUB_TOKEN" ] || [ -z "$NETLIFY_AUTH_TOKEN" ]; then
    echo -e "${RED}Error: GITHUB_TOKEN or NETLIFY_AUTH_TOKEN is not set in the .env file.${NC}"
    exit 1
fi

# Check for required CLIs
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI ('gh') is not installed. Please install it to continue.${NC}"
    exit 1
fi
if ! command -v netlify &> /dev/null; then
    echo -e "${RED}Error: Netlify CLI ('netlify') is not installed. Please install it to continue.${NC}"
    exit 1
fi

# --- User Input and Confirmation ---

read -p "Enter the name of the project to delete: " PROJECT_NAME

if [ -z "$PROJECT_NAME" ]; then
    echo -e "${RED}Error: Project name cannot be empty.${NC}"
    exit 1
fi

# Authenticate with GitHub and get username
GH_USERNAME=$(gh api user -q .login)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to authenticate with GitHub. Is your GITHUB_TOKEN valid?${NC}"
    exit 1
fi

# Construct the full names of the resources to be deleted
REPO_NAME="$GH_USERNAME/$PROJECT_NAME"
NETLIFY_SITE_NAME="alexander-minchin-$PROJECT_NAME"

echo -e "\n${YELLOW}You are about to permanently delete the following resources:${NC}"
echo -e "- Local Directory: ${YELLOW}./$PROJECT_NAME/${NC}"
echo -e "- GitHub Repo:     ${YELLOW}$REPO_NAME${NC}"
echo -e "- Netlify Site:    ${YELLOW}$NETLIFY_SITE_NAME${NC}"

read -p "Are you absolutely sure? This action cannot be undone. Type 'DELETE' to confirm: " CONFIRMATION

if [ "$CONFIRMATION" != "DELETE" ]; then
    echo -e "${GREEN}Teardown cancelled.${NC}"
    exit 0
fi

cd "./$PROJECT_NAME" || {
    echo -e "${RED}Error: Could not change to project directory '$PROJECT_NAME'. Does it exist?${NC}"
    exit 1
}

# --- Deletion Process ---

# Step 1: Delete the Netlify Site
echo -e "\n${GREEN}Step 1: Deleting Netlify site...${NC}"
NETLIFY_SITE_ID=$(netlify status --json | jq -r '.siteData."site-id"')
# The '--force' flag bypasses the interactive confirmation from the Netlify CLI
if netlify sites:delete "$NETLIFY_SITE_ID" --force; then
    echo -e "${GREEN}✔ Netlify site '$NETLIFY_SITE_NAME' deleted successfully.${NC}"
else
    # This is a warning, not an error, as the user may have already deleted it manually.
    echo -e "${YELLOW}Warning: Could not delete Netlify site '$NETLIFY_SITE_NAME'. It might have been already deleted or the name is incorrect.${NC}"
fi

# Step 2: Delete the GitHub Repository
echo -e "\n${GREEN}Step 2: Deleting GitHub repository...${NC}"
# The '--yes' flag confirms the deletion for the GitHub CLI
if gh repo delete "$REPO_NAME" --yes; then
    echo -e "${GREEN}✔ GitHub repository '$REPO_NAME' deleted successfully.${NC}"
else
    echo -e "${YELLOW}Warning: Could not delete GitHub repository '$REPO_NAME'. It might have been already deleted or the name is incorrect.${NC}"
fi

# Step 3: Delete the Local Project Directory
echo -e "\n${GREEN}Step 3: Deleting local project directory...${NC}"
# Safety check: if the current path ends with the project name, move up one level.
if [[ "$(pwd)" == *"/$PROJECT_NAME" ]]; then
    echo -e "${YELLOW}Changing directory out of '$PROJECT_NAME' before deleting...${NC}"
    cd ..
fi

if [ -d "$PROJECT_NAME" ]; then
    rm -rf "$PROJECT_NAME"
    echo -e "${GREEN}✔ Local directory '$PROJECT_NAME' deleted successfully.${NC}"
else
    echo -e "${YELLOW}Warning: Local directory '$PROJECT_NAME' not found. Skipping deletion.${NC}"
fi

# --- Completion ---

echo -e "\n${GREEN}🎉 Teardown complete! All specified resources for '$PROJECT_NAME' have been removed.${NC}"
