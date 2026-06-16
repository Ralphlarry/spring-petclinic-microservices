#!/bin/bash

set -e

declare -A SERVICES=(
  [spring-petclinic-config-server]="8888"
  [spring-petclinic-discovery-server]="8761"
  [spring-petclinic-api-gateway]="8080"
  [spring-petclinic-customers-service]="8081"
  [spring-petclinic-visits-service]="8082"
  [spring-petclinic-vets-service]="8083"
  [spring-petclinic-genai-service]="8084"
  [spring-petclinic-admin-server]="9090"
)

VERSION=4.0.1

for SERVICE in "${!SERVICES[@]}"
do
  PORT=${SERVICES[$SERVICE]}

  IMAGE_NAME=$(echo $SERVICE | sed 's/spring-//')

  echo "Building $IMAGE_NAME..."

  docker build \
    -f docker/Dockerfile \
    -t ${IMAGE_NAME}:${VERSION} \
    --build-arg ARTIFACT_NAME=${SERVICE}-${VERSION} \
    --build-arg EXPOSED_PORT=${PORT} \
    ${SERVICE}/target
done
