#!/bin/bash
set -e

source .env.prod

DATABASE_SCHEMA="prod-$(git rev-parse --short HEAD)"

# Configuration - Set these environment variables before running
# Required:
#   GCP_PROJECT_ID - Your GCP project ID
#   GCP_REGION - GCP region (e.g., us-central1)
#   CLOUD_SQL_INSTANCE - Cloud SQL instance connection name (PROJECT:REGION:INSTANCE)
#   PONDER_RPC_URL_1 - RPC URL for mainnet
#   DB_USER - Database user (default: postgres)
#   DB_NAME - Database name
#   DB_PASSWORD_SECRET - Secret name in Secret Manager containing the password
#
# Optional:
#   INDEXER_CPU - CPU allocation for indexer (default: 2)
#   INDEXER_MEMORY - Memory for indexer (default: 4Gi)
#   API_CPU - CPU allocation for API (default: 1)
#   API_MEMORY - Memory for API (default: 2Gi)
#   API_MAX_INSTANCES - Max instances for API (default: 10)
#   SECRET_VERSION - Secret version to use (default: latest)

# Validate required environment variables
if [ -z "$GCP_PROJECT_ID" ]; then
  echo "Error: GCP_PROJECT_ID is not set"
  exit 1
fi

if [ -z "$GCP_REGION" ]; then
  echo "Error: GCP_REGION is not set"
  exit 1
fi

if [ -z "$CLOUD_SQL_INSTANCE" ]; then
  echo "Error: CLOUD_SQL_INSTANCE is not set"
  exit 1
fi

if [ -z "$DATABASE_SCHEMA" ]; then
  echo "Error: DATABASE_SCHEMA is not set"
  exit 1
fi

if [ -z "$PONDER_RPC_URL_1" ]; then
  echo "Error: PONDER_RPC_URL_1 is not set"
  exit 1
fi

# Validate database connection configuration
if [ -z "$DB_PASSWORD_SECRET" ]; then
  echo "Error: DB_PASSWORD_SECRET must be set"
  exit 1
fi

if [ -z "$DB_NAME" ]; then
  echo "Error: DB_NAME is required"
  exit 1
fi

DB_USER=${DB_USER:-postgres}

# Set defaults for optional variables
INDEXER_CPU=${INDEXER_CPU:-2}
INDEXER_MEMORY=${INDEXER_MEMORY:-4Gi}
API_CPU=${API_CPU:-1}
API_MEMORY=${API_MEMORY:-2Gi}
API_MAX_INSTANCES=${API_MAX_INSTANCES:-10}

echo "Deploying Ponder services to Cloud Run..."
echo "Project: $GCP_PROJECT_ID"
echo "Region: $GCP_REGION"
echo "Schema: $DATABASE_SCHEMA"
echo ""

# Build environment variables and secrets for indexer
INDEXER_ENV_VARS="DATABASE_SCHEMA=$DATABASE_SCHEMA,PONDER_RPC_URL_1=$PONDER_RPC_URL_1,PONDER_WS_URL_1=$PONDER_WS_URL_1,NODE_ENV=production,DB_USER=$DB_USER,DB_NAME=$DB_NAME,CLOUD_SQL_INSTANCE=$CLOUD_SQL_INSTANCE"
INDEXER_SECRETS="DB_PASSWORD=$DB_PASSWORD_SECRET"

# Deploy Indexer Service (ponder start)
echo "Deploying indexer service..."
# Temporarily copy Dockerfile for Cloud Run build (--source requires Dockerfile in root)
cp Dockerfile.indexer Dockerfile

gcloud run deploy ponder-indexer \
  --source . \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --min-instances 1 \
  --cpu "$INDEXER_CPU" \
  --memory "$INDEXER_MEMORY" \
  --set-env-vars "$INDEXER_ENV_VARS" \
  --set-secrets "$INDEXER_SECRETS" \
  --add-cloudsql-instances "$CLOUD_SQL_INSTANCE" \
  --no-allow-unauthenticated \
  --timeout 3600 \
  --platform managed

# Clean up temporary Dockerfile
rm -f Dockerfile
trap - EXIT


echo ""
echo "Indexer service deployed successfully!"
echo ""

# Build environment variables and secrets for API
API_ENV_VARS="DATABASE_SCHEMA=$DATABASE_SCHEMA,NODE_ENV=production,DB_USER=$DB_USER,DB_NAME=$DB_NAME,CLOUD_SQL_INSTANCE=$CLOUD_SQL_INSTANCE"
API_SECRETS="DB_PASSWORD=$DB_PASSWORD_SECRET"

# Deploy API Service (ponder serve)
echo "Deploying API service..."
# Temporarily copy Dockerfile for Cloud Run build (--source requires Dockerfile in root)
cp Dockerfile.api Dockerfile

gcloud run deploy ponder-api \
  --source . \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --cpu "$API_CPU" \
  --memory "$API_MEMORY" \
  --max-instances "$API_MAX_INSTANCES" \
  --set-env-vars "$API_ENV_VARS" \
  --set-secrets "$API_SECRETS" \
  --add-cloudsql-instances "$CLOUD_SQL_INSTANCE" \
  --allow-unauthenticated \
  --timeout 300 \
  --platform managed

# Clean up temporary Dockerfile
rm -f Dockerfile
trap - EXIT

echo ""
echo "API service deployed successfully!"
echo ""
echo "Deployment complete!"
echo ""
echo "Indexer URL (private):"
gcloud run services describe ponder-indexer \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --format "value(status.url)"
echo ""
echo "API URL (public):"
gcloud run services describe ponder-api \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --format "value(status.url)"

