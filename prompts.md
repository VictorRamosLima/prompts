```kotlin
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
