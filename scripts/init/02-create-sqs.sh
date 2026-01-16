#!/bin/bash
set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="sa-east-1"
QUEUE_NAME="worker-dce-queue.fifo"

echo "[SQS] Iniciando criação da fila FIFO: ${QUEUE_NAME}"

EXISTING_QUEUE=$(awslocal sqs list-queues --region "${REGION}" --query "QueueUrls[?contains(@, '${QUEUE_NAME}')]" --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_QUEUE}" ] && [ "${EXISTING_QUEUE}" != "None" ]; then
    echo "[SQS] Fila '${QUEUE_NAME}' já existe: ${EXISTING_QUEUE}"
else
    QUEUE_URL=$(awslocal sqs create-queue \
        --queue-name "${QUEUE_NAME}" \
        --region "${REGION}" \
        --attributes '{
            "FifoQueue": "true",
            "ContentBasedDeduplication": "true",
            "DeduplicationScope": "messageGroup",
            "FifoThroughputLimit": "perMessageGroupId",
            "VisibilityTimeout": "30",
            "MessageRetentionPeriod": "345600",
            "ReceiveMessageWaitTimeSeconds": "20"
        }' \
        --query "QueueUrl" \
        --output text)
    echo "[SQS] Fila FIFO criada com sucesso: ${QUEUE_URL}"
fi

echo "[SQS] Listando filas disponíveis:"
awslocal sqs list-queues --region "${REGION}"

echo "[SQS] Atributos da fila:"
QUEUE_URL=$(awslocal sqs get-queue-url --queue-name "${QUEUE_NAME}" --region "${REGION}" --query "QueueUrl" --output text)
awslocal sqs get-queue-attributes --queue-url "${QUEUE_URL}" --attribute-names All --region "${REGION}"

echo "[SQS] Script finalizado com sucesso."
