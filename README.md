# DwarfMac

Eine macOS-App (SwiftUI) zum Steuern und Überwachen eines **Dwarf**-Teleskops über
WLAN. Die App verbindet sich per WebSocket mit dem Gerät und zeigt beide Kamera-Livebilder
(Teleobjektiv und Weitwinkel) als RTSP-Video an.

## Funktionsübersicht

### Verbindung & Status
- **Verbinden / Trennen** mit dem Dwarf; Geräte-IP in den Einstellungen einstellbar.
- **Automatische Geräteerkennung**: Schaltfläche „Suchen" in den Einstellungen sendet einen
  UDP-Broadcast und übernimmt die IP des antwortenden Geräts automatisch.
- **Beim Verbinden** werden automatisch Uhrzeit, Zeitzone und Beobachter-Standort (GPS oder
  manuelle Koordinaten) an das Gerät übertragen sowie der Gerätezustand abgerufen.
- **Statusleiste** (halbtransparent links oben im Video): Akkustand, Sensor- und
  Systemtemperatur, freier/gesamter SD-Karten-Speicher.
- Automatischer **Wiederverbindungsversuch** mit deutschen Fehlermeldungen.

### Livebild
- **Zwei Kameras gleichzeitig**: eine groß, die andere als kleines Bild-im-Bild (PiP).
- **Tippen auf das kleine Bild** wechselt, welche Kamera groß angezeigt wird — die
  Videostreams bleiben dabei verbunden (kein Neuaufbau).
- **Tele-FoV-Overlay**: ein grünes Rechteck auf dem Weitwinkel-Stream markiert den
  Bildausschnitt der Telekamera (Position und Größe per Messung kalibriert und hardcodiert).
- **Aufnahme-Status-Leiste** (oben mittig über dem Video): zeigt laufende Aufnahme,
  Belichtungsfortschritt und Geräte-Fehlermeldungen aus den Notify-Paketen.

### Steuerung
- **Steuerkreuz** (links unten halbtransparent über dem Video): Bewegung des Teleskops in
  alle vier Richtungen per Drücken-und-Halten, Stopp beim Loslassen.
- **Cursor-Tasten**: steuern das Teleskop identisch zum D-Pad (gleiche Rampen-Logik,
  funktioniert ohne Fokus auf einer bestimmten Schaltfläche).
- **Gamepad-Steuerung** (USB/Bluetooth): der linke Analogstick steuert den Joystick-Befehl;
  D-Pad als Fallback. Deadzone und Maximalgeschwindigkeit sind in den Einstellungen konfigurierbar.
- **GoTo** (Knopf in der Verbindungsleiste): Astro-Objekte nach Name oder Katalognummer suchen
  (Planeten, Sterne, Nebel, Galaxien, Kugelsternhaufen, Mond/Sonne) und das Teleskop automatisch
  ausrichten. Benötigt Beobachter-Standort (GPS mit Vorrang, sonst manuelle Koordinaten).

### Aufnahme & Kamera
- **Kamera-Kontrollleiste** (unter der Verbindungsleiste): Stream starten/stoppen und
  Aufnahme-Typ wählen — direkt erreichbar ohne Tabs.
- **Aufnahme-Typ**:
  - **StackedFoto** – Live-Stacking (Astro-Langzeitbelichtung)
  - **Video** – Videoaufnahme
  - **Serienfoto** – Serienbild mit einstellbarer Bildanzahl
  - **Zeitraffer** – Zeitraffer mit Intervall und Bildanzahl
- **Großer Aufnahme-Knopf** (rechts mittig über dem Video): startet und stoppt die aktuelle
  Aufnahme.
- **Bildeinstellungen** (Icon oben rechts über dem Video, klappt zum Panel auf):
  - Fokus (nah/fern, Drücken-und-Halten)
  - Filter (IR-Sperre / IR-Durchlass)
  - Belichtungszeit und Verstärkung (Auto/Manuell + Index)
  - Weißabgleich (Farbtemperatur oder Szene)
  - Helligkeit, Kontrast, Sättigung, Farbton, Schärfe

Alle Parameter werden **sofort beim Ändern** an das Teleskop gesendet und zwischen
App-Starts gespeichert.

### Teleskop-Archiv
- **Archiv-Schaltfläche** (neben der Kamera-Kontrollleiste, nur wenn verbunden): öffnet das
  Teleskop-Archiv.
- **Thumbnail-Raster** mit Filter nach Medientyp (Alle / Fotos / Videos / Serienfoto /
  Astro / Zeitraffer) und automatischem Nachladen beim Scrollen.
- **Detailansicht**: Vorschau, Dateiinfos (Größe, Datum, Kamera), Herunterladen via
  Speichern-Dialog, Löschen direkt vom Gerät.
- Zugriff über HTTP-API (Port 8082), Dateiauslieferung über Port 80 (nginx auf dem Gerät).

### BLE-Erstkonfiguration
- **BLE-Einrichtung** (in Einstellungen, Schaltfläche „BLE-Einrichtung…"): scannt nach
  Dwarf-Geräten per Bluetooth, überträgt WLAN-Zugangsdaten (SSID + Passwort) ans Teleskop
  und erkennt die zugewiesene IP automatisch per UDP-Broadcast.
- Geführter 4-Schritt-Flow: Gerät scannen → WLAN wählen → Konfiguration senden →
  IP übernehmen.

### RGB & Power
- **LED-Ring** ein-/ausschalten über das App-Menü.
- **Akkuanzeige** am Gerät ein-/ausschalten über das App-Menü.
- **Neustart** und **Ausschalten** ebenfalls im App-Menü.

### Einstellungen (⌘,)
- **Verbindung**: Geräte-IP manuell eingeben oder per UDP-Broadcast automatisch suchen.
- **BLE-Einrichtung**: Teleskop per Bluetooth erstmalig mit WLAN verbinden.
- **Beobachter-Standort**: Breiten-/Längengrad für GoTo und Kalibrierung (GPS hat Vorrang).
- **Gamepad**: Deadzone (Standard 15 %) und Maximalgeschwindigkeit (Standard 50 %).
- **Zeitzone**: zeigt die Systemzeitzone — wird beim Verbinden automatisch übertragen.

### Hinweise zum aktuellen Stand
- Belichtung und Verstärkung werden über einen **Index-Regler** eingestellt (keine
  Echtzeit-Beschriftung in Sekunden/dB).
- Die **Anzahl** bei StackedFoto wird gespeichert, aber noch nicht an das Gerät übertragen
  (das Protokoll bietet keinen direkten Befehl; geplant: automatischer Stopp nach N Frames).

## Installation & Start

```bash
./run.sh        # baut, bindet das VLCKit-Framework ein und startet die App
```

> `./run.sh` verwenden (nicht `swift run`): VLCKit ist ein dynamisches Framework, das vor dem
> Start an die richtige Stelle verlinkt werden muss. In Xcode (`open Package.swift`) ist das
> nicht nötig.

**Voraussetzungen:** macOS 14+, vollständiges Xcode-SDK. Schlägt der Build mit
`unable to find utility "xctest"` fehl:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Technik (Kurz)

SwiftUI · MVVM mit `@Observable` · WebSocket (`URLSessionWebSocketTask`) · hand-implementiertes
Protobuf für das Dwarf-Protokoll · **VLCKit** für die RTSP-Wiedergabe ·
**GameController.framework** für Gamepad · **CoreLocation** für GPS ·
**CoreBluetooth** für BLE-Erstkonfiguration ·
**SQLite3** für die Astro-Objekt-Datenbank (GoTo). Entwicklerdetails zur Architektur und
zum Protokoll stehen in [`CLAUDE.md`](CLAUDE.md).
