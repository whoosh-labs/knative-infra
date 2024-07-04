#!/bin/bash

set -x  # Exit script on any error

DOMAIN=$1
CUSTOMER_NAME=$2
ENVIRONEMNT_NAME=$3

az login --identity
az keyvault secret show --name $CUSTOMER_NAME-$ENVIRONEMNT_NAME-secrets --vault-name $CUSTOMER_NAME-$ENVIRONEMNT_NAME-secrets --query value -o tsv > /tmp/secrets.json | tr -d '"'

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
sudo -u ubuntu minikube start --cpus 14 --memory 30720 --driver=docker
sleep 30
sudo -u ubuntu minikube status | grep -i "host" | awk '{print $2}'

# # Function to check Minikube status
# check_minikube_status() {
#   status=$(sudo -u ubuntu minikube status | grep -i "host" | awk '{print $2}')
#   echo "Minikube status: $status"
#   if [ "$status" == "Running" ]; then
#     echo "Minikube is running." 
#     sleep 20
#     exit 0
#   else
#     echo "Minikube is not running."
#     sudo usermod -aG docker ubuntu 
#     sudo -u ubuntu minikube start --driver=docker
#   fi
# }

# # Loop to check Minikube status every 30 seconds
# while true; do
#   check_minikube_status
#   echo "Waiting for 30 seconds before next check..."
#   sleep 10
# done

# mkdir /.kube
# cat /home/ubuntu/.kube/config > /.kube/config

# Add MySQL Operator Helm repository and install MySQL Operator
# git clone https://github.com/mysql/mysql-operator.git
sudo -u ubuntu helm repo add mysql-operator https://mysql.github.io/mysql-operator/
sudo -u ubuntu helm repo update
sudo -u ubuntu helm install mysql-operator mysql-operator/mysql-operator --namespace mysql-operator --create-namespace

# Change directory to MySQL InnoDB Cluster Helm chart
# cd mysql-operator/helm/mysql-innodbcluster/


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
sudo -u ubuntu helm install mycluster mysql-operator/mysql-innodbcluster \
    --namespace mysql-operator \
    -f values.yaml


until sudo -u ubuntu kubectl get pods -n mysql-operator | grep mycluster-0 | grep Running
do
    echo "Waiting for mysql cluster pods to be ready..."
    sleep 10
done

sudo -u ubuntu kubectl apply /knative-infra/lightweight-infra/post-execution-scripts/export-db-to-nodeport.yaml

sudo -u ubuntu minikube service mycluster-nodeport -n mysql-operator --url

bash /knative-infra/lightweight-infra/post-execution-scripts/flyway_automation.sh $(jq ".GITHUB_PASWWROD" /tmp/secrets.json | tr -d '"') $(jq ".MYSQL_USERNAME" /tmp/secrets.json | tr -d '"') $(jq ".MYSQL_PASSWORD" /tmp/secrets.json | tr -d '"') 192.168.49.2 31100

sudo -u ubuntu helm repo add bitnami https://charts.bitnami.com/bitnami
sudo -u ubuntu helm install redis bitnami/redis --set auth.enabled=false --set architecture=standalone -n redis --create-namespace
sudo -u ubuntu helm repo add elastic https://helm.elastic.co
sudo -u ubuntu helm repo update
sudo -u ubuntu helm install elastic-operator elastic/eck-operator -n elk --create-namespace
sudo -u ubuntu kubectl create secret generic elastic-serch-cluster-es-elastic-user -n elk --from-literal=elastic=$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"') 
sudo -u ubuntu kubectl apply -f es-kibana.yaml -n elk
sed -i "s/elastic_search_password/$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"')"/g logstash.yaml
sudo -u ubuntu helm upgrade --install elk-logstash --version 8.5.1 --namespace elk -f logstash.yaml elastic/logstash
sudo -u ubuntu helm upgrade --install elk-filebeat --version 8.5.1 --namespace elk -f filebeat.yaml elastic/filebeat
sudo -u ubuntu kubectl create ns raga
sudo -u ubuntu kubectl create ns raga-models
sudo -u ubuntu kubectl create secret generic backend -n raga --from-literal=API_HOST=https://backend.${DOMAIN}/api --from-literal=AWS_BUCKET_NAME=$(jq ".AWS_S3_BUCKET" /tmp/secrets.json | tr -d '"') --from-literal=AWS_REGION=$(jq ".AWS_S3_BUCKET_REGION" /tmp/secrets.json | tr -d '"') --from-literal=FRONTEND_URL=https://${DOMAIN} --from-literal=GITHUB_CLIENT_ID="NA" --from-literal=GITHUB_CLIENT_SECRET="NA" --from-literal=GOOGLE_CLIENT_ID="NA" --from-literal=GOOGLE_CLIENT_SECRET="NA" --from-literal=JWT_SECRET="NA" --from-literal=MYSQL_PASSWORD=$(jq ".MYSQL_PASSWORD" /tmp/secrets.json | tr -d '"') --from-literal=MYSQL_URL="mycluster.mysql-operator.svc.cluster.local" --from-literal=MYSQL_USERNAME=$(jq ".MYSQL_USERNAME" /tmp/secrets.json | tr -d '"')
sudo -u ubuntu kubectl create secret generic cluster-operators -n raga --from-literal=ELASTIC_PASSWORD=$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"') --from-literal=S3_BUCKET=$(jq ".AWS_S3_BUCKET" /tmp/secrets.json | tr -d '"')
sudo -u ubuntu kubectl create secret generic llm-data-loader -n raga --from-literal=ELASTIC_PASSWORD=$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"') --from-literal=S3_BUCKET=$(jq ".AWS_S3_BUCKET" /tmp/secrets.json | tr -d '"')
sudo -u ubuntu kubectl create secret generic llm-platform-api -n raga --from-literal=AES_ENCRYPTION_KEY=$(jq ".AES_ENCRYPTION_KEY" /tmp/secrets.json | tr -d '"') --from-literal=API_HOST=https://backend.${DOMAIN}/api --from-literal=AWS_BUCKET_NAME=$(jq ".AWS_S3_BUCKET" /tmp/secrets.json | tr -d '"') --from-literal=AWS_REGION=$(jq ".AWS_S3_BUCKET_REGION" /tmp/secrets.json | tr -d '"') --from-literal=ENV_TYPE=$(jq ".ENV_NAME" /tmp/secrets.json | tr -d '"') --from-literal=FRONTEND_URL="https://llm-${DOMAIN}" --from-literal=GITHUB_CLIENT_ID="NA" --from-literal=GITHUB_CLIENT_SECRET="NA" --from-literal=GOOGLE_CLIENT_ID="NA" --from-literal=GOOGLE_CLIENT_SECRET="NA" --from-literal=JWT_SECRET="NA" --from-literal=MYSQL_PASSWORD=$(jq ".MYSQL_PASSWORD" /tmp/secrets.json | tr -d '"') --from-literal=MYSQL_URL="mycluster.mysql-operator.svc.cluster.local" --from-literal=MYSQL_USERNAME="$(jq ".MYSQL_USERNAME" /tmp/secrets.json | tr -d '"')"
sudo -u ubuntu kubectl create secret generic llm-platform-operators -n raga --from-literal=ELASTIC_PASSWORD=$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"') --from-literal=S3_BUCKET="$(jq ".AWS_S3_BUCKET" /tmp/secrets.json | tr -d '"')"
sudo -u ubuntu kubectl create secret generic model-packager -n raga-models --from-literal=DOCKERHUB_PASSWORD=$(jq ".DOCKERHUB_PASSWORD" /tmp/secrets.json | tr -d '"') --from-literal=DOCKERHUB_USERNAME="$(jq ".DOCKERHUB_USERNAME" /tmp/secrets.json | tr -d '"')"
sudo -u ubuntu kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=$(jq ".DOCKERHUB_USERNAME" /tmp/secrets.json | tr -d '"') --docker-password=$(jq ".DOCKERHUB_PASSWORD" /tmp/secrets.json | tr -d '"') --docker-email=$(jq ".DOCKERHUB_EMAIL" /tmp/secrets.json | tr -d '"') -n raga
sudo -u ubuntu kubectl create secret docker-registry regcred --docker-server=https://index.docker.io/v1/ --docker-username=$(jq ".DOCKERHUB_USERNAME" /tmp/secrets.json | tr -d '"') --docker-password=$(jq ".DOCKERHUB_PASSWORD" /tmp/secrets.json | tr -d '"') --docker-email=$(jq ".DOCKERHUB_EMAIL" /tmp/secrets.json | tr -d '"') -n raga-models


until sudo -u ubuntu kubectl get pods -n mysql-operator | grep mycluster-0 | grep Running
do
    echo "Waiting for mysql cluster pods to be ready..."
    sleep 10
done

sed -i "s/GITHUB_PASSWORD/$(jq ".GITHUB_PASWWROD" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/es-templates-job.yaml
sed -i "s/ELASTIC_SEARCH_PASSWORD/$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/es-templates-job.yaml
sudo -u ubuntu kubectl apply -f /knative-infra/lightweight-infra/post-execution-scripts/es-templates-configmap.yaml
sudo -u ubuntu kubectl apply -f /knative-infra/lightweight-infra/post-execution-scripts/es-templates-job.yaml


cd raga-testing-platform

# services=("frontend") 

services=( "frontend" "backend") 

for service in "${services[@]}"
do
    echo "Installing Helm chart for $service"
  
    sudo -u ubuntu helm install $service -f $service.yaml . -n raga

    echo "Checking if pods are running for $service"
    until sudo -u ubuntu kubectl get pods -n raga | grep $service | grep Running
    do
        echo "Waiting for pods to be ready..."
        sleep 10
    done
    echo "Pods are running for $service"
done
echo "All services deployed successfully"
sudo -u ubuntu minikube service frontend-nodeport -n raga --url



sed -i "s/CUSTOMER_NAME/$CUSTOMER_NAME/g" /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/ENVIRONMENT_NAME/$ENVIRONEMNT_NAME/g" /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/AWS_S3_BUCKET_REGION/$(jq ".AWS_S3_BUCKET_REGION" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/ELASTIC_SEARCH_PASSWORD/$(jq ".ELASTIC_SEARCH_PASSWORD" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/MYSQL_FQDN/mycluster.mysql-operator.svc.cluster.local/g" /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/MYSQL_USERNAME/$(jq ".MYSQL_USERNAME" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/MYSQL_PASSWORD/$(jq ".MYSQL_PASSWORD" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml
sed -i "s/AWS_S3_BUCKET/$(jq ".AWS_S3_BUCKET" /tmp/secrets.json | tr -d '"')"/g /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml


sudo -u ubuntu kubectl apply -f /knative-infra/lightweight-infra/post-execution-scripts/property-manager-config.yaml
sudo -u ubuntu kubectl apply -f /knative-infra/lightweight-infra/post-execution-scripts/property-manager-job.yaml


## proxy configuration
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod proxy_balancer
sudo a2enmod lbmethod_byrequests


cat <<EOF > /etc/apache2/sites-available/reverse-proxy-frontend.conf
<VirtualHost *:80>
    ServerName $DOMAIN

    ProxyRequests Off
    ProxyPreserveHost On

    <Proxy *>
        Require all granted
    </Proxy>

    ProxyPass / http://192.168.49.2:31000/
    ProxyPassReverse / http://192.168.49.2:31000/

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# cat <<EOF > /etc/apache2/sites-available/reverse-proxy-backend.conf
# <VirtualHost *:80>
#     ServerName backend.$DOMAIN

#     ProxyRequests Off
#     ProxyPreserveHost On

#     <Proxy *>
#         Require all granted
#     </Proxy>

#     ProxyPass / http://192.168.49.2:32000/
#     ProxyPassReverse / http://192.168.49.2:32000/

#     ErrorLog \${APACHE_LOG_DIR}/error.log
#     CustomLog \${APACHE_LOG_DIR}/access.log combined
# </VirtualHost>
# EOF

sudo a2ensite reverse-proxy-frontend.conf
# sudo a2ensite reverse-proxy-backend.conf
sudo systemctl restart apache2
