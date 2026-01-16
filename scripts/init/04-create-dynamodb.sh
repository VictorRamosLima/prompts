#!/bin/bash
set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="sa-east-1"

TABLE_1="tbrw9001_decl_ctud_elet_supm"
TABLE_2="tbrw9002_docm_reme_supm"

echo "[DynamoDB] Iniciando criação das tabelas"

# Tabela 1: tbrw9001_decl_ctud_elet_supm
echo "[DynamoDB] Processando tabela: ${TABLE_1}"

EXISTING_TABLE_1=$(awslocal dynamodb describe-table --table-name "${TABLE_1}" --region "${REGION}" 2>&1 || echo "NOT_FOUND")

if [[ "${EXISTING_TABLE_1}" != *"NOT_FOUND"* ]] && [[ "${EXISTING_TABLE_1}" != *"ResourceNotFoundException"* ]]; then
    echo "[DynamoDB] Tabela '${TABLE_1}' já existe."
else
    awslocal dynamodb create-table \
        --table-name "${TABLE_1}" \
        --region "${REGION}" \
        --attribute-definitions \
            AttributeName=cod_idt_decl_ctud_elet,AttributeType=S \
            AttributeName=txt_situ_emis_decl_ctud_elet,AttributeType=S \
            AttributeName=dat_hor_cria_decl_ctud_elet,AttributeType=S \
        --key-schema \
            AttributeName=cod_idt_decl_ctud_elet,KeyType=HASH \
        --global-secondary-indexes '[
            {
                "IndexName": "xrw90012",
                "KeySchema": [
                    {"AttributeName": "txt_situ_emis_decl_ctud_elet", "KeyType": "HASH"},
                    {"AttributeName": "dat_hor_cria_decl_ctud_elet", "KeyType": "RANGE"}
                ],
                "Projection": {"ProjectionType": "ALL"},
                "ProvisionedThroughput": {"ReadCapacityUnits": 5, "WriteCapacityUnits": 5}
            }
        ]' \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
    
    echo "[DynamoDB] Tabela '${TABLE_1}' criada com sucesso (incluindo GSI 'xrw90012')."
fi

# Tabela 2: tbrw9002_docm_reme_supm
echo "[DynamoDB] Processando tabela: ${TABLE_2}"

EXISTING_TABLE_2=$(awslocal dynamodb describe-table --table-name "${TABLE_2}" --region "${REGION}" 2>&1 || echo "NOT_FOUND")

if [[ "${EXISTING_TABLE_2}" != *"NOT_FOUND"* ]] && [[ "${EXISTING_TABLE_2}" != *"ResourceNotFoundException"* ]]; then
    echo "[DynamoDB] Tabela '${TABLE_2}' já existe."
else
    awslocal dynamodb create-table \
        --table-name "${TABLE_2}" \
        --region "${REGION}" \
        --attribute-definitions \
            AttributeName=cod_idt_docm_reme,AttributeType=S \
        --key-schema \
            AttributeName=cod_idt_docm_reme,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5
    
    echo "[DynamoDB] Tabela '${TABLE_2}' criada com sucesso."
fi

echo "[DynamoDB] Listando tabelas disponíveis:"
awslocal dynamodb list-tables --region "${REGION}"

echo "[DynamoDB] Detalhes da tabela '${TABLE_1}':"
awslocal dynamodb describe-table --table-name "${TABLE_1}" --region "${REGION}" --query "Table.{Name:TableName,Status:TableStatus,KeySchema:KeySchema,GSI:GlobalSecondaryIndexes[].IndexName}"

echo "[DynamoDB] Detalhes da tabela '${TABLE_2}':"
awslocal dynamodb describe-table --table-name "${TABLE_2}" --region "${REGION}" --query "Table.{Name:TableName,Status:TableStatus,KeySchema:KeySchema}"

echo "[DynamoDB] Script finalizado com sucesso."
