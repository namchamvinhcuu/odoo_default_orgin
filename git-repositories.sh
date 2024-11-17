#!/bin/bash

# Directory to store repositories
REPO_DIR="/home/namchamvinhcuu/workspace/odoo15/autonsi-projects/almus-tech/addons"

# Replace with your GitHub token and organization name
TOKEN=""
ORG_NAME="autonsi-almus"
IGNORE_LIST="ignore_repos.txt" # File containing repositories to ignore
PAGE=1

# Define color codes
LIGHT_GRAY='\033[0;37m'
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
RED='\033[1;31m'
RESET='\033[0m'

# Store the current directory
CURRENT_DIR=$(pwd)

# Ensure IGNORE_LIST has an absolute path
IGNORE_LIST_PATH="$CURRENT_DIR/$IGNORE_LIST"

# Check if jq is installed
if ! command -v jq &>/dev/null; then
  echo "jq is required but not installed. Please install jq."
  exit 1
fi

# Check if IGNORE_LIST file exists, if not, set it to an empty string
if [ ! -f "$IGNORE_LIST_PATH" ]; then
  echo "Ignore list file not found. Continuing with no ignored repositories."
  IGNORE_LIST_PATH=""
fi

# Function to check if a repository should be ignored
should_ignore() {
  local repo_name=$1
  # If IGNORE_LIST_PATH is empty, do not ignore any repositories
  if [ -z "$IGNORE_LIST_PATH" ]; then
    return 1
  fi
  grep -qxF "$repo_name" "$IGNORE_LIST_PATH"
}

# Track the status of each repository
declare -A STATUS
declare -A REPOS_BY_STATUS

while :; do
  echo "Fetching repositories from page $PAGE..."

  # Fetch repository URLs
  RESPONSE=$(curl -s -H "Authorization: token $TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/orgs/$ORG_NAME/repos?per_page=100&page=$PAGE")

  if [ $? -ne 0 ]; then
    echo "Failed to fetch repositories. Please check your network connection and API token."
    exit 1
  fi

  # Extract repository URLs
  REPOS=$(echo "$RESPONSE" | jq -r '.[].clone_url')

  if [ -z "$REPOS" ]; then
    echo "No more repositories found or reached end of list."
    break
  fi

  # Navigate to the repositories directory
  cd "$REPO_DIR" || exit

  for REPO in $REPOS; do
    REPO_NAME=$(basename -s .git "$REPO")

    if should_ignore "$REPO_NAME"; then
      STATUS[$REPO_NAME]="ignored"
      REPOS_BY_STATUS[ignored]+="$REPO_NAME\n"
      echo "Ignoring repository $REPO_NAME"
      continue
    fi

    if [ -d "$REPO_NAME" ]; then
      echo "Directory $REPO_NAME exists. Pulling latest changes..."
      cd "$REPO_NAME" || exit
      OUTPUT=$(git pull 2>&1)
      echo "$OUTPUT"

      GIT_PULL_STATUS=$? # Capture the exit status of `git pull`

      if echo "$OUTPUT" | grep -q "Already up to date"; then
        STATUS[$REPO_NAME]="unchanged"
        REPOS_BY_STATUS[unchanged]+="$REPO_NAME\n"
      elif [ $GIT_PULL_STATUS -eq 0 ]; then
        STATUS[$REPO_NAME]="updated"
        REPOS_BY_STATUS[updated]+="$REPO_NAME\n"
      else
        STATUS[$REPO_NAME]="error"
        REPOS_BY_STATUS[error]+="$REPO_NAME\n"
      fi
      cd "$REPO_DIR" || exit
    else
      echo "Directory $REPO_NAME does not exist. Cloning repository..."
      git clone "$REPO"
      if [ $? -eq 0 ]; then
        STATUS[$REPO_NAME]="cloned"
        REPOS_BY_STATUS[cloned]+="$REPO_NAME\n"
      else
        STATUS[$REPO_NAME]="error"
        REPOS_BY_STATUS[error]+="$REPO_NAME\n"
      fi
    fi
  done

  # Return to the current directory after processing each page
  cd "$CURRENT_DIR" || exit

  PAGE=$((PAGE + 1))
done

# Report statuses with color, ordered by status
echo -e "\nSummary:"
echo "------------------------------"

# Ordered list of statuses
for STATUS_TYPE in ignored unchanged updated cloned error; do
  case $STATUS_TYPE in
  ignored)
    COLOR=$LIGHT_GRAY
    ;;
  unchanged)
    COLOR=$YELLOW
    ;;
  updated)
    COLOR=$YELLOW
    ;;
  cloned)
    COLOR=$GREEN
    ;;
  error)
    COLOR=$RED
    ;;
  esac

  if [ -n "${REPOS_BY_STATUS[$STATUS_TYPE]}" ]; then
    echo -e "${COLOR}${STATUS_TYPE^}: ${RESET}"
    echo -e "${REPOS_BY_STATUS[$STATUS_TYPE]}" | sed 's/^\n//'
  fi
done

echo "------------------------------"
