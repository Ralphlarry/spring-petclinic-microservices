#!/bin/bash

AWS_REGION=eu-central-1

repos=(
petclinic-config-server
petclinic-discovery-server
petclinic-api-gateway
petclinic-customers-service
petclinic-vets-service
petclinic-visits-service
petclinic-genai-service
petclinic-admin-server
)

for repo in "${repos[@]}"
do
  aws ecr create-repository \
    --repository-name $repo \
    --image-scanning-configuration scanOnPush=true \
    --region $AWS_REGION
done
