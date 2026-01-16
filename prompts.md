## Prompt

Atue como um **engenheiro de software sênior**, com ampla experiência em **AWS**, **infraestrutura local com LocalStack** e **automação via Docker**.

Crie um **arquivo `docker-compose.yml`** responsável por subir um ambiente **LocalStack** para desenvolvimento local, seguindo **boas práticas de organização, clareza e reprodutibilidade**.

### Requisitos gerais

- Utilizar **LocalStack na versão `4.12.0`**
- O ambiente deve inicializar automaticamente todos os recursos necessários
- Utilizar **scripts separados e idempotentes** para a criação dos recursos
- Os scripts devem ser executados automaticamente na subida do container
- Não utilizar recursos mockados fora do LocalStack
- Priorizar clareza, organização e nomes explícitos

---

## Estrutura esperada de scripts

Crie **quatro scripts distintos**, cada um responsável por um tipo de recurso:

1. **Um script exclusivo para SNS**
2. **Um script exclusivo para SQS**
3. **Um script exclusivo para S3 (criando os 3 buckets)**
4. **Um script exclusivo para DynamoDB (criando as 2 tabelas)**

---

## Mensageria

### SNS
- **Nome do tópico:** `dces-result`
- **ARN esperado:** `arn:aws:sns:sa-east-1:*:dces-result`

### SQS
- **Nome da fila:** `worker-dce-queue.fifo`
- **Tipo:** FIFO
- **Observação:** garantir as configurações obrigatórias para filas FIFO

---

## Banco de Dados (DynamoDB)

### Tabela 1
- **Nome:** `tbrw9001_decl_ctud_elet_supm`
- **Chave de partição:**
  - `cod_idt_decl_ctud_elet` (String)
- **Índice Secundário Global (GSI):**
  - **Nome:** `xrw90012`
  - **Chave de partição:** `txt_situ_emis_decl_ctud_elet` (String)
  - **Chave de ordenação:** `dat_hor_cria_decl_ctud_elet` (String)

---

### Tabela 2
- **Nome:** `tbrw9002_docm_reme_supm`
- **Chave de partição:**
  - `cod_idt_docm_reme` (String)

---

## Buckets S3

Criar exatamente **3 buckets S3** com os seguintes nomes:

- `rw9-relatorios-dce-local`
- `rw9-relatorios-dce-historico-local`
- `rw9-documento-remessa-local`

---

## Script auxiliar em Python (SQS)

Além dos scripts de infraestrutura, criar **um script simples em Python** com as seguintes características:

- Responsável **exclusivamente** por publicar mensagens na fila **SQS**
- Deve enviar mensagens para a fila `worker-dce-queue.fifo`
- Utilizar **AWS SDK for Python (boto3)**
- Apontar explicitamente para o endpoint do **LocalStack**
- Suportar envio repetido/contínuo de mensagens (ex: loop simples ou parametrizável)
- Não incluir integração com SNS, S3 ou DynamoDB — **apenas SQS**
- Código direto, sem abstrações desnecessárias

---

## Entrega esperada

- `docker-compose.yml` completo e funcional
- Scripts separados por responsabilidade:
  - `create-sns.sh`
  - `create-sqs.sh`
  - `create-s3.sh`
  - `create-dynamodb.sh`
- Script Python adicional:
  - `send-sqs-messages.py`
- Scripts compatíveis com execução automática via LocalStack (`/etc/localstack/init/ready.d`)
- Utilizar AWS CLI apontando corretamente para o endpoint do LocalStack
- Não incluir explicações extras — apenas o código e a estrutura necessária
## Prompt

Atue como um **engenheiro de software sênior**, com ampla experiência em **AWS**, **infraestrutura local com LocalStack** e **automação via Docker**.

Crie um **arquivo `docker-compose.yml`** responsável por subir um ambiente **LocalStack** para desenvolvimento local, seguindo **boas práticas de organização, clareza e reprodutibilidade**.

### Requisitos gerais

- Utilizar **LocalStack na versão `4.12.0`**
- O ambiente deve inicializar automaticamente todos os recursos necessários
- Utilizar **scripts separados e idempotentes** para a criação dos recursos
- Os scripts devem ser executados automaticamente na subida do container
- Não utilizar recursos mockados fora do LocalStack
- Priorizar clareza, organização e nomes explícitos

---

## Estrutura esperada de scripts

Crie **quatro scripts distintos**, cada um responsável por um tipo de recurso:

1. **Um script exclusivo para SNS**
2. **Um script exclusivo para SQS**
3. **Um script exclusivo para S3 (criando os 3 buckets)**
4. **Um script exclusivo para DynamoDB (criando as 2 tabelas)**

---

## Mensageria

### SNS
- **Nome do tópico:** `dces-result`
- **ARN esperado:** `arn:aws:sns:sa-east-1:*:dces-result`

### SQS
- **Nome da fila:** `worker-dce-queue.fifo`
- **Tipo:** FIFO
- **Observação:** garantir as configurações obrigatórias para filas FIFO

---

## Banco de Dados (DynamoDB)

### Tabela 1
- **Nome:** `tbrw9001_decl_ctud_elet_supm`
- **Chave de partição:**
  - `cod_idt_decl_ctud_elet` (String)
- **Índice Secundário Global (GSI):**
  - **Nome:** `xrw90012`
  - **Chave de partição:** `txt_situ_emis_decl_ctud_elet` (String)
  - **Chave de ordenação:** `dat_hor_cria_decl_ctud_elet` (String)

---

### Tabela 2
- **Nome:** `tbrw9002_docm_reme_supm`
- **Chave de partição:**
  - `cod_idt_docm_reme` (String)

---

## Buckets S3

Criar exatamente **3 buckets S3** com os seguintes nomes:

- `rw9-relatorios-dce-local`
- `rw9-relatorios-dce-historico-local`
- `rw9-documento-remessa-local`

---

## Script auxiliar em Python (SQS)

Além dos scripts de infraestrutura, criar **um script simples em Python** com as seguintes características:

- Responsável **exclusivamente** por publicar mensagens na fila **SQS**
- Deve enviar mensagens para a fila `worker-dce-queue.fifo`
- Utilizar **AWS SDK for Python (boto3)**
- Apontar explicitamente para o endpoint do **LocalStack**
- Suportar envio repetido/contínuo de mensagens (ex: loop simples ou parametrizável)
- Não incluir integração com SNS, S3 ou DynamoDB — **apenas SQS**
- Código direto, sem abstrações desnecessárias

---

## Entrega esperada

- `docker-compose.yml` completo e funcional
- Scripts separados por responsabilidade:
  - `create-sns.sh`
  - `create-sqs.sh`
  - `create-s3.sh`
  - `create-dynamodb.sh`
- Script Python adicional:
  - `send-sqs-messages.py`
- Scripts compatíveis com execução automática via LocalStack (`/etc/localstack/init/ready.d`)
- Utilizar AWS CLI apontando corretamente para o endpoint do LocalStack
- Não incluir explicações extras — apenas o código e a estrutura necessária
