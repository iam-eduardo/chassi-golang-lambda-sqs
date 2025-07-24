#!/bin/bash

set -e

REGION="us-east-1"
SQS_IN="minha-fila"
SQS_SNS="fila-sns"
SNS_TOPIC="meu-topico"
FUNCTION_NAME="hello-world-lambda"
ROLE_ARN="arn:aws:iam::000000000000:role/lambda-role"
ZIP_FILE="lambda.zip"
HANDLER="main"
MSG_ORIG='"msg": "mensagem de teste"'

echo -e "\n=== Criando o tópico SNS ==="
SNS_ARN=$(aws --endpoint-url=http://localhost:4566 --region $REGION sns create-topic --name $SNS_TOPIC --query TopicArn --output text)
echo "SNS_ARN=$SNS_ARN"

echo -e "\n=== Criando fila SQS de entrada ==="
aws --endpoint-url=http://localhost:4566 --region $REGION sqs create-queue --queue-name $SQS_IN || true
SQS_IN_URL=$(aws --endpoint-url=http://localhost:4566 --region $REGION sqs get-queue-url --queue-name $SQS_IN --query QueueUrl --output text)
SQS_IN_ARN=$(aws --endpoint-url=http://localhost:4566 --region $REGION sqs get-queue-attributes --queue-url $SQS_IN_URL --attribute-name QueueArn --query 'Attributes.QueueArn' --output text)
echo "SQS_IN_URL=$SQS_IN_URL"
echo "SQS_IN_ARN=$SQS_IN_ARN"

echo -e "\n=== Criando fila SQS listener do SNS ==="
aws --endpoint-url=http://localhost:4566 --region $REGION sqs create-queue --queue-name $SQS_SNS || true
SQS_SNS_URL=$(aws --endpoint-url=http://localhost:4566 --region $REGION sqs get-queue-url --queue-name $SQS_SNS --query QueueUrl --output text)
SQS_SNS_ARN=$(aws --endpoint-url=http://localhost:4566 --region $REGION sqs get-queue-attributes --queue-url $SQS_SNS_URL --attribute-name QueueArn --query 'Attributes.QueueArn' --output text)
echo "SQS_SNS_URL=$SQS_SNS_URL"
echo "SQS_SNS_ARN=$SQS_SNS_ARN"

echo -e "\n=== Inscrevendo fila-sns no SNS ==="
aws --endpoint-url=http://localhost:4566 --region $REGION sns subscribe \
  --topic-arn $SNS_ARN \
  --protocol sqs \
  --notification-endpoint $SQS_SNS_ARN > /dev/null

echo -e "\n=== Permitindo SNS enviar para fila-sns ==="
aws --endpoint-url=http://localhost:4566 --region $REGION sqs set-queue-attributes \
  --queue-url $SQS_SNS_URL \
  --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"sns.amazonaws.com\\\"},\\\"Action\\\":\\\"sqs:SendMessage\\\",\\\"Resource\\\":\\\"$SQS_SNS_ARN\\\",\\\"Condition\\\":{\\\"ArnEquals\\\":{\\\"aws:SourceArn\\\":\\\"$SNS_ARN\\\"}}}]}\"}"

echo -e "\n=== Buildando e deployando a Lambda ==="
GOOS=linux GOARCH=amd64 go build -o main main.go
rm -f $ZIP_FILE
"/c/Program Files/7-Zip/7z.exe" a $ZIP_FILE main > /dev/null

aws --endpoint-url=http://localhost:4566 --region $REGION lambda delete-function --function-name $FUNCTION_NAME || true

aws --endpoint-url=http://localhost:4566 --region $REGION lambda create-function \
  --function-name $FUNCTION_NAME \
  --runtime go1.x \
  --handler $HANDLER \
  --zip-file fileb://$ZIP_FILE \
  --role $ROLE_ARN \
  --environment Variables="{SNS_TOPIC_ARN=$SNS_ARN,AWS_REGION=$REGION}"

echo -e "\n=== Permitindo SQS invocar Lambda ==="
aws --endpoint-url=http://localhost:4566 --region $REGION lambda add-permission \
  --function-name $FUNCTION_NAME \
  --statement-id sqs-permission \
  --action "lambda:InvokeFunction" \
  --principal "sqs.amazonaws.com" \
  --source-arn $SQS_IN_ARN || true

echo -e "\n=== Criando mapping da SQS de entrada para Lambda ==="
aws --endpoint-url=http://localhost:4566 --region $REGION lambda create-event-source-mapping \
  --function-name $FUNCTION_NAME \
  --batch-size 1 \
  --event-source-arn $SQS_IN_ARN || true

echo -e "\n=== Enviando mensagem para fila de entrada ==="
aws --endpoint-url=http://localhost:4566 --region $REGION sqs send-message \
  --queue-url $SQS_IN_URL \
  --message-body "{$MSG_ORIG}"

echo -e "\nAguardando processamento da Lambda/SNS (5s)..."
sleep 5

echo -e "\n=== Mensagem recebida pela fila-sns (via SNS) ==="
aws --endpoint-url=http://localhost:4566 --region $REGION sqs receive-message \
  --queue-url $SQS_SNS_URL

echo -e "\nPronto! Veja também os logs detalhados da Lambda com:"
echo "docker-compose logs -f localstack"
