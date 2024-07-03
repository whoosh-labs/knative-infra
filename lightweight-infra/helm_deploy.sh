#!/bin/bash

# List of services and corresponding Helm chart names
services=("backend" "llm-platform-operators" "umap-operators" "cluster-operators" "data-loader" "esservice"
 "event-executor" "frontend" "llm-data-loader" "llm-node-backend" "llm-platform-api" "ll-platform-esservice"
 "plotly" "property-manager-client" "python-operator-batch-processor" "python-operator" 
  "status-updater" "umap-operators") 


for service in "${services[@]}"
do
    echo "Installing Helm chart for $service"
  
    helm install $service -f <service-yaml-file> .


    echo "Checking if pods are running for $service"
    until kubectl get pods | grep $service | grep Running
    do
        echo "Waiting for pods to be ready..."
        sleep 10
    done

    echo "Pods are running for $service"
done

echo "All services deployed successfully" >>helm.log
