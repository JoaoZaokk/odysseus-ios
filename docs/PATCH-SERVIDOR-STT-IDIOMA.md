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
