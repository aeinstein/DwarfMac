# DwarfMac

Eine macOS-App (SwiftUI) zum Steuern und Überwachen eines **Dwarf**-Teleskops über
WLAN. Die App verbindet sich per WebSocket mit dem Gerät und zeigt beide Kamera-Livebilder
(Teleobjektiv und Weitwinkel) als RTSP-Video an.

## Funktionsübersicht

### Verbindung & Status
- **Verbinden / Trennen** mit dem Dwarf (Standard-IP `192.168.88.1`); die Geräte-IP ist in den
  Einstellungen änderbar.
- **Statusleiste** (bei bestehender Verbindung): Akkustand, Sensor- und System-Temperatur,
  freier/gesamter SD-Karten-Speicher.
- Automatischer **Wiederverbindungsversuch** mit verständlichen deutschen Fehlermeldungen.

### Livebild
- **Zwei Kameras gleichzeitig**: eine groß, die andere als kleines Bild-im-Bild (PiP).
- **Tippen auf das kleine Bild** wechselt, welche Kamera groß angezeigt wird — die Videostreams
  bleiben dabei verbunden (kein Neuaufbau).

### Steuerung (Tab „Steuerung")
- **Steuerkreuz** (links unten halbtransparent über dem großen Video): Bewegung des Teleskops in
  alle vier Richtungen per Drücken-und-Halten, Stopp beim Loslassen.
- **Geschwindigkeit** der Bewegung per Schieberegler.
- **Kameras** starten/stoppen.
- **System**: Neustart und Herunterfahren des Geräts.

### Aufnahme & Kamera (Tab „Aufnahme")
- **Modus**: `Allgemein`, `DeepSky`, `Sonnensystem`, `Milchstraße`, `Sternspuren`.
  Aktuell ist nur **Allgemein** umgesetzt; die übrigen sind Platzhalter.
- **Aufnahme-Typ** (innerhalb von „Allgemein"):
  - **StackedFoto** – Live-Stacking (Astro-Aufnahme)
  - **Video** – Videoaufnahme
  - **Serienfoto** – Serienbild mit Bildanzahl
  - **Zeitraffer** – Zeitrafferaufnahme
- **Tele-Kamera-Parameter** (je nach Aufnahme-Typ):
  - Immer verfügbar: **Fokus** (nah/fern, Drücken-und-Halten), **Filter** (IR-Sperre/IR-Durchlass),
    **Belichtungszeit** (Auto/Manuell), **Verstärkung** (Auto/Manuell).
  - Nur bei **StackedFoto**: zusätzlich **Anzahl** (Bildanzahl).
  - Bei **Video/Serienfoto/Zeitraffer**: zusätzlich **Weißabgleich**, **Helligkeit**, **Kontrast**,
    **Farbton**, **Sättigung**, **Schärfe**.
- **Aufnahme starten/stoppen** mit einem Knopf — passend zum gewählten Aufnahme-Typ.

Alle Parameter werden **sofort beim Ändern** an das Teleskop gesendet und bleiben zwischen den
App-Starts gespeichert.

### Hinweise zum aktuellen Stand
- **Belichtung** und **Verstärkung** werden vorerst über einen **Index-Regler** eingestellt (noch
  ohne echte Sekunden-/dB-Beschriftung).
- Die **Anzahl** bei StackedFoto wird gespeichert, aber noch nicht an das Gerät übertragen — das
  Protokoll bietet dafür keinen direkten Befehl (geplant: automatischer Stopp nach N Bildern).

## Installation & Start

```bash
./run.sh        # baut, bindet das VLCKit-Framework ein und startet die App
```

> `./run.sh` verwenden (nicht `swift run`): VLCKit ist ein dynamisches Framework, das vor dem Start
> an die richtige Stelle verlinkt werden muss. In Xcode (`open Package.swift`) ist das nicht nötig.

**Voraussetzungen:** macOS 14+, das vollständige Xcode-SDK. Schlägt der Build mit
`unable to find utility "xctest"` fehl:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Technik (Kurz)

SwiftUI · MVVM mit `@Observable` · WebSocket (`URLSessionWebSocketTask`) · hand-implementiertes
Protobuf für das Dwarf-Protokoll · **VLCKit** für die RTSP-Wiedergabe. Entwicklerdetails zur
Architektur und zum Protokoll stehen in [`CLAUDE.md`](CLAUDE.md).
