# Handoff — próxima fase: arquitetura

Estado em 2026-08-30, fim do ciclo de qualidade. Tudo abaixo está em `main`.

## O que fechou

| | |
|---|---|
| PR #27 | 34 defeitos verificados da auditoria round 2 — fecha #12–#19, #21–#24 |
| PR #28 | localização em 44 idiomas, guia de email migrado, fix do Whisper — fecha #25, #26 |
| #9 | fechada: as duas metades já estavam corrigidas antes do relato (autor estava na 1.7) |

`main` está em **1.9 / build 22** (macOS build 16). 152 testes, iOS e macOS
compilando sem aviso. Os 44 catálogos têm exatamente 616 chaves cada, e nenhum
literal em português no Swift está sem chave — varrido, não presumido.

## O que sobrou: issue #20

**Só isso.** 76 achados de qualidade que não viraram issue própria.

### Leia o aviso da issue antes de agir

Cada linha é a alegação de **um agente, sem ninguém tentar refutar**. Dos oito que
passaram por verificação adversarial nesta mesma auditoria, **três caíram** — 37%
de erro numa amostra que já parecia sólida.

Tratar a lista como fila de tarefas gera trabalho inventado. Ela é matéria-prima
para triagem, não backlog.

## Qual ferramenta usar

**`improve-codebase-architecture`, sozinho.** Não repetir o
`thermo-nuclear-code-quality-review`.

O motivo é que já rodou: a issue #20 **é a saída dele**. Rodar de novo produz outra
pilha de alegações não verificadas sobre o mesmo código, e o gargalo aqui nunca
foi gerar achados — foi separar os reais dos plausíveis.

`improve-codebase-architecture` é instrumento diferente: explora, escreve um
relatório HTML de candidatos a aprofundamento, e **para** para perguntar qual
explorar antes de propor interface. É o que a #20 precisa.

### Aponte para a #20, não deixe explorar do zero

O skill diz para pesar o histórico recente do git. O histórico recente agora é
**auditoria e tradução** — vai apontar para `Resources/*.lproj` e para os arquivos
que os fixes tocaram, que não é onde a arquitetura dói.

Dê a #20 como escopo explícito.

### Leia `docs/adr/0001` primeiro

Sete candidatos a aprofundamento foram propostos nesta auditoria. **Seis foram
refutados** por verificação adversarial, e o sétimo era uma deleção, não um
aprofundamento.

O motivo se repete nos seis: **o app não declara nenhum protocolo.**

```bash
grep -rE "^\s*(public|internal|private|fileprivate)? ?protocol " Odysseus/
```

Não devolve nada. `APIClient` é `final class` concreta, todo view model a recebe
por esse tipo concreto, e não existe segunda implementação de nada. Então cada
seam proposto teria exatamente um adapter — seam hipotético, indireção comprada
sem alavancagem.

A ADR existe para que a próxima revisão não re-proponha os mesmos seis. Se um
deles voltar, ele precisa derrubar o argumento da ADR, não ignorá-lo.

## Contexto que não está no código

- **`docs/ROUND2-ACHADOS.md`** — os achados com o que foi verificado e o que não foi.
- **`docs/HANDOFF-QUALITY-ROUND2.md`** — como a fase de qualidade foi conduzida.
- **`docs/ROUND2-RELATORIO.html`** — o relatório visual.
- **`docs/i18n-tibetano-revisao.md`** — o que a revisão do tibetano decidiu e o que não.
- **`docs/PATCH-SERVIDOR-STT-IDIOMA.md`** — patch de 3 linhas para o servidor honrar o
  idioma na transcrição. **Não é urgente:** o app usa o reconhecedor da Apple por
  padrão e o servidor nasce com `stt_provider: "disabled"` — os dois lados precisam
  ser ligados de propósito. Aplique só se ligar o Whisper no servidor.

## Armadilhas desta base

1. **A chave é o literal em pt-BR.** Reescrever o texto em Swift desativa a tradução
   em 43 idiomas, e nada falha. `OdysseusTests/EmailLoginGuideTests.swift` fixa isso
   para o guia de email; o resto ainda depende de varredura.
2. **`Text(x)` com `String` pula a busca.** Precisa ser
   `Text(LocalizedStringKey(x))`. Texto interpolado nunca vira chave — tem que ser
   `L("… %@", x)` na origem.
3. **`perl -CSD -pi -e` com padrão não-ASCII não substitui nada e sai com status 0.**
   Use `python3` com `assert t.count(old) == 1` antes do `replace`.
4. **`Closes #1, #2, #3` fecha só a primeira.** Uma linha `Closes #N` por issue.
5. **SwiftUI renderiza `Int` interpolado como `%lld`, não `%@`.** Varredura que
   assume `%@` dá falso positivo.
6. **`xcodegen generate`** depois de adicionar ou remover arquivo.
