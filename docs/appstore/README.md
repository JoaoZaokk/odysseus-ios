# Imagens da App Store

Geradas a partir das telas de `docs/mockups/odysseus-iphone.html`, uma pasta por idioma da loja em `out/<locale>/` (a pasta não vai para o git: gere de novo ou use o pacote entregue).

| Pasta | Tamanho (px) | Slot no App Store Connect |
|---|---|---|
| `iphone-6.9` | 1320 × 2868 | iPhone 6,9" |
| `iphone-6.3` | 1206 × 2622 | iPhone com Dynamic Island (tela média) |
| `iphone-duo` | 1398 × 2034 | iPhone Duo (só pt-BR e en-US) |
| `ipad-13` | 2064 × 2752 | iPad 13" |
| `promo` | 2000 × 857 e 2000 × 1333 | imagens de divulgação |
| `pt-BR/sem-moldura` | os mesmos tamanhos | só as telas, sem moldura nem legenda (não é para enviar) |

Idiomas: pt-BR, en-US, es-ES, fr-FR, de-DE, it, nl-NL, ja, ko, zh-Hans, zh-Hant, ru.

## Gerar

Precisa da SF Pro instalada (pacote de fontes da Apple), de uma fonte CJK (Noto Sans CJK) e do Playwright com Chromium.

```bash
node docs/appstore/extract.js
```

```bash
node docs/appstore/render.js
```

`extract.js` lista todo texto das imagens em `i18n/source.json` (a chave é o texto em pt-BR). Cada idioma tem `i18n/<locale>.json` com `{ lang, strings }`; os textos de interface seguem o `Localizable.strings` do app, para a imagem bater com o app naquele idioma. As legendas ficam em `CAP`, em `shots.js`.

## Regras da ficha

- O Cookbook fica de fora: os pacotes dele são motores de IA de terceiros pelo nome (llama.cpp, vLLM…).
- Os modelos que aparecem são `mimo-v2.6-pro` e `mimo-v2.6-flash`.
- Nenhuma imagem cita serviço ou modelo de IA de terceiros (OpenAI, ChatGPT, GPT, Copilot, Whisper…): a ficha inteira segue essa regra.
