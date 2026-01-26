# Ponder Deployment Guide for Google Cloud Run

This guide explains how to deploy Ponder on Google Cloud Run with Cloud SQL (Postgres).

## Prerequisites

1. Google Cloud Project with billing enabled
2. Cloud SQL (Postgres) instance created in the same region
3. `gcloud` CLI installed and authenticated
4. Required environment variables set (see below)

## Environment Variables

Before deploying, set these required environment variables:

```bash
export GCP_PROJECT_ID="your-project-id"
export GCP_REGION="us-central1"  # Must match Cloud SQL region
export CLOUD_SQL_INSTANCE="PROJECT:REGION:INSTANCE"  # e.g., "myproject:us-central1:myinstance"
export DATABASE_URL="postgres://USER:PASSWORD@/DBNAME?host=/cloudsql/PROJECT:REGION:INSTANCE"
export DATABASE_SCHEMA="prod-$(git rev-parse --short HEAD)"  # Unique schema per deployment
export PONDER_RPC_URL_1="https://your-rpc-endpoint"  # Mainnet RPC URL
```

### Optional Environment Variables

```bash
export INDEXER_CPU="2"              # Default: 2
export INDEXER_MEMORY="4Gi"         # Default: 4Gi
export API_CPU="1"                  # Default: 1
export API_MEMORY="2Gi"             # Default: 2Gi
export API_MAX_INSTANCES="10"       # Default: 10
```

## Deployment

1. Navigate to the ponder directory:
   ```bash
   cd ponder
   ```

2. Run the deployment script:
   ```bash
   ./deploy.sh
   ```

The script will:
- Deploy the indexer service (`ponder start`) with:
  - Minimum 1 instance (always running)
  - CPU always allocated (for continuous indexing)
  - Private (no public access)
  
- Deploy the API service (`ponder serve`) with:
  - Auto-scaling (0 to max instances)
  - Public access enabled
  - Same database schema as indexer

## Architecture

- **Indexer Service**: Runs `ponder start`, continuously indexes blockchain data. Must stay running.
- **API Service**: Runs `ponder serve`, serves HTTP API. Can scale based on traffic.

Both services connect to the same Cloud SQL instance but use the same schema to share data.

## Health Checks

- `/health` - Returns 200 immediately (use for liveness)
- `/ready` - Returns 200 only when caught up to realtime (use for readiness)

## Important Notes

1. **Database Schema**: Each deployment must use a unique schema. The script uses `DATABASE_SCHEMA` env var.
2. **CPU Always Allocated**: The indexer service has CPU always allocated to ensure indexing continues even without HTTP traffic.
3. **Min Instances**: The indexer has `min-instances=1` to prevent scaling to zero.
4. **Region**: Cloud SQL and Cloud Run should be in the same region to minimize latency (<50ms recommended by Ponder).

## Troubleshooting

- If indexing stops: Check that CPU always allocated is enabled on the indexer service
- If API can't connect: Verify both services use the same `DATABASE_SCHEMA`
- If slow indexing: Check database latency (should be <50ms roundtrip)

