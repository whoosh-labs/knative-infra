#!/bin/bash


helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update


helm install my-redis bitnami/redis


echo "Waiting for Redis pods to be in running state..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=redis --timeout=300s


helm status my-redis

echo "Redis installation completed successfully." >>redis.log
