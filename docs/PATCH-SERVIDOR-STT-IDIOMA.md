# Patch do servidor — aceitar o idioma no `/api/stt/transcribe`

Aplicar em `odysseus` (o servidor), não no app iOS. Três linhas.

## O problema

`routes/stt_routes.py` liga só o arquivo:

```python
@router.post("/transcribe")
async def transcribe_audio(file: UploadFile = File(...)):
    ...
    text = stt_service.transcribe(audio_bytes)
```

E `services/stt/stt_service.py` tira o idioma do ajuste global `stt_language`,
que fica vazio por padrão:

```python
def transcribe(self, audio_bytes: bytes) -> Optional[str]:
    settings = self._load_settings()
    language = settings.get("stt_language", "")   # "" = Whisper adivinha
```

Vazio faz o faster-whisper detectar sozinho, e em áudio curto ou com ruído ele
erra — responde em português ou espanhol para quem falou inglês.

`stt_language` **não** está em `_PER_USER_KEYS` (`src/settings.py`), então é do
servidor inteiro. Fixar ali resolveria para um usuário e quebraria para os outros.
Por isso o idioma tem que vir no pedido.

## O patch

### 1 · `routes/stt_routes.py`

```diff
-from fastapi import APIRouter, HTTPException, UploadFile, File
+from fastapi import APIRouter, HTTPException, UploadFile, File, Form
```

```diff
     @router.post("/transcribe")
-    async def transcribe_audio(file: UploadFile = File(...)):
+    async def transcribe_audio(file: UploadFile = File(...),
+                               language: str = Form("")):
         """Transcribe uploaded audio file to text"""
         try:
```

```diff
             audio_bytes = await read_upload_limited(file, STT_MAX_AUDIO_BYTES, "Audio file")
             if not audio_bytes:
                 raise HTTPException(status_code=400, detail={"message": "Empty audio file"})

-            text = stt_service.transcribe(audio_bytes)
+            text = stt_service.transcribe(audio_bytes, language=language)
```

### 2 · `services/stt/stt_service.py`

```diff
-    def transcribe(self, audio_bytes: bytes) -> Optional[str]:
+    def transcribe(self, audio_bytes: bytes, language: str = "") -> Optional[str]:
         settings = self._load_settings()
         if settings.get("stt_enabled") is False:
             return None
         provider = settings["stt_provider"]
         model = settings["stt_model"]
-        language = settings.get("stt_language", "")
+        # O idioma do pedido vence o ajuste global: `stt_language` é do servidor
+        # inteiro (não está em `_PER_USER_KEYS`), então fixá-lo lá acertaria um
+        # usuário e erraria todos os outros. Vazio continua caindo no ajuste,
+        # que é o comportamento de antes.
+        language = language or settings.get("stt_language", "")
```

`_transcribe_local` e `_transcribe_api` já recebem `language` e já tratam string
vazia como "detectar" — não mudam.

### 3 · Normalizar e validar (defesa, não requisito)

O app iOS já manda só código base — `AppLanguage.sttServerCode` corta região e
script (`pt-BR` → `pt`, `zh-Hant` → `zh`) e devolve nil para uigur, que não existe
na tabela `LANGUAGES` do Whisper. Mas a rota é pública e outro cliente pode mandar
`en_US`, ` en-US ` ou lixo, e aí o faster-whisper levanta em vez de responder.

```python
_WHISPER_LANGS = None

def _normalize_language(value: str) -> str:
    """'en_US ' → 'en'. Devolve '' para vazio ou desconhecido, que é o mesmo
    que não pedir idioma nenhum — detectar erra menos que abortar."""
    code = (value or "").strip().replace("_", "-").split("-")[0].lower()
    if not code:
        return ""
    global _WHISPER_LANGS
    if _WHISPER_LANGS is None:
        # `faster_whisper`, não `openai-whisper` — é o que este servidor importa
        # em `_ensure_model`. A constante é privada (`_LANGUAGE_CODES`), então o
        # fallback importa: se ela sumir numa versão futura, o set fica vazio e a
        # validação passa a aceitar tudo, que é o comportamento de hoje. Melhor
        # que quebrar a transcrição por causa de um detalhe interno da lib.
        try:
            from faster_whisper.tokenizer import _LANGUAGE_CODES
            _WHISPER_LANGS = set(_LANGUAGE_CODES)
        except Exception:
            logger.warning("STT: lista de idiomas do faster-whisper indisponível, "
                           "seguindo sem validar")
            _WHISPER_LANGS = set()
    if _WHISPER_LANGS and code not in _WHISPER_LANGS:
        logger.warning("STT: idioma desconhecido %r, detectando", value)
        return ""
    return code
```

Chame em `transcribe()`, antes do `or`:

```diff
-        language = language or settings.get("stt_language", "")
+        language = _normalize_language(language) or settings.get("stt_language", "")
```

**Degradar para detecção, não devolver 400.** O usuário está falando ao microfone;
perder a gravação por um código mal formado é pior que transcrever adivinhando.

### 4 · Testes mínimos

- rota encaminha `language=en` ao serviço;
- campo ausente mantém o fallback para `stt_language`;
- idioma do pedido vence o ajuste global;
- `" en-US "` chega como `en` no provedor;
- código desconhecido (`ug`, `zz`) vira `""` e não levanta — `ug` é real, é o
  único dos 44 idiomas do app que o Whisper não conhece, e o app já manda nil
  para ele (`AppLanguage.sttServerCode`); o teste existe para o caso de outro
  cliente mandar mesmo assim;
- com `_LANGUAGE_CODES` indisponível, a normalização degrada para "aceita tudo"
  em vez de levantar no import;
- `_transcribe_local` e `_transcribe_api` recebem o valor já normalizado.

## Compatibilidade

- **App antigo, servidor novo:** não manda o campo, `Form("")` dá `""`, cai no
  ajuste global. Igual a hoje.
- **App novo, servidor antigo:** manda o campo, FastAPI ignora campo não ligado.
  Não quebra, só não adianta — é o estado até você aplicar isto.
- **Navegador:** não usa esta rota (`provider == "browser"` é resolvido no cliente).

## Como verificar

```bash
curl -s -b cookies.txt -F "file=@amostra.wav" -F "language=en" \
  https://SEU-SERVIDOR/api/stt/transcribe
```

E no log do servidor, a linha que já existe:

```
Local STT: 42 chars, lang=en, prob=0.99
```

`lang=` tem que ser o que você mandou. Se vier `pt` com áudio em inglês, o patch
não pegou.
