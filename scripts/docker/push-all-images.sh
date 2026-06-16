#!/bin/bash

set -e

AWS_ACCOUNT_ID=524338476341
AWS_REGION=eu-central-1

ECR_REGISTRY=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

VERSION=4.0.1

images=(
petclinic-config-server
petclinic-discovery-server
petclinic-api-gateway
petclinic-customers-service
petclinic-vets-service
petclinic-visits-service
petclinic-genai-service
petclinic-admin-server
)

for image in "${images[@]}"
do
  echo "Pushing $image..."

  docker tag \
    ${image}:${VERSION} \
    ${ECR_REGISTRY}/${image}:${VERSION}

  docker push \
    ${ECR_REGISTRY}/${image}:${VERSION}
done
