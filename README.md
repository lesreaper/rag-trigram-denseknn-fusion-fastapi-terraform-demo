
# RAG PoC Infrastructure

This was made for a company as a demo take-home test. 4 days of work with a full 30 minute presentation (Keynote).

It was fully deployed on AWS with Terraform, and a fully matching local containerized Docker environment. 

This system will ingest any CSV or CSV link and allow you to look up information on it using Trigram and Dense KNN in a sensor fusion setup.

I didn't add the agentic ingestion using LlamaIndex to help on the data ingestion and parsing. Only thing I would have changed or added for the demo, but 4 days of work was enough. There is a LOT to fix here, but it's an UNPAID DEMO. 

Didn't get the gig. Anybody hiring? ¯\\\_(ツ)_/¯

## Quick Local Start

```
cd ui-frontend
pnpm i (npi i or yarn, whatever)
cd ..
docker compose up --build
```
Everything should load on localhost:3000

## Quick AWS start

```
aws configure sso --profile ProfileName
aws sts get-caller-identity --profile ProfileName
```

```bash
cd infra
terraform init && terraform plan -out plan.tfout
terraform apply plan.tfout
```

