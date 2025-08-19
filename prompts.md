TAREFA: Migrar um sistema hoje em Python para Kotlin moderno, preservando 100% do comportamento observável (APIs, contratos, formatos, erros esperados, métricas, logs e compatibilidade de banco/filas). Priorizar performance e simplicidade.

STACK OBRIGATÓRIA:
- Kotlin (última estável) + JVM com Java 21 (toolchain 21).
- Micronaut (última estável) para DI/HTTP/Config.
- Gradle Kotlin DSL, com Version Catalog (libs.versions.toml) e dependências pinadas.
- Testes: Kotest (incluindo property-based), Kluent para asserts fluent.
- Coverage: JaCoCo com meta mínima 85% (linhas); core/domain ≥ 95%.
- Docker: multi-stage (build → runtime); imagem final mínima. docker-compose para dev.
- Sem frameworks/libraries não citados sem justificativa técnica.

ENTREGÁVEIS (OBRIGATÓRIOS):
1) Código Kotlin compilável, pronto para rodar em Java 21, com testes passando.
2) Estrutura de projeto Micronaut (Gradle):
   - app/ (ou service/) com main Micronaut
   - domain/, application/, infrastructure/ (separação clara de camadas)
   - src/main/kotlin, src/test/kotlin
   - resources/ (application.yml)
3) Testes:
   - Unitários + property-based para regras de domínio críticas.
   - Integração (HTTP/Repo/Filas) com Testcontainers quando aplicável.
4) Relatório de cobertura JaCoCo no build.
5) Dockerfile multi-stage e docker-compose.yml.
6) Documentos:
   - README.md: build, test, run, perf flags, endpoints.
   - MIGRATION_NOTES.md: mapeamento Python→Kotlin (módulos, deps, configs), decisões, gaps.
   - API_COMPATIBILITY.md: tabela de contratos preservados e casos-limite validados.

CONSTRANGIMENTOS E PADRÕES:
- Kotlin idiomático. `val` por padrão; funções puras em domain. Side effects apenas em application/infrastructure.
- Programação funcional/declarativa sem perder legibilidade. Null-safety estrita; erros de domínio via tipos explícitos (sealed) e `Result`/`Either` caseiro.
- Micronaut apenas nas bordas (HTTP, DI, Config). Domínio sem dependência de framework.
- Logs estruturados; sem prints. Mensagens/códigos de erro preservados.
- Config em application.yml + variáveis de ambiente. Sem hardcode.
- YAGNI/KISS/DRY/SOLID. Sem boilerplate.
- Performance: minimizar alocações, evitar reflexão no hot path, coroutines para IO, `inline` onde fizer sentido, `tailrec` quando aplicável. Medir antes de otimizar.

VARIÂNCIA, TIPOS E MODELAGEM:
- Declarar variância nos tipos genéricos: `out T` para produtores, `in T` para consumidores. Usar-site variance quando necessário (`List<out T>`, `Comparable<in T>`).
- APIs de portas devem expor tipos com variância adequada (`Repository<in C, out R>`, `Mapper<in A, out B>`).
- Preferir interfaces funcionais (SAM) com `fun interface` para estratégias, validadores, policies e mapeadores; permitir SAM-conversion com lambdas.
- Usar sealed classes/ sealed interfaces para modelar somas de tipos (eventos, erros, estados). Exigir `when` exaustivo sem `else`.
- Encapsular invariantes em value objects (`@JvmInline value class`) quando leve.
- Usar `typealias` para funções de alto-uso (ex.: `typealias Validator<T> = (T) -> Either<Error, T>`).
- Extensões puras para enriquecer domínio sem acoplamento.
- Preferir `Sequence` e operações lazy quando houver pipelines grandes; evitar materializações desnecessárias.
- Scoped functions (`let/run/also/apply/with`): usar intensivamente para clareza, porém com no máximo 1 nível de aninhamento. Acima disso, refatorar em funções nomeadas. Proibir `also` + `apply` aninhados além do limite.

PLANO DE EXECUÇÃO (PASSO A PASSO):
1) Descoberta:
   - Inventariar projeto Python: módulos, entrypoints, endpoints/CLI, integrações (DB/filas/caches), middlewares, configs.
   - Extrair suite de testes ou criar testes de caracterização (golden tests) para comportamentos críticos.
   - Gerar TABELA_DE_MAPEAMENTO.md (Python→Kotlin): pacote/arquivo, responsabilidade, dependências, substitutos Kotlin.
2) Arquitetura alvo:
   - Camadas: domain (entidades/validadores/serviços puros), application (casos de uso, orquestração, transações), infrastructure (adapters HTTP, repos, messaging, config).
   - Portas e adapters genéricos com variância explícita; policies via SAM.
3) Setup do projeto:
   - Inicializar Micronaut com Gradle Kotlin DSL; fixar versões no version catalog.
   - Toolchain Java 21; `-Xjsr305=strict`; ativar `-Xjvm-default=all` se necessário para interfaces.
   - Tasks Gradle: `test`, `jacocoTestReport`, `checkCoverage` (falhar < metas).
4) Migração incremental:
   - Portar primeiro o domínio (sealed/values/variância/SAMs), com property-based tests para invariantes.
   - Portar casos de uso (application) validando contratos via testes de caracterização.
   - Implementar adapters (infra): controllers Micronaut, repos, mensageria, mapeadores. Serialização compatível.
5) Testes:
   - Unitários com Kotest/Kluent.
   - Property-based: invariantes (associatividade, idempotência, limites, monotonicidade, leis de mapeamento).
   - Integração: Testcontainers p/ DB/filas. Smoke HTTP.
   - Tests de compatibilidade de payload (JSON/Protobuf) byte-to-byte quando aplicável.
6) Dockerização:
   - Dockerfile multi-stage:
     - build: eclipse-temurin:21-jdk; cache do Gradle; build fat/optimized jar.
     - runtime: eclipse-temurin:21-jre (ou distroless); user não-root; flags de heap e GC.
   - docker-compose.yml: app + deps (DB/filas), healthchecks, envs.
7) Verificação final:
   - Rodar suite completa; comparar respostas/erros com baseline Python.
   - Medir cold start e throughput; anotar no README.
   - Entregar README, MIGRATION_NOTES, API_COMPATIBILITY.

CRITÉRIOS DE ACEITAÇÃO:
- `./gradlew clean test jacocoTestReport` passa; cobertura ≥ 85% global, domínio ≥ 95%.
- `docker build` e `docker-compose up` OK com healthcheck.
- Contratos/erros/formatos idênticos ao Python.
- Payload-compat tests aprovados.
- Imagem final enxuta; sem dependências desnecessárias.
- Documentação mínima entregue e atualizada.

DETALHES DE IMPLEMENTAÇÃO (ESPECÍFICOS):
- Gradle (build.gradle.kts): plugins `kotlin("jvm")`, `io.micronaut.application`, `jacoco`. Toolchain 21. `kotlinOptions { freeCompilerArgs += listOf("-Xjsr305=strict") }`.
- Dependências: `micronaut-http-server-netty` (se HTTP), `micronaut-validation`, `kotlinx-coroutines-core`, `kotest-runner-junit5`, `kotest-assertions-core`, `kotest-property`, `org.amshove.kluent`, `micronaut-test-junit5`.
- Sealed + Result/Either: implementar tipos como `sealed interface DomainError` e `sealed interface Either<out L, out R>`. `map/flatMap/fold` covariantes; parâmetros de entrada contravariantes (`in`).
- Portas genéricas com variância:
  - `fun interface Mapper<in A, out B> { fun map(a: A): B }`
  - `interface Repository<in K, in C : Command, out E : Entity> { suspend fun create(cmd: C): E; suspend fun find(key: K): E? }`
- Funções inline/reified para mapeamento/reflection controlada; evitar reflexão pesada em runtime.
- `@MicronautTest` apenas quando necessário; priorizar testes puros. Property-based: `checkAll`, `forAll` com `Arb`/`Exhaustive`.
- Scoped functions: guideline — `apply` para build de objetos mutáveis locais, `also` para efeitos colaterais, `let` para encadeamento nulo/transformação, `run` para escopo local; no máximo 1 aninhamento.
- Serialização: Jackson Micronaut (ou kotlinx.serialization se ganho mensurável). Preservar nomes/casos/camel/kebab/datas exatos. Tests de roundtrip.
- Logging: SLF4J + Logback, campos estruturados. Sem stacktraces em hot path a menos que necessário.

VERSÕES PINADAS:
- Kotlin: 2.2.10
- Java (Eclipse Temurin): 21.0.8
- Gradle: 8.14.3
- Micronaut Framework: 4.9.2
- Micronaut Gradle Plugin (io.micronaut.application): 4.5.4
- Kotest: 6.0.0
- Kotest Property: 6.0.0
- Kluent: 1.73
- JUnit Jupiter: 5.13.4
- Testcontainers (Java): 1.21.3
- kotlinx-coroutines-core: 1.10.2
- kotlinx-serialization-json (opcional): 1.9.0
- JaCoCo: 0.8.13
- SLF4J API: 2.0.17
- Logback Classic: 1.5.18
- Docker base images:
  - build: eclipse-temurin:21.0.8_9-jdk
  - runtime: eclipse-temurin:21.0.8_9-jre

ENTREGAS FINAIS DO DEVIN:
- Repositório pronto (código Kotlin, testes, Gradle, Dockerfile, docker-compose.yml).
- libs.versions.toml com versões estáveis atuais (registrar no MIGRATION_NOTES).
- README.md com requisitos, build, testes, execução local (docker-compose), endpoints e exemplos.
- MIGRATION_NOTES.md e API_COMPATIBILITY.md conforme descrito.

SEMPRE:
- Documentar no MIGRATION_NOTES qualquer divergência e mitigação.
- Não introduzir breaking changes sem justificativa forte e testes cobrindo o novo contrato.
