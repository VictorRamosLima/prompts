#!/usr/bin/env kotlin

@file:DependsOn("software.amazon.awssdk:sqs:2.25.60")
@file:DependsOn("software.amazon.awssdk:auth:2.25.60")

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.sqs.SqsClient
import software.amazon.awssdk.services.sqs.model.SendMessageRequest
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest
import java.net.URI
import java.time.Instant
import java.util.UUID

val LOCALSTACK_ENDPOINT = "http://localhost:4566"
val REGION = Region.SA_EAST_1
val QUEUE_NAME = "worker-dce-queue.fifo"

val credentials = AwsBasicCredentials.create("test", "test")

val sqsClient: SqsClient = SqsClient.builder()
    .endpointOverride(URI.create(LOCALSTACK_ENDPOINT))
    .region(REGION)
    .credentialsProvider(StaticCredentialsProvider.create(credentials))
    .build()

fun getQueueUrl(): String {
    val request = GetQueueUrlRequest.builder()
        .queueName(QUEUE_NAME)
        .build()
    return sqsClient.getQueueUrl(request).queueUrl()
}

fun sendMessage(queueUrl: String, messageBody: String, messageGroupId: String): String {
    val deduplicationId = UUID.randomUUID().toString()
    
    val request = SendMessageRequest.builder()
        .queueUrl(queueUrl)
        .messageBody(messageBody)
        .messageGroupId(messageGroupId)
        .messageDeduplicationId(deduplicationId)
        .build()
    
    val response = sqsClient.sendMessage(request)
    return response.messageId()
}

fun createSampleMessage(index: Int): String {
    return """
        {
            "messageIndex": $index,
            "timestamp": "${Instant.now()}",
            "correlationId": "${UUID.randomUUID()}",
            "payload": {
                "action": "PROCESS_DCE",
                "documentId": "DOC-${String.format("%05d", index)}",
                "status": "PENDING"
            }
        }
    """.trimIndent()
}

fun main() {
    println("=".repeat(60))
    println("SQS Message Sender - LocalStack")
    println("=".repeat(60))
    println("Endpoint: $LOCALSTACK_ENDPOINT")
    println("Queue: $QUEUE_NAME")
    println("Region: $REGION")
    println("=".repeat(60))
    
    val queueUrl: String
    try {
        queueUrl = getQueueUrl()
        println("Queue URL: $queueUrl")
    } catch (e: Exception) {
        println("Erro ao obter URL da fila: ${e.message}")
        println("Verifique se o LocalStack está rodando e a fila foi criada.")
        return
    }
    
    val totalMessages = args.firstOrNull()?.toIntOrNull() ?: 5
    val messageGroupId = args.getOrNull(1) ?: "default-group"
    val delayMs = args.getOrNull(2)?.toLongOrNull() ?: 1000L
    
    println("\nConfigurações:")
    println("  - Total de mensagens: $totalMessages")
    println("  - Message Group ID: $messageGroupId")
    println("  - Delay entre mensagens: ${delayMs}ms")
    println("\nIniciando envio...\n")
    
    var successCount = 0
    var errorCount = 0
    
    for (i in 1..totalMessages) {
        try {
            val messageBody = createSampleMessage(i)
            val messageId = sendMessage(queueUrl, messageBody, messageGroupId)
            
            println("[${String.format("%03d", i)}/$totalMessages] Mensagem enviada - ID: $messageId")
            successCount++
            
            if (i < totalMessages) {
                Thread.sleep(delayMs)
            }
        } catch (e: Exception) {
            println("[${String.format("%03d", i)}/$totalMessages] Erro ao enviar: ${e.message}")
            errorCount++
        }
    }
    
    println("\n" + "=".repeat(60))
    println("Resumo:")
    println("  - Mensagens enviadas com sucesso: $successCount")
    println("  - Erros: $errorCount")
    println("=".repeat(60))
}

main()
