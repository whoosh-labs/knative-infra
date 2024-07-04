#!/bin/bash

# Namespace
namespace="raga"

# Function to check the status of a job
check_job_status() {
  local job_name=$1
  local namespace=$2
  local timeout=300  # Total wait time of 5 minutes (300 seconds)
  local interval=30  # Check interval of 30 seconds
  local elapsed=0

  while [[ $elapsed -lt $timeout ]]; do
    job_status=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')

    if [[ "$job_status" == "True" ]]; then
      echo "Job $job_name completed successfully."
      return 0
    fi

    echo "Waiting for job $job_name to complete..."
    sleep $interval
    elapsed=$((elapsed + interval))
  done

  echo "Job $job_name did not complete within the timeout period."
  return 1
}

# Array of job names, configs, and job files
jobs=("db-migration" "es-templates" "property-manager")
configs=("db-migration-config.yaml" "es-templates-config.yaml" "property-manager-config.yaml")
job_files=("db-migration-job.yaml" "es-templates-job.yaml" "property-manager-job.yaml")

# Loop through each pair of config and job files
for i in "${!jobs[@]}"; do
  job_name="${jobs[$i]}"
  config="${configs[$i]}"
  job_file="${job_files[$i]}"

  echo "Applying config: $config"
  kubectl apply -f "$config" -n "$namespace"

  echo "Applying job: $job_file"
  kubectl apply -f "$job_file" -n "$namespace"

  # Check the status of the job
  if check_job_status "$job_name" "$namespace"; then
    echo "Proceeding to the next job."
  else
    echo "Job $job_name failed to complete within the timeout period. Exiting."
    exit 1
  fi
done

echo "All jobs completed successfully."