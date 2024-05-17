#!/bin/bash

# Check if the correct number of arguments are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 SSH_PRIVATE_KEY ES_PASSWORD NODE1_IP NODE2_IP"
    exit 1
fi

# Assign the arguments to variables
SSH_PRIVATE_KEY=$1
ES_PASSWORD=$2
NODE1_IP=$3
NODE2_IP=$4

# Variables
SSH_USERNAME="ubuntu"
ES_USERNAME="elastic"

# Create a temporary file to store the private key
temp_key_file=$(mktemp)
echo "$SSH_PRIVATE_KEY" > "$temp_key_file"
chmod 600 "$temp_key_file"

remote_token_path="/tmp/token"
local_token_path="./token"
scp -i "$temp_key_file" "$SSH_USERNAME@$NODE1_IP:$remote_token_path" "$local_token_path"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy the token from $NODE1_IP"
    rm -f "$temp_key_file"
    exit 1
fi

echo "Token successfully copied to $local_token_path"

scp -i "$temp_key_file" "$local_token_path" "$SSH_USERNAME@$NODE2_IP:$remote_token_path"
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy the token to $NODE2_IP"
    rm -f "$temp_key_file"
    exit 1
fi

echo "Token successfully copied to $NODE2_IP:$remote_token_path"

ssh -i "$temp_key_file" "ec2-user@$NODE2_IP" << EOF
yes y | sudo /usr/share/elasticsearch/bin/elasticsearch-reconfigure-node --enrollment-token \$(cat $remote_token_path) # TODO: Need to test this
if [ $? -ne 0 ]; then
    echo "Error: Failed to reconfigure Elasticsearch node"
    exit 1
fi

sudo systemctl restart elasticsearch.service
if [ $? -ne 0 ]; then
    echo "Error: Failed to restart Elasticsearch service"
    exit 1
fi

echo "Elasticsearch node reconfigured and service restarted successfully"
EOF

ssh -i "$temp_key_file" "$SSH_USERNAME@$NODE1_IP" << EOF
printf '$ES_PASSWORD\n$ES_PASSWORD' | sudo  /usr/share/elasticsearch/bin/elasticsearch-reset-password -u $ES_USERNAME -bi
sudo sed -i "/^#*network.host:/c\network.host: 0.0.0.0" /etc/elasticsearch/elasticsearch.yml
sudo systemctl restart elasticsearch.service
EOF

ssh -i "$temp_key_file" "$SSH_USERNAME@$NODE2_IP" << EOF
printf '$ES_PASSWORD\n$ES_PASSWORD' | sudo  /usr/share/elasticsearch/bin/elasticsearch-reset-password -u $ES_USERNAME -bi
sudo sed -i "/^#*network.host:/c\network.host: 0.0.0.0" /etc/elasticsearch/elasticsearch.yml
sudo systemctl restart elasticsearch.service
EOF

# Clean up the temporary private key file
rm -f "$temp_key_file"
