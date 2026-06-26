# DwarfMac — Umsetzungsstand

Native macOS-App (SwiftUI) zur Steuerung eines **Dwarf**-Teleskops (primär
**DwarfMini**) über WebSocket + Protobuf, mit Live-Video.

> Maßgebliche, gepflegte Doku: **`CLAUDE.md`**. Dieses Dokument hält nur den
> groben Stand und die wichtigen Abweichungen vom ursprünglichen Bauplan fest.

## Status: umgesetzt & am echten Gerät verifiziert

- [x] **WebSocket-Transport** (`DeviceConnection`) — echte Verbindungserkennung
  über `URLSessionWebSocketDelegate`, Auto-Reconnect mit Backoff, `"ping"`-
  Keepalive (+ `81 04 ping/pong`), deutsche Fehlermeldungen in der UI.
- [x] **Protobuf-Protokoll** — `WsPacket`-Envelope + befehlsspezifisches Payload.
- [x] **Steuerkreuz (D-Pad)** — Joystick-Befehl (`cmd 14006`/Stop `14008`),
  Halten = fahren, Loslassen = stoppen, Speed-Slider.
- [x] **Kameras & Power** — Tele/Weitwinkel öffnen/schließen, Neustart, Shutdown.
- [x] **Telemetrie** — Akku/Sensor-Temp/System-Temp/SD aus Notify-Meldungen
  (`StatusBar`).
- [x] **Video** — beide RTSP-Kameras gleichzeitig als **Picture-in-Picture**
  (Tausch ohne Stream-Neuaufbau), mit Fehlerausgabe je Stream.
- [x] **Einstellungen** — persistente Geräte-IP (⌘,-Fenster, `@AppStorage`).

## Wichtige Abweichungen vom ursprünglichen Plan

1. **Protobuf statt JSON, aber hand-gerollt statt SwiftProtobuf.**
   Das tatsächliche Protokoll ist Protobuf über *binäre* WS-Frames
   (`WsPacket`-Envelope). Da nur wenige, kleine Nachrichten gebraucht werden,
   gibt es einen minimalen eigenen Codec (`Models/ProtobufWire.swift`) — kein
   `protoc`/Codegen, keine SwiftProtobuf-Abhängigkeit.
   Quelle der Wahrheit: `aeinstein/dwarfii_api`, **Branch `apiV2`**
   (`src/proto/*.proto`, `src/*.js`, `websocket_class.js`).

2. **Video ist RTSP/H.265, nicht MJPEG** — abgespielt mit **VLCKit**
   (`VLCKitSPM`), da AVFoundation kein RTSP kann.
   URLs: Tele `rtsp://IP:554/ch0/stream0`, Weitwinkel `…/ch1/stream0`.

3. **Start via `./run.sh`** (nicht `swift run`): VLCKit ist ein dynamisches
   Framework, das `swift run` nicht einbettet — `run.sh` verlinkt es an die
   rpath-Stelle. Details in `CLAUDE.md`.

## Bekanntes / offen

- Akku-Notify-Mapping (`CMD_NOTIFY_ELE`) ist heuristisch (erstes Feld = %);
  bei Bedarf an einem echten Paket verifizieren.
- `device_id` ist fest 1 (DWARF II/Mini); für Dwarf 3 ggf. konfigurierbar machen.
- Weitere Befehle (Fokus, GoTo, Astro, Tracking) sind im Protokoll vorhanden,
  aber noch nicht verdrahtet.
