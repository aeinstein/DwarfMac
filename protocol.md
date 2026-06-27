# Dwarf-Protokoll — Erkenntnisse & Referenz

Gesammelte Erkenntnisse aus PCAP-Analyse, Dekompilierung der Android-App und
praktischen Tests am DWARF mini (2026-06-25/26). Gilt für Firmware-Generation
DWARF mini / Dwarf 3; ältere DWARF-II-Firmware weicht teilweise ab.

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
| `rgbPower` | 5 | 13502, 13505 |
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

## 14. Geräteerkennung (UDP-Broadcast)

```
Phone sendet UDP-Broadcast → 255.255.255.255:9900 (15-Byte Proto3):
  Field 1 (varint) = 1
  Field 2 (varint) = Unix-Timestamp in Millisekunden
  Field 3 (string) = "txtl"

Gerät antwortet per UDP-Unicast; Quell-IP = Geräte-IP.
```

Alle 1 s wiederholen, bis eine Antwort eingeht; dann Listener schließen.

---

## 15. Notify-Codes (eingehend)

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

## 16. Bekannte Fallstricke

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
