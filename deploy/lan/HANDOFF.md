# LAN Offline Mode — Stato dei lavori e guida per riprendere

Questo documento e' per una nuova sessione di Claude Code (o per lo sviluppatore umano) che deve riprendere il lavoro sul porting offline/LAN di Kyber.

---

## Filosofia del progetto

**Zero connessioni esterne se non strettamente necessarie.** Questa e' una LAN party che deve girare 100% offline. Ogni chiamata HTTP/gRPC/WebSocket verso internet e' un bug. Auditare ogni endpoint, ogni client HTTP, ogni env-gated URL. Non saltare dettagli.

Tipici target da verificare:
- Sentry DSN (Launcher, API, Module, Proxy, CLI)
- Version check / auto-update (CLI, Launcher)
- License endpoints (EA novafusion, Kyber license proxy)
- NexusMods API
- Patreon / Discord OAuth
- EA accounts.ea.com / gateway.ea.com / service-aggregation-layer
- Kyber cloud: s3.kyber.gg, api-rpc.prod.kyber.gg
- JWKS endpoints (solo il locale deve essere raggiunto)
- Download manager / image fetcher

---

## Stato attuale del fork

Branch: `ver/beta10`
Remote: `https://github.com/gionko/battlefront2.git` (fork dell'utente)

**3 commit gia' pushati:**

| SHA | Descrizione |
|-----|-------------|
| `1a53a77` | Infrastruttura LAN: API `lanLogin()`, Docker stack in `deploy/lan/`, Module `KYBER_INSECURE`, factory `KyberGRPCService.lan()` |
| `1878907` | Launcher UI: form LAN login con nome giocatore, `requestLanLogin()` in maxima_cubit, skip Maxima/EA OAuth |
| `8c5fe6f` | CLI: server hosting LAN, skip Docker bypass check, login con nome diretto, `KYBER_INSECURE` per Module |

**Piano completo originale:** `C:\Users\Gionko\.claude\plans\goofy-dazzling-hippo.md`

---

## Componenti del progetto

| Componente | Linguaggio | Build |
|-----------|-----------|-------|
| API | Go 1.24+ | `cd API && go build ./cmd/server` |
| Module (Kyber.dll) | C++ | `cd Module && bazel --output_user_root="C:\bz" build --config=release Kyber` |
| Proxy | Rust nightly | `cd Proxy && cargo build --release` |
| Launcher | Flutter/Dart | `cd Launcher && flutter build windows` |
| CLI | Dart + Rust FFI | `cd CLI && dart build cli bin/kyber_cli.dart` |
| Packages Dart | Dart | `melos bootstrap` (da root) |
| Maxima (submodule) | Rust | Non si ricompila, usato come dep dal Launcher/CLI |

---

## Tool installati sulla macchina (paths non standard!)

| Tool | Versione | Path |
|------|----------|------|
| Go | 1.26.2 | in PATH |
| Rust nightly | 1.97.0-nightly | `C:\Users\Gionko\.cargo\bin` in PATH |
| Flutter master | 3.44.0-1.0.pre-98 | `D:\LanpartyStorage\tools\flutter\bin` in PATH |
| Dart | 3.13.0-19.0.dev | incluso con Flutter |
| protoc | 25.9 | `D:\LanpartyStorage\tools\protoc-25.9-win64\bin` in PATH |
| protoc-gen-go | v1.36.11 | `C:\Users\Gionko\go\bin` |
| protoc-gen-go-grpc | 1.6.1 | `C:\Users\Gionko\go\bin` |
| Melos | 7.5.1 | `C:\Users\Gionko\AppData\Local\Pub\Cache\bin` |
| Bazel (via bazelisk) | 9.0.2 | `D:\LanpartyStorage\tools\bazelisk\bazel.exe` (copia di bazelisk.exe) in PATH |
| MSVC | 14.44.35207 | `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207` |
| Windows SDK | 10.0.26100.0 | `C:\Program Files (x86)\Windows Kits\10` |
| MSYS2 | installato | `C:\msys64` |
| Bazel output dir | creato | `C:\bz` |
| Docker Desktop | 27.4.0 | avviato |
| Git long paths | `true` | configurato globalmente |

**Nota:** Il PATH utente richiede che le nuove shell vengano aperte dopo l'aggiunta di `D:\LanpartyStorage\tools\flutter\bin`. Se si apre una shell prima, ricaricare l'env o usare path assoluti.

---

## Cosa e' stato modificato (recap dettagliato)

### API (Go)
- `API/cmd/server/main.go` — `MINIO_SECURE` env var
- `API/internal/rpc/authentication.go` — struct field `lanMode`, skip `ea2.LoadJwks()` in LAN, nuovo metodo `lanLogin()` che:
  - Accetta username come `req.GetToken()`
  - Genera PID deterministico via `sha256(username)[:8]` hex
  - Estrae IP da `peer.FromContext(ctx)` (fallback `127.0.0.1`)
  - Crea utente via `store.Users.Create()` con `JwtUserPersonaInformationClaims{ID: 0, Ns: "cem_ea_id", Dis: username, Nic: username}` + `EAJwtNexusClaims{Pid: pid}`
  - Pubblica evento RabbitMQ `player.connected`
  - Ritorna `LoginResponse{Id, Name, Token, Entitlements: [], IsPatreon: false}`
- `API/internal/rpc/server_browser.go` — fallback IP da `peer.FromContext()` quando `cf-connecting-ip` manca
- `API/internal/rpc/report.go` — R2/MinIO opzionale, no panic se non configurato, nil check in `GenerateEvidenceLinks()`

### Module (C++)
- `Module/Source/RPC/API.cpp` — `KYBER_INSECURE` env var attiva `grpc::InsecureChannelCredentials()` al posto di SSL

### Packages Dart
- `Packages/kyber/lib/src/services/api_service.dart` — nuova factory `KyberGRPCService.lan(String host, {int port = 9027})`

### Launcher (Dart/Flutter)
- `Launcher/lib/injection_container.dart` — getter top-level `isLanMode` e `lanHost` da env, registrazione condizionale di `KyberGRPCService`
- `Launcher/lib/features/maxima/providers/maxima_cubit.dart` — import `isLanMode`, nuovo metodo `requestLanLogin(String username)`, skip Maxima init in `init()` se LAN mode, skip Kyber status check in `requestLogin()`
- `Launcher/lib/features/maxima/screens/maxima_login.dart` — header "LAN Login" in LAN mode, nuovo widget `_LanLoginForm` con TextBox per player name

### CLI (Dart)
- `CLI/lib/command_runner.dart` — isLanMode, usa `KyberGRPCService.lan(lanHost)`, skip module update check, dummy auth storage per Maxima
- `CLI/lib/commands/start_server_command.dart` — getter `_isLanMode`, skip Docker bypass in LAN, player name da `KYBER_LAN_PLAYER_NAME` env o da credentials flag, login LAN con nome diretto, setta `KYBER_INSECURE=1`

### Docker Stack (nuovo in `deploy/lan/`)
- `docker-compose.yml` — MongoDB, Redis, RabbitMQ, MinIO, Kyber API, Kyber Proxy
- `.env` — template env vars (MinIO credentials, MAXIMA_DENUVO_TOKEN placeholder)
- `config/whitelist.yaml` — whitelist vuota
- `config/event-blacklist.yaml` — blacklist vuota
- `client-setup.ps1` — script PowerShell per setup client (copia license, genera batch files, test connessione)
- `prepare-tokens.ps1` — script per catturare Denuvo token e license file da un run online

---

## Env vars master reference

| Variabile | Dove | Valore |
|-----------|------|--------|
| `KYBER_LAN_MODE` | API, Launcher, CLI | `true` |
| `KYBER_LAN_HOST` | Launcher, CLI | IP server LAN (es. `192.168.1.100`) |
| `KYBER_LAN_PLAYER_NAME` | CLI (start_server) | Nome giocatore per il dedicated server |
| `KYBER_INSECURE` | Module | `1` (set auto da Launcher/CLI in LAN) |
| `KYBER_API_HOSTNAME` | Module | `{host}:9027` (set auto) |
| `KYBER_HTTP_HOSTNAME` | Module | `{host}:9028` (set auto) |
| `KYBER_API_TOKEN` | Module | token Kyber (set auto dopo login) |
| `MAXIMA_DENUVO_TOKEN` | Launcher, CLI | token Denuvo pre-cached |
| `WHITELIST_ENABLED` | API | `false` (gia' in `deploy/lan/docker-compose.yml`) |
| `MINIO_SECURE` | API | `false` (HTTP MinIO) |
| `MONGO_URI`, `REDIS_URI`, `AMQP_URL`, `MINIO_HOST/KEY/SECRET` | API | configurate in docker-compose |
| `JWKS_URL` | Proxy | `http://api:9028/.well-known/jwks.json` |

---

## Prossimo passo: Step 8 — Audit Module per zero-bandwidth

**Obiettivo:** controllare ogni chiamata esterna dal Module (Kyber.dll) e disabilitarla/by-passarla in LAN mode.

**Azioni:**
1. Cercare in `Module/Source/` tutti gli endpoint hardcoded e client HTTP
2. Ispezionare `Module/Source/Core/Sentry.cpp` per Sentry DSN — va disabilitato se LAN
3. Verificare il subscriber ProxyEvent, NexusMods, download manager
4. Controllare ogni `std::getenv` e ogni chiamata `httpClient` / `grpc::CreateChannel`
5. Aggiungere un `KYBER_LAN_MODE` check anche nel Module dove necessario (es. per skippare Sentry init)
6. Rebuildare `Kyber.dll` e verificare

Poi compilare tutto (step 9):
- `cd API && go build ./cmd/server`
- `melos bootstrap` dalla root
- `cd Launcher && flutter build windows --debug` (prima debug per validare, poi release)
- `cd CLI && dart build cli bin/kyber_cli.dart`
- `cd Proxy && cargo build --release`
- `cd Module && bazel --output_user_root="C:\bz" build --config=release Kyber`

**Ricorda**: il Module richiede `--config=release` obbligatoriamente (debug crasha).

---

## Verifica end-to-end (quando tutto compila)

1. `cd deploy/lan && docker compose up -d` sulla macchina server LAN
2. Controllare logs API: `docker compose logs -f api`
3. Su un client Windows: settare env + lanciare Launcher
   ```
   set KYBER_LAN_MODE=true
   set KYBER_LAN_HOST=192.168.1.100
   .\kyber_launcher.exe
   ```
4. Inserire nome giocatore → login deve andare a buon fine
5. Creare un server da un altro client → vedere in server browser
6. Joinare e verificare gameplay

---

## File di memoria Claude (persistenti tra sessioni)

Path: `C:\Users\Gionko\.claude\projects\D--LanpartyStorage-tools-Kyber-ver-beta10\memory\`

- `MEMORY.md` — indice
- `user_profile.md` — profilo utente
- `project_lan_offline.md` — contesto progetto
- `feedback_bandwidth.md` — filosofia zero connessioni esterne

Una nuova sessione di Claude legge automaticamente MEMORY.md e dovrebbe poi leggere questo HANDOFF.md.

---

## Utili per una nuova sessione

- **Directory di lavoro:** `D:\LanpartyStorage\tools\Kyber-ver-beta10`
- **Piano originale completo:** `C:\Users\Gionko\.claude\plans\goofy-dazzling-hippo.md`
- **Il Maxima submodule** e' clonato e disponibile a `ThirdParty/Maxima/` — il codice sorgente di auth/login/lsx e' leggibile
- **Shell**: bash/git-bash. PowerShell per script Windows. Usare `powershell.exe -Command` o creare file `.ps1` se serve eseguire script.
