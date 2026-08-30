# Handoff — auditoria round 2 e o mapa que falta criar

Estado em 2026-08-30. Escrito para sobreviver a um `/compact`: quem pegar isso não
precisa reler a sessão anterior.

## Onde o código está

`main` @ `db1b07c` — o merge do PR #11. iOS e macOS compilando sem warnings, 128
testes passando. Árvore limpa, nada pendente.

`main` está em **1.8 (21)**. A decisão do dono (Q3 abaixo) é que todo trabalho
novo vai para a **1.9**, então em algum momento o `project.yml` precisa do bump —
e o comentário lá dentro explica por que 1.8 é menor que o 1.9 que existia antes.
Não faça esse bump por conta própria: ele marca o início de um ciclo de release.

## O que a auditoria produziu

Duas passadas independentes sobre 86 arquivos / 17 292 linhas, depois refutação
adversarial. **83 achados de qualidade + 33 candidatos de arquitetura.**

Relatório HTML: [docs/ROUND2-RELATORIO.html](ROUND2-RELATORIO.html) — copiado para o repo.
O original ficou em
`$TMPDIR/architecture-review-20260830-034447.html` — **é efêmero**, o `/tmp` do
macOS é limpo. Se ainda existir, vale salvar; se não, o conteúdo essencial está
abaixo e nos journals (caminhos no fim deste doc).

### Os 8 defeitos verificados

Cada um sobreviveu a dois refutadores independentes ou foi confirmado à mão.
Ordenados por gravidade:

1. **Deep Research: quatro controles são placebo.** `DeepResearchView` renderiza
   menus para Format / Search / Endpoint / Model, ligados a `vm.format`,
   `vm.searchEngine`, `vm.endpointId`, `vm.model`. `start()` passa só
   `query`, `maxRounds`, `category`; `startResearch` monta
   `{query, max_rounds, category}`. Os quatro campos nunca são lidos por nada que
   monte um request. `api.modelEndpoints()` é chamado só para popular um menu inerte.
   — `Features/Research/DeepResearchView.swift:145`, `ResearchAPI.swift:67`

2. **Chave de busca gravada sob o nome do provedor errado.** `SearchSettingsVM`
   tem um único campo `key` para quatro provedores. O menu faz
   `vm.provider = p; Task { await vm.save() }`, e o `save()` grava esse campo sob
   `keyField[provider]` — já o novo. Brave → Tavily manda a chave da Brave como
   `tavily_api_key`. O `load()` também não limpa `key` quando o provedor não tem
   campo de chave. — `Features/Settings/SettingsSections.swift:145–190`

3. **Oito view models escrevem um `error` que nenhuma view lê.** Brain, Notes,
   Tasks, Gallery, Library, Compare, mais `ChatViewModel` e `SessionStore`.
   Em Tasks, "Rodar agora" falhando com 403 é pixel-a-pixel idêntico ao sucesso.
   Em Notes, salvar com o servidor em 500 fecha a folha e a nota some sem aviso.
   Pior: o estado vazio é gateado só por `items.isEmpty`, então uma carga que
   **falhou** renderiza "Sem notas ainda" — diz ao usuário que os dados dele não existem.

4. **Arquivo com `&` no nome não pode ser apagado, e o app diz que apagou.**
   `deletePersonal` usa `.urlQueryAllowed` cru em vez do `encQuery` canônico.
   O servidor responde 200 sem apagar; a linha some e o arquivo volta no refresh,
   ainda indexado no RAG. — `Features/Library/LibraryView.swift:52`

5. **Editar nota arquivada a desarquiva.** `save` monta `NotePayload(archived: false)`
   fixo. Da cadeira do usuário, a nota some ao salvar. — `Features/Notes/NotesView.swift:26`

6. **Erro de stream mostra JSON cru.** `extractError` devolve `String(body[r])` —
   o match inteiro da regex, não o grupo capturado. — `Networking/ChatStreamClient.swift:136`

7. **Navegação chaveada pelo valor inteiro da sessão.** `WorkspacePane.Kind.chat(ChatSession)`
   com `Hashable` sintetizado compara todos os campos; renomear a sessão troca o
   endereço do painel. — `Features/Navigation/Workspace.swift:10`

8. **Quatro limites do agente viram zero num servidor novo.**
   `bag.int("agent_max_rounds")` sem `default:` cai em 0, e o Salvar grava 0.
   — `Features/Settings/SettingsAdminSections.swift:254`

### Os 7 candidatos de arquitetura

Nenhum foi verificado adversarialmente — é isso que a fase (a) precisa fazer.
Ordenados por convergência entre lentes independentes:

| # | Candidato | Lentes | Concentra |
|---|---|---|---|
| 1 | **A tela de coleção remota** | 2 | 20 sítios |
| 2 | **Uma configuração declarada uma vez** | 3 | 8 view models |
| 3 | **A autoridade da sessão** | 2 | 5 stores |
| 4 | **A descrição do request** | 2 | 81 métodos |
| 5 | **Decodificação tolerante** | 1 | 25 decoders |
| 6 | **O leitor de SSE** | 3 | 2 implementações |
| 7 | **`Features` — módulo que ninguém lê** | 1 | deleta 30 linhas + 3 awaits |

Contagens que eu **confirmei à mão** (não são estimativa de agente): 29 cópias do
mesmo `msg(_:)`, 22 `catch is CancellationError`, 21 `.task { await vm.load() }`,
19 `@Published var error`, 18 `@Published var loading`, 17 `loading = true; defer`,
13 `extension APIClient` espalhadas por 12 módulos (4 delas dentro de arquivos de view).

O número que organiza tudo: **128 testes, e zero tocam o caminho de carga que toda
tela roda.** O que é testável hoje foi extraído como função pura porque o resto não
é alcançável pela interface que tem.

### O que a refutação matou

Três claims plausíveis caíram. Taxa de erro de 27% numa amostra que eu já achava
sólida — é o argumento inteiro para a fase (a) existir.

- `Font.ody(design:)` descarta o parâmetro: **fato real, "e daí" falso.** Nenhuma
  fonte renderizada mudaria. Limpeza menor, não achado.
- `decodeList` engole falhas: **refutado.** 16 dos 17 tipos têm decoder tolerante
  por design; drift degrada linhas, nunca esvazia listas.
- `ChatViewModel` recriado por render: **refutado.** `@StateObject` retém o
  primeiro; as duas linhas de configuração mutam a cópia descartada.

## As decisões do dono (grill de destino, respondido)

| | Pergunta | Resposta |
|---|---|---|
| **Q1** | O que "verificar todos" entrega | **(a)** backlog confiável primeiro, sem código. Depois **(b)** corrigir os 8 defeitos, depois **(c)** tudo. **(d)** spec de arquitetura fica por último. |
| **Q2** | Quanta verificação | **(c)** primeiro: só claims de *comportamento* levam refutação adversarial; claims estruturais ("existem 29 cópias") se confirmam por `grep` e custam nada. Depois rodar **(a)**, verificação completa. |
| **Q3** | Relação com a 1.8 na Apple | **(c)** ignorar — tudo vai para a 1.9. |
| **Q4** | Escopo de "todos" | **(b)**: os 8 defeitos + 7 candidatos entram no mapa; os outros 68 achados viram **um issue guarda-chuva**, registrados e linkados, prontos para graduar. Depois **(a)**, os 116. |

**Regra permanente que ele deu, e que vale além deste esforço:**
> Se o escopo maior for selecionado no lugar de um menor, escolha o menor, depois
> das correções escale para a maior.

Salva em memória como [scope-smallest-first](../../.claude/projects/-Users-joaozao-Projetos/memory/scope-smallest-first.md).

## O mapa: passo 1 feito, passo 2 é onde você pega

O `/wayfinder` chart tem seis passos. **Passo 1 (nomear o destino) está feito** —
é a tabela acima. **Passo 2 (grill de fronteira, em largura) não foi feito**, e
eu deliberadamente não criei o mapa nem os tickets: meio-cartografar produz um
mapa pior que nenhum.

### Destino do primeiro mapa (fase `a`, o menor escopo)

> Um backlog em que o dono confia: cada um dos 15 achados destacados (8 defeitos
> + 7 candidatos de arquitetura) confirmado ou descartado, com os outros 68
> registrados num issue guarda-chuva. Nenhum código alterado.

Repare que os 8 defeitos **já estão verificados** — o trabalho real da fase (a)
é sobre os 7 candidatos, que nunca passaram por refutação, e sobre as afirmações
medidas dentro deles.

### Notes que o mapa deve carregar

- Tracker: GitHub Issues via `gh`. Convenções em `docs/agents/issue-tracker.md`
  (sub-issues via `gh api`, blocking via dependências nativas, claim por assignee).
- **Labels `wayfinder:*` não existem ainda** — `gh label create` para
  `wayfinder:map`, `wayfinder:research`, `wayfinder:prototype`,
  `wayfinder:grilling`, `wayfinder:task` antes de criar o mapa.
- Não existe `CONTEXT.md` nem `docs/adr/`. Criar preguiçosamente, quando o
  primeiro termo se resolver.
- Regra de escopo do dono (acima): sempre o menor primeiro.
- Q2 = (c): antes de gastar um agente refutando, pergunte se um `grep` responde.
  Verificar duplicação medida com refutação adversarial é queimar token para
  reconfirmar um comando.

### Fog inicial — o que já dá para ver mas não dá para ticketar

- Se os candidatos 1, 3 e 4 são **um** aprofundamento ou três. O candidato 1
  precisa de onde o 401 chegar (que é o 3) e de uma costura de transporte (que é
  o 4); fazer o 1 primeiro define a forma dos outros dois, o inverso não vale.
  A pergunta "são um ou três?" não está afiada o bastante para virar ticket.
- Quanto dos 68 achados parqueados sobrevive a uma leitura crítica. Suspeita:
  bem menos que 68, pelos mesmos 27% de cima.
- Se `CONTEXT.md` vale a pena para este repo, e quais termos ele fixaria
  ("sessão", "coleção remota", "configuração", "motor"). Depende de quantos
  candidatos sobreviverem à fase (a).

### Fora de escopo (fase a)

- Escrever qualquer código de correção — é a fase (b).
- A spec de arquitetura — é a fase (d), explicitamente por último.
- O bump para 1.9 — marca um ciclo de release, não é passo desta rota.

## Onde os dados brutos vivem

Índice compacto dos 116 achados: [docs/ROUND2-ACHADOS.md](ROUND2-ACHADOS.md) — vive no repo,
não depende de nada efêmero. Os journals têm o texto completo de cada um
(problem / move / payoff, e para os candidatos também deletionTest / beforeShape /
afterShape). **São locais e não versionados** — se a pasta da sessão sumir, o índice
acima é o que resta:

```
~/.claude/projects/-Users-joaozao-Projetos/aae19c9d-e660-4976-b539-7f0d405bd454/subagents/workflows/
  wf_c0938565-c71/journal.jsonl   # 83 achados de qualidade, 8 fatias
  wf_fa58d64c-06d/journal.jsonl   # 33 candidatos de arquitetura, 6 lentes
  wf_d7428f6f-e7f/journal.jsonl   # 16 refutadores, 8 claims
```

Extração: cada linha `{"type":"result",…}` tem o retorno estruturado do agente.

## Um aviso sobre o método

A convergência entre lentes que não se viram é o sinal mais confiável que esse
formato produz — "configuração declarada uma vez" saiu de três lentes
separadamente, "leitor de SSE" de três, "tela de lista remota" de duas.

O sinal **menos** confiável é um achado isolado, de uma lente só, que ninguém
refutou. Os 68 parqueados são majoritariamente disso. Trate-os como hipóteses,
não como dívida conhecida — foi exatamente essa a diferença entre os 5 claims
que sobreviveram e os 3 que caíram.
