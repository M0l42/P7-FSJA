#!/usr/bin/env bash
# One-shot setup of the local ELK stack (run by the "setup" service of docker-compose-elk.yml).
# Passwords come from environment variables (.env, never committed) and are never printed.
set -euo pipefail

ES=http://elasticsearch:9200
auth=(-s -f -u "elastic:${ELASTIC_PASSWORD}" -H "Content-Type: application/json")

echo "Setting the kibana_system password"
curl "${auth[@]}" -X POST "$ES/_security/user/kibana_system/_password" \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}" > /dev/null

echo "Creating the least-privilege role and user used by Logstash (write to microcrm-logs-* only)"
curl "${auth[@]}" -X PUT "$ES/_security/role/microcrm_logs_writer" -d '{
  "cluster": ["monitor", "manage_index_templates"],
  "indices": [{ "names": ["microcrm-logs-*"], "privileges": ["create_index", "create_doc", "write"] }]
}' > /dev/null
curl "${auth[@]}" -X PUT "$ES/_security/user/logstash_internal" \
  -d "{\"password\":\"${LOGSTASH_PASSWORD}\",\"roles\":[\"microcrm_logs_writer\"]}" > /dev/null

echo "Creating the index template of the logs (field types used by the dashboards)"
curl "${auth[@]}" -X PUT "$ES/_index_template/microcrm-logs" -d '{
  "index_patterns": ["microcrm-logs-*"],
  "template": {
    "settings": { "number_of_shards": 1, "number_of_replicas": 0 },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "message":    { "type": "text" },
        "log":        { "properties": { "level": { "type": "keyword" }, "logger": { "type": "keyword" } } },
        "service":    { "properties": { "name": { "type": "keyword" } } },
        "event":      { "properties": { "dataset": { "type": "keyword" }, "outcome": { "type": "keyword" }, "duration": { "type": "long" } } },
        "http":       { "properties": {
                          "request":  { "properties": { "method": { "type": "keyword" } } },
                          "response": { "properties": { "status_code": { "type": "integer" }, "body": { "properties": { "bytes": { "type": "long" } } } } } } },
        "url":        { "properties": { "path": { "type": "keyword" }, "query": { "type": "keyword" } } },
        "response_time_ms": { "type": "float" },
        "error":      { "properties": { "type": { "type": "keyword" }, "message": { "type": "text" }, "stack_trace": { "type": "text" } } }
      }
    }
  }
}' > /dev/null

echo "Setup done"
