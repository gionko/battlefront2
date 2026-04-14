# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kyber is an open-source private server tool for Star Wars Battlefront II (2017). Multi-language monorepo with five major components communicating via gRPC and Protocol Buffers. Fork: `gionko/battlefront2`.

## Architecture

| Component | Language | Build System | Purpose |
|-----------|----------|-------------|---------|
| **Launcher** | Dart/Flutter | Flutter + Melos | Desktop GUI (server browser, mod management, game launching) |
| **CLI** | Dart + Rust FFI | Dart + flutter_rust_bridge | Command-line server management |
| **API** | Go 1.24+ | Go modules | gRPC/HTTP backend (auth, server browser, stats). Ports: gRPC `:9027`, HTTP `:9028` |
| **Proxy** | Rust (nightly) | Cargo | WebSocket bridge between game clients and servers with JWT validation |
| **Module** | C++ | Bazel (MSVC only) | DLL injected into the game client for hooking and network manipulation |

**Shared Dart packages** in `Packages/`: `kyber`, `kyber_collection`, `nexus_bridge`, `nexus_gql`.
**Proto definitions** in `Module/Proto/`, generate bindings for C++, Dart, Go.
**Maxima** (Rust crate) in `ThirdParty/Maxima` — handles EA auth, LSX server, game launching.

## Build Commands

### Prerequisites
- Clone with `--recurse-submodules`
- `protoc` in PATH
- Flutter (master channel), Rust (nightly), Melos (`dart pub global activate melos`)

### Dart/Flutter workspace
```bash
melos bootstrap                          # Install deps + generate all bindings
melos run generate                       # Run build_runner code generation
melos run generate_proto                 # Regenerate protobuf Dart bindings
melos run generate_frb                   # Regenerate Rust FFI bindings
```

### Launcher
```bash
cd Launcher && dart run tool/ffigen.dart # Generate FFI bindings (first time)
flutter run                              # Debug mode
flutter build windows                    # Release
```

### API (Go)
```bash
cd API
scripts\gen-proto.bat                    # Windows proto gen
go build -o kyber-api.exe ./cmd/server
go test ./...
```

### Proxy (Rust)
```bash
cd Proxy && cargo build --release
```

### Module (C++ - Windows only)
```bash
cd Module
bazel --output_user_root="C:\bz" build --config=release Kyber
# Always use --config=release. Debug builds crash.
```

### Linting
```bash
melos run analyze                        # Dart analyzer
dart format .                            # Format Dart
```

## LAN Offline Mode

This fork adds `KYBER_LAN_MODE=true` for fully offline LAN party operation.

### Server-side (Docker)
```bash
docker compose -f deploy/lan/docker-compose.yml up
```
Runs: MongoDB, Redis, RabbitMQ, MinIO, Kyber API, Kyber Proxy.

### Key env vars for LAN
| Variable | Component | Purpose |
|----------|-----------|---------|
| `KYBER_LAN_MODE=true` | API, Launcher, CLI | Master LAN switch |
| `KYBER_LAN_HOST` | Launcher, CLI | LAN server IP |
| `KYBER_INSECURE=1` | Module | Use insecure gRPC (no SSL) |
| `KYBER_API_HOSTNAME` | Module | gRPC endpoint (e.g. `192.168.1.100:9027`) |
| `MAXIMA_DENUVO_TOKEN` | Launcher, CLI | Pre-cached license token |
| `WHITELIST_ENABLED=false` | API | Disable whitelist check |
| `MINIO_SECURE=false` | API | MinIO over HTTP |

### LAN login flow
In LAN mode, `Login()` accepts a username string (not EA JWT). The API generates a deterministic user ID from the username and creates/updates the user in MongoDB without any EA network calls.

## Code Standards

### Module (C++)
- C++11, clang-format enforced. Guards over nesting. `g_` globals, `m_` members.
- Hooks: `Hk` suffix, `HookManager::Call()` trampoline, `TL_DECLARE_FUNC` as `ClassName_functionName`.
- EASTL over std. Game memory arenas over `new`. `ThreadExecutor` for cross-thread. `Mutex<>` for shared fields.

### Launcher (Dart/Flutter)
- Feature-based: `lib/features/<feature>/{dialogs,helper,models,providers,screens,services,widgets}/`.
- BLoC/Cubit in `providers/`. GetIt DI via `sl`. Assets via `gen/assets.gen.dart`.
- Naming: `<Feature>Cubit`, `<Feature>Service`, `_<Widget>` private. Effective Dart, `const` constructors.

## Key Entry Points
- **Launcher:** `Launcher/lib/main.dart`
- **CLI:** `CLI/bin/kyber_cli.dart`
- **API:** `API/cmd/server/main.go`
- **Proxy:** `Proxy/src/main.rs`
- **Module:** `Module/Source/` → `Kyber.dll`
- **Maxima:** `ThirdParty/Maxima/maxima-lib/src/`
