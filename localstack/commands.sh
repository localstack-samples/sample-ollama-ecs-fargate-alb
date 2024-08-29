#!/bin/bash

export VPC_ID=$(awslocal ec2 create-vpc --cidr-block 10.0.0.0/16 | jq -r '.Vpc.VpcId')

export SUBNET_ID1=$(awslocal ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  | jq -r '.Subnet.SubnetId')

export SUBNET_ID2=$(awslocal ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  | jq -r '.Subnet.SubnetId')


export INTERNET_GW_ID=$(awslocal ec2 create-internet-gateway | jq -r '.InternetGateway.InternetGatewayId')
awslocal ec2 attach-internet-gateway \
  --internet-gateway-id $INTERNET_GW_ID \
  --vpc-id $VPC_ID

export RT_ID=$(awslocal ec2 create-route-table \
  --vpc-id $VPC_ID | jq -r '.RouteTable.RouteTableId')

awslocal ec2 associate-route-table \
  --route-table-id $RT_ID \
  --subnet-id $SUBNET_ID1

awslocal ec2 associate-route-table \
  --route-table-id $RT_ID \
  --subnet-id $SUBNET_ID2

awslocal ec2 create-route \
  --route-table-id $RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $INTERNET_GW_ID


#Service side SG

export SG_ID1=$(awslocal ec2 create-security-group \
  --group-name ApplicationLoadBalancerSG \
  --description "Security Group of the Load Balancer" \
  --vpc-id $VPC_ID | jq -r '.GroupId')

awslocal ec2 authorize-security-group-ingress \
  --group-id $SG_ID1 \
  --protocol tcp \
  --port 80 --cidr 0.0.0.0/0

# LB side SG

export SG_ID2=$(awslocal ec2 create-security-group \
  --group-name ContainerFromLoadBalancerSG \
  --description "Inbound traffic from the First Load Balancer" \
  --vpc-id $VPC_ID \
  | jq -r '.GroupId')

 # Port # 0-65535

awslocal ec2 authorize-security-group-ingress \
  --group-id $SG_ID2 \
  --protocol tcp \
  --port 11434 \
  --source-group $SG_ID1

export LB_ARN=$(awslocal elbv2 create-load-balancer \
  --name ecs-load-balancer \
  --subnets $SUBNET_ID1 $SUBNET_ID2 \
  --security-groups $SG_ID1 \
  --scheme internet-facing \
  | jq -r '.LoadBalancers[0].LoadBalancerArn')

export TG_ARN=$(awslocal elbv2 create-target-group \
  --name ecs-targets \
  --protocol HTTP \
  --port 11434 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --health-check-protocol HTTP \
  --region us-east-1 \
  --health-check-path / \
  --health-check-interval-seconds 10 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  | jq -r '.TargetGroups[0].TargetGroupArn')


awslocal elbv2 modify-target-group-attributes \
  --target-group-arn $TG_ARN \
  --attributes Key=deregistration_delay.timeout_seconds,Value=10


awslocal elbv2 create-listener \
    --load-balancer-arn $LB_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=$TG_ARN

# Create repository for the image


awslocal ecr create-repository --repository-name ollama-service

export MODEL_NAME=tinyllama

docker build --build-arg MODEL_NAME=$MODEL_NAME -t ollama-service .

docker tag ollama-service:latest 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4510/ollama-service:latest
docker push 000000000000.dkr.ecr.us-east-1.localhost.localstack.cloud:4510/ollama-service:latest

awslocal ecs create-cluster --cluster-name OllamaCluster


awslocal iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://ecs-task-trust-policy.json

export ECS_TASK_PARN=$(awslocal iam create-policy \
  --policy-name ecsTaskPolicy \
  --policy-document file://ecs-task-policy.json | jq -r '.Policy.Arn')

awslocal iam attach-role-policy \
  --role-name ecsTaskRole \
  --policy-arn $ECS_TASK_PARN

awslocal iam update-assume-role-policy \
  --role-name ecsTaskRole \
  --policy-document file://ecs-cloudwatch-policy.json


awslocal iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-trust-policy.json

export ECS_TASK_EXEC_PARN=$(awslocal iam create-policy \
  --policy-name ecsTaskExecutionPolicy \
  --policy-document file://ecs-task-exec-policy.json | jq -r '.Policy.Arn')

awslocal iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn $ECS_TASK_EXEC_PARN

awslocal iam update-assume-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-document file://ecs-cloudwatch-policy.json


awslocal logs create-log-group --log-group-name ollama-service-logs

awslocal ecs register-task-definition \
  --family ollama-task \
  --cli-input-json file://task_definition.json


awslocal ecs create-service \
  --cluster OllamaCluster \
  --service-name OllamaService \
  --task-definition ollama-task \
  --desired-count 2 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNET_ID1,$SUBNET_ID2],securityGroups=[$SG_ID2],assignPublicIp=ENABLED}" \
  --load-balancers "targetGroupArn=$TG_ARN,containerName=ollama-container,containerPort=11434"


  awslocal s3 mb s3://frontend-bucket

  awslocal s3 website s3://frontend-bucket --index-document index.html

 awslocal s3api put-public-access-block \
  --bucket frontend-bucket \
  --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

  awslocal s3api put-bucket-policy \
  --bucket frontend-bucket \
  --policy file://bucket-policy.json

  awslocal s3 sync ./frontend/chatbot/build s3://frontend-bucket
