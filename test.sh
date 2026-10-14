#!/usr/bin/env bash
# Check the stack from localstack/commands.sh works the way the README describes:
# 1. the ECS service runs both Ollama tasks, registered behind the load balancer
# 2. the model answers through the load balancer, called the way the frontend calls it
# 3. the chatbot frontend is served from the S3 website and points at the load balancer
set -euo pipefail

MODEL_NAME=${MODEL_NAME:-tinyllama}
CLUSTER=OllamaCluster
SERVICE=OllamaService
LB_URL=${LB_URL:-http://ecs-load-balancer.elb.localhost.localstack.cloud:4566}
SITE_URL=${SITE_URL:-http://frontend-bucket.s3-website.us-east-1.localhost.localstack.cloud:4566}
MAX_WAIT_SECONDS=${MAX_WAIT_SECONDS:-900}

# wait_for <description> <command...>: retry the command every 10s until it succeeds
wait_for() {
  local description=$1 waited=0
  shift
  until "$@"; do
    if (( waited >= MAX_WAIT_SECONDS )); then
      echo "Test failed: $description not reached after ${MAX_WAIT_SECONDS}s"
      return 1
    fi
    sleep 10
    waited=$((waited + 10))
  done
}

service_running() {
  local desired running
  read -r desired running < <(lstk aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].[desiredCount,runningCount]' --output text)
  echo "ECS service: $running of $desired tasks running"
  [ "$running" = "$desired" ] && [ "$desired" -gt 0 ]
}

TG_ARN=$(lstk aws elbv2 describe-target-groups --names ecs-targets --query 'TargetGroups[0].TargetGroupArn' --output text)
targets_registered() {
  local targets
  targets=$(lstk aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
    --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]' --output text)
  echo "Targets:"; echo "${targets:-  none}"
  [ "$(echo "$targets" | grep -c .)" = "$1" ]
}

ollama_up() {
  curl -s -m 10 "$LB_URL/" | grep -q 'Ollama is running'
}

wait_for "both ECS tasks running" service_running
echo "PASS: the ECS service runs all its tasks"

desired=$(lstk aws ecs describe-services --cluster "$CLUSTER" --services "$SERVICE" --query 'services[0].desiredCount' --output text)
wait_for "$desired targets registered" targets_registered "$desired"
echo "PASS: each task is registered as a load balancer target"

wait_for "Ollama answering through the load balancer" ollama_up
echo "PASS: GET / through the load balancer returns 'Ollama is running'"

if ! curl -s -m 30 "$LB_URL/api/tags" | jq -e --arg m "$MODEL_NAME" 'any(.models[]; .name | startswith($m + ":"))' > /dev/null; then
  echo "Test failed: $MODEL_NAME is not in /api/tags"
  exit 1
fi
echo "PASS: $MODEL_NAME is baked into the image"

# Same request as frontend/chatbot/src/App.js: streamed, from the S3 website origin, to /api/generate/
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT
body=$(curl -sS -L -m 600 -D "$headers" -o - -w '\n%{http_code}' -X POST "$LB_URL/api/generate/" \
  -H 'Content-Type: application/json' -H "Origin: $SITE_URL" \
  -d "{\"model\": \"$MODEL_NAME\", \"prompt\": \"Why is the sky blue? Answer in one sentence.\", \"stream\": true, \"options\": {\"num_predict\": 48}}")
status=${body##*$'\n'}
body=${body%$'\n'*}
if [ "$status" != "200" ]; then
  echo "Test failed: POST /api/generate/ returned HTTP $status: $body"
  exit 1
fi
if ! grep -qi '^access-control-allow-origin:' "$headers"; then
  echo "Test failed: the response has no Access-Control-Allow-Origin header, so the browser would block it"
  cat "$headers"
  exit 1
fi
answer=$(echo "$body" | jq -rs 'map(.response // "") | join("")')
if ! echo "$body" | jq -se 'last | .done == true' > /dev/null || [ -z "${answer//[[:space:]]/}" ]; then
  echo "Test failed: the streamed answer did not complete: $body"
  exit 1
fi
echo "Model answer: $answer"
echo "PASS: $MODEL_NAME streamed an answer through the load balancer to the frontend's origin"

index=$(curl -s -m 30 "$SITE_URL/")
if [[ "$index" != *'<div id="root">'* ]]; then
  echo "Test failed: the S3 website did not serve the React app: $index"
  exit 1
fi
bundle=$(echo "$index" | grep -o '/static/js/main\.[a-z0-9]*\.js' | head -1)
if [ -z "$bundle" ] || ! curl -s -m 30 "$SITE_URL$bundle" | grep -q 'ecs-load-balancer.elb.localhost.localstack.cloud:4566/api/generate'; then
  echo "Test failed: the frontend bundle '$bundle' does not call the load balancer"
  exit 1
fi
echo "PASS: the S3 website serves the chatbot, which calls the load balancer"

echo "Test passed: Ollama on ECS answers through the ALB and the chatbot frontend is served"
