```kotlin
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.booleans.shouldBeTrue
import io.kotest.matchers.collections.shouldHaveSize
import io.kotest.matchers.shouldBe
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardOpenOption
import kotlin.io.path.deleteRecursively
import kotlin.io.path.exists
import kotlin.io.path.isRegularFile
import kotlin.random.Random

class LocalObjectStorageStringSpec : StringSpec({

    lateinit var root: Path
    lateinit var storage: LocalObjectStorage

    fun sha256Hex(bytes: ByteArray): String {
        val md = java.security.MessageDigest.getInstance("SHA-256")
        return md.digest(bytes).joinToString("") { "%02x".format(it) }
    }

    fun sanitize(s: String): String = s.replace("..", "").trim('/')

    beforeSpec {
        root = Files.createTempDirectory("local-object-storage-test-")
        storage = LocalObjectStorage(root)
    }

    afterSpec {
        root.deleteRecursively()
    }

    "creates root directory on init" {
        val newRoot = root.resolve("sub-not-exists")
        LocalObjectStorage(newRoot) // must not throw
        newRoot.exists().shouldBeTrue()
    }

    "writes file and returns sha256" {
        val content = "hello-world".toByteArray()
        val hash = storage.put("bucket", "dir/file.txt", content, "text/plain")
        hash shouldBe sha256Hex(content)
        Files.readAllBytes(root.resolve("bucket/dir/file.txt")) shouldBe content
    }

    "creates intermediate directories" {
        val content = byteArrayOf(1, 2, 3)
        storage.put("bkt", "a/b/c/d.bin", content, null)
        Files.readAllBytes(root.resolve("bkt/a/b/c/d.bin")) shouldBe content
    }

    "overwrites and truncates existing file" {
        val p = root.resolve("b/over/file.dat")
        Files.createDirectories(p.parent)
        Files.write(p, ByteArray(1024) { 7 }, StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING)

        val newContent = ByteArray(3) { 9 }
        val h = storage.put("b", "over/file.dat", newContent, null)

        h shouldBe sha256Hex(newContent)
        Files.readAllBytes(p) shouldBe newContent
    }

    "handles empty content" {
        val content = ByteArray(0)
        val h = storage.put("empty", "zero.bin", content, "application/octet-stream")
        h shouldBe sha256Hex(content)
        Files.size(root.resolve("empty/zero.bin")) shouldBe 0
    }

    "sanitizes storageName and key (no path traversal, stays under root)" {
        val content = "x".toByteArray()
        val storageName = "..my-bucket.."
        val key = "/../etc//../passwd.txt"
        storage.put(storageName, key, content, null)

        val expected = root.resolve(sanitize(storageName)).resolve(sanitize(key)).normalize()
        expected.startsWith(root).shouldBeTrue()

        Files.isRegularFile(expected).shouldBeTrue()
        Files.readAllBytes(expected) shouldBe content
    }

    "multiple slashes and leading/trailing slashes are tolerated" {
        val content = "slash".toByteArray()
        storage.put("///bucket///", "///a///b//c.txt///", content, null)

        val expected = root
            .resolve(sanitize("///bucket///"))
            .resolve(sanitize("///a///b//c.txt///"))
            .normalize()

        Files.readAllBytes(expected) shouldBe content
    }

    "large payload integrity (5MB)" {
        val content = Random.Default.nextBytes(5 * 1024 * 1024)
        val h = storage.put("large", "payload.bin", content, "application/octet-stream")
        h shouldBe sha256Hex(content)
        Files.readAllBytes(root.resolve("large/payload.bin")) shouldBe content
    }

    "concurrent writes to different keys are consistent" {
        val n = 50
        val payloads = List(n) { i -> ("data-$i").toByteArray() }

        coroutineScope {
            payloads.mapIndexed { i, bytes ->
                async { i to storage.put("concurrent", "k$i.dat", bytes, null) }
            }.awaitAll().forEach { (i, hash) ->
                hash shouldBe sha256Hex(payloads[i])
                Files.readAllBytes(root.resolve("concurrent/k$i.dat")) shouldBe payloads[i]
            }
        }

        Files.walk(root.resolve("concurrent"))
            .filter { it.isRegularFile() }
            .toList()
            .shouldHaveSize(n)
    }

    "contentType is ignored and does not affect result" {
        val content = "mime-agnostic".toByteArray()
        val h1 = storage.put("mime", "f.txt", content, "text/plain")
        val h2 = storage.put("mime", "g.bin", content, "application/octet-stream")
        h1 shouldBe sha256Hex(content)
        h2 shouldBe sha256Hex(content)
    }
})

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.StringSpec
import io.kotest.matchers.booleans.shouldBeTrue
import io.kotest.matchers.nulls.shouldBeNull
import io.kotest.matchers.shouldBe
import io.mockk.CapturingSlot
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.every
import io.mockk.impl.annotations.MockK
import io.mockk.slot
import io.mockk.verify
import kotlinx.coroutines.test.runTest
import software.amazon.awssdk.core.async.AsyncRequestBody
import software.amazon.awssdk.core.internal.async.ByteArrayAsyncRequestBody
import software.amazon.awssdk.services.s3.S3AsyncClient
import software.amazon.awssdk.services.s3.model.PutObjectRequest
import software.amazon.awssdk.services.s3.model.PutObjectResponse
import java.nio.ByteBuffer
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Flow

class S3ObjectStorageStringSpec : StringSpec({

    @MockK lateinit var client: S3AsyncClient

    lateinit var storage: S3ObjectStorage
    lateinit var reqSlot: CapturingSlot<PutObjectRequest>
    lateinit var bodySlot: CapturingSlot<AsyncRequestBody>

    fun succeedWithETag(etag: String?): CompletableFuture<PutObjectResponse> =
        CompletableFuture.completedFuture(PutObjectResponse.builder().eTag(etag).build())

    beforeSpec {
        MockKAnnotations.init(this)
    }

    beforeTest {
        clearAllMocks()
        storage = S3ObjectStorage(client)
        reqSlot = slot()
        bodySlot = slot()
    }

    "puts object with correct bucket, key, contentType and returns eTag" {
        every { client.putObject(capture(reqSlot), capture(bodySlot)) } returns succeedWithETag("abc123")

        runTest {
            val bytes = "payload".toByteArray()
            val etag = storage.put(
                storageName = "bucket-name",
                key = "folder/file.txt",
                bytes = bytes,
                contentType = "text/plain"
            )
            etag shouldBe "abc123"
        }

        reqSlot.isCaptured.shouldBeTrue()
        with(reqSlot.captured) {
            bucket() shouldBe "bucket-name"
            key() shouldBe "folder/file.txt"
            contentType() shouldBe "text/plain"
        }

        bodySlot.isCaptured.shouldBeTrue()
        val len = bodySlot.captured.contentLength().orElse(-1)
        len shouldBe "payload".toByteArray().size.toLong()
    }

    "returns empty string if SDK response has null eTag" {
        every { client.putObject(any(), any()) } returns succeedWithETag(null)

        runTest {
            val result = storage.put("b", "k", ByteArray(0), "application/octet-stream")
            result shouldBe ""
        }
    }

    "propagates exception when client completes exceptionally" {
        every { client.putObject(any(), any()) } returns CompletableFuture.failedFuture(IllegalStateException("S3 failure"))

        runTest {
            shouldThrow<IllegalStateException> {
                storage.put("b", "k", "x".toByteArray(), "text/plain")
            }.message shouldBe "S3 failure"
        }
    }

    "supports empty payloads (0 bytes)" {
        every { client.putObject(capture(reqSlot), capture(bodySlot)) } returns succeedWithETag("empty-etag")

        runTest {
            val etag = storage.put("bucket", "empty.bin", ByteArray(0), "application/octet-stream")
            etag shouldBe "empty-etag"
        }

        reqSlot.captured.bucket() shouldBe "bucket"
        reqSlot.captured.key() shouldBe "empty.bin"
        reqSlot.captured.contentType() shouldBe "application/octet-stream"
        bodySlot.captured.contentLength().orElse(-1) shouldBe 0
    }

    "accepts unicode keys and nested paths" {
        every { client.putObject(capture(reqSlot), any()) } returns succeedWithETag("etag-unicode")

        runTest {
            val bytes = "δοκιμή-数据-テスト".toByteArray()
            val etag = storage.put("bkt-ê", "nível/二/レベル/árvore.txt", bytes, "text/plain; charset=utf-8")
            etag shouldBe "etag-unicode"
        }

        reqSlot.captured.bucket() shouldBe "bkt-ê"
        reqSlot.captured.key() shouldBe "nível/二/レベル/árvore.txt"
        reqSlot.captured.contentType() shouldBe "text/plain; charset=utf-8"
    }

    "passes bytes to AsyncRequestBody (content length and emitted data match)" {
        val data = ByteArray(1024) { (it % 251).toByte() }

        every { client.putObject(capture(reqSlot), capture(bodySlot)) } answers {
            // Validate by subscribing to the body and collecting emitted ByteBuffers
            val body = bodySlot.captured
            val collected = mutableListOf<ByteBuffer>()

            // Minimal subscriber to aggregate all buffers synchronously
            val latch = java.util.concurrent.CountDownLatch(1)
            body.subscribe(object : Flow.Subscriber<ByteBuffer> {
                lateinit var sub: Flow.Subscription
                override fun onSubscribe(subscription: Flow.Subscription) {
                    sub = subscription
                    sub.request(Long.MAX_VALUE)
                }
                override fun onNext(item: ByteBuffer) { collected.add(item) }
                override fun onError(throwable: Throwable) { latch.countDown(); throw throwable }
                override fun onComplete() { latch.countDown() }
            })
            latch.await()

            // Merge and assert
            val merged = ByteArray(collected.sumOf { it.remaining() })
            var pos = 0
            collected.forEach {
                val slice = ByteArray(it.remaining())
                it.get(slice)
                System.arraycopy(slice, 0, merged, pos, slice.size)
                pos += slice.size
            }

            // Length check (also via contentLength if present)
            body.contentLength().orElse(-1) shouldBe data.size.toLong()
            merged.contentEquals(data).shouldBeTrue()

            succeedWithETag("ok")
        }

        runTest {
            val etag = storage.put("bucket", "bin.dat", data, "application/octet-stream")
            etag shouldBe "ok"
        }

        reqSlot.captured.bucket() shouldBe "bucket"
        reqSlot.captured.key() shouldBe "bin.dat"
        reqSlot.captured.contentType() shouldBe "application/octet-stream"
    }

    "does not mutate request when called repeatedly (idempotent request building)" {
        every { client.putObject(capture(reqSlot), any()) } returns succeedWithETag("e1") andThen succeedWithETag("e2")

        runTest {
            val e1 = storage.put("b", "k1", "a".toByteArray(), "text/plain")
            val e2 = storage.put("b", "k2", "b".toByteArray(), "text/plain")
            e1 shouldBe "e1"
            e2 shouldBe "e2"
        }

        verify(exactly = 2) { client.putObject(any<PutObjectRequest>(), any<AsyncRequestBody>()) }
    }

    "uses AsyncRequestBody.fromBytes internally (implementation detail smoke check)" {
        // We can only assert the effective type for common SDK impl
        every { client.putObject(any(), capture(bodySlot)) } returns succeedWithETag("t")
        runTest { storage.put("b", "k", byteArrayOf(1,2,3), "x/y") }
        (bodySlot.captured is ByteArrayAsyncRequestBody).shouldBeTrue()
    }

    "null contentType should be allowed if method signature changes to nullable (defensive check)" {
        // If the production signature ever becomes nullable, ensure we don't break.
        every { client.putObject(capture(reqSlot), any()) } returns succeedWithETag("n")
        runTest {
            val method = S3ObjectStorage::class.java.methods.first { it.name == "put" }
            // Just ensure current signature is non-null; if it becomes nullable, this test reminds to adapt.
            method.parameterTypes[3].kotlin.isMarkedNullable.shouldBeFalse()
        }
    }

    // Helper extension for assertion without introducing extra libs
    fun Boolean.shouldBeFalse() = (this == false).shouldBeTrue()
})
```
