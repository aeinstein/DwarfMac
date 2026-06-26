# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
./run.sh                     # build + link VLCKit framework + run (preferred)
swift build                  # build only
swift package resolve        # fetch dependencies (downloads the VLCKit xcframework, ~large)
open Package.swift           # open in Xcode
```

**Run via `./run.sh`, not `swift run`.** VLCKit is a *dynamic* framework; `swift run` produces no .app bundle and does not embed it, so the binary fails at launch with `Library not loaded: …/Frameworks/VLCKit.framework`. `run.sh` symlinks the xcframework's macOS slice to the rpath location (`<bin>/../Frameworks/`) before running. In Xcode (which builds a bundle and embeds frameworks) this is not needed.

No test targets are defined yet. Linting (SwiftLint) is not configured.

## Architecture

**DwarfMac** is a macOS SwiftUI app that controls/monitors a Dwarf telescope device over WebSocket (`ws://192.168.88.1:9900`), using **Protobuf** messages over **binary** frames.

**Pattern**: MVVM + `@Observable` (Swift 5.9 macro, not `ObservableObject`)

**Protocol**: Every message is a protobuf `WsPacket` envelope (`major_version=1, minor_version=9, device_id=1, module_id, cmd, type, data, client_id`). The command-specific payload is itself protobuf-encoded and lives in the `data` field; `cmd` (a `DwarfCMD` code) is the discriminator. Frames are **binary**. Keepalive: send a text `"ping"` frame every 10 s; the device's app-level ping (`81 04 "ping"`) is answered with `81 04 "pong"`. Protocol reference: https://github.com/aeinstein/dwarfii_api **branch `apiV2`** — `src/proto/*.proto` (`protocol.proto` = codes/enums, `base.proto` = envelope) and `src/*.js` (message builders, `websocket_class.js` = transport) are the source of truth.

**Protobuf is hand-rolled** (`Models/ProtobufWire.swift`), not SwiftProtobuf — the messages are tiny, so there is no `protoc`/codegen step and no external dependency.

**Data flow**:
```
WebSocket binary frame (protobuf WsPacket)
  → DeviceConnection.receiveLoop() → handleIncoming() (ping/pong handled here)
  → onMessage callback
  → MessageRouter.route(data)     ← WsPacket.decode, dispatch on `cmd`
  → DeviceState (notify telemetry: battery/temp/SD)
  → SwiftUI re-renders automatically
```

**Key components**:

- `Models/ProtobufWire.swift` — minimal proto3 encoder (`ProtoWriter`) / decoder (`ProtoReader`): varint, double, bytes, string. proto3 omits zero/default fields.
- `Models/DwarfProtocol.swift` — `Module`, `MessageType`, `DwarfCmd` enums (codes from `protocol.proto`), envelope constants (`DwarfProtocol`), and `DwarfEndpoint` (WebSocket + RTSP stream URLs).
- `Models/WsPacket.swift` — envelope `encode()` / `decode(_:)`.
- `Models/DwarfCommands.swift` — `enum DwarfCommands` with static builders returning an encoded `Data` packet: motion (joystick, joystickStop), camera open/close, capture start/stop (live-stacking, record, burst, timelapse), tele-camera parameters (exposure/gain mode+index, IR-cut, white balance, brightness/contrast/hue/saturation/sharpness), focus (continuous near/far), reboot, powerDown. See **Capture & Camera** below.
- `Networking/DeviceConnection.swift` — WebSocket client (`URLSessionWebSocketTask` + delegate for real open/close state). `send(_ packet: Data)` sends a binary frame. Exponential-backoff reconnect (6 retries), `"ping"` keepalive every 10 s, German error messages in `lastError`.
- `Networking/MessageRouter.swift` — `WsPacket.decode` then dispatch on `cmd`; parses notify payloads into `DeviceState`.
- `ViewModels/DeviceState.swift` — `@Observable` telemetry (battery %, sensor/system temp, SD card).
- `Views/` — `ContentView` (root; the lower area is a `TabView` with "Steuerung" = `ControlPanel` and "Aufnahme" = `CaptureView`), `ConnectionBar`, `StatusBar` (telemetry), `ControlPanel` (speed slider + cameras/power; the D-pad "Steuerkreuz" lives in `DPadView`, overlaid on the video), `CaptureView` (capture mode/type + tele-camera parameters — see **Capture & Camera** below).
- `Video/` — `RTSPPlayerView` + `CameraPiPView` (see Video Streaming below).

**Tech stack**: Swift 5.10, SwiftUI, `URLSessionWebSocketTask`, async/await, macOS 14+. One dependency: **VLCKit** (`VLCKitSPM`) for RTSP playback. The Dwarf protobuf protocol itself is hand-rolled (no SwiftProtobuf).

## Steuerkreuz (D-pad motion)

The control cross uses the motor **joystick** command (matches the working reference in `telescope.ts`), not the discrete `stepMotorRun`:
- Press-and-hold a direction → `DwarfCommands.joystick(angle:speed:)` (`cmd 14006`, `ReqMotorServiceJoystick { double vector_angle=1; double vector_length=2 }`). Angles: up=90, right=0, down=270, left=180 (degrees, CCW). `speed`/`vector_length` ∈ 0–1 from the slider.
- Release → `DwarfCommands.joystickStop()` (`cmd 14008`, empty payload).

## Capture & Camera (`Views/CaptureView.swift`)

The "Aufnahme" tab drives image capture and the **tele** camera's parameters. Two nested
selectors plus conditional parameters; all controls send their command **immediately** on
change (live), via the same `send(_:)` Task pattern as `DPadView`. Selection + values persist
through `@AppStorage` (see Settings & Persistence).

**Hierarchy:** `Modus → (only when Allgemein) Aufnahme-Typ → conditional parameters → Start/Stop`.

- **Modus** (`enum ObservingMode`): `Allgemein / DeepSky / Sonnensystem / Milchstraße / Sternspuren`.
  Only **Allgemein** is implemented — the other four render a placeholder ("noch nicht implementiert").
- **Aufnahme-Typ** (`enum CaptureType`): `StackedFoto / Video / Serienfoto / Zeitraffer`. The
  Start/Stop button maps each type to a command pair:
  - StackedFoto → `astroStartLiveStacking` / `astroStopLiveStacking` (`cmd 11005/11006`, module `astro`)
  - Video → `teleStartRecord` / `teleStopRecord` (`10005/10006`)
  - Serienfoto → `teleBurst(count:)` / `teleStopBurst` (`10003/10004`, `ReqBurstPhoto { int32 count=1 }`)
  - Zeitraffer → `teleStartTimelapse` / `teleStopTimelapse` (`10033/10034`)

**Tele-camera parameters** (conditional on Aufnahme-Typ). Always shown:
- **Fokus** — press-and-hold near/far (`focusStartContinu(direction:)` / `focusStopContinu()`,
  `cmd 15002/15003`, module `focus`; direction 0=fern, 1=nah), same gesture pattern as the D-pad.
- **Filter** — IR-cut picker (`teleSetIrCut`, `cmd 10031`; 0=CUT/IR-Sperre, 1=PASS).
- **Belichtungszeit** — Auto/Manuell toggle (`teleSetExpMode`, `10007`) + index stepper when manual
  (`teleSetExp(index:)`, `10009`).
- **Verstärkung** — Auto/Manuell toggle (`teleSetGainMode`, `10011`) + index stepper (`teleSetGain(index:)`, `10013`).

Then **StackedFoto** adds **Anzahl** only; **all other types** add white balance + 6 image sliders:
- **Weißabgleich** — via the **PARAM module** (`DwarfCommands.paramSetWb`, cmd `16702`):
  `ReqSetWb { param_id=2, mode, value }`. Mode (WBMode) AUTO=0, **MANUAL=1** (Farbtemperatur/gear),
  **SCENE=2**. `value` = color-temp gear index (0,3,…,141 → 2800…7500 K) or scene index 0…6. UI: mode
  picker (Farbtemperatur/Szene) + value picker from `CameraParams.wbColorTemps` / `wbScenes`.
- **Helligkeit / Kontrast / Sättigung / Farbton / Schärfe** sliders — also via the **PARAM module**
  (`DwarfCommands.paramSetGeneralInt`, cmd `16703`): `ReqSetGeneralIntParam { param_id, value }`.
  **Compound param_ids (PCAP-verifiziert 2026-06-25):** Die App sendet 64-bit compound-IDs:
  `compound = 0x0101_0000_0000_0000 | (camera << 44) | paramId`, wobei camera=0 für Tele,
  camera=1 für Weitwinkel. Tatsächliche paramId-Nummern (aus Notify 15264 und Helligkeits-PCAP):
  **BRIGHTNESS=4, CONTRAST=5, SATURATION=6, HUE=7, SHARPNESS=8** — `ParamType.java` gibt 3–7 an,
  das Gerät reagiert aber nur auf 4–8. Value is the **raw** UI value (ranges from `params_config.json`):
  brightness/contrast/saturation −100…100 (default 0), hue −180…180 (default 0), sharpness 0…100
  (default 50) — equal to the slider ranges, no scaling.

  > **Device mechanism note (important, hard-won):** The **DWARF mini uses the global PARAM module**
  > (`MODULE_PARAM`, wire ordinal **15**; cmds `CMD_PARAM_SET_*` `16700`–`16706`) for image params,
  > exactly like it uses TASK_CENTER for the camera stream. Two earlier attempts were WRONG and reverted:
  > (1) the **dedicated per-param cmds** (`SET_BRIGHTNESS` `10015` / `SET_WB_*` …) — the mini *silently
  > applies* them but produces a blue image for any non-neutral value (it half-resets WB); they were
  > verified "working" only because value 0 = proto3-omitted = neutral. (2) the **tele feature-param**
  > path (`CMD_CAMERA_TELE_SET_FEATURE_PARAM` `10037`, `CommonParam`) the decompiled app's
  > `WsSetFeatureReq` uses — the mini gives **no response at all**. The phone app's sliders DO work on
  > the mini, and the app routes everything through `WsSetGeneralIntParamReq`/`WsSetWBParamReq`/… →
  > PARAM module. The mini confirms this by emitting notify `15264` (GENERAL_INT_PARAM) and `15270`
  > (NOTIFY_WB). Param value ranges are RAW (no 0…255 scaling). **Exposure/Gain/IR-cut are still on the
  > dedicated camera cmds** (verified working earlier); if they ever misbehave, move them to
  > `CMD_PARAM_SET_EXPOSURE` `16700` / `SET_GAIN` `16701` (`ReqSetExposure { param_id, mode, value }`,
  > param_id 0/1). No WB device-state mirroring (`notifyWb`→UI) — it caused a feedback-loop blue image.

**Index controls are placeholders.** Exposure/gain/WB use raw protocol *indices* (0…30), not real
seconds/dB/Kelvin labels — value tables can be added later.

**Open item — StackedFoto "Anzahl":** `ReqCaptureRawLiveStacking` (`11005`) has **no** count field,
so the WS API offers no direct way to set the stack frame count (only dark-frame capture has
`cap_size`). The `stackCount` value is currently persisted but **not sent**; wiring it would mean a
client-side auto-stop after N stacked frames (via the notify pipeline) or an astro config command if
one exists in `astro.proto`. The same `stackCount` doubles as the burst `count` for Serienfoto.

## Adding a Command

1. Add the `cmd` to `DwarfCmd` (and `Module` if needed) in `DwarfProtocol.swift` (from `protocol.proto`).
2. Add a static builder in `DwarfCommands.swift`: encode the inner payload with `ProtoWriter` (fields per `src/proto/*.proto`), wrap in `WsPacket(module:cmd:data:)`, return `.encode()`.
3. Send it via `conn.send(DwarfCommands.myCommand(...))`.

## Video Streaming (RTSP via VLCKit)

The DwarfMini streams **RTSP/H.265**, separate from the WebSocket. AVFoundation cannot play RTSP, so playback uses **VLCKit** (`VLCKitSPM` SwiftPM package). URLs in `DwarfEndpoint`:
- Telephoto: `rtsp://IP:554/ch0/stream0`
- Wide-angle: `rtsp://IP:554/ch1/stream0`

- `Video/RTSPPlayerView.swift` — `RTSPPlayer` (`@MainActor @Observable`) wraps `VLCMediaPlayer` + a `VLCVideoView` (hosted in SwiftUI via `NSViewRepresentable`). Forces RTSP-over-TCP (`:rtsp-tcp`) and low `:network-caching`. `VLCMediaPlayerDelegate.mediaPlayerStateChanged` maps state → `status`/`errorMessage`. `RTSPPlayerView` shows a title badge, placeholder, and a red error overlay.
- `Video/CameraPiPView.swift` — both cameras at once: one large, the other as a Picture-in-Picture inset; tap the inset to swap which camera is main. `ContentView` passes `ip`/`active` (active while connected).
  - **Swap = relayout, not reconnect.** Each `RTSPPlayerView` keeps a *fixed* camera URL and stable view identity (constant declaration order in the `ZStack`). `teleIsMain` only drives `frame`/`position`/`zIndex` (animated) — applied via the *same* modifier chain on both views (no `if/else`, which would create `_ConditionalContent` and lose identity → restart). So swapping never changes a `url`, never triggers `RTSPPlayerView.onChange(of: url)`, and the RTSP streams stay connected (no re-`DESCRIBE/SETUP/PLAY`).

## Settings & Persistence

- `Views/SettingsView.swift` is shown via a `Settings { }` scene in `DwarfMacApp` → standard macOS "Einstellungen…" window (⌘,).
- Persistent settings use `@AppStorage` (UserDefaults): `"deviceIP"` (default `DwarfEndpoint.defaultIP`) and `"motorSpeed"` (joystick speed). `ContentView` reads `deviceIP` and assigns `conn.host` before connecting; the RTSP URLs are derived from `conn.host` too. IP changes take effect on the next connect.
- `CaptureView` persists its selection and all tele-camera parameters via `@AppStorage`: `"observingMode"`, `"captureType"` (enum `rawValue`s), `"teleExpManual"`/`"teleExpIndex"`, `"teleGainManual"`/`"teleGainIndex"`, `"teleIrCut"`, `"stackCount"`, `"teleWbMode"`/`"teleWbIndex"`, and `"teleBrightness"`/`"teleContrast"`/`"teleHue"`/`"teleSaturation"`/`"teleSharpness"`.

## App Activation (run.sh / swift run)

`DwarfMacApp` installs an `AppDelegate` (`@NSApplicationDelegateAdaptor`) that calls `NSApp.setActivationPolicy(.regular)` + `activate(...)` on launch. Without it, a bare SwiftPM executable (no .app bundle) launches as an accessory process — **no menu bar, no Dock icon, window not focused**. Keep this when running outside Xcode.

## Connection State & Errors

`DeviceConnection` is `@MainActor @Observable` and uses `URLSessionWebSocketDelegate` for *real* open/close detection (state is `.connected` only after `didOpenWithProtocol`, not optimistically). `didCompleteWithError` drives disconnect + exponential-backoff reconnect (6 tries, 2 s base, max 30 s) and sets a human-readable German `lastError` (mapped from `URLError`), shown by `ConnectionBar`.

## Toolchain Note

SwiftUI requires the full Xcode SDK. If `swift build` fails with `unable to find utility "xctest"`, point to Xcode:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## UI Language

UI labels and code comments are in German (e.g., `"Verbinden"` = Connect, `"Steuerung"` = Control). Keep new UI strings in German for consistency.
