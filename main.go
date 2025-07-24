package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/aws/aws-lambda-go/events" // Importa os tipos de eventos AWS, inclusive SQS
	"github.com/aws/aws-lambda-go/lambda" // Importa o SDK da Lambda para Go
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sns"
	"os"
	"strings"
	"time"
)

// Log utilitário para prints padronizados (horário + etapa)
func Log(step, msg string) {
	fmt.Printf("[%s][%s] %s\n", time.Now().Format(time.RFC3339), step, msg)
}

// processMessage: Processamento de exemplo (upper case)
func processMessage(msg string) string {
	Log("process", fmt.Sprintf("Processando mensagem: %s", msg))
	return strings.ToUpper(msg)
}

// publishToSNS: Publica mensagem no tópico SNS usando AWS SDK v2
func publishToSNS(ctx context.Context, client *sns.Client, topicARN, message string) error {
	Log("sns", fmt.Sprintf("Enviando mensagem para SNS: %s", message))
	_, err := client.Publish(ctx, &sns.PublishInput{
		Message:  aws.String(message),
		TopicArn: aws.String(topicARN),
	})
	if err != nil {
		Log("sns", fmt.Sprintf("Erro ao publicar no SNS: %v", err))
		return err
	}
	Log("sns", "Mensagem publicada no SNS com sucesso!")
	return nil
}

func getSNSTopicARN() string {
	return os.Getenv("SNS_TOPIC_ARN")
}

func Handler(ctx context.Context, sqsEvent events.SQSEvent) error {
	// Carrega a configuração AWS padrão (usa as variáveis do ambiente, ideal para LocalStack)
	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(os.Getenv("AWS_REGION")))
	if err != nil {
		Log("init", fmt.Sprintf("Erro ao carregar config AWS: %v", err))
		return err
	}

	// Cria o client SNS do aws-sdk-go-v2
	snsClient := sns.NewFromConfig(cfg)

	topicARN := getSNSTopicARN()
	if topicARN == "" {
		Log("init", "SNS_TOPIC_ARN não definido")
		return fmt.Errorf("SNS_TOPIC_ARN não está definido")
	}

	for _, record := range sqsEvent.Records {
		Log("sqs", fmt.Sprintf("Mensagem recebida da fila: %s", record.Body))

		var payload map[string]interface{}
		if err := json.Unmarshal([]byte(record.Body), &payload); err != nil {
			Log("sqs", fmt.Sprintf("Erro ao decodificar JSON: %v", err))
			continue
		}

		msg, ok := payload["msg"].(string)
		if !ok {
			Log("sqs", "Campo 'msg' ausente ou inválido, pulando mensagem")
			continue
		}

		result := processMessage(msg)
		if err := publishToSNS(ctx, snsClient, topicARN, result); err != nil {
			Log("error", fmt.Sprintf("Falha ao publicar no SNS: %v", err))
		}
	}
	return nil
}

func main() {
	Log("init", "Iniciando Lambda...")
	lambda.Start(Handler)
}
