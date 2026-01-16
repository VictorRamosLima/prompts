import org.springframework.boot.CommandLineRunner
import org.springframework.context.annotation.Profile
import org.springframework.stereotype.Component
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbEnhancedAsyncClient
import software.amazon.awssdk.enhanced.dynamodb.DynamoDbAsyncTable
import software.amazon.awssdk.enhanced.dynamodb.Key
import software.amazon.awssdk.enhanced.dynamodb.TableSchema
import software.amazon.awssdk.enhanced.dynamodb.model.PutItemEnhancedRequest
import software.amazon.awssdk.services.sqs.SqsAsyncClient
import software.amazon.awssdk.services.sqs.model.SendMessageRequest
import java.time.Instant
import java.util.UUID
import kotlin.random.Random
import kotlinx.coroutines.*
import kotlinx.coroutines.future.await

@Profile("local")
@Component
class SeedDCe(
  private val enhanced: DynamoDbEnhancedAsyncClient,
  private val sqs: SqsAsyncClient,
  private val localQueueUrl: String, // provide via @Value("\${...}") or @Bean elsewhere
) : CommandLineRunner {

  override fun run(vararg args: String?) {
    runBlocking(Dispatchers.Default) {
      seedOnce()
      awaitForever()
    }
  }

  private suspend fun seedOnce() =
    tables()
      .let { (drTable, dceTable) ->
        newId()
          .also { drId -> drTable.put(drItem(drId)).await() }
          .let { drId ->
            (1..5)
              .asSequence()
              .map { newId() }
              .map { dceId -> dceId.also { dceTable.put(dceItem(dceId, drId)).await() } to drId }
              .map { (dceId, drId) -> sendToSqs(drId = drId, dceId = dceId) }
              .toList()
              .awaitAll()
              .let { Unit }
          }
      }

  private fun tables(): Pair<DynamoDbAsyncTable<DocmRemeItem>, DynamoDbAsyncTable<DeclCtudEletItem>> =
    enhanced.table("tbrw9002_docm_reme_supm", TableSchema.fromImmutableClass(DocmRemeItem::class.java)) to
      enhanced.table("tbrw9001_decl_ctud_elet_supm", TableSchema.fromImmutableClass(DeclCtudEletItem::class.java))

  private fun drItem(drId: String) =
    DocmRemeItem.builder()
      .codIdtDocmReme(drId)
      .createdAt(Instant.now().toString())
      .build()

  private fun dceItem(dceId: String, drId: String) =
    DeclCtudEletItem.builder()
      .codIdtDeclCtudElet(dceId)
      .codIdtDocmReme(drId)
      .txtSituEmisDeclCtudElet("PENDING")
      .datHorCriaDeclCtudElet(Instant.now().toString())
      .build()

  private fun sendToSqs(drId: String, dceId: String): Deferred<Unit> =
    coroutineScope {
      async {
        sqs.sendMessage(
          SendMessageRequest.builder()
            .queueUrl(localQueueUrl)
            .messageGroupId("seed-${drId}")
            .messageDeduplicationId("seed-${drId}-${dceId}")
            .messageBody("""{"id_dr":"$drId","id_dce":"$dceId","evento":"SOLICITACAO_EMISSAO"}""")
            .build(),
        ).await()
      }.let { it }
    }

  private fun newId(): String = UUID.randomUUID().toString()

  private suspend fun awaitForever(): Nothing =
    CompletableDeferred<Unit>().await().let { error("unreachable") }
}

/**
 * Assuma que essas classes já existem no projeto como @DynamoDbImmutable / builders compatíveis com Enhanced Client.
 * Se não existirem, adapte os nomes dos getters/builders para os seus modelos reais.
 */
interface DocmRemeItem {
  fun codIdtDocmReme(): String
  fun createdAt(): String
  companion object {
    fun builder(): Builder = throw UnsupportedOperationException("provided by your codegen")
  }
  interface Builder {
    fun codIdtDocmReme(v: String): Builder
    fun createdAt(v: String): Builder
    fun build(): DocmRemeItem
  }
}

interface DeclCtudEletItem {
  fun codIdtDeclCtudElet(): String
  fun codIdtDocmReme(): String
  fun txtSituEmisDeclCtudElet(): String
  fun datHorCriaDeclCtudElet(): String
  companion object {
    fun builder(): Builder = throw UnsupportedOperationException("provided by your codegen")
  }
  interface Builder {
    fun codIdtDeclCtudElet(v: String): Builder
    fun codIdtDocmReme(v: String): Builder
    fun txtSituEmisDeclCtudElet(v: String): Builder
    fun datHorCriaDeclCtudElet(v: String): Builder
    fun build(): DeclCtudEletItem
  }
}
