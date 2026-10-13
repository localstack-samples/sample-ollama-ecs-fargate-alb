export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export AWS_DEFAULT_REGION=us-east-1
SHELL := /bin/bash

usage:		## Show this help
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$//' | sed -e 's/##//'

install:	## Install dependencies
	@which lstk || npm install -g @localstack/lstk
	cd localstack/frontend/chatbot && npm ci

start:		## Start LocalStack with the same settings as localstack/docker-compose.yml
	@test -n "${LOCALSTACK_AUTH_TOKEN}" || (echo "LOCALSTACK_AUTH_TOKEN is not set. Find your token at https://app.localstack.cloud/workspace/auth-token"; exit 1)
	@LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) \
		LOCALSTACK_DEBUG=1 \
		LOCALSTACK_ENFORCE_IAM=1 \
		LOCALSTACK_DISABLE_CORS_CHECKS=1 \
		LOCALSTACK_DISABLE_CUSTOM_CORS_S3=1 \
		lstk start

stop:		## Stop LocalStack
	@lstk stop

build:		## Build the React frontend
	cd localstack/frontend/chatbot && npm run build

deploy:		## Create the stack on LocalStack (builds and pushes the Ollama image)
	bash localstack/commands.sh

test:		## Check Ollama answers through the load balancer and the frontend is served
	./test.sh

logs:		## Save the logs in a separate file
	@lstk logs > logs.txt

.PHONY: usage install start stop build deploy test logs
