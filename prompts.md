Contexto
- Sistema migrado de Python para Kotlin. Objetivo: validar paridade funcional e de regras de negócio entre os repositórios legado e migração, apontar divergências, sugerir correções e abrir PRs.
- Repositórios:
  • Legacy (Python): <PY_REPO_URL> @ <PY_BRANCH_OR_SHA>
  • Migração (Kotlin/Java 21): <KT_REPO_URL> @ <KT_BRANCH_OR_SHA>
- Stack Kotlin: Gradle, Kotlin 2.x, testes com Kotest, MockK, Testcontainers; estáticos com Detekt; cobertura com JaCoCo. Framework: <Micronaut|Spring|Ktor>.

Objetivos (DoD)
1) 100% de endpoints/handlers/processos de domínio do Python mapeados para equivalentes em Kotlin.
2) Catálogo de regras de negócio extraído do Python e confrontado com o Kotlin (paridade, divergência, lacuna).
3) Testes gerados/ajustados no Kotlin para comprovar equivalência (unit, property-based, contratos de API, integrações essenciais).
4) Relatórios e PRs criados com plano de correções priorizado (blocker/major/minor) e evidências (traços, diffs, casos de teste, métricas).

Entregáveis
- docs/MIGRATION_AUDIT.md: visão executiva, métricas (itens mapeados, divergências, lacunas), riscos e próximos passos.
- docs/BUSINESS_RULES_CATALOG_(py).md e docs/BUSINESS_RULES_CATALOG_(kt).md.
- reports/PARITY_MATRIX.csv: Python_entity → Kotlin_entity; tipo (endpoint/UC/domínio/job/evento); status (match/diverge/gap); referências (arquivos:linhas; commits).
- reports/GAPS_AND_CHANGES.md: divergências e lacunas com severidade, impacto, proposta de mudança e esforço estimado.
- reports/API_COMPATIBILITY.md: diffs de contratos (REST/gRPC/eventos/filas), esquemas e mapeamentos de códigos de erro.
- reports/TEST_PLAN.md: matriz de testes (unit, property, contrato, integração), dados de teste e cobertura-alvo.
- reports/AUDIT_SUMMARY.json: resumo estruturado (para consumo por CI/BI).
- PRs:
  • PR-Tests+Docs: adição/ajustes de testes, relatórios e validações.
  • PR-Fixes: correções mínimas no Kotlin para fechar gaps prioritários.
- Tags/artefatos: SHAs usados, logs de execução, links de CI, percentuais de cobertura.

Procedimento (Playbook — siga na ordem, 1 step por linha)
1) Clonar ambos repositórios; fixar em <PY_BRANCH_OR_SHA> e <KT_BRANCH_OR_SHA>; registrar SHAs.
2) Executar indexação/Wiki/Search dos repositórios; construir visão de arquitetura (módulos, camadas, entidades, fluxos, endpoints, jobs, eventos, integrações externas).
3) No Python, extrair catálogo de regras: varrer handlers/use-cases/services/domínio/testes/docs; consolidar em BUSINESS_RULES_CATALOG_(py) com campos: id, descrição, precondições, pós-condições, invariantes, erros, side-effects, idempotência, consistência, relógio/tempo, moeda/localização, limites de taxa, concorrência, transações, tolerância a falhas; incluir referências (arquivos:linhas; commit).
4) No Kotlin, repetir a extração e gerar BUSINESS_RULES_CATALOG_(kt) com mesmos campos e referências.
5) Construir PARITY_MATRIX.csv relacionando entidades Python↔Kotlin: endpoint/rota, payloads/DTOs, códigos de status/erros, casos de uso, comandos/eventos, repositórios/gateways, mapeamentos de exceções, contratos externos (HTTP/SQS/Kafka/gRPC), configurações/feature flags.
6) Gerar conjunto de casos de verificação “golden” a partir do Python: para cada regra, derivar entradas mínimas/limítrofes/negativas; quando possível, executar no Python para capturar outputs esperados e serializar em fixtures estáveis.
7) No Kotlin, implementar/verificar testes:
   - Unit: comportamento de domínio e serviços.
   - Property-based (Kotest): propriedades invariantes, metamórficas e limites; seeds fixos para reprodutibilidade.
   - Contratos (API): validação de esquemas, status codes, headers, erros padronizados.
   - Integração essencial (Testcontainers): repositórios, filas/eventos e downstreams críticos.
   - Critérios: falha sempre que divergir do expected do Python ou violar propriedades.
8) Rodar pipeline Kotlin: build, detekt, testes, jacoco; gerar cobertura; salvar relatórios.
9) Identificar divergências: lógica, bordas, padrões de erro, idempotência, ordering, precision/rounding, timezones/clock, retries/circuit-breakers, consistência eventual, transações, paralelismo; documentar em GAPS_AND_CHANGES.md com severidade e impacto.
10) Para cada divergência blocker/major, propor fix minimal e criar patch (isolado, coeso, pequeno), com testes de proteção; preparar PR-Fixes com Conventional Commits e descrição objetiva, linkando itens da PARITY_MATRIX e casos de teste.
11) Preparar PR-Tests+Docs com todos relatórios, fixtures e testes adicionados/ajustados; anexar métricas (itens mapeados, % cobertura, # asserts property-based, # contratos verificados).
12) Gerar MIGRATION_AUDIT.md com: sumário executivo, tabela de KPIs, lista de gaps, decisões tomadas, trade-offs, e backlog de melhorias não bloqueantes.
13) Publicar AUDIT_SUMMARY.json com contagens e referências de artefatos; anexar links de CI e wikis.
14) Entregar relatório final nesta conversa com: sumário, KPIs, links dos PRs, matriz de paridade, principais divergências e recomendações.

Padrões e critérios
- Estilo Kotlin: imutabilidade por padrão, funções puras onde aplicável, erros modelados com Result/Either/selados; sem reflection em hot paths; evitar alocações desnecessárias.
- Testes: nomes dados como especificações; cobrir happy/edge/negative; seeds estáveis; falhar em comportamento não-paritário.
- Cobertura mínima: ≥85% linhas no domínio e ≥95% para regras críticas; reportar módulo a módulo.
- Performance: para rotas/algoritmos críticos, adicionar microbenchmarks JMH e relatar variação >±10% vs baseline (se houver).
- Segurança: preservar semântica de autorização/escopos, validação de entrada, sanitização, segredos/configs; nunca relaxar checks.
- Observabilidade: garantir correspondência de métricas/logs/tracing de negócio; alinhar nomes e cardinalidades.
- Contratos: qualquer mudança de schema/erro requer migração documentada e versão de contrato.

Parâmetros de execução (preencher antes de rodar)
- Serviços externos e credenciais de teste (mock/fake sempre que possível): <...>
- Nome do job/serviço crítico a priorizar: <...>
- Limites de tempo para testes de integração: <...>
- Cobertura alvo por módulo: <...>

Saída esperada nesta conversa
- Resumo executivo (≤25 linhas) com KPIs.
- Tabela compacta dos Top 10 gaps por impacto.
- Links dos PRs e caminhos dos relatórios/artefatos no repositório.