#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 NODE1_IP KIBANA_CREDENTIALS CUSTOMER_ENV_PREFIX"
    exit 1
fi

# Assign the arguments to variables
NODE1_IP=$1
KIBANA_CREDENTIALS=$2
CUSTOMER_ENV_PREFIX=$3

# Variables
ELASTICSEARCH_URL="http://$NODE1_IP:9200"
KIBANA_URL="http://$NODE1_IP:5601"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
NDJSON_FILE="$SCRIPT_DIR/saved_objects_data_views.ndjson"
ILM_POLICIES_FILE="$SCRIPT_DIR/ilm_policies.json"
INDEX_TEMPLATES_FILE="$SCRIPT_DIR/index_templates.json"
S3_BUCKET_NAME="$CUSTOMER_ENV_PREFIX-elasticsearch-snapshots"
REPO_NAME="$CUSTOMER_ENV_PREFIX-elasticsearch-snapshots"
POLICY_NAME="$CUSTOMER_ENV_PREFIX-snapshot-policy"
SNAPSHOT_EXPIRY_LIMIT="30d"

# Function to display error message and exit
exit_with_error() {
  echo "Error: $1"
  exit 1
}

# Function to authenticate and get the Kibana session cookie
authenticate() {
  echo "Authenticating to Kibana..."
  response=$(curl -s -u $KIBANA_CREDENTIALS "$KIBANA_URL/api/status")
  if [ $? -ne 0 ]; then
    exit_with_error "Failed to authenticate. Check Kibana URL and credentials."
  fi
  echo "Authenticated successfully."
}

# Function to import objects using Kibana Import API
import_objects() {
  echo "Importing objects from $NDJSON_FILE..."
  response=$(curl -s -u $KIBANA_CREDENTIALS -X POST -H "kbn-xsrf: true" -F file=@$NDJSON_FILE "$KIBANA_URL/api/saved_objects/_import?createNewCopies=true")
  if [ $? -ne 0 ]; then
    exit_with_error "Failed to import objects. Check JSON file and Kibana connection."
  fi
  if echo "$response" | grep -q "error"; then
    exit_with_error "Failed to import objects. Kibana returned errors: $response"
  fi
  echo "Objects imported successfully."
}

create_ilm_policy() {
  local policy_name="$1"
  local policy_body="$2"

  local full_policy_name="$CUSTOMER_ENV_PREFIX-$policy_name"

  echo "Creating ILM policy '$full_policy_name'..."
  response=$(curl -s -u $KIBANA_CREDENTIALS -X PUT -H "Content-Type: application/json" -d "$policy_body" "$ELASTICSEARCH_URL/_ilm/policy/$full_policy_name")
  if ! echo "$response" | grep -q '"acknowledged":true'; then
    exit_with_error "Failed to create ILM policy '$full_policy_name'. Response: $response"
  fi
  echo "ILM policy '$full_policy_name' created successfully."
}

create_ilm_policies() {
  while IFS= read -r key; do
      value=$(jq '.["'"$key"'"]' $ILM_POLICIES_FILE)
      create_ilm_policy "$key" "$value"
  done < <(jq -r 'keys[]' $ILM_POLICIES_FILE)
}

create_index_template() {
  local template_name="$1"
  local template_body="$2"

  local full_template_name="$CUSTOMER_ENV_PREFIX-$template_name"
  template_body=$(echo $template_body | jq --arg CUSTOMER_ENV_PREFIX "$CUSTOMER_ENV_PREFIX" '.template.settings.index.lifecycle.name |= ($CUSTOMER_ENV_PREFIX + "-" + .)')

  echo "Creating Index Template '$full_template_name'..."
  response=$(curl -s -u $KIBANA_CREDENTIALS -X PUT -H "Content-Type: application/json" -d "$template_body" "$ELASTICSEARCH_URL/_index_template/$full_template_name")
  if ! echo "$response" | grep -q '"acknowledged":true'; then
    exit_with_error "Failed to create ILM policy '$full_template_name'. Response: $response"
  fi
  echo "Index Template '$full_template_name' created successfully."
}

create_index_templates() {
  while IFS= read -r key; do
      value=$(jq '.["'"$key"'"]' $INDEX_TEMPLATES_FILE)
      create_index_template "$key" "$value"
  done < <(jq -r 'keys[]' $INDEX_TEMPLATES_FILE)
}

create_snapshot_repository() {
  JSON_DATA=$(cat <<EOF
{
  "type": "s3",
  "settings": {
    "bucket": "$S3_BUCKET_NAME"
  }
}
EOF
)
  response=$(curl -s -u $KIBANA_CREDENTIALS -X PUT "$ELASTICSEARCH_URL/_snapshot/$REPO_NAME?pretty" -H 'Content-Type: application/json' -d "$JSON_DATA")
  if echo "$response" | grep -q "error"; then
    exit_with_error "Failed to create repository, returned errors: $response"
  fi
  echo "Repository created successfully."
}

create_snapshot_policy() {
  JSON_DATA=$(cat <<EOF
{
  "schedule": "0 30 1 * * ?",
  "name": "<daily-snap-{now/d}>",
  "repository": "$REPO_NAME",
  "config": {
    "ignore_unavailable": false,
    "include_global_state": false
  },
  "retention": {
    "expire_after": "$SNAPSHOT_EXPIRY_LIMIT",
    "min_count": 5,
    "max_count": 50
  }
}
EOF
)
  response=$(curl -s -u $KIBANA_CREDENTIALS -X PUT "$ELASTICSEARCH_URL/_slm/policy/$POLICY_NAME?pretty" -H 'Content-Type: application/json' -d "$JSON_DATA")
  if echo "$response" | grep -q "error"; then
    exit_with_error "Failed to create snapshot policy, returned errors: $response"
  fi
  echo "Snapshot policy created successfully."
}

# Main function
main() {
  authenticate
  import_objects
  create_ilm_policies
  create_index_templates
  create_snapshot_repository
  create_snapshot_policy
}

# Execute main function
main
