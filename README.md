<p align="center">
  <img src="res/ndisafe_logo.svg" width="120" alt="NDISafe Desk Logo" />
</p>

<h1 align="center">NDISafe Desk</h1>
<p align="center">Secure remote desktop for teams — built on RustDesk, owned by you.</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-1.4.9-teal" />
  <img src="https://img.shields.io/badge/platform-Windows-blue" />
  <img src="https://img.shields.io/badge/rust-1.75-orange" />
  <img src="https://img.shields.io/badge/flutter-3.24.5-blue" />
  <img src="https://img.shields.io/github/actions/workflow/status/kiin-innovation/Ndisafe-Desk/build.yml?branch=ndisafe-desk&label=CI" />
</p>

---

## What is NDISafe Desk?

NDISafe Desk is a TeamViewer-style remote desktop application built on top of [RustDesk](https://github.com/rustdesk/rustdesk). It is fully self-hosted — it connects only to **your own relay servers**, not RustDesk's public infrastructure.

**Key differences from upstream RustDesk:**
- Branded with the NDISafe identity (logo, colors, app name)
- Pre-configured to connect to your own `hbbs`/`hbbr` server — the rendezvous IP **and** public key are baked into the binary, so users never configure anything
- Portable Windows build distributed via GitHub Actions CI
- No dependency on any third-party relay service

---

## Current Deployment (as of this writing)

| Item | Value |
|---|---|
| Production VPS | `68.168.211.152` |
| Server public key | `2SvuoqbjN93LAF227EEGaj0fHNXd9V83IuhUv4HOGQM=` |
| Server image | `calvin207/ndisafedesk:1.1.16` (published by CI, Debian-based with `bash`/`sh`) |
| Docker Compose | `docker/server/docker-compose.yml` (run on the VPS) |
| Known peer for testing | `192.168.1.223` (LAN machine, runs the same client build) |
| Client build version | `1.4.9` |

The values above are set in **`libs/hbb_common/src/config.rs`**:

```rust
pub const RENDEZVOUS_SERVERS: &[&str] = &["68.168.211.152"];
pub const RS_PUB_KEY: &str = "2SvuoqbjN93LAF227EEGaj0fHNXd9V83IuhUv4HOGQM=";
```

> ⚠️ **Every peer must use a build with the same `RS_PUB_KEY`.** If one machine has an older/different key baked in, the server responds `LICENSE_MISMATCH` and the connection fails with **`Key mismatch`** (see Troubleshooting). Keep the old downloads around only if you still need them; otherwise replace all machines at once.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                 NDISafe Desk Client              │
│  Flutter UI  ←→  librustdesk.dll (Rust core)    │
└───────────────────────┬─────────────────────────┘
                        │ TCP/UDP 21116
                        ▼
┌─────────────────────────────────────────────────┐
│              Your hbbs (ID/Rendezvous)           │
│                  port 21116                      │
└───────────────────────┬─────────────────────────┘
                        │ TCP 21117
                        ▼
┌─────────────────────────────────────────────────┐
│              Your hbbr (Relay)                   │
│                  port 21117                      │
└─────────────────────────────────────────────────┘
```

| Component | Technology | Purpose |
|---|---|---|
| Desktop client | Rust + Flutter | UI and remote desktop protocol |
| `librustdesk.dll` | Rust (cdylib) | Core engine — screen capture, input, audio |
| `hbbs` | RustDesk server | ID registration and NAT traversal |
| `hbbr` | RustDesk server | Relay when direct connection fails |

How a connection works:

1. The client starts and registers its 9-digit ID with `hbbs` via UDP/TCP `21116`.
2. The controller asks `hbbs` where the peer is; hbbs answers with the peer's current address.
3. Both sides attempt a direct (punch-through) connection. If that fails, traffic goes through `hbbr` relay on `21117`.
4. On top of the (possibly relayed) TCP stream, NDISafe Desk runs its own custom protocol (`src/rendezvous_mediator.rs` / `src/server/connection.rs`).

---

## Customizations in this fork

These are the intentional NDISafe changes over upstream RustDesk. When in doubt, blame one of these commits.

- **Baked-in rendezvous + key** — `config.rs` points at the VPS and its real public key, so users do zero configuration.
- **Portable installer + MSI** — CI produces a self-extracting installer and an `.msi`, not just a zip.
- **Server image with a shell** — the hbbs/hbbr Docker image is Debian-based (not `FROM scratch`) so you can `docker exec -it hbbs bash` to debug.

---

## For Team Members — Running the App

### Download the latest build

1. Go to [GitHub Actions](https://github.com/kiin-innovation/Ndisafe-Desk/actions)
2. Click the latest successful **NDISafe Desk – Windows Portable Build** run
3. Scroll to **Artifacts** at the bottom
4. Download **NDISafe-Desk-1.4.9-windows-portable** (zip), or the self-extracting **exe** / **msi**
5. Extract the zip to any folder (e.g. `C:\NDISafe Desk\`)
6. Double-click **`ndisafe-desk.exe`**

> **Windows Defender note:** On first run Windows may show a SmartScreen warning. Click **More info → Run anyway**. This happens because the exe is not yet code-signed.

### Sharing your screen

1. Open NDISafe Desk — your **9-digit ID** is shown on the main screen
2. Share that ID with a teammate
3. They enter it in the **Connect** field and click **Connect**
4. Accept the incoming connection request

### Connecting to someone else

1. Ask them for their 9-digit ID
2. Enter it in the **Connect** field
3. Click **Connect**

---

## For Developers — Local Setup

### Prerequisites

| Tool | Version | Download |
|---|---|---|
| Rust | 1.75 | https://rustup.rs |
| Flutter | 3.24.5 | https://docs.flutter.dev/get-started/install/windows |
| Visual Studio Build Tools | 2022+ | https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022 |
| vcpkg | pinned commit | See below |
| NASM | any | `choco install nasm` |
| Docker Desktop | any | https://www.docker.com/products/docker-desktop |
| Python | 3.x | https://python.org |

### 1. Clone the repo

```powershell
git clone https://github.com/kiin-innovation/Ndisafe-Desk --branch ndisafe-desk
cd Ndisafe-Desk
```

> Note: `libs/hbb_common` is tracked as a regular directory (not a submodule) so no `--recursive` flag is needed.

### 2. Set up vcpkg

```powershell
git clone https://github.com/microsoft/vcpkg C:\vcpkg
C:\vcpkg\bootstrap-vcpkg.bat

$env:VCPKG_ROOT = "C:\vcpkg"
$env:VCPKG_INSTALLED_ROOT = "C:\vcpkg\installed"

C:\vcpkg\vcpkg install --triplet x64-windows-static
```

> `VCPKG_INSTALLED_ROOT` must point to `C:\vcpkg\installed`, **not** `C:\vcpkg\installed\x64-windows-static` — the build scripts append the triplet name themselves.

### 3. Build and run locally

```powershell
$env:VCPKG_ROOT = "C:\vcpkg"
$env:VCPKG_INSTALLED_ROOT = "C:\vcpkg\installed"
$d = "flutter\build\windows\x64\runner\Release"
$t = "target\release"

# Build the Rust core (needed when src/ or libs/hbb_common/ changes)
cargo build --features flutter --lib --bins --release

# Build the Flutter UI (needed when flutter/lib/ changes)
cd flutter; flutter build windows --release; cd ..

# Rust build first, THEN flutter build — flutter's CMake links against the
# fresh librustdesk.dll. Verify $d\librustdesk.dll timestamp is newer.
```

Then copy the freshly built Rust binaries over the Flutter output (this is exactly what `.github/workflows/build.yml` "Assemble portable bundle" does):

```powershell
Copy-Item "$t\librustdesk.dll","$t\service.exe","$t\naming.exe","$t\dylib_virtual_display.dll" $d -Force
Copy-Item "C:\vcpkg\installed\x64-windows-static\bin\opus.dll" $d -Force

# Launch
Start-Process "$d\ndisafe-desk.exe" -WorkingDirectory $d
```

**When do I need to rebuild what?**

| Changed files | Rebuild needed |
|---|---|
| `src/**/*.rs` or `libs/**/*.rs` | Rust only: `cargo build --features flutter --lib --bins --release` |
| `flutter/lib/**/*.dart` | Flutter only: `flutter build windows --release` |
| `libs/hbb_common/src/config.rs` | Rust only (this bake-in is compiled into the binary) |
| Both | Rust first, then Flutter |

---

## Logs, Config, and Debugging

The app does **not** use the upstream `%APPDATA%\RustDesk\` folder. With the brand rename, everything lives under the app name:

```
%APPDATA%\NDISafe Desk\
├── config\NDISafe Desk.toml     # options + confirmed keys
├── log\
│   └── ndisafe-desk_rCURRENT.log  # the real log file to grep
└── ...
```

Key log facts:

- A **fresh** log file is written each run; `rCURRENT` is the live one.
- When connecting, expect lines about rendezvous (`68.168.211.152:21116`), a punch attempt with the peer's LAN IP + an 8-9 digit id, and a possible `Connection closed: Key mismatch(0)` (see below).
- `Key mismatch` comes from `bail!("Key mismatch")` at `src/client.rs` when `hbbs` answers `LICENSE_MISMATCH` — the peer's client build has a different baked key than the server.

Debug sessions:

```powershell
# tail the live log
Get-Content "$env:APPDATA\NDISafe Desk\log\ndisafe-desk_rCURRENT.log" -Tail 50 -Wait
```

---

## CI/CD — GitHub Actions

Workflows in `.github/workflows/`:

| Workflow | Triggers | Produces |
|---|---|---|
| `build.yml` | push to `ndisafe-desk`, manual | portable zip, self-extracting `NDISafe-Desk-1.4.9-windows-x86_64.exe`, `NDISafe-Desk-1.4.9-windows-x86_64.msi`, Linux portable `NDISafe-Desk-1.4.9-linux-portable.tar.gz`, Linux single-file `NDISafe-Desk-1.4.9-x86_64.AppImage` |
| `docker-server.yml` | push to `ndisafe-desk` | `calvin207/ndisafedesk:latest` and `:1.1.16` on Docker Hub |
| `bridge.yml` | used by the build | Flutter/Rust FFI bridge files |

`build.yml` in detail: `generate-bridge` (Ubuntu), then `build-windows` (Windows 2022) which installs tooling, runs `cargo build --features flutter --lib --bins --release`, runs `flutter build windows --release`, assembles the portable bundle, builds the self-extracting installer (`libs/portable/generate.py`), builds the MSI (msi.sln), and uploads artifacts. `build-linux` (Ubuntu 22.04) installs system deps + vcpkg (x64-linux, builds ffmpeg for `hwcodec`), runs `cargo build --features hwcodec,flutter,unix-file-copy-paste --lib --release`, runs `flutter build linux --release`, and tars `flutter/build/linux/x64/release/bundle/` (plus `ndisafe-desk.desktop`, `ndisafe-desk.png`, `ndisafe-desk.svg` at the root) into the portable tarball — extract it anywhere and run `./ndisafe-desk`. For a launcher entry: copy `ndisafe-desk.desktop` to `~/.local/share/applications/`, the icon files to `~/.local/share/icons/`, and point the desktop file's `Exec=` at the extracted binary's full path. Prefer the single-file option: download `NDISafe-Desk-1.4.9-x86_64.AppImage`, `chmod +x` it, and run — no extraction needed (on Ubuntu 22.04+ install `libfuse2` first: `sudo apt install libfuse2`). Note: `res/icon.png` is still the upstream RustDesk icon — the NDISafe Linux icon is rendered from `res/ndisafe_logo.svg` at build time (`rsvg-convert`, PNGs are gitignored).

**Notes:**
- The Docker workflow requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets; without them it fails.
- The Docker image builds with the **current** `config.rs` too, so server and clients stay in sync only when you push both at once.

**Trigger a build manually:**

```powershell
git commit --allow-empty -m "ci: trigger build"
git push origin ndisafe-desk
```

Or via GitHub UI: Actions tab → **NDISafe Desk – Windows Portable Build** → **Run workflow**.

> The GitHub CLI (`gh`) is not authenticated on the dev machine, so CI status is checked via the Actions web UI, not terminal.

---

## Server Deployment (VPS)

The server lives in `docker/server/` (a compose file plus the custom `Dockerfile` that layers the packaged `hbbs`/`hbbr` onto Debian).

```bash
# On the VPS
cd docker/server
cp .env.example .env        # set RELAY_PUBLIC_HOST to your public IP or domain
docker compose pull         # get the freshly built image
docker compose up -d        # starts hbbs (21115/21116/21118) and hbbr (21117/21119)
docker exec -it hbbs bash   # shell available for debugging
```

- The server key pair is generated on **first start** and persisted in the volume (`./data/` on the VPS, `C:\ndisafe-server\` in local dev). `id_ed25519.pub` holds the public key — copy it into `config.rs` if the server is ever recreated.
- Restarting the container does **not** regenerate the key (good — the baked client key keeps matching).
- Firewall ports to open on the VPS:

| Port | Protocol | Purpose |
|---|---|---|
| 21115 | TCP | NAT test |
| 21116 | TCP + UDP | ID registration, heartbeat |
| 21117 | TCP | Relay |
| 21118 | TCP | WebSocket rendezvous |
| 21119 | TCP | WebSocket relay |

### Local dev server (Docker Desktop)

```powershell
New-Item -ItemType Directory -Path C:\ndisafe-server -Force
docker run --name hbbs -p 21115:21115 -p 21116:21116 -p 21116:21116/udp -p 21118:21118 -v "C:\ndisafe-server:/root" -d calvin207/ndisafedesk hbbs
docker run --name hbbr -p 21117:21117 -p 21119:21119 -v "C:\ndisafe-server:/root" -d calvin207/ndisafedesk hbbr
docker update --restart=always hbbs hbbr
Get-Content C:\ndisafe-server\id_ed25519.pub
```

> **Do not rely on a local LAN Docker server for real use.** The production setup is the VPS (68.168.211.152); all clients point at it. Using a LAN host instead means every client's baked key/address must point at that machine instead.

---

## Repository Structure

```
Ndisafe-Desk/
├── src/                    # Rust application source
│   ├── core_main.rs        # App startup, IPC, portable service
│   ├── client.rs           # Client connection logic (Key mismatch lives here)
│   ├── client/io_loop.rs   # Controller-side message loop, permissions
│   ├── server/connection.rs# Host-side connection and input gating
│   ├── rendezvous_mediator.rs # Communication with hbbs
│   ├── flutter.rs          # Flutter FFI exports
│   ├── platform/           # Windows/macOS/Linux platform code
│   └── lang/               # Localization (template.rs is the key list; never edit as part of translations)
├── libs/
│   ├── hbb_common/         # Config, proto, shared utils (OWNED — not a submodule)
│   │   └── src/config.rs   # ← SERVER ADDRESS and PUBLIC KEY live here
│   ├── scrap/              # Screen capture
│   ├── enigo/              # Input simulation
│   └── virtual_display/    # Virtual display driver (Windows)
├── flutter/
│   ├── lib/
│   │   ├── common.dart     # MyTheme colors
│   │   ├── desktop/        # Desktop UI pages and widgets
│   │   │   └── pages/remote_page.dart  # ← remote view (overlay fix landed here)
│   │   │   └── pages/server_page.dart  # ← host connection manager
│   │   └── mobile/         # Mobile UI
│   ├── assets/             # Icons, SVGs, fonts
│   └── windows/runner/     # Windows runner (CMake, .rc file, icon)
├── docker/server/          # Dockerfile + docker-compose for hbbs/hbbr
├── res/
│   ├── ndisafe_logo.svg    # ← Master logo
│   └── icon.ico            # Compiled icon (auto-generated)
└── .github/workflows/
    ├── build.yml           # ← NDISafe CI (portable zip + installers)
    ├── docker-server.yml   # ← builds/pushes calvin207/ndisafedesk
    └── bridge.yml          # Flutter/Rust FFI bridge generation
```

---

## Branding

| Asset | Location | Notes |
|---|---|---|
| Logo SVG | `res/ndisafe_logo.svg` | Source of truth for all icon/logo derivatives |
| App icon (exe) | `flutter/windows/runner/resources/app_icon.ico` | Embedded in `.exe` |
| Flutter logo asset | `flutter/assets/logo.svg` | Shown on the main screen |
| App name | `libs/hbb_common/src/config.rs` → `APP_NAME` | `"NDISafe Desk"` |

**Color palette** (from logo SVG):

| Token | Hex | Usage |
|---|---|---|
| NDISafe Teal | `#4EB79B` | Primary accent, buttons hover, ID color |
| NDISafe Blue | `#3D5D89` | Buttons, secondary elements |
| NDISafe Navy | `#2A496E` | Deep backgrounds, canvas |
| NDISafe Dark Navy | `#1A2E42` | Dark theme canvas |

---

## Troubleshooting

**`Connection closed: Key mismatch(0)` when connecting**
- The peer's client build has a different baked `RS_PUB_KEY` than the server actually uses.
- Read the server's real key: `docker exec hbbs cat /root/id_ed25519.pub` (VPS) — for this project it must be `2SvuoqbjN93LAF227EEGaj0fHNXd9V83IuhUv4HOGQM=`.
- Fix: update `config.rs`, rebuild, and **redeploy to every machine** (especially the remote peer — e.g. `192.168.1.223` — which is easy to forget).
- Make sure the peer runs a build with the same `RS_PUB_KEY` (redeploy to every machine; the remote peer is easy to forget).

**App opens to a white/blank screen, or the remote view has a white cover**
- Another NDISafe Desk/RustDesk instance from an older path may still be running. Kill all `rustdesk`/`ndisafe-desk` processes and relaunch.
- If the **remote view** is covered in white: this was the `BlockableOverlay` white-canvas bug (Flutter `Overlay` widget painting white). Fixed by rendering the remote body unwrapped (`remote_page.dart`). A build with commit `3714e9b9a` or later is required.

**"Connection failed" or can't connect to peers**
- Check `hbbs`/`hbbr` containers are running: `docker ps` / `docker compose ps`
- Verify the IP/key in `config.rs` matches your server
- Ensure firewall allows ports 21115–21119 (TCP) and 21116 UDP
- Check the log: `%APPDATA%\NDISafe Desk\log\`

**Flutter build fails with "Visual Studio 16 2019 not found"**
- The Flutter tool needs a patch for newer VS versions:
  - In `C:\flutter\packages\flutter_tools\lib\src\windows\visual_studio.dart`, add the matching `cmakeGenerator` entry
  - Delete `C:\flutter\bin\cache\flutter_tools.snapshot` and rerun

**`scrap` build fails with "vpx/vp8.h not found"**
- `VCPKG_INSTALLED_ROOT` must point to `C:\vcpkg\installed` (the scripts append the triplet themselves).

**opus.dll not found at runtime**
- Copy `C:\vcpkg\installed\x64-windows-static\bin\opus.dll` next to `ndisafe-desk.exe`, or add that directory to PATH.

---

## License

NDISafe Desk is based on [RustDesk](https://github.com/rustdesk/rustdesk) which is licensed under [AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.en.html).

All NDISafe-specific modifications are the property of Kiin Innovation.

---

<p align="center">Built by <strong>Kiin Innovation</strong></p>