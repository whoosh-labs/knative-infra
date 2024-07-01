
#!/bin/bash

# Script to setup MySQL on Minikube using Helm and the MySQL Operator

# Exit immediately if a command exits with a non-zero status
set -e

# Add Helm GPG key
echo "Adding Helm GPG key..."
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -

# Install apt-transport-https
echo "Installing apt-transport-https..."
sudo apt-get install apt-transport-https --yes

# Add Helm stable repository
echo "Adding Helm stable repository..."
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

# Update apt package index
echo "Updating apt package index..."
sudo apt-get update

# Install Helm
echo "Installing Helm..."
sudo apt-get install helm

# Check Helm version
echo "Checking Helm version..."
helm version

# Add MySQL Operator Helm repository
echo "Adding MySQL Operator Helm repository..."
helm repo add mysql-operator https://mysql.github.io/mysql-operator/

# Update Helm repositories
echo "Updating Helm repositories..."
helm repo update

# Clone and install MySQL Operator
echo "Cloning MySQL Operator repository..."
git clone https://github.com/mysql/mysql-operator.git
cd mysql-operator

echo "Installing MySQL Operator..."
helm install mysql-operator mysql-operator/mysql-operator --namespace mysql-operator --create-namespace

# Change directory to mysql-innodbcluster/
cd helm/mysql-innodbcluster/

# Replace values.yaml with the edited version
echo "Creating custom values.yaml..."
cat <<EOF > values.yaml
image:
  pullPolicy: IfNotPresent
  pullSecrets:
    enabled: false
    secretName:

credentials:
  root:
    user: root
    password: raga123
    host: "%"

tls:
  useSelfSigned: true
#  caSecretName:
#  serverCertAndPKsecretName:
#  routerCertAndPKsecretName: # or use router.certAndPKsecretName

#serverVersion: 8.0.31
serverInstances: 1
routerInstances: 1 # or use router.instances
baseServerId: 1000

podSpec:
  containers:
  - name: mysql
    resources:
      requests:
        memory: "1024Mi"  # adapt to your needs
        cpu: "1000m"      # adapt to your needs
      limits:
        memory: "1536Mi"  # adapt to your needs
        cpu: "1500m"      # adapt to your needs

disableLookups: false
EOF

# Make the init.sh script executable
echo "Making the init.sh script executable..."
chmod +x init.sh

# Install MySQL InnoDB Cluster using Helm
echo "Installing MySQL InnoDB Cluster..."
helm install mycluster mysql-operator/mysql-innodbcluster \
    --namespace mysql-operator \
    -f values.yaml

# Check pods in mysql-operator namespace
echo "Checking pods in mysql-operator namespace..."
kubectl get po -n mysql-operator

# Check InnoDB Cluster resources
echo "Checking InnoDB Cluster resources..."
kubectl get innodbcluster -n mysql-operator

# Check pods in mysql-operator namespace again
echo "Checking pods in mysql-operator namespace again..."
kubectl get po -n mysql-operator

echo "MySQL InnoDB Cluster setup completed successfully!"
