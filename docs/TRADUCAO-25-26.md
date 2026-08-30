# Pacote de tradução — 39 idiomas

Dois trabalhos independentes. Pode fazer os dois no mesmo lote ou separados.

**Regra que vale para tudo:** a chave é o literal em pt-BR, *ao pé da letra*.
Nunca reescreva a chave — só o valor à direita do `=`. Reescrever a chave
desativa a tradução nos outros 43 idiomas de uma vez.

## Os 39 idiomas que faltam

`de` `de-AT` `de-CH` `nl` `lb` `fr` `it` `sv` `fi` `ru` `uk` `be` `pl` `cs` `sk` `sl` `hr` `sr` `bg` `mk` `lv` `hu` `tr` `he` `hi` `bn` `ur` `ps` `fa` `id` `ms` `vi` `th` `ko` `zh-Hant` `zh-HK` `bo` `ug` `ar`

Já prontos e que **não** entram: `pt-BR` `en` `es` `ja` `zh-Hans`.

## Lotes sugeridos

Não peça os 39 numa resposta só — o modelo perde entradas e o tom vagueia no fim
da lista. Um lote por vez, e cada lote fecha em uma resposta:

- **A · Germânicas e românicas** (9): `de` `de-AT` `de-CH` `nl` `lb` `fr` `it` `sv` `fi`
- **B · Eslavas e bálticas** (12): `ru` `uk` `be` `pl` `cs` `sk` `sl` `hr` `sr` `bg` `mk` `lv`
- **C · Húngaro, turco, hebraico** (3): `hu` `tr` `he`
- **D · Índicas e iranianas** (5): `hi` `bn` `ur` `ps` `fa`
- **E · Sudeste asiático e CJK** (9): `id` `ms` `vi` `th` `ko` `zh-Hant` `zh-HK` `bo` `ug`
- **F · Árabe** (1): `ar`

## Formato de saída (peça exatamente isto)

Um bloco por idioma, no formato `.strings` da Apple, pronto para colar:

```
/* === de === */
"chave em pt-BR" = "tradução";
"outra chave" = "tradução";
```

Sem comentários extras, sem markdown dentro do bloco, sem reordenar as chaves.
Assim dá pra conferir mecanicamente que nenhuma sumiu.

---

# Trabalho 1 — 12 chaves novas (issue #26)

Curto. Doze strings, 39 idiomas.

## Regras dos placeholders

- `%d`, `%lld`, `%@` **têm que sobreviver**, na mesma quantidade.
- Se o idioma pede outra ordem de palavras, use forma posicional: `%1$@`, `%2$@`.
  Só a `"Falha ao instalar %@: %@"` tem dois, então é a única onde isso importa.
- `%lld` é inteiro, `%d` é inteiro, `%@` é texto. Não troque um pelo outro.
- Idiomas com plural que muda a palavra (ru, pl, cs, ar, he…): use a forma
  genérica que sirva para qualquer número — não estamos usando `.stringsdict`.
  Para `"%lld linhas"`, se não houver forma neutra decente, prefira a do plural.

## As chaves

| Chave | O que é | Exemplo renderizado |
|---|---|---|
| `"Erro %d"` | Erro genérico quando o servidor não manda detalhe. `%d` é o código HTTP (500, 502…). | `Erro 502` |
| `"Resposta inesperada do servidor: %@"` | Resposta malformada. `%@` é o detalhe técnico do decoder, em inglês. | `Resposta inesperada do servidor: keyNotFound(...)` |
| `"%lld linhas"` | Menu de quantidade de linhas do log. `%lld` é um número inteiro. | `100 linhas` |
| `"cabe"` | Coluna de capacidade do ComfyUI: o modelo cabe na VRAM da GPU. Minúscula, é um rótulo curto ao lado do nome do modelo. | `cabe` |
| `"apertado"` | Mesma coluna: cabe, mas no limite. | `apertado` |
| `"Evento: %@"` | Linha de agendamento de uma tarefa disparada por evento. `%@` é o nome do evento. | `Evento: nova_mensagem` |
| `"Cron: %@"` | Tarefa com expressão cron. `%@` é a expressão, não traduzir. | `Cron: 0 9 * * 1` |
| `"Uma vez %@"` | Tarefa que roda uma única vez. `%@` é data/hora. | `Uma vez 2026-09-01 09:00` |
| `"Diário %@"` | Tarefa diária. `%@` é a hora. | `Diário 09:00` |
| `"Semanal %@"` | Tarefa semanal. `%@` é dia e hora. | `Semanal seg 09:00` |
| `"Agendado %@"` | Fallback para qualquer outro agendamento. `%@` é data/hora. | `Agendado 09:00` |
| `"Falha ao instalar %@: %@"` | Erro do Cookbook. Primeiro `%@` é o nome do pacote, segundo é a mensagem do servidor. | `Falha ao instalar diffusers: timeout` |

## Glossário — como o app já traduz os termos vizinhos

Case com isto. São valores reais dos catálogos, não sugestão:


**A · Germânicas e românicas**

- `de` — Cancelar→Abbrechen, Conta→Konto, Email→E-Mail, Falha→Fehlgeschlagen, Idioma→Sprache, Instalar→Installieren, Modelos→Modelle, Nenhum→Keiner, Porta→Port, Salvar→Speichern, Salvo→Gespeichert, Senha→Passwort, Servidor→Server, Todos→Alle, Usuário→Benutzername
- `de-AT` — Cancelar→Abbrechen, Conta→Konto, Email→E-Mail, Falha→Fehlgeschlagen, Idioma→Sprache, Instalar→Installieren, Modelos→Modelle, Nenhum→Keiner, Porta→Port, Salvar→Speichern, Salvo→Gespeichert, Senha→Passwort, Servidor→Server, Todos→Alle, Usuário→Benutzername
- `de-CH` — Cancelar→Abbrechen, Conta→Konto, Email→E-Mail, Falha→Fehlgeschlagen, Idioma→Sprache, Instalar→Installieren, Modelos→Modelle, Nenhum→Keiner, Porta→Port, Salvar→Speichern, Salvo→Gespeichert, Senha→Passwort, Servidor→Server, Todos→Alle, Usuário→Benutzername
- `nl` — Cancelar→Annuleren, Conta→Account, Email→E-mail, Falha→Mislukt, Idioma→Taal, Instalar→Installeren, Modelos→Modellen, Nenhum→Geen, Porta→Poort, Salvar→Opslaan, Salvo→Opgeslagen, Senha→Wachtwoord, Servidor→Server, Todos→Alle, Usuário→Gebruikersnaam
- `lb` — Cancelar→Ofbriechen, Conta→Konto, Email→E-Mail, Falha→Feelgeschloen, Idioma→Sprooch, Instalar→Installéieren, Modelos→Modeller, Nenhum→Keen, Porta→Port, Salvar→Späicheren, Salvo→Gespäichert, Senha→Passwuert, Servidor→Server, Todos→All, Usuário→Benotzernumm
- `fr` — Cancelar→Annuler, Conta→Compte, Email→E-mail, Falha→Échec, Idioma→Langue, Instalar→Installer, Modelos→Modèles, Nenhum→Aucun, Porta→Port, Salvar→Enregistrer, Salvo→Enregistré, Senha→Mot de passe, Servidor→Serveur, Todos→Tous, Usuário→Nom d'utilisateur
- `it` — Cancelar→Annulla, Conta→Account, Email→Email, Falha→Fallito, Idioma→Lingua, Instalar→Installa, Modelos→Modelli, Nenhum→Nessuno, Porta→Porta, Salvar→Salva, Salvo→Salvato, Senha→Password, Servidor→Server, Todos→Tutti, Usuário→Nome utente
- `sv` — Cancelar→Avbryt, Conta→Konto, Email→E-post, Falha→Misslyckades, Idioma→Språk, Instalar→Installera, Modelos→Modeller, Nenhum→Ingen, Porta→Port, Salvar→Spara, Salvo→Sparad, Senha→Lösenord, Servidor→Server, Todos→Alla, Usuário→Användarnamn
- `fi` — Cancelar→Peruuta, Conta→Tili, Email→Sähköposti, Falha→Epäonnistui, Idioma→Kieli, Instalar→Asenna, Modelos→Mallit, Nenhum→Ei mitään, Porta→Portti, Salvar→Tallenna, Salvo→Tallennettu, Senha→Salasana, Servidor→Palvelin, Todos→Kaikki, Usuário→Käyttäjätunnus

**B · Eslavas e bálticas**

- `ru` — Cancelar→Отмена, Conta→Аккаунт, Email→Email, Falha→Ошибка, Idioma→Язык, Instalar→Установить, Modelos→Модели, Nenhum→Нет, Porta→Порт, Salvar→Сохранить, Salvo→Сохранено, Senha→Пароль, Servidor→Сервер, Todos→Все, Usuário→Пользователь
- `uk` — Cancelar→Скасувати, Conta→Акаунт, Email→Email, Falha→Помилка, Idioma→Мова, Instalar→Встановити, Modelos→Моделі, Nenhum→Немає, Porta→Порт, Salvar→Зберегти, Salvo→Збережено, Senha→Пароль, Servidor→Сервер, Todos→Всі, Usuário→Користувач
- `be` — Cancelar→Адмяніць, Conta→Акаўнт, Email→Email, Falha→Памылка, Idioma→Мова, Instalar→Усталяваць, Modelos→Мадэлі, Nenhum→Няма, Porta→Порт, Salvar→Захаваць, Salvo→Захавана, Senha→Пароль, Servidor→Сервер, Todos→Усе, Usuário→Карыстальнік
- `pl` — Cancelar→Anuluj, Conta→Konto, Email→E-mail, Falha→Niepowodzenie, Idioma→Język, Instalar→Zainstaluj, Modelos→Modele, Nenhum→Brak, Porta→Port, Salvar→Zapisz, Salvo→Zapisano, Senha→Hasło, Servidor→Serwer, Todos→Wszystkie, Usuário→Nazwa użytkownika
- `cs` — Cancelar→Zrušit, Conta→Účet, Email→E-mail, Falha→Selhání, Idioma→Jazyk, Instalar→Nainstalovat, Modelos→Modely, Nenhum→Žádné, Porta→Port, Salvar→Uložit, Salvo→Uloženo, Senha→Heslo, Servidor→Server, Todos→Vše, Usuário→Uživatelské jméno
- `sk` — Cancelar→Zrušiť, Conta→Účet, Email→E-mail, Falha→Zlyhanie, Idioma→Jazyk, Instalar→Inštalovať, Modelos→Modely, Nenhum→Žiadne, Porta→Port, Salvar→Uložiť, Salvo→Uložené, Senha→Heslo, Servidor→Server, Todos→Všetky, Usuário→Používateľské meno
- `sl` — Cancelar→Prekliči, Conta→Račun, Email→E-pošta, Falha→Neuspeh, Idioma→Jezik, Instalar→Namesti, Modelos→Modeli, Nenhum→Brez, Porta→Vrata, Salvar→Shrani, Salvo→Shranjeno, Senha→Geslo, Servidor→Strežnik, Todos→Vse, Usuário→Uporabniško ime
- `hr` — Cancelar→Odustani, Conta→Račun, Email→E-pošta, Falha→Neuspjeh, Idioma→Jezik, Instalar→Instaliraj, Modelos→Modeli, Nenhum→Bez, Porta→Vrata, Salvar→Spremi, Salvo→Spremljeno, Senha→Lozinka, Servidor→Poslužitelj, Todos→Sve, Usuário→Korisničko ime
- `sr` — Cancelar→Откажи, Conta→Налог, Email→Email, Falha→Грешка, Idioma→Језик, Instalar→Инсталирај, Modelos→Модели, Nenhum→Нема, Porta→Порт, Salvar→Сачувај, Salvo→Сачувано, Senha→Лозинка, Servidor→Сервер, Todos→Сви, Usuário→Корисник
- `bg` — Cancelar→Отказ, Conta→Акаунт, Email→Email, Falha→Грешка, Idioma→Език, Instalar→Инсталирай, Modelos→Модели, Nenhum→Няма, Porta→Порт, Salvar→Запази, Salvo→Запазено, Senha→Парола, Servidor→Сървър, Todos→Всички, Usuário→Потребител
- `mk` — Cancelar→Откажи, Conta→Сметка, Email→Email, Falha→Грешка, Idioma→Јазик, Instalar→Инсталирај, Modelos→Модели, Nenhum→Нема, Porta→Порт, Salvar→Зачувај, Salvo→Зачувано, Senha→Лозинка, Servidor→Сервер, Todos→Сите, Usuário→Корисник
- `lv` — Cancelar→Atcelt, Conta→Konts, Email→E-pasts, Falha→Neizdevās, Idioma→Valoda, Instalar→Instalēt, Modelos→Modeļi, Nenhum→Nav, Porta→Ports, Salvar→Saglabāt, Salvo→Saglabāts, Senha→Parole, Servidor→Serveris, Todos→Visi, Usuário→Lietotājvārds

**C · Húngaro, turco, hebraico**

- `hu` — Cancelar→Mégse, Conta→Fiók, Email→E-mail, Falha→Sikertelen, Idioma→Nyelv, Instalar→Telepítés, Modelos→Modellek, Nenhum→Nincs, Porta→Port, Salvar→Mentés, Salvo→Mentve, Senha→Jelszó, Servidor→Szerver, Todos→Összes, Usuário→Felhasználónév
- `tr` — Cancelar→İptal, Conta→Hesap, Email→E-posta, Falha→Başarısız, Idioma→Dil, Instalar→Kur, Modelos→Modeller, Nenhum→Yok, Porta→Port, Salvar→Kaydet, Salvo→Kaydedildi, Senha→Parola, Servidor→Sunucu, Todos→Tümü, Usuário→Kullanıcı adı
- `he` — Cancelar→ביטול, Conta→חשבון, Email→אימייל, Falha→נכשל, Idioma→שפה, Instalar→התקנה, Modelos→מודלים, Nenhum→ללא, Porta→פורט, Salvar→שמירה, Salvo→נשמר, Senha→סיסמה, Servidor→שרת, Todos→הכול, Usuário→שם משתמש

**D · Índicas e iranianas**

- `hi` — Cancelar→रद्द करें, Conta→खाता, Email→ईमेल, Falha→विफल, Idioma→भाषा, Instalar→इंस्टॉल करें, Modelos→मॉडल, Nenhum→कोई नहीं, Porta→पोर्ट, Salvar→सेव करें, Salvo→सेव हो गया, Senha→पासवर्ड, Servidor→सर्वर, Todos→सभी, Usuário→यूज़रनेम
- `bn` — Cancelar→বাতিল, Conta→অ্যাকাউন্ট, Email→ইমেল, Falha→ব্যর্থ, Idioma→ভাষা, Instalar→ইনস্টল করুন, Modelos→মডেল, Nenhum→কোনোটিই নয়, Porta→পোর্ট, Salvar→সেভ করুন, Salvo→সেভ হয়েছে, Senha→পাসওয়ার্ড, Servidor→সার্ভার, Todos→সব, Usuário→ইউজারনেম
- `ur` — Cancelar→منسوخ کریں, Conta→اکاؤنٹ, Email→ای میل, Falha→ناکام, Idioma→زبان, Instalar→نصب کریں, Modelos→ماڈلز, Nenhum→کوئی نہیں, Porta→پورٹ, Salvar→محفوظ کریں, Salvo→محفوظ ہو گیا, Senha→پاس ورڈ, Servidor→سرور, Todos→سب, Usuário→صارف
- `ps` — Cancelar→لغوه کول, Conta→حساب, Email→بریښنالیک, Falha→ناکام, Idioma→ژبه, Instalar→نصبول, Modelos→ماډلونه, Nenhum→هیڅ, Porta→پورټ, Salvar→خوندي کول, Salvo→خوندي شو, Senha→پاسورډ, Servidor→سرور, Todos→ټول, Usuário→کارونکی
- `fa` — Cancelar→لغو, Conta→حساب, Email→ایمیل, Falha→ناموفق, Idioma→زبان, Instalar→نصب, Modelos→مدل‌ها, Nenhum→هیچ‌کدام, Porta→پورت, Salvar→ذخیره, Salvo→ذخیره شد, Senha→رمز عبور, Servidor→سرور, Todos→همه, Usuário→کاربر

**E · Sudeste asiático e CJK**

- `id` — Cancelar→Batal, Conta→Akun, Email→Email, Falha→Gagal, Idioma→Bahasa, Instalar→Instal, Modelos→Model, Nenhum→Tidak ada, Porta→Port, Salvar→Simpan, Salvo→Tersimpan, Senha→Kata sandi, Servidor→Server, Todos→Semua, Usuário→Nama pengguna
- `ms` — Cancelar→Batal, Conta→Akaun, Email→E-mel, Falha→Gagal, Idioma→Bahasa, Instalar→Pasang, Modelos→Model, Nenhum→Tiada, Porta→Port, Salvar→Simpan, Salvo→Disimpan, Senha→Kata laluan, Servidor→Pelayan, Todos→Semua, Usuário→Nama pengguna
- `vi` — Cancelar→Hủy, Conta→Tài khoản, Email→Email, Falha→Thất bại, Idioma→Ngôn ngữ, Instalar→Cài đặt, Modelos→Mô hình, Nenhum→Không, Porta→Cổng, Salvar→Lưu, Salvo→Đã lưu, Senha→Mật khẩu, Servidor→Máy chủ, Todos→Tất cả, Usuário→Tên người dùng
- `th` — Cancelar→ยกเลิก, Conta→บัญชี, Email→อีเมล, Falha→ล้มเหลว, Idioma→ภาษา, Instalar→ติดตั้ง, Modelos→โมเดล, Nenhum→ไม่มี, Porta→พอร์ต, Salvar→บันทึก, Salvo→บันทึกแล้ว, Senha→รหัสผ่าน, Servidor→เซิร์ฟเวอร์, Todos→ทั้งหมด, Usuário→ชื่อผู้ใช้
- `ko` — Cancelar→취소, Conta→계정, Email→이메일, Falha→실패, Idioma→언어, Instalar→설치, Modelos→모델, Nenhum→없음, Porta→포트, Salvar→저장, Salvo→저장됨, Senha→비밀번호, Servidor→서버, Todos→전체, Usuário→사용자 이름
- `zh-Hant` — Cancelar→取消, Conta→帳戶, Email→郵件, Falha→失敗, Idioma→語言, Instalar→安裝, Modelos→模型, Nenhum→無, Porta→連接埠, Salvar→儲存, Salvo→已儲存, Senha→密碼, Servidor→伺服器, Todos→全部, Usuário→使用者名稱
- `zh-HK` — Cancelar→取消, Conta→帳戶, Email→郵件, Falha→失敗, Idioma→語言, Instalar→安裝, Modelos→模型, Nenhum→無, Porta→連接埠, Salvar→儲存, Salvo→已儲存, Senha→密碼, Servidor→伺服器, Todos→全部, Usuário→使用者名稱
- `bo` — Cancelar→ཕྱིར་འཐེན, Conta→རྩིས་ཐོ, Email→གློག་འཕྲིན, Falha→འཐུས་ཤོར, Idioma→སྐད་ཡིག, Instalar→སྒྲིག་སྦྱོར, Modelos→དཔེ་དབྱིབས, Nenhum→གང་ཡང་མེད, Porta→འབྲེལ་སྒོ, Salvar→ཉར་ཚགས, Salvo→ཉར་ཚགས་ཟིན, Senha→གསང་ཨང, Servidor→ཞབས་ཞུའི་འཕྲུལ་ཆས, Todos→ཚང་མ, Usuário→སྤྱོད་མཁན་མིང
- `ug` — Cancelar→ۋاز كېچىش, Conta→ھېسابات, Email→ئېلخەت, Falha→مەغلۇپ بولدى, Idioma→تىل, Instalar→ئورنىتىش, Modelos→مودېل, Nenhum→يوق, Porta→پورت, Salvar→ساقلاش, Salvo→ساقلاندى, Senha→پارول, Servidor→مۇلازىمېتىر, Todos→ھەممىسى, Usuário→ئىشلەتكۈچى

**F · Árabe**

- `ar` — Cancelar→إلغاء, Conta→الحساب, Email→البريد الإلكتروني, Falha→فشل, Idioma→اللغة, Instalar→تثبيت, Modelos→النماذج, Nenhum→لا شيء, Porta→المنفذ, Salvar→حفظ, Salvo→تم الحفظ, Senha→كلمة المرور, Servidor→الخادم, Todos→الكل, Usuário→المستخدم

---

# Trabalho 2 — guia de login de email (issue #25)

Oito strings, 39 idiomas. Mais longo e mais delicado que o Trabalho 1: é um
tutorial, então tom e naturalidade importam mais que literalidade.

**Contexto:** tela de ajuda "Como conectar seu email", aberta pelo "?" na tela de
Email. Explica que provedores com 2FA exigem senha de aplicativo.

## Fonte em pt-BR (as chaves)

```
"Como conectar seu email"
"Provedores com verificação em duas etapas (iCloud, Gmail, Outlook) exigem uma senha de app — não a senha normal da sua conta."
"Gere uma senha de app no site do provedor. iCloud: account.apple.com → Iniciar Sessão e Segurança → Senhas de App → +."
"No Odysseus, abra Email → ícone de contas → toque em +."
"Preencha: Nome, seu email, servidor IMAP e porta, usuário (seu email) e a senha de app."
"Toque em Salvar. A caixa carrega em alguns segundos."
"Servidores comuns"
"Se aparecer “timed out”, a senha provavelmente está errada — gere uma nova senha de app."
```

## Traduções que já existem — use como referência de tom

Estas cinco já estão escritas e aprovadas. Não as retraduza; use-as para calibrar
registro e vocabulário. O `en` em particular é o melhor pivô para os idiomas onde
o pt-BR for ambíguo.

### en
```
"Connect your email"
"Providers with two-factor auth (iCloud, Gmail, Outlook) require an app-specific password — not your normal account password."
"Generate an app password on your provider’s site. iCloud: account.apple.com → Sign-In & Security → App-Specific Passwords → +."
"In Odysseus, open Email → the accounts icon → tap +."
"Fill in: Name, your email, IMAP server and port, username (your email), and the app password."
"Tap Save. The inbox loads in a few seconds."
"Common servers"
"If it times out, the password is usually wrong — generate a fresh app password."
```

### es
```
"Conecta tu correo"
"Los proveedores con verificación en dos pasos (iCloud, Gmail, Outlook) requieren una contraseña de aplicación — no la contraseña normal de tu cuenta."
"Genera una contraseña de aplicación en el sitio de tu proveedor. iCloud: account.apple.com → Inicio de sesión y seguridad → Contraseñas específicas → +."
"En Odysseus, abre Email → el icono de cuentas → toca +."
"Rellena: Nombre, tu correo, servidor IMAP y puerto, usuario (tu correo) y la contraseña de aplicación."
"Toca Guardar. La bandeja carga en unos segundos."
"Servidores comunes"
"Si da “timed out”, la contraseña suele estar mal — genera una nueva contraseña de aplicación."
```

(`ja` e `zh-Hans` também existem no arquivo `EmailLoginHelpView.swift`, se quiser
passar como referência para os idiomas do lote E.)

## Regras específicas deste tutorial

- **Não traduzir:** `Odysseus`, `iCloud`, `Gmail`, `Outlook`, `IMAP`, `SMTP`,
  `account.apple.com`, e o `“timed out”` entre aspas — é a mensagem literal que o
  usuário vê na tela, em inglês.
- **Traduzir:** os nomes de menu da Apple (`Iniciar Sessão e Segurança`,
  `Senhas de App`) devem usar a redação oficial da Apple naquele idioma. Se o
  modelo não tiver certeza, peça para ele marcar com `<!-- checar -->` em vez de
  chutar.
- **Manter as setas `→` e o `+`** como estão.
- **"senha de app"** é o termo central — escolha um e repita nas quatro
  ocorrências. Inconsistência aqui é o erro mais provável.
- As aspas curvas `“ ”` devem virar as aspas próprias do idioma (`« »` em fr,
  `„ “` em de, 「 」 em ja/zh).

## Glossário por idioma


**A · Germânicas e românicas**

- `de` — Cancelar→Abbrechen, Conta→Konto, Email→E-Mail, Falha→Fehlgeschlagen, Idioma→Sprache, Instalar→Installieren, Modelos→Modelle, Nenhum→Keiner, Porta→Port, Salvar→Speichern, Salvo→Gespeichert, Senha→Passwort, Servidor→Server, Todos→Alle, Usuário→Benutzername
- `de-AT` — Cancelar→Abbrechen, Conta→Konto, Email→E-Mail, Falha→Fehlgeschlagen, Idioma→Sprache, Instalar→Installieren, Modelos→Modelle, Nenhum→Keiner, Porta→Port, Salvar→Speichern, Salvo→Gespeichert, Senha→Passwort, Servidor→Server, Todos→Alle, Usuário→Benutzername
- `de-CH` — Cancelar→Abbrechen, Conta→Konto, Email→E-Mail, Falha→Fehlgeschlagen, Idioma→Sprache, Instalar→Installieren, Modelos→Modelle, Nenhum→Keiner, Porta→Port, Salvar→Speichern, Salvo→Gespeichert, Senha→Passwort, Servidor→Server, Todos→Alle, Usuário→Benutzername
- `nl` — Cancelar→Annuleren, Conta→Account, Email→E-mail, Falha→Mislukt, Idioma→Taal, Instalar→Installeren, Modelos→Modellen, Nenhum→Geen, Porta→Poort, Salvar→Opslaan, Salvo→Opgeslagen, Senha→Wachtwoord, Servidor→Server, Todos→Alle, Usuário→Gebruikersnaam
- `lb` — Cancelar→Ofbriechen, Conta→Konto, Email→E-Mail, Falha→Feelgeschloen, Idioma→Sprooch, Instalar→Installéieren, Modelos→Modeller, Nenhum→Keen, Porta→Port, Salvar→Späicheren, Salvo→Gespäichert, Senha→Passwuert, Servidor→Server, Todos→All, Usuário→Benotzernumm
- `fr` — Cancelar→Annuler, Conta→Compte, Email→E-mail, Falha→Échec, Idioma→Langue, Instalar→Installer, Modelos→Modèles, Nenhum→Aucun, Porta→Port, Salvar→Enregistrer, Salvo→Enregistré, Senha→Mot de passe, Servidor→Serveur, Todos→Tous, Usuário→Nom d'utilisateur
- `it` — Cancelar→Annulla, Conta→Account, Email→Email, Falha→Fallito, Idioma→Lingua, Instalar→Installa, Modelos→Modelli, Nenhum→Nessuno, Porta→Porta, Salvar→Salva, Salvo→Salvato, Senha→Password, Servidor→Server, Todos→Tutti, Usuário→Nome utente
- `sv` — Cancelar→Avbryt, Conta→Konto, Email→E-post, Falha→Misslyckades, Idioma→Språk, Instalar→Installera, Modelos→Modeller, Nenhum→Ingen, Porta→Port, Salvar→Spara, Salvo→Sparad, Senha→Lösenord, Servidor→Server, Todos→Alla, Usuário→Användarnamn
- `fi` — Cancelar→Peruuta, Conta→Tili, Email→Sähköposti, Falha→Epäonnistui, Idioma→Kieli, Instalar→Asenna, Modelos→Mallit, Nenhum→Ei mitään, Porta→Portti, Salvar→Tallenna, Salvo→Tallennettu, Senha→Salasana, Servidor→Palvelin, Todos→Kaikki, Usuário→Käyttäjätunnus

**B · Eslavas e bálticas**

- `ru` — Cancelar→Отмена, Conta→Аккаунт, Email→Email, Falha→Ошибка, Idioma→Язык, Instalar→Установить, Modelos→Модели, Nenhum→Нет, Porta→Порт, Salvar→Сохранить, Salvo→Сохранено, Senha→Пароль, Servidor→Сервер, Todos→Все, Usuário→Пользователь
- `uk` — Cancelar→Скасувати, Conta→Акаунт, Email→Email, Falha→Помилка, Idioma→Мова, Instalar→Встановити, Modelos→Моделі, Nenhum→Немає, Porta→Порт, Salvar→Зберегти, Salvo→Збережено, Senha→Пароль, Servidor→Сервер, Todos→Всі, Usuário→Користувач
- `be` — Cancelar→Адмяніць, Conta→Акаўнт, Email→Email, Falha→Памылка, Idioma→Мова, Instalar→Усталяваць, Modelos→Мадэлі, Nenhum→Няма, Porta→Порт, Salvar→Захаваць, Salvo→Захавана, Senha→Пароль, Servidor→Сервер, Todos→Усе, Usuário→Карыстальнік
- `pl` — Cancelar→Anuluj, Conta→Konto, Email→E-mail, Falha→Niepowodzenie, Idioma→Język, Instalar→Zainstaluj, Modelos→Modele, Nenhum→Brak, Porta→Port, Salvar→Zapisz, Salvo→Zapisano, Senha→Hasło, Servidor→Serwer, Todos→Wszystkie, Usuário→Nazwa użytkownika
- `cs` — Cancelar→Zrušit, Conta→Účet, Email→E-mail, Falha→Selhání, Idioma→Jazyk, Instalar→Nainstalovat, Modelos→Modely, Nenhum→Žádné, Porta→Port, Salvar→Uložit, Salvo→Uloženo, Senha→Heslo, Servidor→Server, Todos→Vše, Usuário→Uživatelské jméno
- `sk` — Cancelar→Zrušiť, Conta→Účet, Email→E-mail, Falha→Zlyhanie, Idioma→Jazyk, Instalar→Inštalovať, Modelos→Modely, Nenhum→Žiadne, Porta→Port, Salvar→Uložiť, Salvo→Uložené, Senha→Heslo, Servidor→Server, Todos→Všetky, Usuário→Používateľské meno
- `sl` — Cancelar→Prekliči, Conta→Račun, Email→E-pošta, Falha→Neuspeh, Idioma→Jezik, Instalar→Namesti, Modelos→Modeli, Nenhum→Brez, Porta→Vrata, Salvar→Shrani, Salvo→Shranjeno, Senha→Geslo, Servidor→Strežnik, Todos→Vse, Usuário→Uporabniško ime
- `hr` — Cancelar→Odustani, Conta→Račun, Email→E-pošta, Falha→Neuspjeh, Idioma→Jezik, Instalar→Instaliraj, Modelos→Modeli, Nenhum→Bez, Porta→Vrata, Salvar→Spremi, Salvo→Spremljeno, Senha→Lozinka, Servidor→Poslužitelj, Todos→Sve, Usuário→Korisničko ime
- `sr` — Cancelar→Откажи, Conta→Налог, Email→Email, Falha→Грешка, Idioma→Језик, Instalar→Инсталирај, Modelos→Модели, Nenhum→Нема, Porta→Порт, Salvar→Сачувај, Salvo→Сачувано, Senha→Лозинка, Servidor→Сервер, Todos→Сви, Usuário→Корисник
- `bg` — Cancelar→Отказ, Conta→Акаунт, Email→Email, Falha→Грешка, Idioma→Език, Instalar→Инсталирай, Modelos→Модели, Nenhum→Няма, Porta→Порт, Salvar→Запази, Salvo→Запазено, Senha→Парола, Servidor→Сървър, Todos→Всички, Usuário→Потребител
- `mk` — Cancelar→Откажи, Conta→Сметка, Email→Email, Falha→Грешка, Idioma→Јазик, Instalar→Инсталирај, Modelos→Модели, Nenhum→Нема, Porta→Порт, Salvar→Зачувај, Salvo→Зачувано, Senha→Лозинка, Servidor→Сервер, Todos→Сите, Usuário→Корисник
- `lv` — Cancelar→Atcelt, Conta→Konts, Email→E-pasts, Falha→Neizdevās, Idioma→Valoda, Instalar→Instalēt, Modelos→Modeļi, Nenhum→Nav, Porta→Ports, Salvar→Saglabāt, Salvo→Saglabāts, Senha→Parole, Servidor→Serveris, Todos→Visi, Usuário→Lietotājvārds

**C · Húngaro, turco, hebraico**

- `hu` — Cancelar→Mégse, Conta→Fiók, Email→E-mail, Falha→Sikertelen, Idioma→Nyelv, Instalar→Telepítés, Modelos→Modellek, Nenhum→Nincs, Porta→Port, Salvar→Mentés, Salvo→Mentve, Senha→Jelszó, Servidor→Szerver, Todos→Összes, Usuário→Felhasználónév
- `tr` — Cancelar→İptal, Conta→Hesap, Email→E-posta, Falha→Başarısız, Idioma→Dil, Instalar→Kur, Modelos→Modeller, Nenhum→Yok, Porta→Port, Salvar→Kaydet, Salvo→Kaydedildi, Senha→Parola, Servidor→Sunucu, Todos→Tümü, Usuário→Kullanıcı adı
- `he` — Cancelar→ביטול, Conta→חשבון, Email→אימייל, Falha→נכשל, Idioma→שפה, Instalar→התקנה, Modelos→מודלים, Nenhum→ללא, Porta→פורט, Salvar→שמירה, Salvo→נשמר, Senha→סיסמה, Servidor→שרת, Todos→הכול, Usuário→שם משתמש

**D · Índicas e iranianas**

- `hi` — Cancelar→रद्द करें, Conta→खाता, Email→ईमेल, Falha→विफल, Idioma→भाषा, Instalar→इंस्टॉल करें, Modelos→मॉडल, Nenhum→कोई नहीं, Porta→पोर्ट, Salvar→सेव करें, Salvo→सेव हो गया, Senha→पासवर्ड, Servidor→सर्वर, Todos→सभी, Usuário→यूज़रनेम
- `bn` — Cancelar→বাতিল, Conta→অ্যাকাউন্ট, Email→ইমেল, Falha→ব্যর্থ, Idioma→ভাষা, Instalar→ইনস্টল করুন, Modelos→মডেল, Nenhum→কোনোটিই নয়, Porta→পোর্ট, Salvar→সেভ করুন, Salvo→সেভ হয়েছে, Senha→পাসওয়ার্ড, Servidor→সার্ভার, Todos→সব, Usuário→ইউজারনেম
- `ur` — Cancelar→منسوخ کریں, Conta→اکاؤنٹ, Email→ای میل, Falha→ناکام, Idioma→زبان, Instalar→نصب کریں, Modelos→ماڈلز, Nenhum→کوئی نہیں, Porta→پورٹ, Salvar→محفوظ کریں, Salvo→محفوظ ہو گیا, Senha→پاس ورڈ, Servidor→سرور, Todos→سب, Usuário→صارف
- `ps` — Cancelar→لغوه کول, Conta→حساب, Email→بریښنالیک, Falha→ناکام, Idioma→ژبه, Instalar→نصبول, Modelos→ماډلونه, Nenhum→هیڅ, Porta→پورټ, Salvar→خوندي کول, Salvo→خوندي شو, Senha→پاسورډ, Servidor→سرور, Todos→ټول, Usuário→کارونکی
- `fa` — Cancelar→لغو, Conta→حساب, Email→ایمیل, Falha→ناموفق, Idioma→زبان, Instalar→نصب, Modelos→مدل‌ها, Nenhum→هیچ‌کدام, Porta→پورت, Salvar→ذخیره, Salvo→ذخیره شد, Senha→رمز عبور, Servidor→سرور, Todos→همه, Usuário→کاربر

**E · Sudeste asiático e CJK**

- `id` — Cancelar→Batal, Conta→Akun, Email→Email, Falha→Gagal, Idioma→Bahasa, Instalar→Instal, Modelos→Model, Nenhum→Tidak ada, Porta→Port, Salvar→Simpan, Salvo→Tersimpan, Senha→Kata sandi, Servidor→Server, Todos→Semua, Usuário→Nama pengguna
- `ms` — Cancelar→Batal, Conta→Akaun, Email→E-mel, Falha→Gagal, Idioma→Bahasa, Instalar→Pasang, Modelos→Model, Nenhum→Tiada, Porta→Port, Salvar→Simpan, Salvo→Disimpan, Senha→Kata laluan, Servidor→Pelayan, Todos→Semua, Usuário→Nama pengguna
- `vi` — Cancelar→Hủy, Conta→Tài khoản, Email→Email, Falha→Thất bại, Idioma→Ngôn ngữ, Instalar→Cài đặt, Modelos→Mô hình, Nenhum→Không, Porta→Cổng, Salvar→Lưu, Salvo→Đã lưu, Senha→Mật khẩu, Servidor→Máy chủ, Todos→Tất cả, Usuário→Tên người dùng
- `th` — Cancelar→ยกเลิก, Conta→บัญชี, Email→อีเมล, Falha→ล้มเหลว, Idioma→ภาษา, Instalar→ติดตั้ง, Modelos→โมเดล, Nenhum→ไม่มี, Porta→พอร์ต, Salvar→บันทึก, Salvo→บันทึกแล้ว, Senha→รหัสผ่าน, Servidor→เซิร์ฟเวอร์, Todos→ทั้งหมด, Usuário→ชื่อผู้ใช้
- `ko` — Cancelar→취소, Conta→계정, Email→이메일, Falha→실패, Idioma→언어, Instalar→설치, Modelos→모델, Nenhum→없음, Porta→포트, Salvar→저장, Salvo→저장됨, Senha→비밀번호, Servidor→서버, Todos→전체, Usuário→사용자 이름
- `zh-Hant` — Cancelar→取消, Conta→帳戶, Email→郵件, Falha→失敗, Idioma→語言, Instalar→安裝, Modelos→模型, Nenhum→無, Porta→連接埠, Salvar→儲存, Salvo→已儲存, Senha→密碼, Servidor→伺服器, Todos→全部, Usuário→使用者名稱
- `zh-HK` — Cancelar→取消, Conta→帳戶, Email→郵件, Falha→失敗, Idioma→語言, Instalar→安裝, Modelos→模型, Nenhum→無, Porta→連接埠, Salvar→儲存, Salvo→已儲存, Senha→密碼, Servidor→伺服器, Todos→全部, Usuário→使用者名稱
- `bo` — Cancelar→ཕྱིར་འཐེན, Conta→རྩིས་ཐོ, Email→གློག་འཕྲིན, Falha→འཐུས་ཤོར, Idioma→སྐད་ཡིག, Instalar→སྒྲིག་སྦྱོར, Modelos→དཔེ་དབྱིབས, Nenhum→གང་ཡང་མེད, Porta→འབྲེལ་སྒོ, Salvar→ཉར་ཚགས, Salvo→ཉར་ཚགས་ཟིན, Senha→གསང་ཨང, Servidor→ཞབས་ཞུའི་འཕྲུལ་ཆས, Todos→ཚང་མ, Usuário→སྤྱོད་མཁན་མིང
- `ug` — Cancelar→ۋاز كېچىش, Conta→ھېسابات, Email→ئېلخەت, Falha→مەغلۇپ بولدى, Idioma→تىل, Instalar→ئورنىتىش, Modelos→مودېل, Nenhum→يوق, Porta→پورت, Salvar→ساقلاش, Salvo→ساقلاندى, Senha→پارول, Servidor→مۇلازىمېتىر, Todos→ھەممىسى, Usuário→ئىشلەتكۈچى

**F · Árabe**

- `ar` — Cancelar→إلغاء, Conta→الحساب, Email→البريد الإلكتروني, Falha→فشل, Idioma→اللغة, Instalar→تثبيت, Modelos→النماذج, Nenhum→لا شيء, Porta→المنفذ, Salvar→حفظ, Salvo→تم الحفظ, Senha→كلمة المرور, Servidor→الخادم, Todos→الكل, Usuário→المستخدم

## Ordem importante

Este trabalho **não pode ser aplicado por partes**, ao contrário do Trabalho 1.
O código só muda depois que os 39 estiverem prontos — hoje quem não é pt/en/es/ja/zh
lê o guia em inglês, e mudar o código antes da hora faria esses 39 caírem para
português, que é pior. Junte tudo, depois eu troco o código de uma vez.
