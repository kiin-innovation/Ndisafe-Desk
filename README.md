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
- Pre-configured to connect to your own `hbbs`/`hbbr` server
- Portable Windows build distributed via GitHub Actions CI
- No dependency on any third-party relay service

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

---

## For Team Members — Running the App

### Download the latest build

1. Go to [GitHub Actions](https://github.com/kiin-innovation/Ndisafe-Desk/actions)
2. Click the latest successful **NDISafe Desk – Windows Portable Build** run
3. Scroll to **Artifacts** at the bottom
4. Download **NDISafe-Desk-1.4.9-windows-portable**
5. Extract the zip to any folder (e.g. `C:\NDISafe Desk\`)
6. Double-click **`rustdesk.exe`**

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

### 3. Start the local relay server (Docker)

```powershell
# Create data directory (stores generated key pair)
New-Item -ItemType Directory -Path C:\ndisafe-server -Force

# Start rendezvous/ID server
docker run --name hbbs `
  -p 21115:21115 -p 21116:21116 -p 21116:21116/udp -p 21118:21118 `
  -v "C:\ndisafe-server:/root" -d rustdesk/rustdesk-server hbbs

# Start relay server
docker run --name hbbr `
  -p 21117:21117 -p 21119:21119 `
  -v "C:\ndisafe-server:/root" -d rustdesk/rustdesk-server hbbr
```

Get your server's public key (needed for `config.rs`):

```powershell
Get-Content C:\ndisafe-server\id_ed25519.pub
```

Make containers restart automatically after reboot:

```powershell
docker update --restart=always hbbs hbbr
```

### 4. Configure the server address

Edit `libs/hbb_common/src/config.rs`:

```rust
// Line ~117 — set to your machine's LAN IP or VPS IP
pub const RENDEZVOUS_SERVERS: &[&str] = &["192.168.1.xxx"];

// Line ~118 — paste the key from id_ed25519.pub
pub const RS_PUB_KEY: &str = "your-base64-key-here=";
```

> **For production:** replace `192.168.1.xxx` with your VPS IP or domain.  
> **For local dev:** use your machine's Wi-Fi IP (`ipconfig` → look for 192.168.x.x).

### 5. Build and run locally

```powershell
$env:VCPKG_ROOT = "C:\vcpkg"
$env:VCPKG_INSTALLED_ROOT = "C:\vcpkg\installed"
$d = "flutter\build\windows\x64\runner\Release"
$t = "target\release"

# Build the Rust core (needed when src/ or libs/hbb_common/ changes)
cargo build --features flutter --lib --bins --release

# Build the Flutter UI (needed when flutter/lib/ changes)
cd flutter; flutter build windows --release; cd ..

# Copy all required files to the output directory
Copy-Item "$t\librustdesk.dll","$t\service.exe","$t\naming.exe","$t\dylib_virtual_display.dll" $d -Force
Copy-Item "C:\vcpkg\installed\x64-windows-static\bin\opus.dll" $d -Force

# Launch
Start-Process "$d\rustdesk.exe" -WorkingDirectory $d
```

**When do I need to rebuild what?**

| Changed files | Rebuild needed |
|---|---|
| `src/**/*.rs` or `libs/**/*.rs` | Rust only: `cargo build --features flutter --lib --bins --release` |
| `flutter/lib/**/*.dart` | Flutter only: `flutter build windows --release` |
| Both | Rust first, then Flutter |

---

## CI/CD — GitHub Actions

The workflow file is at `.github/workflows/build.yml`.

It runs automatically on every push to `ndisafe-desk` and can also be triggered manually via **Actions → Run workflow**.

**What the pipeline does:**

1. **`generate-bridge`** (Ubuntu, ~5 min) — generates the Flutter/Rust FFI bridge files
2. **`build-windows`** (Windows 2022, ~30 min):
   - Installs LLVM, Flutter 3.24.5, Rust 1.75, vcpkg
   - Builds `librustdesk.dll` with `--features flutter`
   - Builds `service.exe` and `naming.exe`
   - Runs `flutter build windows --release`
   - Assembles everything into a portable zip with `opus.dll` and support binaries
   - Uploads artifact: **`NDISafe-Desk-1.4.9-windows-portable`**

**Trigger a build manually:**

```powershell
# Empty commit approach (no GitHub CLI login needed)
git commit --allow-empty -m "ci: trigger build"
git push origin ndisafe-desk
```

Or via GitHub UI: Actions tab → **NDISafe Desk – Windows Portable Build** → **Run workflow**.

---

## Branding

| Asset | Location | Notes |
|---|---|---|
| Logo SVG | `res/ndisafe_logo.svg` | Source of truth for all icon/logo derivatives |
| App icon (exe) | `flutter/windows/runner/resources/app_icon.ico` | 16/32/48/64/128/256px, embedded in `.exe` |
| Legacy icon | `res/icon.ico` | Used by Sciter build path |
| Flutter logo asset | `flutter/assets/logo.svg` | Shown on the main screen |
| App name | `libs/hbb_common/src/config.rs` → `APP_NAME` | `"NDISafe Desk"` |

**Color palette** (from logo SVG):

| Token | Hex | Usage |
|---|---|---|
| NDISafe Teal | `#4EB79B` | Primary accent, buttons hover, ID color |
| NDISafe Blue | `#3D5D89` | Buttons, secondary elements |
| NDISafe Navy | `#2A496E` | Deep backgrounds, canvas |
| NDISafe Dark Navy | `#1A2E42` | Dark theme canvas |

To regenerate icons after updating the logo SVG:

```powershell
# Requires: node (sharp), python (Pillow)
node C:\tmp_build2\render.js  # renders PNGs at each size

python -c "
# ... (see scripts/gen_icon.py for full script)
"
```

---

## Moving to Production

When you have a VPS ready (DigitalOcean, Hetzner, Vultr — any $5/month VPS works):

### 1. Deploy server

```bash
# On your VPS
docker run --name hbbs -p 21115-21116:21115-21116 -p 21116:21116/udp -p 21118:21118 \
  -v /opt/ndisafe-server:/root -d --restart=always rustdesk/rustdesk-server hbbs

docker run --name hbbr -p 21117:21117 -p 21119:21119 \
  -v /opt/ndisafe-server:/root -d --restart=always rustdesk/rustdesk-server hbbr

cat /opt/ndisafe-server/id_ed25519.pub
```

### 2. Update client config

In `libs/hbb_common/src/config.rs`:

```rust
pub const RENDEZVOUS_SERVERS: &[&str] = &["your.vps.domain.or.ip"];
pub const RS_PUB_KEY: &str = "your-production-public-key=";
```

### 3. Open firewall ports

| Port | Protocol | Purpose |
|---|---|---|
| 21115 | TCP | NAT test |
| 21116 | TCP + UDP | ID registration, heartbeat |
| 21117 | TCP | Relay |
| 21118 | TCP | WebSocket rendezvous |
| 21119 | TCP | WebSocket relay |

### 4. Push and rebuild

```powershell
git add libs/hbb_common/src/config.rs
git commit -m "deploy: switch to production VPS server"
git push origin ndisafe-desk
```

CI builds automatically. Download the new artifact and distribute to your team.

---

## Repository Structure

```
Ndisafe-Desk/
├── src/                    # Rust application source
│   ├── core_main.rs        # App startup, IPC, portable service
│   ├── flutter.rs          # Flutter FFI exports (rustdesk_core_main_args)
│   ├── platform/           # Windows/macOS/Linux platform code
│   └── server/             # Audio, clipboard, input, video services
├── libs/
│   ├── hbb_common/         # Config, proto, shared utils (OWNED — not a submodule)
│   │   └── src/config.rs   # ← SERVER ADDRESS and PUBLIC KEY live here
│   ├── scrap/              # Screen capture
│   ├── enigo/              # Input simulation
│   └── virtual_display/    # Virtual display driver (Windows)
├── flutter/
│   ├── lib/
│   │   ├── common.dart     # ← MyTheme colors live here
│   │   ├── desktop/        # Desktop UI pages and widgets
│   │   └── mobile/         # Mobile UI
│   ├── assets/             # Icons, SVGs, fonts
│   └── windows/runner/     # Windows runner (CMake, .rc file, icon)
├── res/
│   ├── ndisafe_logo.svg    # ← Master logo
│   └── icon.ico            # Compiled icon (auto-generated)
└── .github/workflows/
    ├── build.yml           # ← NDISafe CI (Flutter portable zip)
    └── bridge.yml          # Flutter/Rust FFI bridge generation
```

---

## Troubleshooting

**App opens to a white/blank screen**
- Another RustDesk instance from a different path is running. Kill all `rustdesk` processes and relaunch from your build directory.

**"Connection failed" or can't connect to peers**
- Check that `hbbs` and `hbbr` Docker containers are running: `docker ps`
- Verify the IP in `config.rs` matches your actual machine IP: `ipconfig` → Wi-Fi adapter
- Ensure Windows Firewall allows ports 21115–21117

**Flutter build fails with "Visual Studio 16 2019 not found"**
- You have VS Build Tools 2026 (VS18). The Flutter tool needs a patch:
  - In `C:\flutter\packages\flutter_tools\lib\src\windows\visual_studio.dart`, add `18 => 'Visual Studio 18 2026',` to the `cmakeGenerator` switch
  - Delete `C:\flutter\bin\cache\flutter_tools.snapshot` and rerun

**`scrap` build fails with "vpx/vp8.h not found"**
- `VCPKG_INSTALLED_ROOT` must point to `C:\vcpkg\installed`, **not** `C:\vcpkg\installed\x64-windows-static`. The build scripts append the triplet name themselves.

**opus.dll not found at runtime**
- Copy `C:\vcpkg\installed\x64-windows-static\bin\opus.dll` into the same directory as `rustdesk.exe`
- Or add that directory to your user PATH

---

## License

NDISafe Desk is based on [RustDesk](https://github.com/rustdesk/rustdesk) which is licensed under [AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.en.html).

All NDISafe-specific modifications are the property of Kiin Innovation.

---

<p align="center">Built by <strong>Kiin Innovation</strong></p>
