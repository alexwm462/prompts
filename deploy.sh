#!/bin/bash

# A script to create a simple test page for Supabase and deploy it to Netlify.
# This version uses the Supabase CLI to run a database migration and a Netlify
# Serverless Function to query the data for a full end-to-end test.
#
# This script will:
# 1. Link the Supabase project if it's not already linked.
# 2. Clean up old migration files.
# 3. Create a single, idempotent database migration file.
# 4. Use the Supabase CLI to push the migration to your live database non-interactively.
# 5. Create a serverless function that queries the 'games' table.
# 6. Commit and push all files to GitHub, triggering a Netlify deploy.

# --- Configuration and Pre-flight Checks ---

# Set colors for output messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting the full-stack test site deployment...${NC}"

# Check if we are inside a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${RED}Error: This script must be run from inside a git repository.${NC}"
    exit 1
fi

# Go to the root of the project
cd "$(git rev-parse --show-toplevel)"

# Check if .env file exists in the parent directory and source it for verification
if [ -f "../.env" ]; then
    # Export all variables from the .env file for use by sub-commands
    set -a
    source "../.env"
    set +a
else
    echo -e "${RED}Error: '.env' file not found in the parent directory (${PWD}/..).${NC}"
    exit 1
fi

# Check if required variables are set
if [ -z "$GITHUB_TOKEN" ] || [ -z "$SUPABASE_DB_PASSWORD" ] || [ -z "$SUPABASE_PROJECT_ID" ] || [ -z "$SUPABASE_ACCESS_TOKEN" ]; then
    echo -e "${RED}Error: One or more required variables are not set in the .env file.${NC}"
    echo -e "${YELLOW}Please ensure GITHUB_TOKEN, SUPABASE_DB_PASSWORD, SUPABASE_PROJECT_ID, and SUPABASE_ACCESS_TOKEN are all set.${NC}"
    echo -e "${YELLOW}You can generate an access token at: https://supabase.com/dashboard/account/tokens${NC}"
    exit 1
fi

# --- Database Migration ---
echo -e "\n${GREEN}Step 1: Linking project and applying database migration...${NC}"

# The Supabase CLI will automatically use the SUPABASE_ACCESS_TOKEN from the environment.
if [ ! -f "supabase/config.toml" ]; then
    echo -e "${YELLOW}Supabase project not initialized. Initializing now...${NC}"
    # Pipe 'n' to the init command to prevent it from asking about VS Code settings.
    echo "n" | supabase init
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to initialize Supabase project.${NC}"
        exit 1
    fi
fi

if [ ! -f "supabase/.temp/project-ref.txt" ]; then
    echo -e "${YELLOW}Supabase project not linked. Attempting to link now...${NC}"
    supabase link --project-ref "$SUPABASE_PROJECT_ID"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to link Supabase project.${NC}"
        echo -e "${YELLOW}Please check your SUPABASE_PROJECT_ID and SUPABASE_ACCESS_TOKEN in the .env file.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔ Supabase project linked successfully.${NC}"
else
    echo -e "${GREEN}✔ Supabase project is already linked.${NC}"
fi

MIGRATION_DIR="supabase/migrations"
mkdir -p "$MIGRATION_DIR"

PROJECT_NAME=$(basename "$(pwd)")
# Create a new migration file with a timestamp-project-name-description format
MIGRATION_FILE="${MIGRATION_DIR}/$(date +%Y%m%d%H%M%S)-${PROJECT_NAME}-<INSERT MIGRATION NAME HERE>.sql"

echo -e "${GREEN}Creating migration file: ${MIGRATION_FILE}${NC}"
cat <<EOF > "$MIGRATION_FILE"
<INSERT MIGRATION SQL HERE>
EOF

# Push the migration to the remote database
# The SUPABASE_DB_PASSWORD env var is automatically used by the CLI.
# Add --yes flag to make the command non-interactive.
echo -e "${GREEN}Pushing database migration...${NC}"
supabase db push --yes
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to push database migration.${NC}"
    echo -e "${YELLOW}Please ensure the Supabase CLI is installed, you are logged in, the project is linked, and your DB Password is correct.${NC}"
    exit 1
fi
echo -e "${GREEN}✔ Database migration applied successfully.${NC}"


# --- Create Project Structure ---

echo -e "\n${GREEN}Step 2: Creating project structure for serverless function...${NC}"

# Create netlify.toml to specify the functions directory
cat <<EOF > netlify.toml
[functions]
  directory = "netlify/functions"
EOF

# Create package.json to declare dependencies for the serverless function
cat <<EOF > package.json
{
  "name": "$(basename "$(pwd)")",
  "version": "1.0.0",
  "dependencies": {
    "@supabase/supabase-js": "^2.0.0"
  }
}
EOF

# Create the directory for the function
mkdir -p netlify/functions

# --- Create the Serverless Function ---
echo -e "${GREEN}Creating the serverless function to query the 'games' table...${NC}"
<INSERT CODE HERE FOR EACH SERVERLESS FUNCTION>

# --- Create Frontend Files ---
echo -e "${GREEN}Creating frontend files (index.html and script.js)...${NC}"

# Create index.html
cat <<EOF > index.html
<INSERT HTML CODE HERE>
EOF

# Create client-side script.js
cat <<'EOF' > script.js
<INSERT JAVASCRIPT CODE HERE>
EOF

echo -e "${GREEN}✔ Project files created successfully.${NC}"

# --- Git Commit and Push ---

echo -e "\n${GREEN}Step 3: Committing and pushing files to GitHub...${NC}"
# Remove old template files if they exist
git rm -r --cached templates >/dev/null 2>&1 || true
rm -rf templates

# Add all the new and modified files
git add .

# Only commit if there are actual changes staged
if ! git diff --staged --quiet; then
    git commit -m "feat: Add DB migration and query test"
    echo -e "${GREEN}✔ Changes committed.${NC}"
else
    echo -e "${YELLOW}No new file changes to commit.${NC}"
fi

# Get the original remote URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null)
if [ -z "$REMOTE_URL" ]; then
    echo -e "${RED}Error: No git remote named 'origin' found.${NC}"
    exit 1
fi

# Extract the repository path (e.g., user/repo) from the URL
REPO_PATH=$(echo "$REMOTE_URL" | sed -E 's/https?:\/\/[^/]+\/(.*)(\.git)?/\1/')

# Construct a new remote URL with the token for authentication
REMOTE_WITH_TOKEN="https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO_PATH}"

# Push using the authenticated URL
git push "${REMOTE_WITH_TOKEN}" main
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✔ Files pushed to GitHub. Netlify deployment triggered.${NC}"
else
    echo -e "${RED}Error: Failed to push to GitHub. Please check your GITHUB_TOKEN and repository name.${NC}"
    exit 1
fi

# --- Completion ---

echo -e "\n${GREEN}🎉 All done! Your test site will be live shortly.${NC}"
echo -e "You can monitor the deployment progress in your Netlify dashboard."
