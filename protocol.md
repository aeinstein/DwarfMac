# Dwarf-Protokoll — Erkenntnisse & Referenz

Gesammelte Erkenntnisse aus PCAP-Analyse, Dekompilierung der Android-App und
praktischen Tests am DWARF mini (2026-06-25/26). Gilt für Firmware-Generation
DWARF mini / Dwarf 3; ältere DWARF-II-Firmware weicht teilweise ab.

**Externe Protokoll-Quellen (verlässlich):**
- https://github.com/aeinstein/dwarfii_api (Branch `apiV2`) — `src/proto/*.proto`, `src/*.js`.
- https://github.com/alikh31/dwarflab-sdk — TypeScript-SDK mit vollständigen Protobuf-Defs,
  310+ Befehlen über 12 Module, 38 typisierten Notify-Events und BLE-Setup
  (`proto/`, `packages/sdk/src/generated/`, `docs/`).

---

## 1. Transport

| Eigenschaft | Wert |
|---|---|
| WebSocket-URL | `ws://<IP>:9900/?client_id=<UUID>` |
| Client-ID (fest) | `0000DAF2-0000-1000-8000-00805F9B34FB` |
| Frame-Typ | **binär** (Protobuf) |
| Keepalive | Text-Frame `"ping"` alle 10 s → Antwort: `"pong"` |
| RTSP Teleobjektiv | `rtsp://<IP>:554/ch0/stream0` |
| RTSP Weitwinkel | `rtsp://<IP>:554/ch1/stream0` |

> **Wichtig – `client_id` im Query-String:** Ohne diesen Parameter behandelt das
> Gerät die Verbindung als reinen Beobachter. Notify-Pakete kommen an, aber
> Steuerbefehle wie `ENTER_CAMERA` starten den Stream nicht.

---

## 2. Paket-Envelope (WsPacket)

Jede Nachricht ist ein Protobuf-`WsPacket`:

```
WsPacket {
  uint32  major_version  = 1   // immer 1
  uint32  minor_version  = 2   // immer 9
  uint32  device_id      = 3   // immer 1
  uint32  module_id      = 4   // Modul-Ordinal (siehe §3)
  uint32  cmd            = 5   // Befehlscode (DwarfCMD)
  uint32  type           = 6   // 0=Request 1=Response 2=Notify 3=NotifyResponse
  bytes   data           = 7   // befehlsspezifischer Proto3-Payload
  string  client_id      = 8   // identisch zur URL-UUID
}
```

Das `data`-Feld enthält den tatsächlichen Payload nochmals als Proto3-kodierten
Byte-String. proto3 lässt Felder mit Default-Wert (0 / false / "") aus.

---

## 3. Module

Die App sendet als `module_id` den **Ordinal** des internen `WsModuleId`-Enums,
nicht den protocol.proto-Wert. Wegen eines zusätzlichen `MODULE_FACTORY_TEST`
(Ordinal 12) verschieben sich höhere Module. Modul 0–10 stimmen überein.

| Name | Ordinal (gesendet) | Cmd-Bereich |
|---|---|---|
| `cameraTele` | 1 | 10000–10039 |
| `cameraWide` | 2 | 12000–12035 |
| `astro` | 3 | 11000–11012 |
| `system` | 4 | 13000–13505 |
| `rgbPower` | 5 | 13500–13505 |
| `motor` | 6 | 14000–14008 |
| `focus` | 8 | 15000–15005 |
| `notify` | 9 | 15200–15295 |
| `taskCenter` | **14** | 16400–16405 |
| `param` | **15** | 16700–16703 |

---

## 4. Kamera-Stream starten (DWARF mini / Dwarf 3)

Der RTSP-Stream läuft nicht von selbst. Ablauf beim Verbindungsaufbau:

### 4.1 Verbindungsreihenfolge

```
1. WebSocket verbinden  ws://ip:9900/?client_id=UUID
2. CMD_GLOBAL_TASK_MANAGER_ENTER_CAMERA  (cmd 16404, Modul 14)
3. RTSP-Player starten (rtsp://ip:554/ch0/stream0 und ch1)
```

`openCamera` (cmd 10000 / 12000) allein ist **nicht ausreichend** — der DWARF mini
ignoriert das. Erst `ENTER_CAMERA` aktiviert den RTSP-Ausgang.

### 4.2 ENTER_CAMERA-Payload

```protobuf
// cmd 16404, Modul 14 (taskCenter)
ReqEnterCamera {
  ClientParams client_param = 3 {
    int32 encode_type = 1   // 0=H264, 1=H265 (App sendet 1)
  }
}
```

`client_param` muss **immer** gesetzt sein (auch wenn leer). Fehlt das Feld
komplett, ignoriert das Gerät den Befehl.

### 4.3 Master-Lock

Der DWARF mini akzeptiert Steuerbefehle (Parameter, Aufnahme) nur vom
„Master"-Client. Ohne Lock werden Befehle still ignoriert.

```protobuf
// cmd 13004, Modul 4 (system)
ReqsetMasterLock { bool lock = 1 }   // true = übernehmen
```

---

## 5. Bildregler (Helligkeit, Kontrast, …)

### 5.1 Warum das PARAM-Modul, nicht die dedizierten Kamera-Cmds

Es gibt drei Wege, Bildregler zu setzen — zwei davon funktionieren am DWARF mini **nicht**:

| Weg | Cmd-Bereich | Ergebnis am DWARF mini |
|---|---|---|
| Dedizierte Kamera-Cmds (`SET_BRIGHTNESS` etc.) | 10015–10023 (Tele) | Stumm angenommen, blaues Bild bei WB-Werten ≠ 0 |
| Feature-Param-Pfad (`CMD_CAMERA_TELE_SET_FEATURE_PARAM`) | 10037 | Keine Antwort, keinerlei Wirkung |
| **PARAM-Modul** (`CMD_PARAM_SET_GENERAL_INT_PARAM`) | **16703** | **Funktioniert** ✓ |

Bestätigt per PCAP (2026-06-25): Die Android-App routet alle Schieberegler über
`WsSetGeneralIntParamReq` / `WsSetWBParamReq` → PARAM-Modul. Das Gerät bestätigt
mit Notify `15264` (GENERAL_INT_PARAM) und `15270` (WB).

### 5.2 Compound param_id

```
compound_param_id = 0x0101_0000_0000_0000 | (camera << 44) | paramId

camera:   0 = Teleobjektiv
          1 = Weitwinkel

paramId:  4 = BRIGHTNESS
          5 = CONTRAST
          6 = SATURATION
          7 = HUE
          8 = SHARPNESS
```

Hinweis: `ParamType.java` aus der dekompilierten App gibt paramId 3–7 an —
das Gerät reagiert aber nur auf **4–8** (bestätigt via Notify 15264).

Beispiel Tele-Helligkeit: `0x0101_0000_0000_0004`

### 5.3 Payload (cmd 16703, Modul 15)

```protobuf
ReqSetGeneralIntParam {
  uint64 param_id = 1   // compound_id (64-bit!)
  int32  value    = 2   // Rohwert (kein 0–255-Scaling)
}
```

### 5.4 Wertebereiche

| Regler | Bereich | Default |
|---|---|---|
| Helligkeit | −100 … 100 | 0 |
| Kontrast | −100 … 100 | 0 |
| Sättigung | −100 … 100 | 0 |
| Farbton | −180 … 180 | 0 |
| Schärfe | 0 … 100 | 50 |

Die Werte werden **direkt** gesendet (gleich dem UI-Wert), kein Scaling auf 0–255.

---

## 6. Weißabgleich

Weißabgleich läuft ebenfalls über das PARAM-Modul, aber mit einem eigenen Befehl:

```protobuf
// cmd 16702, Modul 15 (param)
ReqSetWb {
  uint64 param_id = 1   // 2 (fester WB-param_id, kein compound)
  int32  mode     = 2   // 0=AUTO, 1=MANUAL (Farbtemperatur-Gear), 2=SCENE
  int32  value    = 3   // Gear-Index (Farbtemperatur) oder Szenen-Index
}
```

Farbtemperatur-Gear-Werte (`CameraParams.wbColorTemps`): Index 0 … 47 → 2800 … 7500 K.  
Szenen-Indizes (`wbScenes`): 0 … 6 (Bewölkt, Kunstlicht, usw.).

> **Achtung:** Geräteseitige WB-Notifies (cmd 15270) in den UI-State spiegeln
> verursacht eine Rückkopplungs-Schleife → blaues Bild. Kein WB-Notify-Mirroring.

---

## 7. Belichtung & Gain

Belichtung und Gain haben eigene Befehle im Kamera-Modul (nicht PARAM) —
**diese funktionieren am DWARF mini** und sind PCAP-verifiziert.

```protobuf
// Belichtungsmodus: cmd 10007 (Tele) / 12002 (Wide)
{ int32 mode = 1 }   // 0=Auto, 1=Manuell

// Belichtungs-Index: cmd 10009 (Tele) / 12004 (Wide)
{ int32 index = 1 }  // Roher Index 0…30

// Gain-Modus: cmd 10011 (Tele only; Wide hat keinen Mode-Toggle)
{ int32 mode = 1 }   // 0=Auto, 1=Manuell

// Gain-Index: cmd 10013 (Tele) / 12006 (Wide)
{ int32 index = 1 }
```

Sollte Belichtung/Gain jemals nicht mehr reagieren, wäre der Migrationspfad:
`CMD_PARAM_SET_EXPOSURE` (16700) / `CMD_PARAM_SET_GAIN` (16701) mit
`ReqSetExposure { param_id=1, mode=2, value=3 }` (param_id 0=Tele, 1=Wide).

---

## 8. IR-Cut-Filter

```protobuf
// cmd 10031, Modul 1 (cameraTele); kein Weitwinkel-Pendant
{ int32 value = 1 }   // 0=CUT (IR-Sperre), 1=PASS
```

---

## 9. Motor / Steuerkreuz (Joystick)

```protobuf
// Bewegung starten: cmd 14006, Modul 6 (motor)
ReqMotorServiceJoystick {
  double vector_angle  = 1   // Grad, CCW: 0=rechts, 90=oben, 180=links, 270=unten
  double vector_length = 2   // Geschwindigkeit 0.0 … 1.0
}

// Bewegung stoppen: cmd 14008, Modul 6 (leeres Payload)
```

Der ältere Befehl `stepMotorRun` (14000) funktioniert am DWARF mini **nicht** — nur
der Joystick-Befehl wird verarbeitet (entspricht `telescope.ts` in der Referenz-API).

---

## 10. Fokus

```protobuf
// Kontinuierlicher Fokus starten: cmd 15002, Modul 8 (focus)
{ uint32 direction = 1 }   // 0=fern, 1=nah

// Kontinuierlichen Fokus stoppen: cmd 15003 (leeres Payload)

// Einzel-Schritt: cmd 15001
{ uint32 direction = 1 }   // 0=fern, 1=nah

// Normaler Autofokus: cmd 15000
ReqNormalAutoFocus {
  uint32 mode     = 1   // 0=global, 1=Bereichs-AF
  uint32 center_x = 2   // Pixel-X; 0 bei global
  uint32 center_y = 3   // Pixel-Y; 0 bei global
}

// Astro-Autofokus: cmd 15004
ReqAstroAutoFocus { uint32 mode = 1 }   // 0=langsam, 1=schnell
```

---

## 11. Aufnahme (Telekamera)

| Aufnahme-Typ | Start-Cmd | Stop-Cmd | Payload |
|---|---|---|---|
| Einzelfoto | 10002 | — | leer |
| Live-Stacking | 11005 (Modul astro) | 11006 | leer |
| Video | 10005 | 10006 | `{ int32 encode_type=1 }` (0=H264, 1=H265) |
| Serienfoto | 10003 | 10004 | `{ int32 count=1 }` |
| Zeitraffer | 10033 | 10034 | `{ int32 interval=1; int32 count=2 }` |

Nach Live-Stacking Tele-Kamera mit `astroGoLive` (cmd 11010) zurück auf Live-Stream schalten.

Weitwinkel-Pendants: gleiche Payload-Struktur, Modul 2, Cmds im 12000er-Bereich.

---

## 12. System: Zeit, Zeitzone, Standort

Alle drei werden beim Verbinden automatisch gesendet.

```protobuf
// Zeit: cmd 13000, Modul 4
ReqSetTime {
  uint64 timestamp            = 1   // Unix-Sekunden
  int32  timezone_offset_hours = 2   // varint, z. B. 2 für UTC+2
}

// Zeitzone: cmd 13001, Modul 4
ReqSetTimeZone { string timezone_name = 1 }   // IANA, z. B. "Europe/Berlin"

// Standort: cmd 13010, Modul 4
ReqSetLocation {
  double lat    = 1   // WGS84-Dezimalgrad
  double lon    = 2
  double alt    = 3   // Meter; nur senden wenn ≠ 0
  bool   enable = 8   // immer true
}
```

> Feld `timezone_offset_hours` ist ein **varint** (int32), kein double —
> PCAP-bestätigt: die Android-App sendet `2` für UTC+2.

---

## 13. GoTo / Kalibrierung

```protobuf
// Kalibrierung starten: cmd 11000, Modul 3
ReqStartCalibration { double lon = 1; double lat = 2 }

// GoTo Deep-Sky: cmd 11002, Modul 3
ReqGotoDSO {
  double ra        = 1   // Rektaszension in STUNDEN (0–24), nicht Grad!
  double dec       = 2   // Deklination in Grad (J2000)
  string name      = 3   // Objektname
  bool   goto_only = 4   // true = nur fahren, kein Track
}

// GoTo Sonnensystem: cmd 11003, Modul 3
ReqGotoSolarSystem {
  int32  index       = 1   // 0-basiert: 0=Merkur…6=Neptun; Sonne/Mond gesondert
  double lon         = 2   // Beobachter-Längengrad
  double lat         = 3   // Beobachter-Breitengrad
  string name        = 4
  bool   force_start = 5
}

// GoTo abbrechen: cmd 11004 (leer)
```

---

## 14. RGB & Power (LED-Ring, Akkuanzeige)

Alle Befehle nutzen Modul 5 (`rgbPower`) mit **leerem Payload**.

| Cmd | Funktion |
|---|---|
| 13500 | LED-Ring einschalten |
| 13501 | LED-Ring ausschalten |
| 13502 | Gerät ausschalten |
| 13503 | Akkuanzeige am Gerät einschalten |
| 13504 | Akkuanzeige am Gerät ausschalten |
| 13505 | Gerät neu starten |

Notify `15221` (`CMD_NOTIFY_RGB_STATE`) meldet den aktuellen LED-Ring-Status zurück.

---

## 15. Teleskop-Archiv (HTTP-API Port 8082)

Das Gerät betreibt zwei HTTP-Server:

| Port | Software | Funktion |
|---|---|---|
| 80 | nginx | Dateiauslieferung: Fotos, Videos, Thumbnails |
| 8082 | libhv | REST-API für Album-Verwaltung |

### Endpunkte (POST, JSON)

```
POST http://<IP>:8082/album/list/mediaCounts
Body: {}
→ [{ "mediaType": 0, "count": 50 }, …]

POST http://<IP>:8082/album/list/mediaInfos
Body: { "mediaType": 0, "pageIndex": 0, "pageSize": 50 }
→ [{ "fileName": "…", "filePath": "/DWARF_mini/Normal_Photos/…",
     "thumbnailPath": "/DWARF_mini/Normal_Photos/Thumbnail/…",
     "fileSize": 123456, "mediaType": 1, "modificationTime": 1700000000,
     "camId": 0 }]

POST http://<IP>:8082/album/delete
Body: { "datas": [{ "mediaType": 1, "filePath": "…", "fileName": "…", "subType": 0 }] }
```

### mediaType-Werte

| Wert | Bedeutung |
|---|---|
| 0 | Alle |
| 1 | Einzelfoto |
| 2 | Video |
| 3 | Serienfoto |
| 4 | Astro (Live-Stacking) |
| 5 | Zeitraffer |

### Datei-Download

Die `filePath`-Werte aus der API (z. B. `/DWARF_mini/Normal_Photos/…`) werden
direkt über **Port 80** (nginx) ausgeliefert:

```
http://<IP>/DWARF_mini/Normal_Photos/DWARF_mini_WIDE_….jpg   → 200 OK
http://<IP>:8082/DWARF_mini/…                                → 404
```

Alternativ: anonymes FTP (Port 21, vsFTPd 3.0.5) ohne `/DWARF_mini/`-Präfix:
```
ftp://<IP>/Normal_Photos/…
ftp://<IP>/Astronomy/…
ftp://<IP>/Videos/…
```

---

## 16. BLE-Erstkonfiguration

Das Teleskop kann per Bluetooth erstmalig mit einem WLAN verbunden werden.

### BLE-Identifikation

| Eigenschaft | Wert |
|---|---|
| Gerätename-Präfix | `"DWARF"` |
| Service-UUID | `0000DAF5-0000-1000-8000-00805F9B34FB` (geräteabhängig, nicht FFE0!) |
| Characteristic UUID | `00009999-0000-1000-8000-00805F9B34FB` (Write+Notify, props=58) |

### Frame-Format

```
[0xAA, 0x01, cmd, 0x00, 0x01, 0x00, 0x00, len_hi, len_lo, <proto3-payload>, crc16_hi, crc16_lo, 0x0D]
```

- `cmd` = BLE-Befehlsbyte (siehe unten)
- `len_hi/lo` = Payload-Länge Big-Endian
- CRC16 Modbus RTU: Polynom `0xA001`, Init `0xFFFF`, über alle Bytes vor dem CRC

### BLE-Befehle

| cmd | Request | Response |
|---|---|---|
| 1 | `ReqGetconfig { cmd=1, ble_psd=2 }` | `ResGetconfig { cmd=1, code=2, …, ip=10 }` |
| 3 | `ReqSta { cmd=1, auto_start=2, ble_psd=3, ssid=4, psd=5 }` | `ResSta { cmd=1, code=2, ssid=3, psd=4, ip=5 }` |
| 5 | `ReqResetWifi {}` | — |
| 6 | `ReqGetwifilist { cmd=1 }` | `ResWifilist { cmd=1, code=2, ssid[]=4 }` |

### Fehlercode-Interpretation (ResSta)

| code | Bedeutung |
|---|---|
| 0 | Erfolgreich, IP in Feld 5 |
| -20 | Konfiguration angenommen, Gerät verbindet sich noch — Feld 3 (SSID) wird zurückgespiegelt; **kein Fehler** |
| -1, -3, -4, -8, -9, -10 | Echter Fehler (falsches Passwort, Timeout usw.) |

### Standard-BLE-Passwort

`"DWARF_12345678"` (in `bluetooth.js` der Referenz-API dokumentiert)

> **Wichtig:** `scanForPeripherals(withServices:)` mit der erwarteten Service-UUID
> filtert zu aggressiv — der DWARF mini antwortet nicht darauf. Immer `withServices: nil`
> scannen und nach Namens-Präfix `"DWARF"` filtern. Ebenso `discoverServices(nil)` statt
> mit einer festen UUID, da der Service-UUID geräteabhängig ist.

> **Wichtig:** Receive-Buffer als `[UInt8]`-Array führen, nicht als `Data`.
> `Data.removeFirst(n)` verschiebt `startIndex`, wodurch `receiveBuffer[0]` außerhalb der
> Bounds liegt und die App abstürzt.

---

## 17. Geräteerkennung (UDP-Broadcast)

```
Phone sendet UDP-Broadcast → 255.255.255.255:9900 (15-Byte Proto3):
  Field 1 (varint) = 1
  Field 2 (varint) = Unix-Timestamp in Millisekunden
  Field 3 (string) = "txtl"

Gerät antwortet per UDP-Unicast; Quell-IP = Geräte-IP.
```

Alle 1 s wiederholen, bis eine Antwort eingeht; dann Listener schließen.

---

## 18. Notify-Codes (eingehend)

Relevante Notify-Pakete, die die App auswertet:

| cmd | Inhalt |
|---|---|
| 15201 | Akkustand (`int32 battery`) |
| 15202 | Ladestatus |
| 15203 | SD-Karte (frei/gesamt in Bytes) |
| 15243 | Temperatur Werk/Motor |
| 15292 | Sensor-/CMOS-Temperatur |
| 15229 | Gerät schaltet sich aus |
| 15204/15286 | Videoaufnahme-Zeit (Sekunden) |
| 15205/15287 | Zeitraffer-Fortschritt (interval, out_time, total_time) |
| 15208 | Live-Stacking-Status (OperationState) |
| 15209 | Live-Stacking-Fortschritt (stacked_count) |
| 15218/15285 | Serienfoto-Fortschritt (total_count, completed_count) |
| 15257 | Fokusposition |
| 15264 | GENERAL_INT_PARAM geändert (Bestätigung Bildregler) |
| 15267 | Aktueller Kameramodus (nach ENTER_CAMERA) |
| 15270 | Weißabgleich-Bestätigung |
| 15279 | Normaler-Autofokus-Status |
| 15210 | Kalibrierungs-Status (AstroState + plate_solving_times) |
| 15211 | GoTo-Status (AstroState + target_name) |
| 15212 | Tracking-Status |
| 15273–15276 | Foto-/Burst-/Video-/Zeitraffer-Status (OperationState) |
| 15288 | Langzeitbelichtungs-Fortschritt (function_id, total_time, exposured_time) |

---

## 18a. Beobachtungs-Modus umschalten (Allgemein/DeepSky/…)

PCAP-verifiziert 2026-06-27. Ein Moduswechsel in der Handy-App ist **kein einzelner
Befehl**, sondern eine Transaktion über das **Task-Center-Modul (Ordinal 14)**:

| cmd | Name | Payload | Zweck |
|-----|------|---------|-------|
| **16402** | `CMD_..._SWITCH_SHOOTING_MODE` | `{ int32 mode = 1 }` | eigentlicher Moduswechsel |
| **16403** | `CMD_..._SWITCH_SHOOTING_TECH` | `{ int32 tech = 1 }` | „Shooting-Technik" (Unter-Einstellung der Foto-Modi) |
| **11039** | `CMD_ASTRO_GET_ASTRO_SHOOTING_TIME` | `{ f1=-1, f2=100, f3=100, f4=-1, f6=<mode> }` | Astro-Belichtungszeit abfragen (nur Astro-Modi) |

Bestätigung vom Gerät: Notify **15267** (`NOTIFY_SWITCH_SHOOTING_MODE`, Feld 3 = neuer
Modus) bzw. Notify **15269/15271** (Tele-/Wide-Shooting-Tech-State).

**Mode-IDs (= App-Menü-Reihenfolge, 1-basiert; den Klartext-Enum gibt es nur in der
App, nicht im apiV2-Proto):**

| Mode-ID | App-Label | Begleitbefehle beim Wechsel |
|---------|-----------|------------------------------|
| 1 | Allgemein | `switchShootingTech` (16403) |
| 2 | DeepSky | `switchShootingTech` (16403) |
| 3 | Sonnensystem | (nicht erfasst) |
| 4 | Milchstraße | `astro 11039` + Vorschau-Qualität (`cameraTele 10050`, `cameraWide 12036`) |
| 5 | Sternspuren | `astro 11039` (Astro-Zeit-Query) |
| 9 | „Foto/Normal" (Startwert, **nicht** in der Beobachtungsliste) | — |

Muster: **Foto-Modi (1/2)** lösen `SWITCH_SHOOTING_TECH` aus, **Astro-Modi (4/5)**
fragen mit `GET_ASTRO_SHOOTING_TIME` (Modus in Feld 6) die Belichtungszeit ab und
setzen die Vorschau-Qualität. Nach dem Connect stand das Gerät auf **mode 9**.
`getDeviceStateInfo` (16405) listet pro Bildparameter, in welchen Modi er gültig ist
(z. B. Param 1 → {1,3,4,5}, Param 3 → {2,3,4,5}).

> **Achtung — Szene-Mode-IDs ≠ SDK-`ShootingMode`-Enum.** Das dwarflab-sdk definiert
> `ShootingMode { PHOTO=0, VIDEO=1, ASTRO=2, PANORAMA=3 }` — das passt NICHT zu den
> hier per PCAP gemessenen Szene-IDs (1,2,4,5,9), die der DWARF mini für die App-
> Beobachtungsmodi verwendet. Die obige Tabelle (PCAP-Ground-Truth) ist maßgeblich.

**`cmd 10050` = `CAMERA_TELE_SET_PREVIEW_QUALITY`, `cmd 12036` = `CAMERA_WIDE_SET_PREVIEW_QUALITY`**
(`ReqSetPreviewQuality { uint32 level=1; uint32 quality=2 }`; Quelle: dwarflab-sdk `commands.ts`).

> **Preview-Quality aktiviert die RTP-Frame-Produktion — Pflicht für den 2. Stream
> (PCAP+Log-verifiziert 2026-06-27).** Die DwarfMini bedient ch0 (Tele) UND ch1 (Wide)
> per RTSP gleichzeitig (App: `PLAY ch0`+`PLAY ch1` → beide `200 OK`). ABER: Für eine
> Kamera liefert das Gerät nur dann tatsächlich Videoframes, wenn deren Preview-Pipeline
> via `SET_PREVIEW_QUALITY` aktiviert wurde. Ohne das verbindet die RTSP-Session zwar
> (SETUP/PLAY ok), bekommt aber keine Daten → VLC hängt in Buffering und wirft nach ~1s
> `error` (Endlos-Reconnect). Symptom: Tele läuft (Default-aktiv), **Wide nie**. Die App
> sendet nach `enterCamera` Preview-Quality für BEIDE Kameras. DwarfMac repliziert das in
> `DwarfCommands.startCameraStreams()` (enterCamera + tele/wide Preview-Quality level=1),
> aufgerufen beim Connect und im „Kameras→Starten"-Button.

**Milchstraße & Sternspuren sind reine Weitwinkel-Modi — Gerät schaltet Tele ab.**
In diesen beiden Modi bedient das Gerät den Tele-Stream (`ch0/stream0`) NICHT mehr.
Versucht der Client den Tele-Stream weiter anzuzeigen, wirkt er „nicht ansprechbar"
und Reconnects laufen ins Leere — fälschlich als „Stream kaputt, Teleskop-Neustart
nötig" interpretiert. DwarfMac schaltet Tele dort über `ObservingMode.teleActive`
inaktiv (url=nil → Player stoppt, ausgeblendet) und zeigt nur Weitwinkel groß.

**Moduswechsel stellt den RTSP-Stream um → Client muss neu verbinden.** Ein Wechsel
(v. a. Allgemein↔Astro) ändert geräteseitig den Stream; das Gerät meldet das per Notify
**15234 `NOTIFY_STREAM_TYPE`** (`StreamType { stream_type=1; cam_id=2 }`, cam_id 0=Tele,
1=Wide). Verbindet der Client den RTSP-Stream danach nicht neu (frisches
DESCRIBE/SETUP/PLAY), bleibt der alte Stream „hängen" und wirkt nicht mehr ansprechbar.
DwarfMac zählt deshalb pro Kamera einen Reload-Token hoch (`DeviceState.teleStreamReload`/
`wideStreamReload`), den `RTSPPlayerView` beobachtet und bei Änderung neu verbindet — nur
bei echtem Stream-Typ-Wechsel (Dedupe gegen Reconnect-Thrash). `cam_id` 0=Tele, 1=Wide
(dwarflab-sdk `docs/modules.md`).

PCAP-verifiziert (Zurückschalten Sternspuren→Allgemein, 2026-06-27): Beim Wechsel ändert
**Weitwinkel** seinen Stream-Typ (`notifyStreamType f1=2 f2=1` in Astro, `f1=1 f2=1` zurück)
→ Client muss Wide neu verbinden. **Tele** (cam_id 0) wird ohne Notify gestoppt → über
`teleActive` modusabhängig behandeln. Das **Zurückschalten** sendet nur
`switchShootingMode` + `switchShootingTech` (kein `enterCamera`/Preview-Quality/Kamera-
Öffnen) — das Gerät reaktiviert Tele selbst.

**Shooting-Technik (cmd 16403, `ReqSwitchShootingTech { int32 tech=1 }`)** gehört zum
**Aufnahme-Typ**, nicht zum Szene-Modus. SDK-Enum `ShootingTech`:
`SINGLE_SHOT=1, STACKING=2, BURST=3, VIDEO=4, TIMELAPSE=5, PANORAMA=6`. **Muss vor der
Aufnahme gesetzt werden** — Serienfoto (`startBurst` 10003/12023) wird sonst mit
`code:-1 PARSE_PROTOBUF_ERROR` abgelehnt. (Live-Stacking 11005 funktioniert ohne
expliziten Tech-Switch.) Bestätigung: `ResSwitchShootingTech { shooting_tech_id=2 }`
bzw. Notify 15269/15271.

---

## 19. Bekannte Fallstricke

**Blaues Bild nach WB-Befehl:** Die dedizierten WB-Cmds (10025–10029) werden vom
DWARF mini nur scheinbar übernommen — bei Werten ≠ Neutral setzt das Gerät WB intern
zurück und produziert ein blaues Bild. Immer `paramSetWb` (cmd 16702) verwenden.

**ENTER_CAMERA ohne `client_param`:** Das Feld 3 (`ClientParams`) muss immer
codiert sein, auch wenn `encode_type = 0` (proto3-Default). Leeres `data`-Feld
→ Gerät ignoriert Befehl.

**client_id in der WS-URL:** Fehlt `?client_id=...`, empfängt der Client zwar
Notifies, kann aber keine Stream-Befehle auslösen.

**RA in Stunden, nicht Grad:** `ReqGotoDSO.ra` erwartet Stunden (0–24), wie in
Astro-Katalogen üblich — kein Umrechnen auf Grad.

**Modul-Ordinal ≠ Proto-Wert:** taskCenter = Ordinal 14 (nicht 16),
param = Ordinal 15 — durch ein zusätzliches `MODULE_FACTORY_TEST` (Ordinal 12)
verschoben.

**Album-API auf Port 8082, Dateien auf Port 80:** Die API-Endpunkte
(`/album/list/…`, `/album/delete`) laufen auf Port 8082 (libhv). Die tatsächlichen
Dateipfade aus der API (`/DWARF_mini/…`) werden über Port 80 (nginx) ausgeliefert —
Port 8082 gibt für Dateipfade 404 zurück.

**BLE Service-UUID ist geräteabhängig:** Nicht `FFE0` wie in der Dokumentation
erwartet, sondern `DAF5` beim DWARF mini. `discoverServices(nil)` verwenden und den
ersten Nicht-Standard-Service (nicht `1800`/`1801`) nehmen.
