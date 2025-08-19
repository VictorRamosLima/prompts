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
- Kotlin idiomático, imutável por padrão, funções puras no domínio. Evitar side effects fora de application/infrastructure.
- Programação funcional/declarativa quando não afetar legibilidade. Null-safety estrita; Result/Either explícito para erros de domínio.
- Micronaut apenas para bordas (HTTP, DI, Config). Domínio sem dependência de framework.
- Logs estruturados; sem prints. Mensagens e códigos de erro preservados.
- Config via application.yml e variáveis de ambiente. Não hardcode.
- Sem boilerplate desnecessário. YAGNI/KISS/DRY/SOLID.
- Performance: minimizar alocações, evitar reflexão cara no hot path, usar coroutines para IO, medir antes de otimizar.

PLANO DE EXECUÇÃO (PASSO A PASSO):
1) Descoberta:
   - Inventariar o projeto Python: módulos, entrypoints, endpoints/CLI, integração (DB, filas, caches), middlewares, configs.
   - Extrair suite de testes existente e/ou criar testes de caracterização (golden tests) para comportamentos críticos.
   - Gerar TABELA_DE_MAPEAMENTO.md (Python→Kotlin): pacote/arquivo, responsabilidade, dependências, substitutos Kotlin.
2) Arquitetura alvo:
   - Definir camadas: domain (entidades/validações/serviços puros), application (casos de uso, orquestração, transações), infrastructure (adapters HTTP, repos, messaging, config).
   - Definir interfaces de portas (application) e adapters (infra). Sem dependência inversa do domínio.
3) Setup do projeto:
   - Inicializar Micronaut com Gradle Kotlin DSL; fixar Kotlin, Micronaut, Kotest, Kluent, JaCoCo no versions catalog.
   - Habilitar Java toolchain 21; parâmetros de compilação/otimização (inline, no-reflect onde possível).
   - Adicionar tasks Gradle: test, jacocoTestReport, checkCoverage (falhar < metas).
4) Migração incremental:
   - Portar primeiro o domínio puro (regras, validações), criando property-based tests (Geradores Kotest) para invariantes.
   - Portar casos de uso (application) validando contratos com os testes de caracterização.
   - Implementar adapters (infra): HTTP controllers Micronaut, repos (DB), mensagens (SQS/Kafka/etc.), mapeadores.
   - Manter compatibilidade de serialização (campos, nomes, enums, datas). Adicionar testes de compatibilidade (JSON/Protobuf/etc.).
5) Testes:
   - Unit: Kotest + Kluent.
   - Property-based: invariantes de domínio (ex.: idempotência, comutatividade, limites).
   - Integração: Testcontainers quando houver DB/filas. Smoke test de endpoints.
   - Cobertura: garantir relatórios JaCoCo e gates no CI local.
6) Dockerização:
   - Dockerfile multi-stage:
     - Stage build: eclipse-temurin:21-jdk, Gradle wrapper em cache, build fat/optimized jar.
     - Stage runtime: eclipse-temurin:21-jre (ou distroless/base-jre), user não-root, heap sizing via flags.
   - docker-compose.yml: app + dependências (DB/filas) para dev; healthchecks; variáveis de ambiente.
7) Verificação final:
   - Rodar suite completa; comparar respostas/erros com baseline Python.
   - Medir tempo de cold start e throughput básico; anotar no README.
   - Entregar documentos (README, MIGRATION_NOTES, API_COMPATIBILITY).

CRITÉRIOS DE ACEITAÇÃO:
- Build `./gradlew clean test jacocoTestReport` passa; cobertura ≥ 85% global, domínio ≥ 95%.
- `docker build` e `docker-compose up` funcionam localmente, healthcheck OK.
- Endpoints/CLI/Contratos idênticos aos do Python (incluindo mensagens/erros formais e códigos HTTP).
- Testes de compatibilidade de payloads aprovados.
- Sem dependências transitivas desnecessárias; tamanho da imagem final otimizado.
- Documentação mínima entregue e atualizada.

DETALHES DE IMPLEMENTAÇÃO (ESPECÍFICOS):
- Gradle (build.gradle.kts): aplicar plugins `kotlin("jvm")`, `io.micronaut.application`, `jacoco`; configurar toolchain 21; habilitar `-Xjsr305=strict`.
- Dependências principais: `micronaut-http-server-netty` (se HTTP), `micronaut-validation`, `kotlinx-coroutines-core`, `kotest-runner-junit5`, `kotest-assertions-core`, `kotest-property`, `org.amshove.kluent`, `micronaut-test-junit5`.
- Tests: usar `@MicronautTest` apenas quando necessário; preferir testes puros em domínio. Property-based: `checkAll`, `forAll` com `Arb`/`Exhaustive`.
- Serialização: usar Jackson do Micronaut (ou kotlinx.serialization se houver ganho claro), mantendo formatos existentes.
- Logging: SLF4J + Logback; JSON opcional se já usado no Python (preservar formato).

ENTREGAS FINAIS DO DEVIN:
- Repositório pronto (pastas, código Kotlin, testes, Gradle, Dockerfile, docker-compose.yml).
- libs.versions.toml com versões estáveis atuais (registrar no MIGRATION_NOTES).
- README.md com: requisitos, build, testes, execução local (docker-compose), endpoints e exemplos.
- MIGRATION_NOTES.md e API_COMPATIBILITY.md conforme descrito.
- Zip contendo todos os arquivos do projeto.

SEMPRE:
- Explicar no MIGRATION_NOTES qualquer divergência inevitável e a mitigação.
- Não introduzir breaking changes sem forte justificativa documentada e testes cobrindo o novo contrato.
