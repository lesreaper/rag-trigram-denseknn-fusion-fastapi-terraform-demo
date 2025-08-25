#!/bin/bash
AWS_ACCOUNT_ID=
AWS_REGION=
PROFILE=

# Login to ECR
aws ecr get-login-password --region $AWS_REGION --profile $PROFILE \
  | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# API
docker buildx build --platform linux/amd64 -t rag-api:0.11 -f api/Dockerfile api
docker tag rag-api:0.11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/rag-api:0.11
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/rag-api:0.11

# UI
docker buildx build --platform linux/amd64 -t rag-ui:0.11 -f ui-frontend/Dockerfile.prod ui-frontend
docker tag rag-ui:0.11 $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/rag-ui:0.11
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/rag-ui:0.11
