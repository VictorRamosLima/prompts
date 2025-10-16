```kotlin
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
