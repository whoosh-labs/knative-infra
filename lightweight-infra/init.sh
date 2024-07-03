#!/bin/bash

set -x  # Exit script on any error

az login --identity
az keyvault secret show --name raga-test1-secrets --vault-name raga-test1-secrets --query value -o tsv > /tmp/secrets.json | tr -d '"'

# Add Docker's official GPG key and repository
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose

# Install necessary tools: kubectl, Helm, Minikube, MySQL Operator
sudo apt-get install -y curl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Install Minikube
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

sudo usermod -aG docker ubuntu

# Start Minikube (adjust options as needed)
sudo -u ubuntu minikube start --driver=docker


# Function to check Minikube status
check_minikube_status() {
  status=$(sudo -u ubuntu minikube status | grep -i "host" | awk '{print $2}')
  echo "Minikube status: $status"
  if [ "$status" == "Running" ]; then
    echo "Minikube is running."
    exit 0
  else
    echo "Minikube is not running."
    sudo usermod -aG docker ubuntu 
    sudo -u ubuntu minikube start --driver=docker
  fi
}

# Loop to check Minikube status every 30 seconds
while true; do
  check_minikube_status
  echo "Waiting for 30 seconds before next check..."
  sleep 10
done

mkdir ~/.kube
cat /home/ubuntu/.kube/config > ~/.kube/config

cat ~/.kube/config

# Add MySQL Operator Helm repository and install MySQL Operator
git clone https://github.com/mysql/mysql-operator.git
helm repo add mysql-operator https://mysql.github.io/mysql-operator/
helm repo update
helm install mysql-operator mysql-operator/mysql-operator --namespace mysql-operator --create-namespace

# Change directory to MySQL InnoDB Cluster Helm chart
cd mysql-operator/helm/mysql-innodbcluster/


MYSQL_USERNAME=$(jq ".MYSQL_USERNAME" /tmp/secrets.json | tr -d '"')
MYSQL_PASSWORD=$(jq ".MYSQL_PASSWORD" /tmp/secrets.json | tr -d '"') 


# Use a here document to create or update values.yaml
cat <<EOF > values.yaml
image:
  pullPolicy: IfNotPresent
  pullSecrets:
    enabled: false
    secretName:

credentials:
  root:
    user: $MYSQL_USERNAME
    password: $MYSQL_PASSWORD
    host: "%"

tls:
  useSelfSigned: true

serverInstances: 1
routerInstances: 1
baseServerId: 1000

podSpec:
  containers:
  - name: mysql
    resources:
      requests:
        memory: "1024Mi"
        cpu: "1000m"
      limits:
        memory: "1536Mi"
        cpu: "1500m"

disableLookups: false
EOF

# Install MySQL InnoDB Cluster using Helm
helm install mycluster mysql-operator/mysql-innodbcluster \
    --namespace mysql-operator \
    -f values.yaml

# Check pods and resources
kubectl get pods -n mysql-operator
kubectl get innodbcluster -n mysql-operator

echo "Installation completed successfully"
