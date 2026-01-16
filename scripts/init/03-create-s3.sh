#!/bin/bash
set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="sa-east-1"

BUCKETS=(
    "rw9-relatorios-dce-local"
    "rw9-relatorios-dce-historico-local"
    "rw9-documento-remessa-local"
)

echo "[S3] Iniciando criação dos buckets"

for BUCKET_NAME in "${BUCKETS[@]}"; do
    echo "[S3] Processando bucket: ${BUCKET_NAME}"
    
    EXISTING_BUCKET=$(awslocal s3api head-bucket --bucket "${BUCKET_NAME}" --region "${REGION}" 2>&1 || echo "NOT_FOUND")
    
    if [[ "${EXISTING_BUCKET}" != *"NOT_FOUND"* ]] && [[ "${EXISTING_BUCKET}" != *"404"* ]] && [[ "${EXISTING_BUCKET}" != *"NoSuchBucket"* ]]; then
        echo "[S3] Bucket '${BUCKET_NAME}' já existe."
    else
        awslocal s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
        echo "[S3] Bucket '${BUCKET_NAME}' criado com sucesso."
    fi
done

echo "[S3] Listando buckets disponíveis:"
awslocal s3api list-buckets --region "${REGION}" --query "Buckets[].Name" --output table

echo "[S3] Script finalizado com sucesso."
