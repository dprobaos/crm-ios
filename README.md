# Neuro Voice CRM — App iOS (casca WebView + Face ID)

App iOS que espelha o painel web do CRM (`https://neurovoice.com.br/crm/`) numa
casca nativa em Swift, com **login por Face ID / Touch ID**. Mesmas funções do
site: dashboard, pipeline Kanban, leads, perdidos, captura, usuários e o botão
"Abrir WhatsApp" com a mensagem padrão. Segue o mesmo padrão dos outros apps
(Bolão, NeuroVoice, LocaCobrança): sem Mac local, o build é feito na nuvem pelo
**Codemagic** (XcodeGen gera o `.xcodeproj`) e enviado ao **TestFlight**.

- **Bundle ID:** `com.dprobaos.crm`
- **Nome de exibição:** NeuroVoice CRM
- **Team Apple:** `4P5D9V48GJ`
- **Destino do build:** TestFlight (teste interno, sem revisão)

## Como o Face ID funciona (sem mexer no backend)
O CRM já entrega no login um **JWT de 30 dias** (guardado no `localStorage`:
`nv_t` = token, `nv_u` = usuário). O app guarda esse "pacote" (JSON
`{token,user}`) no **Keychain**, protegido pela biometria (`.biometryCurrentSet`,
`WhenUnlockedThisDeviceOnly`), e reidrata a sessão sozinho na próxima abertura.
**Nenhuma alteração de PHP/SQL foi necessária** — só uma ponte JS no `index.html`
do CRM, ativada apenas dentro do app (`window.__NATIVE_APP__`).

Fluxo:
1. Você entra com email + senha 1 vez → o app pergunta "Ativar Face ID?" → confirma a biometria e grava o pacote.
2. Nas próximas aberturas, sem sessão, o Face ID dispara automaticamente → entra sem digitar.
3. Botão manual "🔒 Entrar com Face ID" também aparece na tela de login; e há um botão para ativar/desativar na barra lateral (dentro do app).

## Mapa dos arquivos
- `project.yml` — spec do XcodeGen (target único, Info.plist, permissões).
- `codemagic.yaml` — pipeline: xcodegen → assinatura automática → build → TestFlight.
- `CRMApp/CRMApp.swift` — entrada do app (carrega a WebView do `/crm/`).
- `CRMApp/WebView.swift` — WKWebView endurecida (cookies/localStorage, diálogos JS, links externos/WhatsApp no Safari, ponte Face ID).
- `CRMApp/BiometriaManager.swift` — Keychain + LocalAuthentication (guarda o JWT).
- `CRMApp/Assets.xcassets/…/icon-1024.png` — ícone (funil de vendas dourado → lead convertido).

---

## PASSO A PASSO DO DEPLOY

### ✅ Já feito
- App iOS completo (`ios_crm_app/`).
- Ponte Face ID no site (`crm-neurovoice/godaddy/index.html`) — publicada por FTP em `/crm`.

### ⬜ Só você consegue fazer (contas Apple/Codemagic)

**1) Git — subir a pasta**
Suba **`ios_crm_app/`** como raiz de um repo novo (GitHub/GitLab/Bitbucket),
branch `main`. A pasta do app é a raiz do repo (o `codemagic.yaml` fica na raiz).

```
cd ios_crm_app
git init && git add . && git commit -m "App iOS Neuro Voice CRM"
git branch -M main
git remote add origin <URL_DO_REPO>
git push -u origin main
```

**2) App Store Connect**
- My Apps → **+** → New App → bundle **`com.dprobaos.crm`**, nome "NeuroVoice CRM", idioma pt-BR.
- A **API Key** você já tem (a mesma do NeuroVoice/Bolão) — não precisa criar outra.

**3) Codemagic**
- Conecte o repositório do passo 1.
- A integração App Store Connect já existe: **`NeuroVoice ASC`** (usada no `codemagic.yaml`).
- O grupo de variáveis **`ios_signing`** (com `CM_CERTIFICATE_PRIVATE_KEY`) já existe dos outros apps.
- Copie o **App ID** e o **Workflow ID** gerados e cole em `codemagic-runner/apps.json` (entrada `crm`).

**4) Buildar**
- Push na `main` dispara o build automático (`triggering:` no yaml), **ou**
- Rode pelo runner central:
  ```
  node projetos-claude/codemagic-runner/cm_build.mjs crm
  ```
- Ao terminar, o build fica no **TestFlight** (teste interno, sem revisão).

### Expectativa honesta
O primeiro build costuma pedir **1–2 ajustes** (assinatura/identifier/versão do
Xcode). O log do Codemagic diz exatamente o que falta — me cole o erro que eu
corrijo o `project.yml`/`codemagic.yaml`.
