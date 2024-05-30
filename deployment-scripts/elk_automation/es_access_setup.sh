#!/bin/bash

# Check if the minimum number of arguments is provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 SSH_PRIVATE_KEY ES_PASSWORD MASTER_NODE_IP GIT_PAT WORKER_NODE_IP1 WORKER_NODE_IP2 WORKER_NODE_IP3..."
    exit 1
fi

# Assign the arguments to variables
SSH_PRIVATE_KEY=$1
ES_PASSWORD=$2
MASTER_NODE_IP=$3
GIT_PAT=$4
WORKER_NODE_IPS=("${@:5}")

# Variables
SSH_USERNAME="ubuntu"
ES_USERNAME="elastic"
TF_TEMPLATE_FILE="whoosh-labs/esservices/main/src/main/resources/tf_template.txt"

# Create a temporary file to store the private key
temp_key_file=$(mktemp)
echo -e "$SSH_PRIVATE_KEY" > "$temp_key_file"
chmod 600 "$temp_key_file"

# Fetch the enrollment token from the master node
remote_token_path="/tmp/token"
local_token_path="./token"
scp -o "StrictHostKeyChecking no" -i "$temp_key_file" "$SSH_USERNAME@$MASTER_NODE_IP:$remote_token_path" "$local_token_path"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy the token from $MASTER_NODE_IP"
    rm -f "$temp_key_file"
    exit 1
fi
echo "Token successfully copied to $local_token_path"

# Configure each worker node
for WORKER_NODE_IP in "${WORKER_NODE_IPS[@]}"; do
    echo "Configuring worker node $WORKER_NODE_IP"

    # Copy the token to the worker node
    scp -o "StrictHostKeyChecking no" -i "$temp_key_file" "$local_token_path" "$SSH_USERNAME@$WORKER_NODE_IP:$remote_token_path"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy the token to $WORKER_NODE_IP"
        rm -f "$temp_key_file"
        exit 1
    fi

    echo "Token successfully copied to $WORKER_NODE_IP:$remote_token_path"

    # Reconfigure the worker node
    ssh -o "StrictHostKeyChecking no" -i "$temp_key_file" "$SSH_USERNAME@$WORKER_NODE_IP" << EOF
    yes y | sudo /usr/share/elasticsearch/bin/elasticsearch-reconfigure-node --enrollment-token \$(cat $remote_token_path)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to reconfigure Elasticsearch node"
        exit 1
    fi
    sudo systemctl restart elasticsearch
    if [ $? -ne 0 ]; then
        echo "Error: Failed to restart Elasticsearch service"
        exit 1
    fi
    echo "Elasticsearch node reconfigured and service restarted successfully"

    # Update Elasticsearch configuration
    sudo sed -i "/^#*network.host:/c\network.host: 0.0.0.0" /etc/elasticsearch/elasticsearch.yml
    sudo yq eval '.xpack.security.http.ssl.enabled = false' -i /etc/elasticsearch/elasticsearch.yml
    sudo chown root:elasticsearch /etc/elasticsearch/elasticsearch.yml
    sudo systemctl restart elasticsearch.service
EOF

    if [ $? -ne 0 ]; then
        echo "Error: Failed to configure Elasticsearch on worker node $WORKER_NODE_IP"
        rm -f "$temp_key_file"
        exit 1
    fi
done

# Configure the master node
ssh -o "StrictHostKeyChecking no" -i "$temp_key_file" "$SSH_USERNAME@$MASTER_NODE_IP" << EOF
printf '$ES_PASSWORD\n$ES_PASSWORD' | sudo /usr/share/elasticsearch/bin/elasticsearch-reset-password -u $ES_USERNAME -bi
sudo sed -i "/^#*network.host:/c\network.host: 0.0.0.0" /etc/elasticsearch/elasticsearch.yml
sudo yq eval '.xpack.security.http.ssl.enabled = false' -i /etc/elasticsearch/elasticsearch.yml
sudo chown root:elasticsearch /etc/elasticsearch/elasticsearch.yml
sudo systemctl restart elasticsearch.service
EOF

# Get Kibana bearer token and configure Kibana
KIBANA_BEARER_TOKEN=$(curl -s http://$MASTER_NODE_IP:9200/_security/enroll/kibana -u $ES_USERNAME:$ES_PASSWORD | jq '.token.value' | tr -d '"')
ssh -o "StrictHostKeyChecking no" -i "$temp_key_file" "$SSH_USERNAME@$MASTER_NODE_IP" << EOF
sudo sed -i '/^#*server.host:/c\\server.host: "0.0.0.0"' /etc/kibana/kibana.yml
sudo sed -i -e '/^#* *elasticsearch\.serviceAccountToken:/c\elasticsearch.serviceAccountToken: "'"$KIBANA_BEARER_TOKEN"'"' /etc/kibana/kibana.yml
sudo systemctl restart kibana.service
EOF

# Apply Terraform template
curl -sH "Authorization: token $GIT_PAT" -H "Accept: application/vnd.github.v3.raw" -O -L "https://raw.githubusercontent.com/$TF_TEMPLATE_FILE"
TF_TEMPLATE=$(cat tf_template.txt)
request_type=$(echo "$TF_TEMPLATE" | awk 'NR==1 {print $1}')
request_path=$(echo "$TF_TEMPLATE" | awk 'NR==1 {print $2}')
query=$(echo "$TF_TEMPLATE" | awk 'NR>1' | awk '{$1=$1};1')
curl -X $request_type "$MASTER_NODE_IP:9200/$request_path" -H "Content-Type: application/json" -d "$query" -u $ES_USERNAME:$ES_PASSWORD

# Clean up the temporary private key file
rm -f "$temp_key_file"
echo "Script execution completed successfully"
