# Imagens da App Store

Geradas a partir das telas de `docs/mockups/odysseus-iphone.html`.

| Pasta | Tamanho (px) | Slot no App Store Connect |
|---|---|---|
| `out/iphone-6.9` | 1320 × 2868 | iPhone 6,9" |
| `out/iphone-6.3` | 1206 × 2622 | iPhone com Dynamic Island (tela média) |
| `out/iphone-duo` | 1398 × 2034 | iPhone Duo |
| `out/ipad-13` | 2064 × 2752 | iPad 13" |
| `out/promo` | 2000 × 857 e 2000 × 1333 | imagens de divulgação |
| `out/sem-moldura/*` | os mesmos tamanhos | só as telas, sem moldura nem legenda (não é para enviar) |

As imagens de envio trazem a moldura do aparelho e uma legenda curta; as legendas ficam em `CAP`, em `shots.js`.

Para gerar de novo (precisa da SF Pro instalada, do pacote de fontes da Apple, e do Playwright com Chromium):

```bash
node docs/appstore/render.js
```

O Cookbook fica de fora das imagens de envio: os pacotes dele são motores de IA de terceiros pelo nome (llama.cpp, vLLM…).

Os modelos que aparecem são `mimo-v2.6-pro` e `mimo-v2.6-flash`. Nenhuma imagem pode citar serviço ou modelo de IA de terceiros (OpenAI, ChatGPT, GPT, Copilot, Whisper…): a ficha inteira segue essa regra.
