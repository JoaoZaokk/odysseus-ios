# Tibetano (`bo`) — o que foi contestado e o que ficou

Rodada de 2026-08-30. **Nenhuma string foi alterada.** Este documento existe para
que a próxima revisão não refaça o mesmo debate do zero.

## Estado

As 20 chaves novas em `bo.lproj` estão aplicadas e no ar. O tradutor original
marcou 13 delas como incertas — foi honesto onde não sabia, o que é razão para
confiar mais, não menos, mas não é razão para tratar como fechado.

Ninguém no circuito lê tibetano. Quatro modelos foram consultados; a maioria não
produziu saída utilizável. As alternativas propostas vinham com justificativa
convincente e **sem fonte**, que é exatamente o modo de falha contra o qual não
temos defesa aqui.

## O que a evidência externa sustentou

O [glossário tibetano do WordPress](https://translate.wordpress.org/locale/bo/default/glossary/)
— comunitário, não normativo — registra `Scheduled` = `དུས་བཀག་བྱས་ཟིན།`.

Isso importa por um motivo específico. Uma das objeções levantadas contra o texto
em produção era que `བྱས་ཟིན` marca **aspecto concluído**, e portanto não poderia
descrever algo agendado que ainda não rodou. O app usa:

```
"Agendado %@" = "གཏན་འབེབས་བྱས་ཟིན་ %@";
```

A raiz difere (`གཏན་འབེབས` contra `དུས་བཀག`), mas o `བྱས་ཟིན` é o mesmo — e está
num glossário de localização de software desde 2018. O argumento não se sustenta:
o **agendamento** pode estar concluído enquanto a **execução** segue futura.

Isso não certifica a frase inteira. Certifica que aquela objeção específica não é
motivo para mexer.

## O que continua sem base

- **`Semanal %@` = `བདུན་རེ་ %@`** — existe alternativa documentada (`གཟའ་འཁོར་རེ།`).
  Nenhuma das duas foi demonstrada superior; o glossário não torna a atual errada.
- **`Resposta inesperada do servidor: %@`** — há referência lexical alternativa
  para "unexpected" (`གློ་བུར་གྱི།`), nada que valide ou invalide a frase completa.
- **Linha da caixa de entrada** (`Toque em Criar…`) — sem evidência para a atual
  nem para a reformulação proposta.

## Alegações rejeitadas por falta de demonstração

- *"Shad `།` depois de `%@` quebra a formatação"* — um caractere literal depois do
  placeholder não corrompe o token. Adequação tipográfica é outra discussão, e
  nenhum caso de teste foi apresentado.
- *"Essa expressão é comum em logs"* — decompor os componentes de uma palavra não
  demonstra frequência de uso.

## Fontes que valem para a próxima rodada

Verificadas como existentes, não como autoridade sobre estas frases:
[Monlam](https://monlamit.com/software/1),
[dicionário de Christian Steinert](https://dictionary.christian-steinert.de/),
[THL Terms](https://thlib.org/terms/),
[Mozilla Pontoon em `bo`](https://pontoon.mozilla.org/bo/).

## Regra

Alternativa em tibetano só entra com **uso documentado**, não por maioria entre
modelos. Votação entre quatro modelos que não citam fonte é quatro palpites, não
quatro evidências.
