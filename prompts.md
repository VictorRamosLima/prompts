```kotlin
package com.company.metrics

import io.kotest.core.spec.style.BehaviorSpec
import io.kotest.matchers.collections.shouldContainExactly
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf
import io.mockk.*
import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.Tags
import io.micrometer.core.instrument.Timer
import io.micronaut.aop.MethodInvocationContext
import org.opentracing.Span
import org.opentracing.Tracer
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionStage
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class InstrumentedInterceptorTest : BehaviorSpec({

    val mockRegistry = mockk<MeterRegistry>()
    val mockTracer = mockk<Tracer>()
    val mockCorrelationIdContext = mockk<CorrelationIdContext>()
    val mockSpan = mockk<Span>()
    val mockTimer = mockk<Timer>()
    val mockCounter = mockk<Counter>()

    val interceptor = InstrumentedInterceptor(mockRegistry, mockTracer, mockCorrelationIdContext)

    fun setupCommonMocks() {
        every { mockTracer.activeSpan() } returns mockSpan
        every { mockSpan.setTag(any<String>(), any()) } just Runs
        every { mockSpan.log(any<Map<String, String>>()) } just Runs
        every { mockRegistry.timer(any(), any()) } returns mockTimer
        every { mockRegistry.counter(any(), any()) } returns mockCounter
        every { mockCounter.increment() } just Runs
        every { mockCorrelationIdContext.id } returns "test-correlation-id"
    }

    beforeEach {
        clearAllMocks()
        setupCommonMocks()
    }

    given("InstrumentedInterceptor configuration") {
        
        `when`("extracting configuration from annotation metadata") {
            val metadata = mockk<AnnotationMetadata>()
            
            then("should extract all values correctly") {
                every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("testOperation")
                every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.of("testId")
                every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(true)
                every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(false)

                val config = InstrumentedInterceptor.InstrumentedConfig.from(metadata)

                config.operationName shouldBe "testOperation"
                config.idName shouldBe "testId"
                config.includeIdInMetric shouldBe true
                config.recordErrors shouldBe false
            }

            then("should use default values when not specified") {
                every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.empty()
                every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
                every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.empty()
                every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.empty()

                val config = InstrumentedInterceptor.InstrumentedConfig.from(metadata)

                config.operationName shouldBe "operation"
                config.idName shouldBe ""
                config.includeIdInMetric shouldBe false
                config.recordErrors shouldBe true
            }
        }
    }

    given("synchronous method execution") {
        val context = mockk<MethodInvocationContext<Any, Any>>()
        val metadata = mockk<AnnotationMetadata>()
        
        beforeEach {
            every { context.annotationMetadata } returns metadata
            every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("syncOp")
            every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
            every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
            every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)
            every { context.returnType } returns mockk {
                every { type } returns String::class.java
            }
        }

        `when`("method executes successfully") {
            val sampleSlot = slot<Timer.Sample>()
            val timerTagsSlot = slot<Tags>()
            val counterTagsSlot = slot<Tags>()
            
            then("should record success metrics and annotate span") {
                every { context.proceed() } returns "success-result"
                mockkStatic(Timer.Sample::class)
                val mockSample = mockk<Timer.Sample>()
                every { Timer.start(registry = mockRegistry) } returns mockSample
                every { mockSample.stop(mockTimer) } just Runs

                val result = interceptor.intercept(context)

                result shouldBe "success-result"

                verify {
                    Timer.start(registry = mockRegistry)
                    mockSample.stop(mockTimer)
                    mockRegistry.counter("syncOp.count", capture(counterTagsSlot))
                    mockCounter.increment()
                    mockSpan.setTag("syncOp.correlation_id", "test-correlation-id")
                }

                counterTagsSlot.captured shouldBe Tags.of(
                    "status", "success",
                    "correlation_id", "test-correlation-id"
                )
            }
        }

        `when`("method throws exception") {
            val exception = RuntimeException("Sync operation failed")
            val errorTagsSlot = slot<Tags>()
            
            then("should record error metrics and annotate span with error") {
                every { context.proceed() } throws exception

                shouldThrow<RuntimeException> {
                    interceptor.intercept(context)
                }

                verify {
                    mockRegistry.counter("syncOp.count", capture(errorTagsSlot))
                    mockRegistry.counter("syncOp.errors", Tags.of("error_type", "RuntimeException"))
                    mockCounter.increment()
                    mockSpan.setTag("syncOp.error", true)
                    mockSpan.setTag("syncOp.error_type", "RuntimeException")
                    mockSpan.log(withArg { logMap ->
                        logMap["operation.name"] shouldBe "syncOp"
                        logMap["event"] shouldBe "error"
                        logMap["error.kind"] shouldBe "RuntimeException"
                        logMap["message"] shouldBe "Sync operation failed"
                        logMap["correlation_id"] shouldBe "test-correlation-id"
                    })
                }

                errorTagsSlot.captured shouldBe Tags.of(
                    "status", "error",
                    "correlation_id", "test-correlation-id",
                    "error_type", "RuntimeException"
                )
            }
        }
    }

    given("asynchronous method execution with CompletionStage") {
        val context = mockk<MethodInvocationContext<Any, Any>>()
        val metadata = mockk<AnnotationMetadata>()
        val completableFuture = CompletableFuture<String>()
        
        beforeEach {
            every { context.annotationMetadata } returns metadata
            every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("asyncOp")
            every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
            every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
            every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)
            every { context.returnType } returns mockk {
                every { type } returns CompletionStage::class.java
            }
        }

        `when`("CompletionStage completes successfully") {
            then("should record success metrics when future completes") {
                every { context.proceed() } returns completableFuture

                val result = interceptor.intercept(context)

                result.shouldBeInstanceOf<CompletionStage<*>>()

                // Complete the future to trigger the callback
                completableFuture.complete("async-success")

                verify(timeout = 1000) {
                    mockRegistry.counter("asyncOp.count", withArg { tags ->
                        tags.stream().map { it.key to it.value }.toList() shouldContainExactly listOf(
                            "status" to "success",
                            "correlation_id" to "test-correlation-id"
                        )
                    })
                    mockCounter.increment()
                    mockSpan.setTag("asyncOp.correlation_id", "test-correlation-id")
                }
            }
        }

        `when`("CompletionStage completes with exception") {
            then("should record error metrics when future fails") {
                every { context.proceed() } returns completableFuture

                val result = interceptor.intercept(context)

                result.shouldBeInstanceOf<CompletionStage<*>>()

                // Complete the future with exception to trigger error handling
                val exception = RuntimeException("Async operation failed")
                completableFuture.completeExceptionally(exception)

                verify(timeout = 1000) {
                    mockRegistry.counter("asyncOp.count", withArg { tags ->
                        tags.stream().map { it.key to it.value }.toList() shouldContainExactly listOf(
                            "status" to "error",
                            "correlation_id" to "test-correlation-id",
                            "error_type" to "RuntimeException"
                        )
                    })
                    mockRegistry.counter("asyncOp.errors", Tags.of("error_type", "RuntimeException"))
                    mockCounter.increment()
                    mockSpan.setTag("asyncOp.error", true)
                    mockSpan.setTag("asyncOp.error_type", "RuntimeException")
                }
            }
        }
    }

    given("ID extraction logic") {
        val context = mockk<MethodInvocationContext<Any, Any>>()
        val metadata = mockk<AnnotationMetadata>()
        
        beforeEach {
            every { context.annotationMetadata } returns metadata
            every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("idOp")
            every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)
            every { context.proceed() } returns "result"
            every { context.returnType } returns mockk {
                every { type } returns String::class.java
            }
        }

        `when`("includeIdInMetric is false") {
            then("should not extract ID") {
                every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.of("userId")
                every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)

                interceptor.intercept(context)

                verify(exactly = 0) { 
                    context.executableMethod 
                    context.parameterValues 
                }
            }
        }

        `when`("includeIdInMetric is true and id name is specified") {
            then("should extract ID by parameter name") {
                every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.of("userId")
                every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(true)
                every { context.executableMethod } returns mockk {
                    every { argumentNames } returns listOf("userId", "otherParam")
                }
                every { context.parameterValues } returns listOf("user-123", "other-value")

                val tagsSlot = slot<Tags>()
                interceptor.intercept(context)

                verify {
                    mockRegistry.counter("idOp.count", capture(tagsSlot))
                    mockSpan.setTag("idOp.id", "user-123")
                }

                tagsSlot.captured.stream()
                    .filter { it.key == "id" }
                    .findFirst()
                    .get()
                    .value shouldBe "user-123"
            }
        }

        `when`("includeIdInMetric is true and id name is empty") {
            then("should extract first parameter as ID") {
                every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.of("")
                every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(true)
                every { context.parameterValues } returns listOf("first-param-value", "second-param")

                val tagsSlot = slot<Tags>()
                interceptor.intercept(context)

                verify {
                    mockRegistry.counter("idOp.count", capture(tagsSlot))
                    mockSpan.setTag("idOp.id", "first-param-value")
                }

                tagsSlot.captured.stream()
                    .filter { it.key == "id" }
                    .findFirst()
                    .get()
                    .value shouldBe "first-param-value"
            }
        }

        `when`("ID value is too long") {
            then("should sanitize ID to 32 characters") {
                every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.of("")
                every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(true)
                every { context.parameterValues } returns listOf("this-is-a-very-long-id-value-that-exceeds-thirty-two-characters")

                val tagsSlot = slot<Tags>()
                interceptor.intercept(context)

                verify {
                    mockSpan.setTag("idOp.id", "this-is-a-very-long-id-value-th")
                }

                tagsSlot.captured.stream()
                    .filter { it.key == "id" }
                    .findFirst()
                    .get()
                    .value shouldBe "this-is-a-very-long-id-value-th"
            }
        }
    }

    given("error handling configuration") {
        val context = mockk<MethodInvocationContext<Any, Any>>()
        val metadata = mockk<AnnotationMetadata>()
        val exception = RuntimeException("Test error")
        
        beforeEach {
            every { context.annotationMetadata } returns metadata
            every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("errorOp")
            every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
            every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
            every { context.proceed() } throws exception
            every { context.returnType } returns mockk {
                every { type } returns String::class.java
            }
        }

        `when`("recordErrors is true") {
            then("should record error metrics") {
                every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)

                shouldThrow<RuntimeException> {
                    interceptor.intercept(context)
                }

                verify {
                    mockRegistry.counter("errorOp.count", any())
                    mockRegistry.counter("errorOp.errors", Tags.of("error_type", "RuntimeException"))
                    mockCounter.increment()
                }
            }
        }

        `when`("recordErrors is false") {
            then("should not record error metrics") {
                every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(false)

                shouldThrow<RuntimeException> {
                    interceptor.intercept(context)
                }

                verify(exactly = 0) {
                    mockRegistry.counter(any(), any())
                }

                verify {
                    // But should still annotate span with error
                    mockSpan.setTag("errorOp.error", true)
                    mockSpan.setTag("errorOp.error_type", "RuntimeException")
                    mockSpan.log(any<Map<String, String>>())
                }
            }
        }
    }

    given("correlation ID handling") {
        val context = mockk<MethodInvocationContext<Any, Any>>()
        val metadata = mockk<AnnotationMetadata>()
        
        beforeEach {
            every { context.annotationMetadata } returns metadata
            every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("correlationOp")
            every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
            every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
            every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)
            every { context.proceed() } returns "result"
            every { context.returnType } returns mockk {
                every { type } returns String::class.java
            }
        }

        `when`("correlation ID is present") {
            then("should include correlation ID in tags and span") {
                every { mockCorrelationIdContext.id } returns "test-correlation-123"

                val tagsSlot = slot<Tags>()
                interceptor.intercept(context)

                verify {
                    mockRegistry.counter("correlationOp.count", capture(tagsSlot))
                    mockSpan.setTag("correlationOp.correlation_id", "test-correlation-123")
                }

                tagsSlot.captured.stream()
                    .filter { it.key == "correlation_id" }
                    .findFirst()
                    .get()
                    .value shouldBe "test-correlation-123"
            }
        }

        `when`("correlation ID is null") {
            then("should not include correlation ID") {
                every { mockCorrelationIdContext.id } returns null

                val tagsSlot = slot<Tags>()
                interceptor.intercept(context)

                verify(exactly = 0) {
                    mockSpan.setTag(any<String>(), any<String>())
                }

                val correlationIdTags = tagsSlot.captured.stream()
                    .filter { it.key == "correlation_id" }
                    .toList()

                correlationIdTags shouldBe emptyList()
            }
        }
    }

    given("CompletableFuture specific behavior") {
        val context = mockk<MethodInvocationContext<Any, Any>>()
        val metadata = mockk<AnnotationMetadata>()
        
        beforeEach {
            every { context.annotationMetadata } returns metadata
            every { metadata.stringValue(Instrumented::class.java, "operation") } returns Optional.of("futureOp")
            every { metadata.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
            every { metadata.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
            every { metadata.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)
            every { context.returnType } returns mockk {
                every { type } returns CompletableFuture::class.java
            }
        }

        `when`("CompletableFuture is returned") {
            then("should handle completion stage correctly") {
                val future = CompletableFuture<String>()
                every { context.proceed() } returns future

                val result = interceptor.intercept(context)

                result shouldBe future

                // Test both success and failure paths
                future.complete("future-result")

                verify(timeout = 1000) {
                    mockRegistry.counter("futureOp.count", withArg { tags ->
                        tags.stream().anyMatch { it.key == "status" && it.value == "success" } shouldBe true
                    })
                }

                // Reset and test failure
                clearMocks(mockRegistry, mockCounter, mockSpan)
                setupCommonMocks()

                val future2 = CompletableFuture<String>()
                every { context.proceed() } returns future2
                interceptor.intercept(context)
                future2.completeExceptionally(IllegalStateException("Future failed"))

                verify(timeout = 1000) {
                    mockRegistry.counter("futureOp.count", withArg { tags ->
                        tags.stream().anyMatch { it.key == "status" && it.value == "error" } shouldBe true
                    })
                    mockRegistry.counter("futureOp.errors", Tags.of("error_type", "IllegalStateException"))
                }
            }
        }
    }
})

@Singleton
class InstrumentedInterceptor(
    private val registry: MeterRegistry,
    private val tracer: Tracer,
    private val correlationIdContext: CorrelationIdContext,
) : MethodInterceptor<Any, Any> {

    override fun intercept(context: MethodInvocationContext<Any, Any>): Any? {
        val metadata = context.annotationMetadata
        val config = InstrumentedConfig.from(metadata)
        val idValue = config.extractId(context)

        return try {
            when (val result = context.proceed()) {
                is CompletionStage<*> -> handleAsync(result, config, idValue)
                else -> handleSync(result, config, idValue)
            }
        } catch (e: Exception) {
            handleFailure(e, config, idValue)
            throw e
        }
    }

    private fun handleAsync(
        result: CompletionStage<*>,
        config: InstrumentedConfig,
        idValue: String?
    ): CompletionStage<*> {
        val sample = Timer.start(registry)
        return result.whenComplete { _, throwable ->
            if (throwable != null) {
                handleFailure(throwable, config, idValue)
            } else {
                recordSuccess(config.operationName, idValue)
                annotateSpanSuccess(config.operationName, idValue)
            }
            sample.stop(registry.timer("${config.operationName}.time"))
        }
    }

    private fun <T> handleSync(result: T, config: InstrumentedConfig, idValue: String?): T {
        val sample = Timer.start(registry)
        try {
            recordSuccess(config.operationName, idValue)
            annotateSpanSuccess(config.operationName, idValue)
            return result
        } finally {
            sample.stop(registry.timer("${config.operationName}.time"))
        }
    }

    private fun handleFailure(
        throwable: Throwable,
        config: InstrumentedConfig,
        idValue: String?
    ) {
        if (config.recordErrors) {
            recordError(throwable, config.operationName, idValue)
        }
        annotateSpanError(throwable, config.operationName, idValue)
    }

    private fun recordSuccess(operationName: String, idValue: String?) {
        registry.counter("${operationName}.count", buildTags("success", idValue)).increment()
    }

    private fun recordError(throwable: Throwable, operationName: String, idValue: String?) {
        val errorType = throwable::class.simpleName ?: "UnknownError"
        
        val errorTags = buildTags("error", idValue, "error_type" to errorType)
        registry.counter("${operationName}.count", errorTags).increment()
        registry.counter("${operationName}.errors", Tags.of("error_type", errorType)).increment()
    }

    private fun annotateSpanSuccess(operationName: String, idValue: String?) {
        tracer.activeSpan()?.apply {
            idValue?.let { setTag("${operationName}.id", sanitizeId(it)) }
            correlationIdContext.id?.let { setTag("correlation_id", it) }
        }
    }

    private fun annotateSpanError(throwable: Throwable, operationName: String, idValue: String?) {
        tracer.activeSpan()?.apply {
            setTag("error", true)
            setTag("${operationName}.error_type", throwable::class.simpleName ?: "UnknownError")
            correlationIdContext.id?.let { setTag("correlation_id", it) }
            log(errorDetails(throwable, operationName))
        }
    }

    private fun buildTags(status: String, idValue: String?, vararg extraTags: Pair<String, String>): Tags {
        val tags = mutableListOf<String>().apply {
            addAll(listOf("status", status))
            idValue?.let {
                addAll(listOf("id", sanitizeId(it)))
            }
            correlationIdContext.id?.let {
                addAll(listOf("correlation_id", it))
            }
            extraTags.forEach { (key, value) ->
                addAll(listOf(key, value))
            }
        }
        return Tags.of(*tags.toTypedArray())
    }

    private fun sanitizeId(idValue: String): String = idValue.take(32)
    
    private fun errorDetails(throwable: Throwable, operationName: String): Map<String, String> =
        mutableMapOf<String, String>().apply {
            put("operation.name", operationName)
            put("event", "error")
            put("error.kind", throwable::class.simpleName ?: "UnknownError")
            put("message", throwable.message ?: "An unknown error occurred during $operationName flow")
            correlationIdContext.id?.let { put("correlation_id", it) }
        }.toMap()

    private data class InstrumentedConfig(
        val operationName: String,
        val idName: String,
        val includeIdInMetric: Boolean,
        val recordErrors: Boolean
    ) {
        fun extractId(context: MethodInvocationContext<*, *>): String? = when {
            !includeIdInMetric -> null
            idName.isNotEmpty() -> extractNamedId(context, idName)
            else -> context.parameterValues.firstOrNull()?.toString()
        }

        private fun extractNamedId(context: MethodInvocationContext<*, *>, idName: String): String? =
            context.executableMethod.argumentNames
                .indexOf(idName)
                .takeIf { it >= 0 }
                ?.let { context.parameterValues.getOrNull(it)?.toString() }

        companion object {
            fun from(metadata: AnnotationMetadata): InstrumentedConfig =
                InstrumentedConfig(
                    operationName = metadata.stringValue(Instrumented::class.java, "operation").orElse("operation"),
                    idName = metadata.stringValue(Instrumented::class.java, "id").orElse(""),
                    includeIdInMetric = metadata.booleanValue(Instrumented::class.java, "includeIdInMetric").orElse(false),
                    recordErrors = metadata.booleanValue(Instrumented::class.java, "recordErrors").orElse(true)
                )
        }
    }
}

package com.company.metrics

import io.kotest.core.spec.style.DescribeSpec
import io.kotest.matchers.shouldBe
import io.kotest.assertions.throwables.shouldThrow
import io.mockk.*
import io.micrometer.core.instrument.Counter
import io.micrometer.core.instrument.MeterRegistry
import io.micrometer.core.instrument.Timer
import io.micronaut.aop.MethodInvocationContext
import io.micronaut.core.annotation.AnnotationMetadata
import io.micronaut.core.type.ReturnType
import io.opentracing.Span
import io.opentracing.Tracer
import java.util.Optional
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionStage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred

class InstrumentedInterceptorTest : DescribeSpec({

  lateinit var registry: MeterRegistry
  lateinit var tracer: Tracer
  lateinit var span: Span
  lateinit var correlation: CorrelationIdContext
  lateinit var counter: Counter
  lateinit var errorsCounter: Counter
  lateinit var timer: Timer

  beforeTest {
    registry = mockk(relaxed = true)
    tracer = mockk(relaxed = true)
    span = mockk(relaxed = true)
    correlation = mockk(relaxed = true)
    counter = mockk(relaxed = true)
    errorsCounter = mockk(relaxed = true)
    timer = mockk(relaxed = true)

    every { tracer.activeSpan() } returns span

    // generic registry stubs (specific test cases can override)
    every { registry.counter(any(), any()) } returns counter
    every { registry.counter(any(), any<io.micrometer.core.instrument.Tag>()) } returns counter
    every { registry.timer(any()) } returns timer
  }

  fun mockContext(
    operation: String,
    idParamName: Optional<String>,
    includeId: Optional<Boolean>,
    recordErrors: Optional<Boolean>,
    argNames: Array<String> = emptyArray(),
    params: Array<Any> = emptyArray(),
    returnTypeClass: Class<*>,
    proceedBehavior: () -> Any
  ): MethodInvocationContext<Any, Any> {
    val ctx = mockk<MethodInvocationContext<Any, Any>>(relaxed = true)
    val meta = mockk<AnnotationMetadata>()

    every { meta.stringValue(Instrumented::class.java, "operation") } returns Optional.of(operation)
    every { meta.stringValue(Instrumented::class.java, "id") } returns idParamName
    every { meta.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns includeId
    every { meta.booleanValue(Instrumented::class.java, "recordErrors") } returns recordErrors

    every { ctx.annotationMetadata } returns meta
    every { ctx.executableMethod } returns mockk {
      every { argumentNames } returns argNames
    }
    every { ctx.parameterValues } returns params

    val returnType = mockk<ReturnType<Any>>(relaxed = true)
    every { returnType.type } returns returnTypeClass
    every { ctx.returnType } returns returnType

    every { ctx.proceed() } answers { proceedBehavior() }

    return ctx
  }

  describe("sync success with id and correlation") {
    it("increments success counter, stops timer and tags span with id + correlation") {
      every { correlation.id } returns "corr-1"
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      val ctx = mockContext(
        operation = "order.process",
        idParamName = Optional.of("orderId"),
        includeId = Optional.of(true),
        recordErrors = Optional.of(true),
        argNames = arrayOf("orderId"),
        params = arrayOf("id-123"),
        returnTypeClass = Boolean::class.java
      ) { true }

      val result = interceptor.intercept(ctx)
      result shouldBe true

      verify(exactly = 1) { registry.counter("order.process.count", any()) }
      verify { counter.increment() }
      verify { registry.timer("order.process.time") }
      verify { span.setTag("order.process.id", "id-123") }
      verify { span.setTag("correlation_id", "corr-1") }
    }
  }

  describe("sync failure without id, correlation absent") {
    it("throws, records error counters and tags/logs span") {
      every { correlation.id } returns null
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      // ensure specific counter names return distinct mocks
      every { registry.counter("order.process.count", any()) } returns counter
      every { registry.counter("order.process.errors", any()) } returns errorsCounter

      val ctx = mockContext(
        operation = "order.process",
        idParamName = Optional.empty(),
        includeId = Optional.of(false),
        recordErrors = Optional.of(true),
        argNames = arrayOf(),
        params = arrayOf(),
        returnTypeClass = Boolean::class.java
      ) { throw IllegalStateException("boom") }

      shouldThrow<IllegalStateException> { interceptor.intercept(ctx) }

      verify { registry.counter("order.process.count", any()) }
      verify { counter.increment() }
      verify { registry.counter("order.process.errors", any()) }
      verify { errorsCounter.increment() }
      verify { span.setTag("error", true) }
      verify { span.setTag("order.process.error_type", "IllegalStateException") }
      verify { span.log(match<Map<String, String>> { it["error.kind"] == "IllegalStateException" }) }
      verify { registry.timer("order.process.time") }
    }
  }

  describe("async success CompletionStage") {
    it("attaches completion handler, records success after completion and tags span") {
      every { correlation.id } returns "corr-async"
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      val future = CompletableFuture.completedFuture(true)

      val ctx = mockContext(
        operation = "order.async",
        idParamName = Optional.of("orderId"),
        includeId = Optional.of(true),
        recordErrors = Optional.of(true),
        argNames = arrayOf("orderId"),
        params = arrayOf("async-1"),
        returnTypeClass = CompletionStage::class.java
      ) { future }

      val returned = interceptor.intercept(ctx) as CompletionStage<*>
      returned.toCompletableFuture().join() // ensure complete

      verify { registry.counter("order.async.count", any()) }
      verify { counter.increment() }
      verify { registry.timer("order.async.time") }
      verify { span.setTag("order.async.id", "async-1") }
      verify { span.setTag("correlation_id", "corr-async") }
    }
  }

  describe("async exceptional CompletionStage") {
    it("records error metrics when CompletionStage completes exceptionally") {
      every { correlation.id } returns null
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      every { registry.counter("order.async.count", any()) } returns counter
      every { registry.counter("order.async.errors", any()) } returns errorsCounter

      val future = CompletableFuture<Boolean>()

      val ctx = mockContext(
        operation = "order.async",
        idParamName = Optional.of("orderId"),
        includeId = Optional.of(false),
        recordErrors = Optional.of(true),
        argNames = arrayOf("orderId"),
        params = arrayOf("async-2"),
        returnTypeClass = CompletionStage::class.java
      ) { future }

      val returned = interceptor.intercept(ctx) as CompletionStage<*>

      future.completeExceptionally(RuntimeException("async boom"))

      // allow callback to run (verify with timeout)
      verify(timeout = 1000) { registry.counter("order.async.count", any()) }
      verify { counter.increment() }
      verify { registry.counter("order.async.errors", any()) }
      verify { errorsCounter.increment() }
      verify { span.setTag("error", true) }
      verify { span.setTag("order.async.error_type", "RuntimeException") }
      verify { registry.timer("order.async.time") }
    }
  }

describe("coroutine (Deferred) handling") {

  it("records success metrics after Deferred completes and tags span with id + correlation") {
    every { correlation.id } returns "corr-co"
    val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

    val future = CompletableDeferred<Boolean>()

    val ctx = mockContext(
      operation = "order.coroutine",
      idParamName = Optional.of("orderId"),
      includeId = Optional.of(true),
      recordErrors = Optional.of(true),
      argNames = arrayOf("orderId"),
      params = arrayOf("cor-1"),
      returnTypeClass = Deferred::class.java
    ) { future }

    val returned = interceptor.intercept(ctx) as Deferred<*>

    // complete after intercept -> interceptor must handle async completion
    future.complete(true)

    // verify handlers ran (allow async)
    verify(timeout = 1000) { registry.counter("order.coroutine.count", any()) }
    verify { counter.increment() }
    verify { registry.timer("order.coroutine.time") }
    verify { span.setTag("order.coroutine.id", "cor-1") }
    verify { span.setTag("correlation_id", "corr-co") }
  }

  it("records error metrics when Deferred completes exceptionally and tags span error") {
    every { correlation.id } returns null
    val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

    every { registry.counter("order.coroutine.count", any()) } returns counter
    every { registry.counter("order.coroutine.errors", any()) } returns errorsCounter

    val future = CompletableDeferred<Boolean>()

    val ctx = mockContext(
      operation = "order.coroutine",
      idParamName = Optional.of("orderId"),
      includeId = Optional.of(false),
      recordErrors = Optional.of(true),
      argNames = arrayOf("orderId"),
      params = arrayOf("cor-2"),
      returnTypeClass = Deferred::class.java
    ) { future }

    val returned = interceptor.intercept(ctx) as Deferred<*>

    future.completeExceptionally(RuntimeException("coroutine boom"))

    verify(timeout = 1000) { registry.counter("order.coroutine.count", any()) }
    verify { counter.increment() }
    verify { registry.counter("order.coroutine.errors", any()) }
    verify { errorsCounter.increment() }
    verify { span.setTag("error", true) }
    verify { span.setTag("order.coroutine.error_type", "RuntimeException") }
    verify { registry.timer("order.coroutine.time") }
  }
}
})
```
