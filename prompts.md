// InstrumentedInterceptorTest.kt
package com.company.metrics

import io.kotest.core.spec.style.DescribeSpec
import io.kotest.matchers.doubles.shouldBeGreaterThan
import io.kotest.matchers.ints.shouldBeEqualTo
import io.kotest.matchers.shouldBe
import io.kotest.assertions.timing.eventually
import io.mockk.*
import io.micrometer.core.instrument.simple.SimpleMeterRegistry
import io.micrometer.core.instrument.Tags
import io.micronaut.core.annotation.AnnotationMetadata
import io.micronaut.context.BeanContext
import io.micronaut.aop.MethodInvocationContext
import io.micronaut.core.type.ReturnType
import io.micronaut.context.invoker.DefaultExecutableMethod
import io.opentracing.Span
import io.opentracing.Tracer
import java.util.*
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionStage
import kotlin.time.Duration
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class)
class InstrumentedInterceptorTest : DescribeSpec({

  val registry = SimpleMeterRegistry()
  val tracer = mockk<Tracer>(relaxed = true)
  val span = mockk<Span>(relaxed = true)

  every { tracer.activeSpan() } returns span

  fun resetRegistry() {
    registry.clear()
  }

  fun totalCounter(name: String): Double =
    registry.find(name).counters().sumOf { it.count() }

  fun timerCount(name: String): Long =
    registry.find(name).timers().counter()?.count()?.toLong() ?: registry.find(name).timers().stream().mapToLong { it.count().toLong() }.sum()

  beforeTest {
    clearAllMocks()
    every { tracer.activeSpan() } returns span
    resetRegistry()
  }

  describe("InstrumentedInterceptor - sync success") {
    it("records success counter and timer and annotates span with id and correlation id") {
      val correlation = object : CorrelationIdContext { override val id: String? = "corr-1" }
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      val ctx = mockk<MethodInvocationContext<Any, Any>>()
      val meta = mockk<AnnotationMetadata>()
      val returnType = mockk<ReturnType<Any>>()

      every { meta.stringValue(Instrumented::class.java, "operation") } returns Optional.of("order.process")
      every { meta.stringValue(Instrumented::class.java, "id") } returns Optional.of("orderId")
      every { meta.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(true)
      every { meta.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)

      every { ctx.annotationMetadata } returns meta
      every { ctx.executableMethod } returns mockk {
        every { argumentNames } returns arrayOf("orderId")
      }
      every { ctx.parameterValues } returns arrayOf<Any>("id-123")
      every { returnType.type } returns Boolean::class.java
      every { ctx.returnType } returns returnType
      every { ctx.proceed() } returns true

      val result = interceptor.intercept(ctx)
      result shouldBe true

      // counters
      totalCounter("order.process.count").toInt().shouldBeEqualTo(1)
      // timer exists (at least recorded once)
      registry.find("order.process.time").timers().size shouldBeGreaterThan 0

      verify { span.setTag("order.process.id", "id-123") }
      verify { span.setTag("correlation_id", "corr-1") }
    }
  }

  describe("InstrumentedInterceptor - sync failure") {
    it("records error counters and tags span and logs error") {
      val correlation = object : CorrelationIdContext { override val id: String? = null }
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      val ctx = mockk<MethodInvocationContext<Any, Any>>()
      val meta = mockk<AnnotationMetadata>()
      val returnType = mockk<ReturnType<Any>>()

      every { meta.stringValue(Instrumented::class.java, "operation") } returns Optional.of("order.process")
      every { meta.stringValue(Instrumented::class.java, "id") } returns Optional.empty()
      every { meta.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
      every { meta.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)

      every { ctx.annotationMetadata } returns meta
      every { ctx.executableMethod } returns mockk {
        every { argumentNames } returns arrayOf<String>()
      }
      every { ctx.parameterValues } returns arrayOf<Any>()
      every { returnType.type } returns Boolean::class.java
      every { ctx.returnType } returns returnType
      every { ctx.proceed() } throws IllegalStateException("boom")

      shouldThrow<IllegalStateException> { interceptor.intercept(ctx) }

      totalCounter("order.process.count").toInt().shouldBeEqualTo(1) // error recorded
      // error breakdown counter also incremented
      registry.find("order.process.errors").counters().sumOf { it.count() }.toInt().shouldBeEqualTo(1)

      verify { span.setTag("error", true) }
      verify { span.setTag("order.process.error_type", "IllegalStateException") }
      verify { span.log(match<Map<String, String>> { it["error.kind"] == "IllegalStateException" }) }
    }
  }

  describe("InstrumentedInterceptor - async success") {
    it("handles CompletionStage success and records metrics after completion") {
      val correlation = object : CorrelationIdContext { override val id: String? = "corr-async" }
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      val ctx = mockk<MethodInvocationContext<Any, Any>>()
      val meta = mockk<AnnotationMetadata>()
      val returnType = mockk<ReturnType<Any>>()

      every { meta.stringValue(Instrumented::class.java, "operation") } returns Optional.of("order.async")
      every { meta.stringValue(Instrumented::class.java, "id") } returns Optional.of("orderId")
      every { meta.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(true)
      every { meta.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)

      every { ctx.annotationMetadata } returns meta
      every { ctx.executableMethod } returns mockk {
        every { argumentNames } returns arrayOf("orderId")
      }
      every { ctx.parameterValues } returns arrayOf<Any>("async-1")
      every { returnType.type } returns CompletionStage::class.java
      every { ctx.returnType } returns returnType

      val future = CompletableFuture.completedFuture(true)
      every { ctx.proceed() } returns future

      val returned = interceptor.intercept(ctx) as CompletionStage<*>
      // ensure completion handlers ran
      eventually(Duration.seconds(1)) {
        totalCounter("order.async.count").toInt().shouldBeEqualTo(1)
      }

      verify { span.setTag("order.async.id", "async-1") }
      verify { span.setTag("correlation_id", "corr-async") }
    }
  }

  describe("InstrumentedInterceptor - async failure") {
    it("handles CompletionStage exceptional completion and records error metrics") {
      val correlation = object : CorrelationIdContext { override val id: String? = null }
      val interceptor = InstrumentedInterceptor(registry, tracer, correlation)

      val ctx = mockk<MethodInvocationContext<Any, Any>>()
      val meta = mockk<AnnotationMetadata>()
      val returnType = mockk<ReturnType<Any>>()

      every { meta.stringValue(Instrumented::class.java, "operation") } returns Optional.of("order.async")
      every { meta.stringValue(Instrumented::class.java, "id") } returns Optional.of("orderId")
      every { meta.booleanValue(Instrumented::class.java, "includeIdInMetric") } returns Optional.of(false)
      every { meta.booleanValue(Instrumented::class.java, "recordErrors") } returns Optional.of(true)

      every { ctx.annotationMetadata } returns meta
      every { ctx.executableMethod } returns mockk {
        every { argumentNames } returns arrayOf("orderId")
      }
      every { ctx.parameterValues } returns arrayOf<Any>("async-2")
      every { returnType.type } returns CompletionStage::class.java
      every { ctx.returnType } returns returnType

      val future = CompletableFuture<Boolean>()
      every { ctx.proceed() } returns future

      val returned = interceptor.intercept(ctx) as CompletionStage<*>
      future.completeExceptionally(RuntimeException("async boom"))

      eventually(Duration.seconds(1)) {
        totalCounter("order.async.count").toInt().shouldBeEqualTo(1) // error incremented
        registry.find("order.async.errors").counters().sumOf { it.count() }.toInt().shouldBeEqualTo(1)
      }

      verify { span.setTag("error", true) }
      verify { span.setTag("order.async.error_type", "RuntimeException") }
    }
  }
})
