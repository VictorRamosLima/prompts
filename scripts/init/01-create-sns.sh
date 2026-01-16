#!/bin/bash
set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="sa-east-1"
TOPIC_NAME="dces-result"

echo "[SNS] Iniciando criação do tópico: ${TOPIC_NAME}"

EXISTING_TOPIC=$(awslocal sns list-topics --region "${REGION}" --query "Topics[?ends_with(TopicArn, ':${TOPIC_NAME}')].TopicArn" --output text 2>/dev/null || echo "")

if [ -n "${EXISTING_TOPIC}" ] && [ "${EXISTING_TOPIC}" != "None" ]; then
    echo "[SNS] Tópico '${TOPIC_NAME}' já existe: ${EXISTING_TOPIC}"
else
    TOPIC_ARN=$(awslocal sns create-topic \
        --name "${TOPIC_NAME}" \
        --region "${REGION}" \
        --query "TopicArn" \
        --output text)
    echo "[SNS] Tópico criado com sucesso: ${TOPIC_ARN}"
fi

echo "[SNS] Listando tópicos disponíveis:"
awslocal sns list-topics --region "${REGION}"

echo "[SNS] Script finalizado com sucesso."
