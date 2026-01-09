#!/bin/bash
set -e

# Configuration - Set these environment variables before running
# Required:
#   GCP_PROJECT_ID - Your GCP project ID
#   GCP_REGION - GCP region (e.g., us-central1)
#   CLOUD_SQL_INSTANCE - Cloud SQL instance connection name (PROJECT:REGION:INSTANCE)
#   DATABASE_URL - Full database connection string
#   DATABASE_SCHEMA - Database schema name (e.g., prod-$(git rev-parse --short HEAD))
#   PONDER_RPC_URL_1 - RPC URL for mainnet
#
# Optional:
#   INDEXER_CPU - CPU allocation for indexer (default: 2)
#   INDEXER_MEMORY - Memory for indexer (default: 4Gi)
#   API_CPU - CPU allocation for API (default: 1)
#   API_MEMORY - Memory for API (default: 2Gi)
#   API_MAX_INSTANCES - Max instances for API (default: 10)

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

if [ -z "$DATABASE_URL" ]; then
  echo "Error: DATABASE_URL is not set"
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

# Deploy Indexer Service (ponder start)
echo "Deploying indexer service..."
gcloud run deploy ponder-indexer \
  --source . \
  --dockerfile Dockerfile.indexer \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --min-instances 1 \
  --cpu "$INDEXER_CPU" \
  --memory "$INDEXER_MEMORY" \
  --set-env-vars "DATABASE_SCHEMA=$DATABASE_SCHEMA" \
  --set-env-vars "DATABASE_URL=$DATABASE_URL" \
  --set-env-vars "PONDER_RPC_URL_1=$PONDER_RPC_URL_1" \
  --set-env-vars "NODE_ENV=production" \
  --add-cloudsql-instances "$CLOUD_SQL_INSTANCE" \
  --no-allow-unauthenticated \
  --timeout 3600 \
  --platform managed

# Enable CPU always allocated for indexer (required for continuous indexing)
echo "Enabling CPU always allocated for indexer..."
gcloud run services update ponder-indexer \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --cpu-always-allocated

echo ""
echo "Indexer service deployed successfully!"
echo ""

# Deploy API Service (ponder serve)
echo "Deploying API service..."
gcloud run deploy ponder-api \
  --source . \
  --dockerfile Dockerfile.api \
  --region "$GCP_REGION" \
  --project "$GCP_PROJECT_ID" \
  --cpu "$API_CPU" \
  --memory "$API_MEMORY" \
  --max-instances "$API_MAX_INSTANCES" \
  --set-env-vars "DATABASE_SCHEMA=$DATABASE_SCHEMA" \
  --set-env-vars "DATABASE_URL=$DATABASE_URL" \
  --set-env-vars "NODE_ENV=production" \
  --add-cloudsql-instances "$CLOUD_SQL_INSTANCE" \
  --allow-unauthenticated \
  --timeout 300 \
  --platform managed

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

