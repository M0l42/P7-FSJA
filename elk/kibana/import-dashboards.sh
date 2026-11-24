#!/usr/bin/env bash
# Creates the Kibana data view "microcrm-logs-*" and imports the MicroCRM dashboard (microcrm-dashboard.ndjson).
# Idempotent: re-running it overwrites the same objects. Password read from .env, never printed.
# Usage: make elk-dashboards   (ELK must be running: make elk-up)
set -euo pipefail
cd "$(dirname "$0")/../.."

ELASTIC_PASSWORD=$(grep -E '^ELASTIC_PASSWORD=' .env | cut -d= -f2-)
KIBANA=${KIBANA:-http://localhost:5601}
auth=(-s -f -u "elastic:${ELASTIC_PASSWORD}" -H "kbn-xsrf: true")

echo "Data view microcrm-logs-*"
curl "${auth[@]}" -H "Content-Type: application/json" -X POST "$KIBANA/api/data_views/data_view" -d '{
  "override": true,
  "data_view": { "id": "microcrm-logs", "title": "microcrm-logs-*", "name": "MicroCRM logs", "timeFieldName": "@timestamp" }
}' > /dev/null

echo "Dashboard MicroCRM – Monitoring"
result=$(curl "${auth[@]}" -X POST "$KIBANA/api/saved_objects/_import?overwrite=true" \
  --form file=@elk/kibana/microcrm-dashboard.ndjson)
echo "$result" | grep -q '"success":true' || { echo "Import failed: $result"; exit 1; }

echo "Done: $KIBANA/app/dashboards#/view/mcrm-dashboard"
