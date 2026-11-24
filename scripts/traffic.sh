#!/usr/bin/env bash
# Simulated traffic for the monitoring dashboards (ELK). MicroCRM has no real users: this script reproduces
# a realistic usage so that Kibana shows volume, peaks, errors and response times. The data it creates is fake.
#
# Usage: scripts/traffic.sh [duration_seconds]      (default 300; the app must be running: make up)
#   API=http://localhost:8080 FRONT=http://localhost:4200 scripts/traffic.sh 180
#
# Profile, per second during the run:
#   - about 1 user action per second: mostly reads, some creations and edits, page loads on the front;
#   - about 5% of actions end in an error, as real clients do: unknown records (404), malformed
#     requests (400), malformed identifiers and deleting an organization that has members (both 500);
#   - an activity peak: for 20 seconds around 40% of the run, about 30 requests per second.
set -uo pipefail

DURATION=${1:-300}
API=${API:-http://localhost:8080}
FRONT=${FRONT:-http://localhost:4200}
JSON=(-H "Content-Type: application/json")

req() { curl -s -o /dev/null -m 5 "$@" || true; }

# Front page load: index.html, then the JavaScript and CSS files it references
front_page() {
  local route=$1 html
  html=$(curl -s -m 5 "$FRONT$route") || return 0
  for asset in $(grep -oE '(src|href)="[^"]+\.(js|css)"' <<<"$html" | cut -d'"' -f2); do
    req "$FRONT/${asset#/}"
  done
}

ids=(1)   # persons known to exist (1 = demo data); extended with the persons created by the script
action() {
  local r=$((RANDOM % 100)) id=${ids[RANDOM % ${#ids[@]}]}
  if   (( r < 30 )); then req "$API/persons"
  elif (( r < 45 )); then req "$API/persons/$id"
  elif (( r < 55 )); then req "$API/organizations"; req "$API/organizations/1/persons"
  elif (( r < 63 )); then front_page "/"
  elif (( r < 68 )); then front_page "/persons/$id"
  elif (( r < 80 )); then
    local n=$RANDOM new
    new=$(curl -s -m 5 "${JSON[@]}" -X POST "$API/persons" \
      -d "{\"firstName\":\"Test$n\",\"lastName\":\"Traffic\",\"email\":\"test$n@example.net\"}" \
      | grep -oE '/persons/[0-9]+' | head -1 | cut -d/ -f3)
    [[ -n "$new" ]] && ids+=("$new")
  elif (( r < 90 )); then req "${JSON[@]}" -X PATCH "$API/persons/$id" -d "{\"phone\":\"06$RANDOM\"}"
  elif (( r < 95 )); then req "$API/persons/search/findByEmail?email=jdoe@example.net"
  # ~5% errors
  elif (( r < 97 )); then req "$API/persons/$((900000 + RANDOM))"                       # 404 unknown record
  elif (( r < 98 )); then req "${JSON[@]}" -X POST "$API/persons" -d '{"firstName":'    # 400 malformed JSON
  elif (( r < 99 )); then req "$API/persons/not-a-number"                               # 500 malformed id (bug)
  else                    req -X DELETE "$API/organizations/1"                          # 500 delete with members (bug)
  fi
}

curl -s -o /dev/null -m 5 "$API/persons" || { echo "API not reachable on $API: start the app first (make up)"; exit 1; }

start=$(date +%s); peak_start=$((DURATION * 2 / 5)); peak_end=$((peak_start + 20)); count=0
echo "Simulated traffic for ${DURATION}s on $API and $FRONT (peak between ${peak_start}s and ${peak_end}s)"
while (( $(date +%s) - start < DURATION )); do
  elapsed=$(( $(date +%s) - start ))
  if (( elapsed >= peak_start && elapsed < peak_end )); then
    for _ in $(seq 1 30); do action & done; wait; count=$((count + 30)); sleep 1
  else
    action; count=$((count + 1)); sleep "0.$((5 + RANDOM % 10))"
  fi
  (( count % 50 == 0 )) && echo "  ${elapsed}s: ${count} actions"
done
echo "Done: ${count} actions in ${DURATION}s"
