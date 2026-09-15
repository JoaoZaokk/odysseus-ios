# Ícones de tela inicial (opcional, fora da 1.11 publicada)

O app traz 7 ícones de tela inicial e um seletor em **Ajustes › Aparência ›
Ícone**. Isto **não está em nenhum build publicado**: a 1.11 à venda é o build
27 do iOS, anterior a esta mudança. Está no repositório para ser ligado quando
você quiser — ou revertido em um commit.

## Como funciona

- `Odysseus/Features/Shared/AppIconManager.swift` — `AppIcon` (os 7) e o gerente
  que salva a escolha (`UserDefaults`, chave `odysseus.appicon`) e a aplica.
- A vela é o ícone **primário** (catálogo de assets, `AppIcon.appiconset`); os
  outros 6 são alternativos: arquivos soltos em `Odysseus/AltIcons/` **mais** uma
  entrada em `CFBundleAlternateIcons` (`project.yml`). Faltando qualquer metade,
  `setAlternateIconName` recusa e o ícone simplesmente não muda.
- A escolha **não segue o tema**: são 17 temas e 7 ícones, e amarrar deixaria
  Gemini, Hermes e Open WebUI inalcançáveis.
- Um update de app devolve o ícone primário; `AppIconManager.applySaved()` roda
  no `.task` de `RootView` e recoloca o escolhido. Comparar antes de aplicar é o
  que evita o alerta do sistema em todo lançamento.
- iOS só. macOS não tem ícone alternativo — `AltIcons` está excluído do target
  `Odysseus-macOS`.
- `OdysseusTests/AppIconTests.swift` cobre os dois lados (plist × arquivos) e o
  fallback de uma escolha salva que não existe mais.

## Acrescentar um ícone

1. PNG quadrado, sem canto arredondado (o sistema recorta), em três tamanhos:
   `AppIcon-<id>@2x.png` (120), `@3x.png` (180), `@2x~ipad.png` (152), em
   `Odysseus/AltIcons/`.
2. `case <id>` em `AppIcon` + rótulo em `label`.
3. Entrada em `project.yml`, dentro de `CFBundleIcons.CFBundleAlternateIcons`:
   ```yaml
            AppIcon-<id>:
              CFBundleIconFiles: ["AppIcon-<id>"]
   ```
4. `xcodegen generate` e rode os testes — `AppIconTests` reclama do que faltar.

## Instalar no iPhone (sem loja)

iPhone destravado e pareado.

```bash
cd ~/Projetos/Odysseus-iOS && xcodegen generate
UDID=$(xcrun devicectl list devices | grep physical | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}')
xcodebuild -project Odysseus.xcodeproj -scheme Odysseus -configuration Release \
  -destination "id=$UDID" -derivedDataPath /tmp/dd-device -allowProvisioningUpdates build
xcrun devicectl device install app --device "$UDID" \
  /tmp/dd-device/Build/Products/Release-iphoneos/Odysseus.app
```

O bundle id é o mesmo da loja (`com.zao.odysseus`), então este build **substitui**
o da App Store no aparelho. Para voltar, reinstale pela App Store.

## Se um dia for publicar

1. `CURRENT_PROJECT_VERSION: "28"` no target iOS (o 27 já está à venda).
2. **Traduzir**. `Ícone` e os rótulos só existem em português; sem entrada em
   `Odysseus/Resources/<lang>.lproj/Localizable.strings` os 42 outros idiomas
   mostram o literal em português — foi exatamente o tipo de coisa que derrubou
   a 1.6 na guideline 4.0.
3. Nada muda em privacidade, entitlements ou manifesto: ícone alternativo não
   coleta nada nem pede permissão.
4. O macOS continua fora; não precisa de build novo do Mac por causa disto.
