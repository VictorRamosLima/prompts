Contexto
- Precisamos auditar a suíte de testes do projeto Kotlin para elevar cobertura efetiva, remover test smells, corrigir uso inadequado de mocks e estabilizar testes assíncronos.
- Repositório/branch-alvo: <KT_REPO_URL> @ <KT_BRANCH_OR_SHA>
- Stack de testes: JUnit 5, Kotest, MockK, kotlinx-coroutines-test, (opcional) Turbine para Flow, JaCoCo (cobertura), PIT (mutation testing).

Objetivos (DoD)
1) Mapa completo de cobertura (linhas e ramos) por módulo/pacote/classe e Top 20 trechos não cobertos, com plano de teste para cada.
2) Relatório de test smells e más práticas (mocks relaxados, any() excessivo, sleeps, asserts fracos etc.) com correções propostas.
3) Suíte estabilizada: sem flakiness detectável em 20 execuções consecutivas; testes de corrotinas/Flow rodando sob runTest/StandardTestDispatcher.
4) Ganhos mínimos: +10pp em cobertura de linhas no domínio crítico, +15pp em branches nos arquivos mais sensíveis, MSI (mutation score) ≥ 70% no domínio.
5) PRs pequenos e coesos com melhorias de infraestrutura de teste e casos novos/ajustados; relatórios versionados em /reports e /docs.

Entregáveis
- docs/TEST_AUDIT.md: visão executiva, KPIs, riscos e próximos passos.
- reports/COVERAGE_BASELINE.html|xml e reports/COVERAGE_GAPS.csv (arquivo:linha, tipo: linha|ramo, razão e estratégia de cobertura).
- reports/MUTATION_REPORT.html e reports/MUTATION_SUMMARY.md (MSI por módulo, mutantes vivos/críticos).
- reports/TEST_SMELLS.md: itens com severidade (blocker/major/minor), exemplo de código antes/depois e referência.
- reports/ASYNC_STABILITY.md: problemas de concorrência/tempo (clock, dispatchers, Flow) e correções.
- PRs:
  • PR-TestInfra: configuração/ajustes de JaCoCo, PIT, coroutines-test, Turbine (se usado), tasks Gradle.
  • PR-Tests: novos testes e refactors de testes (subdividido por módulo).
  • PR-Fixes (se necessário): pequenos ajustes no código para testabilidade (injeção de Clock/Dispatcher, reduzir estáticos etc.).

Procedimento (passo-a-passo objetivo)
1) Indexar o repositório; gerar visão de módulos, pacotes, classes e mapeamento atual de testes (por convenção de pastas e nomes). Registrar SHA.
2) Rodar pipeline atual de testes e cobertura (Gradle): capturar baseline (linhas/branches por arquivo) e exportar XML/HTML do JaCoCo. Persistir em reports/COVERAGE_BASELINE.*.
3) Rodar mutation testing (PIT com pitest-junit5 e suporte Kotlin) nos módulos de domínio: gerar MSI por módulo e lista de mutantes vivos; persistir em reports/MUTATION_*.
4) Varrer testes e coletar test smells com busca estática + heurísticas:
   - MockK: mocks com `relaxed = true`; uso de `any()`/`coAny()` como curinga onde é possível `eq(...)`/`match { ... }`/captura (`slot`, `capture`); ausência de `verify(exactly = N)`/`confirmVerified(...)`; uso de `spyk` indevido; verificação de ordem quando necessário (`verifyOrder`, `verifySequence`).
   - Assíncrono: uso de `runBlocking`/`Thread.sleep`/delays reais; ausência de `runTest`/`StandardTestDispatcher`/controle de scheduler; coletar Flows sem Turbine/técnica equivalente; depender de `Dispatchers.IO/Main` reais; não isolar `Clock`/tempo.
   - Asserts fracos: `assertTrue/False` genéricos; ausência de mensagens; não validação de erros/status codes/campos críticos; snapshot sem contrato.
   - Estrutura: testes grandes (fixture geral), lógica condicional em teste, dependência de I/O/rede, dados mágicos, repetição de boilerplate (falta de builders/Arb).
5) Para cada smell, sugerir correção concreta com diff mínimo e exemplo antes/depois; classificar severidade/impacto.
6) Identificar Top 20 lacunas de cobertura (linhas e branches) por impacto de negócio/risco. Para cada, propor caso(s) de teste objetivo(s) cobrindo felizes/borda/negativos; quando envolver corrotinas/Flow, usar `runTest`, dispatcher de teste e, se aplicável, Turbine.
7) Estabilidade: criar job que executa os testes 20x em sequência; coletar flakiness (falhas intermitentes) e logs. Para testes com falha intermitente, aplicar correções (clock fake, dispatcher, await determinístico, eliminação de sleep/polling, verificação de ordem/eventos).
8) Melhorias de infraestrutura:
   - Adicionar/ajustar tasks Gradle para JaCoCo (incluindo branches), publicação de relatórios e enforcement de thresholds por módulo (failOnViolation configurável).
   - Configurar PIT (targetClasses, mutators relevantes, exclusões justificadas) e task de relatório agregada.
   - Padronizar utilitários de teste: `TestClock`/`FixedClock`, `TestDispatcherProvider`, builders/Arb para objetos de domínio, helpers de matchers fortes.
9) Implementar casos de teste novos/refactors priorizados (menores PRs por módulo), garantindo clareza e isolamento; substituir `any()` por `eq`/`match`/capturas; remover relaxados ou justificar explicitamente; adicionar `confirmVerified` quando fizer sentido.
10) Reexecutar cobertura e PIT; registrar ganhos vs baseline; atualizar KPIs em docs/TEST_AUDIT.md e reports/COVERAGE_GAPS.csv.
11) Publicar PRs com Conventional Commits; anexar links dos relatórios e evidências; responder a comentários se necessário.
12) Entregar nesta conversa: sumário executivo (KPIs), Top 10 smells e gaps por impacto, links dos PRs e caminhos dos relatórios.

Critérios e metas
- Cobertura alvo: Domínio ≥ 85% linhas; Branches ≥ 80%; Classes críticas ≥ 90% linhas.
- Mutation testing: MSI ≥ 70% no domínio; mutantes sobreviventes críticos documentados.
- Estabilidade: 0 falhas intermitentes em 20 execuções consecutivas; tempo total de suíte aceitável (< X min, definir).
- Qualidade de mocks: `relaxed` proibido por padrão; permitido apenas quando explicitamente justificado. Evitar `any()` onde `eq`/`match`/`capture` é viável; verificar contagem e ordem quando relevante.
- Corrotinas/Flow: todos os testes com `runTest`; uso de `StandardTestDispatcher`/scheduler; coletar Flow com Turbine (ou equivalente) quando verificação de sequência/erro/completion for necessária.

Parâmetros de execução (preencher)
- Módulos/prioridades de domínio: <...>
- Thresholds por módulo (linhas/branches/MSI): <...>
- Tempo máximo de suíte: <...>
- Integrações externas a isolar (fakes/mocks): <...>

Saída esperada nesta conversa
- Resumo executivo (≤20 linhas) com KPIs (cobertura linhas/branches, MSI, flakiness).
- Tabela Top 10 smells e Top 10 gaps de cobertura por impacto, com arquivo:linha e ação recomendada.
- Links dos PRs e paths dos relatórios em /reports e /docs.