package com.example

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider
import software.amazon.awssdk.regions.Region
import software.amazon.awssdk.services.sqs.SqsClient
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest
import software.amazon.awssdk.services.sqs.model.SendMessageRequest
import java.net.URI
import java.time.Instant
import java.util.UUID

fun main() {
    val sqsClient = SqsClient.builder()
        .endpointOverride(URI.create("http://localhost:4566"))
        .region(Region.SA_EAST_1)
        .credentialsProvider(
            StaticCredentialsProvider.create(
                AwsBasicCredentials.create("test", "test")
            )
        ).build()

    val queueUrl = sqsClient.getQueueUrl(
        GetQueueUrlRequest.builder()
            .queueName("worker-dce-queue.fifo")
            .build()
    ).queueUrl()

    println("Enviando mensagens para: $queueUrl")

    repeat(5) { i ->
        val message = """
            {
                "index": ${i + 1},
                "timestamp": "${Instant.now()}",
                "documentId": "DOC-${String.format("%05d", i + 1)}",
                "action": "PROCESS_DCE"
            }
        """.trimIndent()

        val response = sqsClient.sendMessage(
            SendMessageRequest.builder()
                .queueUrl(queueUrl)
                .messageBody(message)
                .messageGroupId("test-group")
                .messageDeduplicationId(UUID.randomUUID().toString())
                .build()
        )

        println("[${i + 1}/5] Mensagem enviada - ID: ${response.messageId()}")
    }

    println("Seed finalizado.")
}
