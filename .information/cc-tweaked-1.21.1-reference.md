# CC:Tweaked 1.21.1 — Agenten-Nachschlagewerk

Referenz für einen KI-Agenten, der Lua-Programme für CC:Tweaked auf Minecraft 1.21.1 schreibt, inklusive Create, CC:C Bridge und Simple Storage Network. Ziel ist, Websuchen überflüssig zu machen.

**Konventionen in diesem Dokument**
* `name(arg [, optional])` = Lua-Signatur. `?` hinter einem Typ heißt optional/nillable.
* Rückgaben als Liste = mehrere Rückgabewerte.
* Abschnitte mit **[UNSICHER]** sind versionsabhängig und sollten im Spiel verifiziert werden (`peripheral.getMethods(name)`).

---

## 0. Versionsmatrix und Grundannahmen

| Komponente | Stand für MC 1.21.1 | Hinweis |
|---|---|---|
| CC:Tweaked | 1.115 bis 1.120.x | Loader: NeoForge, Forge, Fabric. Ab 1.114 nicht mehr auf CurseForge, Bezug über Modrinth. |
| Create | 6.x (Create 6 alias 0.6/6.0) | Bringt eigene CC-Peripherie mit, **kein** Addon nötig. |
| CC:C Bridge | v1.7.2+ (NeoForge) | Ab v1.7.1 Create-6-kompatibel. Für 1.21.1 nur NeoForge-Builds. |
| Simple Storage Network | siehe Abschnitt 11 | Offizielle 1.21.1-Unterstützung ist wackelig, es existieren Community-Ports. Kein CC-API. |

**Wichtige Neuerung ab CC:T 1.114:** Der Block **Redstone Relay** (`redstone_relay`) existiert nativ. Er ersetzt funktional den RedRouter der CC:C Bridge und beherrscht zusätzlich Bundled Cables.

**Lua-Dialekt:** Lua 5.2-Subset (Cobalt-VM). Kein `goto`-Label-Verhalten wie 5.4, kein Integer/Float-Split, `setfenv`/`getfenv`/`loadstring` sind je nach Config abgeschaltet (`disable_lua51_features`). Verfügbar sind Coroutines, Metatables, `bit32`, `utf8` teilweise.

**Ausführungsmodell:** Jeder Computer ist eine Coroutine. Jede Funktion, die wartet (`os.pullEvent`, `sleep`, `read`, `rednet.receive`), yieldet. Ein Programm ohne Yield für mehrere Sekunden führt zu "Too long without yielding" und Abbruch.

---

## 1. Blöcke und Items der Mod

### 1.1 Computer
| Block | ID | Eigenschaften |
|---|---|---|
| Computer | `computercraft:computer_normal` | 51x19 Terminal, 16 Graustufen-Palette faktisch monochrom (`term.isColor() == false`) |
| Advanced Computer | `computercraft:computer_advanced` | Volle 16 Farben, Maus-Events (`mouse_click`, `mouse_scroll`, `mouse_drag`, `mouse_up`) |
| Command Computer | `computercraft:computer_command` | Nur Kreativ/OP. Aktiviert die `commands`-API. |

Rechtsklick öffnet das Terminal. Redstone-Signal an eine beliebige Seite schaltet den Computer ein. Shift-Rechtsklick platziert ohne GUI.

### 1.2 Turtles
| Block | ID |
|---|---|
| Turtle | `computercraft:turtle_normal` |
| Advanced Turtle | `computercraft:turtle_advanced` |

Turtles haben 16 Inventarslots und die `turtle`-API. Upgrades werden links und rechts angebracht (`turtle.equipLeft()` / `turtle.equipRight()` mit dem Item im aktuell gewählten Slot).

**Standard-Upgrades**
* Diamond Pickaxe → Werkzeug für `turtle.dig*`
* Diamond Axe, Shovel, Hoe, Sword → jeweils passende Blöcke/Angriff
* Crafting Table → aktiviert `turtle.craft([limit])`
* Wireless Modem → `peripheral.wrap("left"/"right")`, ermöglicht `rednet`
* Speaker, weitere Peripherie je nach Version

Treibstoff: alles mit Brennwert (`turtle.refuel([count])`). Jede Bewegung kostet 1 Fuel. Graben/Drehen kostet nichts. `need_fuel = false` in der Config schaltet Treibstoff ab, dann liefert `turtle.getFuelLevel()` den String `"unlimited"`.

### 1.3 Pocket Computer
`computercraft:pocket_computer_normal` / `_advanced`. Item, kein Block. 26x20 Terminal. Upgrade im Rücken-Slot (`pocket.equipBack()` / `pocket.unequipBack()`), typisch Wireless Modem oder Speaker.

### 1.4 Monitore
| Block | ID |
|---|---|
| Monitor | `computercraft:monitor_normal` |
| Advanced Monitor | `computercraft:monitor_advanced` |

Monitore verbinden sich automatisch zu Rechtecken bis 8x6 Blöcke. Nur der Advanced Monitor kann Farben und Maus (`monitor_touch`). Textskalierung `setTextScale(0.5 .. 5.0)` in 0.5-Schritten. Ein Monitorverbund erscheint als **ein** Peripheriegerät.

Anbindung: direkt anliegend an den Computer oder über Wired Modem plus Networking Cable.

### 1.5 Modems und Kabel
| Block | ID | Funktion |
|---|---|---|
| Wireless Modem | `computercraft:wireless_modem_normal` | Reichweite abhängig von Höhe und Wetter, Standard 64 Blöcke |
| Ender Modem | `computercraft:wireless_modem_advanced` | Unbegrenzte Reichweite, dimensionsübergreifend |
| Wired Modem | `computercraft:wired_modem` | Voller Block |
| Wired Modem (flach) | `computercraft:cable` (Modemteil) | Auf Blockfläche geklebt |
| Networking Cable | `computercraft:cable` | Verbindet Wired Modems |

**Kabelnetz-Mechanik (wichtig)**
1. Wired Modem an das Zielgerät (Kiste, Monitor, Create-Block) anlegen.
2. Rechtsklick auf das Modem aktiviert es. Es meldet im Chat den vergebenen Peripherienamen, z. B. `minecraft:chest_3`.
3. Kabel zum Computer ziehen, dort ebenfalls ein Modem anbringen und aktivieren.
4. Im Programm: `peripheral.wrap("minecraft:chest_3")` oder `peripheral.find("inventory")`.

Ein Computer sieht über das Kabelnetz **alle** aktivierten Peripheriegeräte. Der Name ist stabil, solange das Modem nicht deaktiviert und neu aktiviert wird. Item-Transfer zwischen zwei Inventaren im selben Kabelnetz geht über `pushItems` / `pullItems` ohne Entfernungslimit.

### 1.6 Weitere Blöcke
| Block | ID | Peripherietyp |
|---|---|---|
| Disk Drive | `computercraft:disk_drive` | `drive` |
| Printer | `computercraft:printer` | `printer` |
| Speaker | `computercraft:speaker` | `speaker` |
| Redstone Relay | `computercraft:redstone_relay` | `redstone_relay` |

Items: Floppy Disk (`computercraft:disk`, 125 kB, einfärbbar), Printed Page/Pages/Book, Treasure Disk.

---

## 2. Peripherie-Konzept

Seitenbezeichner für direkt anliegende Peripherie: `"top"`, `"bottom"`, `"left"`, `"right"`, `"front"`, `"back"`. Links/rechts sind relativ zur Blickrichtung des Computers, nicht des Spielers.

```lua
local m = peripheral.wrap("right")                 -- feste Seite
local m = peripheral.find("monitor")               -- erstes Gerät des Typs
local all = { peripheral.find("monitor") }         -- alle Geräte des Typs
local names = peripheral.getNames()                -- alle sichtbaren Namen
print(peripheral.getType("right"))
print(textutils.serialize(peripheral.getMethods("right")))
```

`peripheral.find(type [, filter])` ruft `filter(name, wrapped)` auf und übernimmt nur Geräte, für die der Filter wahr ist.

**Generische Peripherie** ist die zentrale Mechanik für Fremdmod-Kompatibilität. Jeder Block mit einem Item-, Fluid- oder Energie-Handler bekommt automatisch die Typen `inventory`, `fluid_storage` bzw. `energy_storage`. Das gilt auch für Create-Vaults, Barrels, Öfen und viele SSN-Blöcke. Ein Gerät kann mehrere Typen haben, prüfbar mit `peripheral.hasType(name, "inventory")`.

---

## 3. Lua-Umgebung und Programmstruktur

### 3.1 Dateisystem
* `/rom` ist schreibgeschützt und enthält Standardprogramme und APIs.
* `/` ist der beschreibbare Bereich des Computers (`/disk`, `/disk1` ... für Floppies).
* `startup.lua` oder Ordner `startup/` wird beim Booten ausgeführt. Bei Floppy im Laufwerk läuft deren `startup` zuerst.

### 3.2 Event-Loop-Muster
```lua
while true do
  local e, p1, p2, p3 = os.pullEvent()
  if e == "redstone" then
    -- ...
  elseif e == "terminate" then
    break
  end
end
```
`os.pullEvent` wirft bei Strg+T eine `terminate`-Exception. `os.pullEventRaw` liefert stattdessen das Event `"terminate"` und erlaubt sauberes Aufräumen.

### 3.3 Nebenläufigkeit
```lua
parallel.waitForAny(f1, f2)   -- endet, sobald eine Funktion endet
parallel.waitForAll(f1, f2)   -- endet, wenn alle enden
```
Es gibt kein echtes Multithreading. Jede Funktion läuft als Coroutine und muss yielden.

---

## 4. Globale APIs (vollständig)

### 4.1 `os`
| Funktion | Beschreibung |
|---|---|
| `os.version()` | z. B. `"CraftOS 1.9"` |
| `os.getComputerID()` / `os.computerID()` | numerische ID |
| `os.getComputerLabel()` / `os.computerLabel()` | Label oder `nil` |
| `os.setComputerLabel([label])` | `nil` löscht das Label |
| `os.run(env, path, ...)` | Programm in eigener Umgebung ausführen |
| `os.pullEvent([filter])` | Event holen, wirft bei `terminate` |
| `os.pullEventRaw([filter])` | Event holen, `terminate` als normales Event |
| `os.queueEvent(name, ...)` | eigenes Event in die Queue |
| `os.startTimer(sec)` → `id` | löst später `timer`-Event aus |
| `os.cancelTimer(id)` | |
| `os.setAlarm(time)` → `id` | `time` als Ingame-Stunde 0..24, löst `alarm` aus |
| `os.cancelAlarm(id)` | |
| `os.sleep(sec)` / global `sleep(sec)` | |
| `os.time([locale])` | `locale`: `"ingame"` (Standard), `"utc"`, `"local"` |
| `os.day([locale])` | |
| `os.epoch([locale])` | Millisekunden |
| `os.clock()` | CPU-Zeit des Computers in Sekunden |
| `os.date([format [, time]])` | wie C `strftime`, `"*t"` liefert Tabelle, `"!"`-Präfix = UTC |
| `os.shutdown()` / `os.reboot()` | |

### 4.2 `term`
`write(text)`, `blit(text, textColours, backColours)`, `clear()`, `clearLine()`, `getCursorPos()` → x,y, `setCursorPos(x, y)`, `getCursorBlink()`, `setCursorBlink(bool)`, `getSize()` → w,h, `scroll(n)`, `isColor()` / `isColour()`, `setTextColour(c)`, `getTextColour()`, `setBackgroundColour(c)`, `getBackgroundColour()`, `setPaletteColour(index, hexRGB)` oder `(index, r, g, b)`, `getPaletteColour(index)`, `nativePaletteColour(c)`, `redirect(target)` → vorheriges Ziel, `current()`, `native()`.

`blit` erwartet drei gleich lange Strings. Farbzeichen sind Hex `0`..`f` gemäß `colors.toBlit(colour)`.

```lua
term.blit("Hello", "01234", "fffff")
```

Umleitung auf einen Monitor:
```lua
local mon = peripheral.find("monitor")
local old = term.redirect(mon)
print("auf dem Monitor")
term.redirect(old)
```

### 4.3 `fs`
`list(path)`, `exists(path)`, `isDir(path)`, `isReadOnly(path)`, `getSize(path)`, `getFreeSpace(path)`, `getCapacity(path)`, `makeDir(path)`, `move(from, to)`, `copy(from, to)`, `delete(path)`, `combine(base, ...)`, `getName(path)`, `getDir(path)`, `getDrive(path)`, `find(pattern)` (Wildcard `*`), `complete(partial, path [, includeFiles [, includeDirs]])`, `attributes(path)` → `{size, isDir, isReadOnly, created, modified}`, `isDriveRoot(path)`, `open(path, mode)`.

Modi: `"r"`, `"w"`, `"a"`, `"rb"`, `"wb"`, `"ab"`, `"r+"`, `"w+"`.

Handle-Methoden: `read([count])`, `readLine([withTrailing])`, `readAll()`, `write(data)`, `writeLine(data)`, `flush()`, `close()`, `seek([whence [, offset]])` (nur Binärmodus, `whence` = `"set"`, `"cur"`, `"end"`).

### 4.4 `peripheral`
`isPresent(name)`, `getType(name|wrapped)`, `hasType(name|wrapped, type)`, `getMethods(name)`, `getName(wrapped)`, `call(name, method, ...)`, `wrap(name)`, `find(type [, filter])`, `getNames()`.

### 4.5 `redstone` (alias `rs`)
`getSides()`, `setOutput(side, on)`, `getOutput(side)`, `getInput(side)`, `setAnalogOutput(side, 0..15)` (alias `setAnalogueOutput`), `getAnalogOutput(side)`, `getAnalogInput(side)`, `setBundledOutput(side, colourMask)`, `getBundledOutput(side)`, `getBundledInput(side)`, `testBundledInput(side, colourMask)`.

Bundled Cables benötigen einen Mod, der sie bereitstellt (Project Red, More Red). Ohne solchen Mod sind die Bundled-Funktionen wirkungslos.

### 4.6 `rednet`
Aufsatz auf Modems mit Adressierung per Computer-ID.

`open(side|name)`, `close([side])`, `isOpen([side])`, `send(recipientID, message [, protocol])`, `broadcast(message [, protocol])`, `receive([protocolFilter] [, timeout])` → `senderID, message, protocol`, `host(protocol, hostname)`, `unhost(protocol)`, `lookup(protocol [, hostname])`.

Konstanten: `CHANNEL_BROADCAST = 65535`, `CHANNEL_REPEAT = 65533`, `MAX_ID_CHANNELS = 65536`.

`message` darf jede serialisierbare Lua-Struktur sein (keine Funktionen, keine Metatables).

### 4.7 `modem` (Peripherie, roher Kanal-Layer)
`open(channel)`, `isOpen(channel)`, `close(channel)`, `closeAll()`, `transmit(channel, replyChannel, message)`, `isWireless()`.
Zusätzlich nur bei Wired Modems: `getNamesRemote()`, `isPresentRemote(name)`, `getTypeRemote(name)`, `hasTypeRemote(name, type)`, `getMethodsRemote(name)`, `callRemote(name, method, ...)`, `getNameLocal()`.

Kanäle 0..65535. Empfang erzeugt `modem_message`.

### 4.8 `gps`
`gps.locate([timeout = 2] [, debug])` → `x, y, z` oder `nil`. Benötigt vier Host-Computer in Reichweite, die `gps host` laufen lassen. `gps.CHANNEL_GPS = 65534`.

### 4.9 `disk`
`isPresent(name)`, `hasData(name)`, `getMountPath(name)`, `setLabel(name, label)`, `getLabel(name)`, `getID(name)`, `hasAudio(name)`, `getAudioTitle(name)`, `playAudio(name)`, `stopAudio(name)`, `eject(name)`.

### 4.10 `settings`
`define(name, options)`, `undefine(name)`, `set(name, value)`, `unset(name)`, `get(name [, default])`, `getDetails(name)`, `clear()`, `getNames()`, `load([path = ".settings"])`, `save([path = ".settings"])`.

Nützliche eingebaute Settings: `shell.allow_disk_startup`, `shell.autocomplete`, `motd.enable`, `bios.use_multishell`, `list.show_hidden`, `edit.autocomplete`.

### 4.11 `textutils`
`slowWrite(text [, rate])`, `slowPrint(text [, rate])`, `formatTime(time [, twentyFourHour])`, `pagedPrint(text [, freeLines])`, `tabulate(...)`, `pagedTabulate(...)`, `serialize(t [, opts])` / `serialise`, `unserialize(s)` / `unserialise`, `serializeJSON(t [, opts])`, `unserializeJSON(s [, opts])`, `urlEncode(s)`, `complete(partial [, env])`.
Marker: `textutils.empty_json_array`, `textutils.json_null`.

`serialize`-Optionen: `{ compact = true, allow_repetitions = true }`.
`unserializeJSON`-Optionen: `{ nbt_style = true, parse_null = true, parse_empty_array = true }`.

### 4.12 `colors` (alias `colours`)
Bitmaskenwerte: `white=1`, `orange=2`, `magenta=4`, `lightBlue=8`, `yellow=16`, `lime=32`, `pink=64`, `gray=128`, `lightGray=256`, `cyan=512`, `purple=1024`, `blue=2048`, `brown=4096`, `green=8192`, `red=16384`, `black=32768`.

`combine(...)`, `subtract(mask, ...)`, `test(mask, colour)`, `packRGB(r,g,b)`, `unpackRGB(rgb)`, `toBlit(colour)`.

### 4.13 `keys`
`keys.getName(code)` und Konstanten (`keys.enter`, `keys.space`, `keys.leftCtrl`, `keys.up`, `keys.f1` ...). Events `key` und `key_up` liefern den Code, `char` liefert das Zeichen.

### 4.14 `paintutils`
`parseImage(data)`, `loadImage(path)`, `drawPixel(x, y [, colour])`, `drawLine(x1,y1,x2,y2 [, colour])`, `drawBox(x1,y1,x2,y2 [, colour])`, `drawFilledBox(...)`, `drawImage(image, x, y)`.

### 4.15 `window`
`window.create(parent, x, y, width, height [, visible])` → Terminalobjekt mit allen `term`-Methoden plus `setVisible(bool)`, `isVisible()`, `redraw()`, `restoreCursor()`, `getPosition()`, `reposition(x, y [, w, h [, parent]])`, `getLine(y)` → `text, textColours, backColours`.

Muster für flimmerfreies Zeichnen: `win.setVisible(false)` → zeichnen → `win.setVisible(true)`.

### 4.16 `vector`
`vector.new(x, y, z)`. Methoden `add`, `sub`, `mul`, `div`, `unm`, `dot(o)`, `cross(o)`, `length()`, `normalize()`, `round([tolerance])`, `tostring()`, `equals(o)`. Operatoren `+ - * /` und unäres Minus sind überladen.

### 4.17 `parallel`
`waitForAny(...)`, `waitForAll(...)`.

### 4.18 `http`
`http.get(url [, headers [, binary]])` oder `http.get{url=, headers=, binary=, method=, redirect=, timeout=}`
`http.post(url, body [, headers [, binary]])` oder Tabellenform
`http.request(...)` asynchron, liefert `http_success` / `http_failure`
`http.checkURL(url)`, `http.checkURLAsync(url)`
`http.websocket(url [, headers])`, `http.websocketAsync(url [, headers])`

Response-Handle: alle Lesemethoden von `fs`-Handles plus `getResponseCode()` → `code, statusText` und `getResponseHeaders()`.
WebSocket-Handle: `send(msg [, binary])`, `receive([timeout])`, `close()`.

HTTP muss serverseitig aktiviert und die Domain per Allowlist erlaubt sein.

### 4.19 `shell` (nur im Shell-Kontext)
`exit()`, `dir()`, `setDir(d)`, `path()`, `setPath(p)`, `resolve(path)`, `resolveProgram(name)`, `programs([includeHidden])`, `complete(line)`, `completeProgram(prog)`, `setCompletionFunction(prog, fn)`, `getCompletionInfo()`, `getRunningProgram()`, `run(...)`, `execute(cmd, ...)`, `openTab(...)`, `switchTab(id)`, `aliases()`, `setAlias(alias, prog)`, `clearAlias(alias)`.

### 4.20 `multishell`
`getCurrent()`, `getCount()`, `launch(env, path, ...)`, `setTitle(id, title)`, `getTitle(id)`, `setFocus(id)`, `getFocus()`.

### 4.21 `turtle`
**Bewegung:** `forward()`, `back()`, `up()`, `down()`, `turnLeft()`, `turnRight()`
**Abbau:** `dig([side])`, `digUp([side])`, `digDown([side])` (`side` = `"left"`/`"right"`, wählt das Werkzeug)
**Platzieren:** `place([text])`, `placeUp([text])`, `placeDown([text])`
**Inventar:** `select(slot)`, `getSelectedSlot()`, `getItemCount([slot])`, `getItemSpace([slot])`, `getItemDetail([slot [, detailed]])`, `transferTo(slot [, count])`, `compareTo(slot)`
**Weltinteraktion:** `detect()`, `detectUp()`, `detectDown()`, `compare()`, `compareUp()`, `compareDown()`, `inspect()`, `inspectUp()`, `inspectDown()` → `bool, table|string`
**Items:** `drop([count])`, `dropUp`, `dropDown`, `suck([count])`, `suckUp`, `suckDown`
**Kampf:** `attack([side])`, `attackUp`, `attackDown`
**Treibstoff:** `refuel([count])`, `getFuelLevel()`, `getFuelLimit()`
**Upgrades:** `equipLeft()`, `equipRight()`
**Crafting:** `craft([limit])` nur mit Crafting-Table-Upgrade. Rezeptmuster liegt in den Slots 1-3, 5-7, 9-11.

Alle Aktionsfunktionen geben `true` oder `false, reason` zurück. Inventaränderungen erzeugen `turtle_inventory`.

### 4.22 `pocket`
`equipBack()`, `unequipBack()`.

### 4.23 `commands` (nur Command Computer)
`exec(cmd)` → `success, output(table), affected?`, `execAsync(cmd)` → `taskID` (Ergebnis via `task_complete`), `list([...])`, `getBlockPosition()` → x,y,z, `getBlockInfo(x, y, z [, dimension])`, `getBlockInfos(x1,y1,z1,x2,y2,z2 [, dimension])`.
`commands.<name>(...)` ruft den Befehl direkt auf, z. B. `commands.say("hi")`. `commands.async.<name>(...)` asynchron.

### 4.24 `cc.*`-Module (via `require`)
```lua
local expect = require("cc.expect").expect
```
| Modul | Inhalt |
|---|---|
| `cc.expect` | `expect(index, value, ...types)`, `field(tbl, key, ...types)`, `range(num [, min [, max]])` |
| `cc.strings` | `wrap(text [, width])`, `ensure_width(text [, width])`, `split(str, sep [, plain [, limit]])` |
| `cc.pretty` | `pretty(obj)`, `render(doc [, width])`, `write(doc)`, `print(doc)`, `pretty_print(obj)`, Kombinatoren `text`, `concat`, `group`, `nest`, `space`, `line` |
| `cc.require` | `make(env, dir)` erzeugt ein eigenes `require` |
| `cc.image.nft` | `parse(str)`, `load(path)`, `draw(image, x, y [, term])` |
| `cc.audio.dfpwm` | `make_encoder()`, `make_decoder()`, `encode(input)`, `decode(input)` |
| `cc.shell.completion` | `file`, `dir`, `dirOrFile`, `program`, `programWithArgs`, `peripheral`, `setting`, `command`, `choice`, `build` |
| `cc.completion` | `choice(text, choices [, add_space])`, `peripheral`, `side`, `setting` |

---

## 5. Events (vollständig)

| Event | Parameter |
|---|---|
| `alarm` | `id` |
| `char` | `character` |
| `computer_command` | `...args` (von `/computercraft queue`) |
| `disk` | `driveName` |
| `disk_eject` | `driveName` |
| `file_transfer` | `TransferredFiles`-Objekt mit `getFiles()` |
| `http_check` | `url, success, reason?` |
| `http_failure` | `url, reason, handle?` |
| `http_success` | `url, handle` |
| `key` | `keycode, isHeld` |
| `key_up` | `keycode` |
| `modem_message` | `side, channel, replyChannel, message, distance?` |
| `monitor_resize` | `monitorName` |
| `monitor_touch` | `monitorName, x, y` |
| `mouse_click` | `button (1 links, 2 rechts, 3 mitte), x, y` |
| `mouse_drag` | `button, x, y` |
| `mouse_scroll` | `direction (-1 hoch, 1 runter), x, y` |
| `mouse_up` | `button, x, y` |
| `paste` | `text` |
| `peripheral` | `name` (angeschlossen) |
| `peripheral_detach` | `name` |
| `rednet_message` | `senderID, message, protocol?` |
| `redstone` | keine |
| `speaker_audio_empty` | `speakerName` |
| `task_complete` | `taskID, success, error?|...results` |
| `term_resize` | keine |
| `terminate` | keine |
| `timer` | `id` |
| `turtle_inventory` | keine |
| `websocket_closed` | `url, reason?, code?` |
| `websocket_failure` | `url, reason` |
| `websocket_message` | `url, message, isBinary` |
| `websocket_success` | `url, handle` |

Peripherie von Fremdmods (Create, CC:C Bridge) fügt weitere Events hinzu, siehe Abschnitte 8 bis 10.

---

## 6. Eingebaute Peripherie-Typen

### 6.1 `monitor`
Alle `term`-Methoden plus `setTextScale(scale)` und `getTextScale()`. Skalen 0.5 bis 5.0 in 0.5-Schritten. Events: `monitor_touch` (nur Advanced), `monitor_resize`.

### 6.2 `speaker`
| Methode | Beschreibung |
|---|---|
| `playNote(instrument [, volume = 1.0] [, pitch = 12])` | `instrument` z. B. `"harp"`, `"bass"`, `"bell"`, `"pling"`, `"snare"`, `"hat"`, `"basedrum"`, `"chime"`, `"guitar"`, `"flute"`, `"xylophone"`, `"iron_xylophone"`, `"cow_bell"`, `"didgeridoo"`, `"bit"`, `"banjo"`. Volume 0..3, Pitch 0..24 |
| `playSound(name [, volume] [, pitch])` | beliebige Sound-ID, z. B. `"minecraft:entity.creeper.primed"` |
| `playAudio(audio [, volume])` | PCM-Tabelle mit Werten -128..127, 48 kHz. Gibt `false` zurück, wenn der Puffer voll ist |
| `stop()` | |

Streaming-Muster:
```lua
local dfpwm = require("cc.audio.dfpwm")
local speaker = peripheral.find("speaker")
local decoder = dfpwm.make_decoder()
for chunk in io.lines("song.dfpwm", 16 * 1024) do
  local buffer = decoder(chunk)
  while not speaker.playAudio(buffer) do
    os.pullEvent("speaker_audio_empty")
  end
end
```
Standardmäßig gilt ein Limit von 8 Noten pro Tick pro Speaker.

### 6.3 `printer`
`newPage()` → bool, `endPage()` → bool, `write(text)`, `setCursorPos(x, y)`, `getCursorPos()`, `getPageSize()` → w,h, `setPageTitle(title)`, `getInkLevel()`, `getPaperLevel()`.

### 6.4 `drive`
`isDiskPresent()`, `getDiskLabel()`, `setDiskLabel(label)`, `hasData()`, `getMountPath()`, `hasAudio()`, `getAudioTitle()`, `playAudio()`, `stopAudio()`, `ejectDisk()`, `getDiskID()`.

### 6.5 `computer`
Ein Computer als Peripherie an einem anderen Computer: `turnOn()`, `shutdown()`, `reboot()`, `getID()`, `isOn()`, `getLabel()`.

### 6.6 `redstone_relay` (ab CC:T 1.114)
Identische Methoden zur `redstone`-API, jedoch als Peripherie: `setOutput(side, on)`, `getOutput(side)`, `getInput(side)`, `setAnalogOutput(side, v)`, `getAnalogOutput(side)`, `getAnalogInput(side)`, `setBundledOutput(side, mask)`, `getBundledOutput(side)`, `getBundledInput(side)`, `testBundledInput(side, mask)`.

Nutzen: über Wired Modems lassen sich beliebig viele Redstone-Punkte von einem Computer aus steuern.

```lua
local relay = peripheral.find("redstone_relay")
while true do
  relay.setOutput("top", not relay.getOutput("top"))
  sleep(0.5)
end
```

### 6.7 Generisch: `inventory`
| Methode | Beschreibung |
|---|---|
| `size()` | Slotanzahl |
| `list()` | dünn besetzte Tabelle `{[slot] = {name=, count=, nbt?=}}`, mit `pairs` iterieren |
| `getItemDetail(slot)` | ausführlich: `displayName`, `maxCount`, `tags`, `itemGroups`, `damage`, `maxDamage`, `durability`, `enchantments` |
| `getItemLimit(slot)` | |
| `pushItems(toName, fromSlot [, limit [, toSlot]])` → verschobene Anzahl | |
| `pullItems(fromName, fromSlot [, limit [, toSlot]])` → verschobene Anzahl | |

`toName` / `fromName` sind Netzwerknamen aus `peripheral.getName(wrapped)`. Beide Inventare müssen im selben Kabelnetz hängen.

### 6.8 Generisch: `fluid_storage`
`tanks()` → Liste `{name=, amount=}`, `pushFluid(toName [, limit [, fluidName]])`, `pullFluid(fromName [, limit [, fluidName]])`.

### 6.9 Generisch: `energy_storage`
`getEnergy()`, `getEnergyCapacity()`.

---

## 7. Shell-Programme und Konfiguration

### 7.1 Wichtige Programme in `/rom/programs`
`alias`, `bg`, `cd`, `clear`, `copy` (`cp`), `delete` (`rm`), `drive`, `edit`, `eject`, `exit`, `fg`, `gps` (`gps host`, `gps locate`), `help`, `id`, `label` (`get`/`set`/`clear`), `list` (`ls`, `dir`), `lua` (REPL), `mkdir`, `monitor <name> <programm>`, `motd`, `move` (`mv`), `pastebin` (`get`/`put`/`run`), `peripherals`, `programs`, `reboot`, `rename`, `set` (Settings), `shell`, `shutdown`, `speaker` (`play`/`sound`/`stop`), `time`, `type`, `wget` (`wget <url> [datei]`, `wget run <url>`).

Rednet: `chat host|join`, `repeat` (Relaisstation).
Turtle: `craft`, `dance`, `equip`, `excavate`, `go`, `refuel`, `tunnel`, `turn`, `unequip`.
Spaß: `adventure`, `worm`, `hello`, `dj`.

`programs` listet alles, was im aktuellen `shell.path()` liegt.

### 7.2 Server-Config (`computercraft-server.toml`)
| Option | Bedeutung |
|---|---|
| `computer_threads` | Threads für alle Computer |
| `max_main_global_time`, `max_main_computer_time` | Millisekunden pro Tick im Hauptthread |
| `disable_lua51_features` | schaltet `setfenv`, `getfenv`, `loadstring` ab |
| `default_computer_settings` | Startwerte für `settings` |
| `log_computer_errors` | |
| `command_require_creative` | Command Computer nur im Kreativmodus |
| `[http] enabled`, `[[http.rules]]` | Allow-/Deny-Listen für Domains und IP-Bereiche |
| `[http] websocket_enabled`, `max_requests`, `max_websockets` | |
| `[turtle] need_fuel`, `normal_fuel_limit`, `advanced_fuel_limit`, `can_push` | |
| `[peripheral] command_block`, `modem_range`, `modem_high_altitude_range`, `max_notes_per_tick`, `monitor_distance`, `monitor_bandwidth` | |
| `[term_sizes]` | Terminalgrößen für Computer, Pocket, Monitore |

Die exakten Schlüsselnamen variieren leicht zwischen Versionen. **[UNSICHER]** bei genauer Schreibweise, im Zweifel die generierte Datei lesen.

### 7.3 `/computercraft`-Befehl (OP)
`/computercraft dump`, `... shutdown`, `... turn-on`, `... track start|stop|dump`, `... queue <id> <args...>` (löst `computer_command` aus).

---

## 8. Create (nativ, ohne Addon)

Create bringt seit 0.5 eigene CC:T-Peripherie mit. Mit Create 6 ist der Umfang stark gewachsen, insbesondere um das Logistiksystem (Packages, Stock Ticker, Frogport) und erweiterte Zug-APIs.

**Anbindung:** Wired Modem direkt an den Create-Block anlegen und aktivieren, oder den Computer direkt anlegen. Die Netzwerknamen folgen dem Muster `Create_StockTicker_3`, `Create_RotationSpeedController_9` usw. Zuverlässiger ist `peripheral.find("Create_StockTicker")`.

**Wichtig:** Sobald ein Sequenced Gearshift oder Rotation Speed Controller an einen Computer angeschlossen ist, wird die manuelle GUI-Konfiguration ausgegraut. Das ist Absicht und verhindert widersprüchliche Steuerung.

### 8.1 Übersicht der Create-Peripherie
| Block | `peripheral.find`-Typ (üblich) |
|---|---|
| Packager | `Create_Packager` |
| Re-Packager | `Create_Repackager` |
| Stock Ticker | `Create_StockTicker` |
| Redstone Requester | `Create_RedstoneRequester` |
| Table Cloth | `Create_TableCloth` |
| Package Frogport | `Create_Frogport` **[UNSICHER]** |
| Postbox | `Create_Postbox` **[UNSICHER]** |
| Train Station | `Create_Station` **[UNSICHER]** |
| Train Signal | `Create_TrainSignal` **[UNSICHER]** |
| Train Observer | `Create_TrainObserver` **[UNSICHER]** |
| Nixie Tube | `Create_NixieTube` **[UNSICHER]** |
| Display Link | `Create_DisplayLink` **[UNSICHER]** |
| Sticker | `Create_Sticker` **[UNSICHER]** |
| Sequenced Gearshift | `Create_SequencedGearshift` **[UNSICHER]** |
| Rotation Speed Controller | `Create_RotationSpeedController` |
| Creative Motor | `Create_CreativeMotor` **[UNSICHER]** |
| Speedometer | `Create_Speedometer` **[UNSICHER]** |
| Stressometer | `Create_Stressometer` **[UNSICHER]** |

Die genauen Typnamen im Zweifel mit `peripheral.getNames()` und `peripheral.getType(name)` verifizieren.

### 8.2 Kinetik

**Speedometer**
* `getSpeed()` → RPM
* Event `speed_change` → `rpm`

**Stressometer**
* `getStress()` → SU
* `getStressCapacity()` → SU
* Events: `overstressed` (keine Parameter), `stress_change` → `stress, capacity`

**Rotation Speed Controller**
* `setTargetSpeed(speed)` — RPM, ganzzahlig, Bereich -256..256, außerhalb wird geklemmt
* `getTargetSpeed()` → RPM

**Creative Motor**
* `setGeneratedSpeed(speed)` — RPM, -256..256, geklemmt
* `getGeneratedSpeed()` → RPM

**Sequenced Gearshift**
* `rotate(angle [, modifier = 1])` — `angle` positive Ganzzahl in Grad. Rückwärts über negativen `modifier`. `modifier` ganzzahlig im Bereich -2..2, Werte außerhalb werden ignoriert und auf 1 gesetzt
* `move(distance [, modifier = 1])` — bewegt angeschlossene Piston-, Pulley- oder Gantry-Kontraptionen um `distance`
* `isRunning()` → bool

**Sticker**
* `isExtended()` → bool
* `isAttachedToBlock()` → bool
* `extend()` → bool (nur `true` beim Zustandswechsel)
* `retract()` → bool
* `toggle()` → bool

### 8.3 Anzeige

**Display Link** (schreibt auf ein beliebiges Create-Display-Target)
* `setCursorPos(x, y)` — darf außerhalb der Displaygrenzen liegen
* `getCursorPos()` → x, y
* `getSize()` → **height, width** (Reihenfolge laut Doku, abweichend von `term.getSize`)
* `isColor()` / `isColour()` → bool
* `write(text)` — schreibt nur in den internen Puffer
* `writeBytes(bytes)` — Bytes statt Text (Create 6)
* `clearLine()`
* `clear()`
* `update()` — überträgt den Puffer an das Display. Ohne `update()` passiert nichts

```lua
local dl = peripheral.find("Create_DisplayLink")
dl.clear()
dl.setCursorPos(1, 1)
dl.write("Stress: " .. math.floor(stress))
dl.update()
```

**Nixie Tube**
* `setText(text [, colour])` — `colour` ist ein Farbstoffname als String, `nil` lässt die Farbe unverändert
* `setTextColour(colour)` (alias `setTextColor`)
* `setSignal(firstSignal, secondSignal)` — steuert genau zwei Röhren mit frei definierbarem Leuchtsignal:

```lua
{
  r = 0,            -- 0..255
  g = 0,
  b = 0,
  glowWidth = 1,    -- 1..4
  glowHeight = 1,   -- 1..4
  blinkPeriod = 40, -- Ticks zwischen Blinks
  blinkOffTime = 20 -- Ticks aus
}
```
Alle Felder sind optional, haben aber keine Standardwerte. Nicht gesetzte Felder behalten den alten Zustand. Nach `{r=255}` und danach `{b=255}` ist die Farbe violett, nicht blau.

### 8.4 Züge

**Train Station**
| Methode | Rückgabe |
|---|---|
| `assemble()` | wirft bei Fehler. Station muss vorher im Assembly-Modus sein, verlässt ihn danach automatisch |
| `disassemble()` | Station darf nicht im Assembly-Modus sein |
| `setAssemblyMode(bool)` | |
| `isInAssemblyMode()` | bool |
| `getStationName()` | string |
| `setStationName(name)` | |
| `isTrainPresent()` | bool |
| `isTrainImminent()` | bool, "imminent" = innerhalb 30 Blöcken, nicht mehr wahr nach dem Halt |
| `isTrainEnroute()` | bool |
| `getTrainName()` | string |
| `setTrainName(name)` | |
| `hasSchedule()` | bool |
| `getSchedule()` | table (Format siehe 8.5) |
| `setSchedule(schedule)` | überschreibt den bestehenden Fahrplan |
| `canTrainReach(destination)` | `bool, reason?` mit `"no-target"` oder `"cannot-reach"` |
| `distanceTo(destination)` | `number` in Blöcken oder `nil`, plus `reason?` |

Fast alle Methoden werfen, wenn die Station nicht mit einem Gleis verbunden ist oder kein Zug anwesend ist.

Events: `train_imminent` → `stationName, trainName`, `train_arrival` → `stationName, trainName`, `train_departure` → `stationName, trainName`.

**Train Signal**
* `getState()` → `"RED"`, `"GREEN"` oder `"YELLOW"` (Gelb nur bei `CROSS_SIGNAL`)
* `isForcedRed()` → bool
* `setForcedRed(bool)` — erzwingt Rot unabhängig von Redstone und freier Strecke. Fällt auf Standardverhalten zurück, sobald die Computerverbindung verloren geht
* `getSignalType()` → `"ENTRY_SIGNAL"` oder `"CROSS_SIGNAL"`
* `cycleSignalType()` — wie ein Schraubenschlüssel-Klick
* `listBlockingTrainNames()` → Liste von Zugnamen

Event `train_signal_state_change` → `side, state`:
```lua
while true do
  local _, side, status = os.pullEvent("train_signal_state_change")
  print("Signal", side, "->", status)
end
```

**Train Observer**
* `isTrainPassing()` → bool
* `getPassingTrainName()` → string oder `nil`
* Events: `train_passing` → `trainName`, `train_passed` → `trainName`

### 8.5 Fahrplan-Format (Lua)

```lua
schedule = {
  cyclic = true,      -- wiederholt sich der Fahrplan?
  entries = {
    {
      instruction = {
        id = "create:destination",
        data = { text = "Station 1" },
      },
      conditions = {          -- äußere Liste = ODER
        {                     -- innere Listen = UND
          { id = "create:delay",   data = { value = 5, time_unit = 1 } },
          { id = "create:powered", data = {} },
        },
        {
          { id = "create:time_of_day", data = { rotation = 0, hour = 14, minute = 0 } },
        },
      },
    },
  },
}
```

**Instruktionen**
| ID | Daten |
|---|---|
| `create:destination` | `text` (Stationsname, `*` als Wildcard). Braucht mindestens eine Bedingung |
| `create:rename` | `text`. Darf keine Bedingungen haben |
| `create:throttle` | `value` ganzzahlig 5..100. Darf keine Bedingungen haben |

**Bedingungen**
| ID | Daten |
|---|---|
| `create:delay` | `value`, `time_unit` (0 Ticks, 1 Sekunden, 2 Minuten) |
| `create:time_of_day` | `hour` 0..23, `minute` 0..59, `rotation` 0..9 |
| `create:fluid_threshold` | `bucket` (Item-Tabelle), `threshold`, `operator` (0 >, 1 <, 2 ==), `measure` = 0 |
| `create:item_threshold` | `item`, `threshold`, `operator` (0 >, 1 <, 2 ==), `measure` (0 Items, 1 Stacks) |
| `create:redstone_link` | `frequency` = Liste aus zwei Item-Tabellen, `inverted` (0 aktiv, 1 inaktiv) |
| `create:player_count` | `count`, `exact` (0 genau, 1 größer gleich) |
| `create:idle` | `value`, `time_unit` |
| `create:unloaded` | keine |
| `create:powered` | keine |

**Rotation-Tabelle für `time_of_day`**
| Wert | Intervall |
|---|---|
| 0 | täglich |
| 1 | alle 12 h |
| 2 | alle 6 h |
| 3 | alle 4 h |
| 4 | alle 3 h |
| 5 | alle 2 h |
| 6 | stündlich |
| 7 | alle 45 min |
| 8 | alle 30 min |
| 9 | alle 15 min |

**Item-Darstellung in Fahrplänen**
```lua
item = { id = "minecraft:stone", count = 1 }
```
`count` sollte in Fahrplänen immer 1 sein.

### 8.6 Logistik (Create 6)

#### Packager (`Create_Packager`)
* `getAddress()` → string
* `setAddress([address])` — erzwingt die Adresse. Wird vergessen, sobald ohne angeschlossenen Computer ein Paket erzeugt wird. Für dauerhafte Zuweisung in `startup.lua` setzen. `nil` stellt das schildbasierte Standardverhalten wieder her
* `list()` → dünn besetzte Slot-Tabelle des angeschlossenen Inventars
* `getItemDetail(slot)` → Detailtabelle oder `nil`
* `getPackage()` → Package-Objekt oder `nil`
* `makePackage()` → bool, wirkt wie ein Redstone-Impuls, meldet aber Erfolg zurück

Events: `package_created` → Package-Objekt (im Packager ist es `isEditable()`), `package_received` → Package-Objekt.

#### Re-Packager (`Create_Repackager`)
Gleiche Methoden wie der Packager. `setAddress` wirkt nur auf nicht-kodierte Pakete (also nicht auf Crafting-Aufträge).

Events: `package_repackaged` → `Package-Objekt, anzahl` (Beispielobjekt plus Anzahl identischer Pakete), `package_received` → Package-Objekt.

#### Stock Ticker (`Create_StockTicker`)
* `list()` → Inhalt des Zahlungsinventars, dünn besetzt
* `getItemDetail(slot)` → Detailtabelle des Zahlungsinventars
* `stock([detailed = false])` → dichte Liste aller Items im Netzwerk. Mit `detailed = true` inklusive `displayName`, `tags`, `maxCount`, `enchantments`
* `getStockItemDetail(index)` → Detail zu einem Netzwerk-Index. Indizes ändern sich bei Netzwerk-Reload, daher vorher `stock()` aufrufen
* `requestFiltered(address, [filter1], [filter2], ...)` → Anzahl angeforderter Items

**Filter-DSL für `requestFiltered`** (das komplexeste Feature der Create-CC-Integration)

Ein Filter ist eine Tabelle, die gegen die Detaildaten der Netzwerk-Items geprüft wird.

Basisfall:
```lua
stockTicker.requestFiltered("lager", { name = "apple", _requestCount = 10 })
```

Sonderschlüssel:
* `_requestCount = n` an der Basis der Tabelle begrenzt die Menge
* `_mode` steuert den Vergleichsmodus auf **dieser** Ebene (nicht rekursiv):
  * `"contains"` (Standard) — alle Schlüssel des Filters müssen im Item vorhanden sein und passen
  * `"exact"` — Schlüssel und Werte müssen 1:1 übereinstimmen
  * `"contained"` — umgekehrt, alle Item-Schlüssel müssen im Filter enthalten sein
* `_op` definiert einen Operator, angewandt auf den Schlüssel `value`:

| `_op` | Bedeutung |
|---|---|
| `">"`, `">="`, `"<"`, `"<="`, `"=="`, `"~="` | numerischer/genereller Vergleich |
| `"type"` | prüft den Typ, `value` = `"nil"`, `"number"`, `"string"`, `"boolean"`, `"table"`, `"list"`, `"map"`, `"object"` |
| `"not"` | invertiert das Ergebnis |
| `"any"` | mindestens einer der Einträge in `value` passt (`value` muss dichte Liste sein) |
| `"all"` | alle Einträge in `value` passen |
| `"regex"` | Regex-Muster in `value` |
| `"glob"` | Glob-Muster in `value` |

Komplexes Beispiel:
```lua
local st = peripheral.find("Create_StockTicker")
st.requestFiltered("meineAdresse",
  {
    _requestCount = 5,
    name = { _op = "any", value = {
      "create:crushing_wheel",
      { _op = "glob", value = "minecraft:*" },
      { _op = "not", value = { _op = "glob", value = "*e*" } },
    }},
    count = { _op = "all", value = {
      { _op = ">", value = 2 },
      { _op = "<", value = 100 },
    }},
  },
  {
    tags = {
      ["forge:rods/wooden"] = true,
      ["forge:rods"] = true,
      ["forge:tools"] = true,
      _mode = "contained",
    },
    nbt = {},
  }
)
```
Mehrere Filter in einem Aufruf ergeben **eine** Bestellung. Passen die Items ins selbe Paket, werden sie zusammen verpackt.

`st.requestFiltered("adresse", {})` fordert alles an, weil ein leerer Filter auf jedes Item passt.

#### Redstone Requester (`Create_RedstoneRequester`)
* `getAddress()` / `setAddress(address)` (`nil` löscht)
* `getConfiguration()` → `"strict"` oder `"allow_partial"`
* `setConfiguration(configuration)` — `"strict"` liefert nur bei vollständiger Verfügbarkeit, `"allow_partial"` immer
* `getRequest()` → Tabelle von itemDetails
* `setRequest([item], ...)` — bis zu 9 Argumente, jeweils `{ name = "...", count = 1..256 }`. Fehlendes `count` = 1
* `setCraftingRequest([count], [itemName], ...)` — erstes Argument ist die Anzahl der Crafting-Durchläufe, danach bis zu 9 Item-Namen für das 3x3-Raster. `nil` oder `"minecraft:air"` = leerer Slot
* `request()` — sendet die Anfrage

```lua
local rr = peripheral.find("Create_RedstoneRequester")
rr.setCraftingRequest(
  1,
  "minecraft:diamond", "minecraft:diamond", "diamond",
  "minecraft:air",     "minecraft:stick",   nil,
  nil,                 "minecraft:stick"
)
rr.setAddress("crafter")
rr.request()
```

**Warnung:** Sobald ein Spieler die GUI des Redstone Requesters öffnet und schließt, verliert die Anfrage ihre Crafting-Kodierung und wird zu einer normalen Anfrage.

`setCraftingRequest()` und `setRequest()` ohne Argumente leeren die Konfiguration.

#### Table Cloth (`Create_TableCloth`)
Nur als Peripherie verfügbar, wenn er ein Shop ist oder Items darauf liegen. Bleibt Peripherie, solange ein Computer/Modem/Turtle angeschlossen ist, auch wenn er leer wird.

* `isShop()` → bool
* `getAddress()` / `setAddress(address)`
* `getWares()` → Tabelle von itemDetails (Kaufpreis in Waren)
* `setWares(item, ...)` — bis zu 9 Argumente `{ name =, count = 1..256 }`. Ohne Argumente hört er auf, ein Shop zu sein
* `getPriceTagItem()` / `setPriceTagItem([name])` (`nil` löscht)
* `getPriceTagCount()` / `setPriceTagCount([count = 1])`

```lua
local tc = peripheral.find("Create_TableCloth")
if tc then
  tc.setWares({ name = "minecraft:diamond" }, { name = "redstone", count = 30 })
  tc.setPriceTagItem("gold_ingot")
  tc.setPriceTagCount(2)
end
```

#### Package Frogport und Postbox
Identische API:
* `getAddress()` / `setAddress(address)`
* `getConfiguration()` / `setConfiguration(configuration)` → `"send_recieve"` oder `"send"` (Schreibweise mit Tippfehler ist die tatsächliche API)
  * `"send_recieve"`: sendet nur Pakete mit fremder Adresse, empfängt Pakete mit eigener Adresse
  * `"send"`: sendet alles, empfängt nichts
* `list()` → dünn besetzte Slot-Tabelle
* `getItemDetail(slot)` → Detailtabelle. Bei Paketen enthält sie zusätzlich das Feld `package` mit dem Package-Objekt

Events: `package_sent` → Package-Objekt, `package_received` → Package-Objekt.
Frogport bezieht sich auf Chain Conveyors, Postbox auf Züge.

#### Package-Objekt
Momentaufnahme eines Pakets. Zu bekommen über `getItemDetail(slot).package`, `packager.getPackage()` oder die Package-Events.

| Methode | Beschreibung |
|---|---|
| `getAddress()` | aktualisiert die Momentaufnahme, wenn `isEditable()` |
| `list()` | dichte Liste der Items im Paket |
| `getItemDetail(slot)` | Slot 1..9, sonst Fehler |
| `getOrderData()` | Order-Data-Objekt oder `nil` |
| `isEditable()` | `true`, solange das Paket im (Re-)Packager liegt |
| `setAddress(address)` | wirft, wenn `isEditable()` falsch ist |

Momentaufnahmen werden **nicht** benachrichtigt, wenn ein anderer Computer die Daten ändert.

#### Order-Data-Objekt
Order Data hängt an jedem Paket, das nicht durch reinen Redstone-Impuls am Packager entstanden ist. Die Daten sind unveränderlich.

| Methode | Beschreibung |
|---|---|
| `getCrafts()` | Liste `{ count = n, recipe = { 9 Item-Namen, `nil` für leer } }` |
| `getIndex()` | n-tes Paket vom selben Packager |
| `getLinkIndex()` | n-ter Packager, der die Bestellung erfüllt |
| `getOrderID()` | eindeutige ID der Gesamtbestellung |
| `isFinal()` | letztes Paket dieses Packagers |
| `isFinalLink()` | letztes Glied der Bestellkette |
| `list()` | alle Items der **Gesamtbestellung**, nur gültig bei `getLinkIndex() == 1`, sonst `nil` |
| `getItemDetail(slot)` | wie `list`, nur bei `linkIndex == 1` |

Beispiel `getCrafts()`:
```lua
{
  { count = 5, recipe = {
      "minecraft:iron_nugget","minecraft:iron_nugget","minecraft:iron_nugget",
      "minecraft:iron_nugget","create:cogwheel",      "minecraft:iron_nugget",
      "minecraft:iron_nugget","minecraft:iron_nugget","minecraft:iron_nugget" } },
}
```

Pakete kennen nicht, wie viele Pakete nach ihnen kommen, nur wie viele vor ihnen waren.

---

## 9. CC:C Bridge

Zusatzmod von Sammy_echt (Tweaked Programs), die CC:Tweaked und Create weiter verzahnt. Für 1.21.1 nur als **NeoForge**-Build verfügbar. Ab v1.7.1 Create-6-kompatibel. Auf Client und Server erforderlich.

Fünf Peripherie-Blöcke: Source Block, Target Block, RedRouter, Scroller Pane, Animatronic. Der frühere Train-Peripheral wurde entfernt, weil Create das inzwischen selbst löst.

### 9.1 Source Block — `"create_source"`
Sendet Text an **Create Display Targets** (Flap Display, Nixie Tubes, Schilder, Lesepult).

Die API ist identisch zur `term`-API plus `getLine` aus der `window`-API. Formatierung wird ignoriert: `setBackgroundColor` und `setTextColor` existieren, haben aber keine Wirkung. `getLine(y)` liefert nur **eine** Zeile (den reinen Text), nicht drei wie die Window-API.

| Metadaten | Wert |
|---|---|
| Peripheral-Version | v1.1 |
| Attach-Name | `"create_source"` |
| Zulässige Seiten | alle |

```lua
local source = peripheral.find("create_source")
local w, h = source.getSize()
source.clear()
source.setCursorPos(math.floor(w/2 - #("Hello World")/2), math.floor(h/2))
source.write("Hello World")
```

Aktualisierungsrate: 1 Sekunde. Schneller geht es mit einem Redstone-Takt auf dem Display Link.

Event: `monitor_resize` → `attached_name`, wenn sich die Zielgröße ändert.

### 9.2 Target Block — `"create_target"`
Simuliert ein Create-Display-Target und empfängt so Daten von **Create Display Sources** (Stressometer, Items auf Bändern, Dampfmaschine).

| Metadaten | Wert |
|---|---|
| Peripheral-Version | v1.2 |
| Attach-Name | `"create_target"` |
| Zulässige Seiten | alle |

| Methode | Beschreibung |
|---|---|
| `resize(width, height)` | legt die simulierte Terminalgröße fest. Wirft bei Werten kleiner 1 |
| `getLine(y)` | Zeile als String. Wirft außerhalb von 1..Höhe |
| `dump()` | Tabelle aller Zeilen, gleich lang und geordnet |
| `getSize()` | `width, height` |

```lua
local target = peripheral.find("create_target")
target.resize(32, 8)
for _, line in ipairs(target.dump()) do print(line) end
print("Stress: " .. target.getLine(1))
```

Die Aktualisierungsrate bestimmt die Quelle. Ein Redstone-Takt auf dem Display Link beschleunigt sie.

**Hinweis zum Zeichensatz:** Create-Displays nutzen einen eingeschränkten Zeichensatz. Source und Target Block setzen seit v1.5 eine Übersetzungsschicht ein, damit beide nahtlos zusammenarbeiten. Bei Sonderzeichen ist mit Abweichungen zu rechnen.

### 9.3 RedRouter — `"redrouter"`
Redstone-Peripherie ohne Bundled-Cable-Unterstützung. Seiten sind **relativ zur Blickrichtung des Blocks**, wie bei Turtles.

**Empfehlung:** In CC:T 1.114+ stattdessen den nativen `redstone_relay` verwenden. Er kann zusätzlich Bundled Cables. Der RedRouter ist nicht als veraltet markiert, wird aber vom Autor nicht mehr empfohlen.

| Metadaten | Wert |
|---|---|
| Peripheral-Version | v1 |
| Attach-Name | `"redrouter"` |
| Zulässige Seiten | alle |

| Methode | Beschreibung |
|---|---|
| `setOutput(side, on)` | `true` = Stärke 15 |
| `setAnalogOutput(side, value)` | 0..15, wirft außerhalb |
| `getOutput(side)` → bool | was der RedRouter senden **soll** |
| `getInput(side)` → bool | was tatsächlich in der Welt anliegt |
| `getAnalogOutput(side)` → 0..15 | |
| `getAnalogInput(side)` → 0..15 | |

Event: `redstone` → `attached_name`.

Verhalten seit v1.6: Der RedRouter leitet keine externen Redstone-Signale mehr durch und sendet starke Signale, wenn eine Seite bestromt ist.

### 9.4 Scroller Pane — `"scroller"`
Spielereingabe als Zahl. Nutzt Creates `NumberBehaviour`-Auswahl (dieselbe wie beim Rotation Speed Controller). Bedienung durch Halten der Rechtsklick-Taste auf der Zahl und Mausbewegung.

| Metadaten | Wert |
|---|---|
| Peripheral-Version | v2 |
| Attach-Name | `"scroller"` |
| Zulässige Seite | nur `"back"` |

Montage: entweder ein Vollmodem platzieren und die Scheibe darauf setzen, oder einen Hilfsblock nutzen, die Scheibe darauf setzen, den Hilfsblock entfernen und danach ein Modem an die Rückseite setzen.

| Methode | Beschreibung |
|---|---|
| `isLocked()` → bool | |
| `setLock(state)` | `true` sperrt die Spielereingabe |
| `getValue()` → number | |
| `setValue(value)` | |
| `getLimit()` → number | Limit relativ zu null |
| `setLimit(limit)` | wird automatisch auf 1..200 geklemmt |
| `hasMinusSpectrum()` → bool | |
| `toggleMinusSpectrum(state)` | bei `true` gilt der Bereich `-limit .. limit`, sonst `0 .. limit` |

Event: `scroller_changed` → `attached_name, new_value`. Wird **nicht** ausgelöst, wenn ein Computer den Wert setzt.

```lua
local scroller = peripheral.find("scroller")
scroller.setLock(true)
local limit = scroller.hasMinusSpectrum() and 32 or 64
scroller.setLimit(limit)
scroller.setValue(32)
scroller.setLock(false)
os.pullEvent("scroller_changed")
```
Achtung: In der offiziellen Doku steht im Beispiel `setLocked`, korrekt ist laut Funktionsliste `setLock`. Im Zweifel `peripheral.getMethods` prüfen.

### 9.5 Animatronic — `"animatronic"`
Animierbare Puppe, ähnlich einem Rüstungsständer. Maximale Rotation je Körperteil 180 Grad in beide Richtungen.

| Metadaten | Wert |
|---|---|
| Peripheral-Version | v1.1 |
| Attach-Name | `"animatronic"` |
| Zulässige Seite | nur `"top"` (Modem **unter** dem Block) |

| Methode | Beschreibung |
|---|---|
| `setFace(face)` | `"normal"`, `"happy"`, `"question"`, `"sad"`. Wirft bei anderen Werten |
| `setTransition(kind)` | `"linear"`, `"none"`, `"rusty"` (Standard). Wirft bei anderen Werten |
| `push()` | überträgt die gespeicherten Rotationen. Danach werden alle gespeicherten Werte auf 0 zurückgesetzt |
| `setHeadRot(x, y, z)` | je -180..180 |
| `setBodyRot(x, y, z)` | `y` und `z` -180..180, `x` beliebig innerhalb 360 |
| `setLeftArmRot(x, y, z)` | je -180..180 |
| `setRightArmRot(x, y, z)` | je -180..180 |
| `getStoredHeadRot()` / `getStoredBodyRot()` / `getStoredLeftArmRot()` / `getStoredRightArmRot()` | → x, y, z (noch nicht angewandt) |
| `getAppliedHeadRot()` / `getAppliedBodyRot()` / `getAppliedLeftArmRot()` / `getAppliedRightArmRot()` | → x, y, z (aktuell sichtbar) |

```lua
local a = peripheral.find("animatronic")
a.setTransition("none")
a.setHeadRot(0, 0, 0)
a.setLeftArmRot(0, 0, 0)
a.setRightArmRot(0, 0, 0)
a.push()
```
Ein Übergang dauert etwa 1 Sekunde, außer bei `"none"`, dann ist er sofort.

Hilfsmittel: Posen lassen sich in Blockbench modellieren und in Rotationswerte übertragen. Die Mod-Doku enthält dazu Anleitungen unter `guides/positioningAnimatronicsBlockbench`.

### 9.6 Auswahlhilfe Create nativ vs. CC:C Bridge
| Aufgabe | Empfehlung |
|---|---|
| Text auf Flap Display, Nixie Tube, Schild schreiben | Create Display Link (nativ) oder CC:C Source Block. Der Source Block bietet ein volles Terminal-Interface, der Display Link ein Puffer/`update()`-Modell |
| Werte aus Create-Maschinen lesen (Stress, Geschwindigkeit) | Nativ per Stressometer/Speedometer. Der Target Block ist nur nötig, wenn eine Display Source keine eigene CC-API hat |
| Redstone über Distanz | `redstone_relay` (CC:T nativ) |
| Numerische Spielereingabe im Bau | Scroller Pane (nur CC:C Bridge) |
| Dekorative Animation | Animatronic (nur CC:C Bridge) |

---

## 10. Weitere Create-Addons mit CC-Unterstützung

**Create Crafts & Additions** liefert den `digital_adapter` sowie Peripherie für `electric_motor` und `accumulator`.

Digital Adapter (Auswahl):
`getType()` → `"digital_adapter"`, `setTargetSpeed(side, speed)`, `getTargetSpeed(side)`, `getKineticStress(side)`, `getKineticCapacity(side)`, `getKineticSpeed(side)`, `getKineticTopSpeed()`, `getPulleyDistance(side)`.

Electric Motor: `getSpeed()`, `getStressCapacity()`, `getEnergyConsumption()`, `getMaxInsert()`, `getMaxExtract()`, `getType()`.
Accumulator: `getEnergy()`, `getCapacity()`.

**[UNSICHER]** für 1.21.1, weil dieses Addon eigene Versionszyklen hat. Methoden im Spiel verifizieren.

---

## 11. Simple Storage Network (SSN)

### 11.1 Blöcke und Mechanik
| Block/Item | Funktion |
|---|---|
| Storage Network Master (Root) | Gehirn des Netzwerks, genau einer pro Netz |
| Storage Cable (Network Cable) | reine Verbindung zwischen Netzwerkpunkten |
| Storage Link Cable | bindet eine Kiste/Barrel/Drawer als Speicher ans Netz |
| Import Cable | zieht Items aus einem externen Inventar ins Netz, Whitelist/Blacklist |
| Export Cable | schiebt Items aus dem Netz in ein externes Inventar |
| Processing Cable | Verarbeitungs- und Autocrafting-Automatisierung, benötigt einen Controller |
| Storage Request Table | GUI-Zugriffspunkt mit Crafting-Raster |
| Expanded Request Table | größere Variante für hohe GUI-Skalierung |
| Storage Remote / Expanded Remote | drahtloser Zugriff, per Rechtsklick am Master gekoppelt, Reichweite bis 64 Blöcke |
| Upgrades | Speed, Stock (Bestandsgrenze), Operation (max. Exportmenge) |

Regeln: Spezialkabel binden jeweils genau **ein** Inventar. Ein Crescent Hammer (oder Wrench) wählt aus, welches. Berührt ein Kabel ein fremdes Netz, wird dessen Root-Block zerstört. Master und Request Table müssen direkt benachbart sein und werden nicht per Kabel verbunden.

### 11.2 Verfügbarkeit auf 1.21.1
Die offizielle Unterstützung für 1.21.1 ist uneinheitlich dokumentiert. Es existiert mindestens ein Community-Port für NeoForge 1.21.1 (`stevedwray/Storage-Network-1.21.1-NeoForge-Port`). Vor der Programmierung im Zweifel Modliste und Version prüfen.

### 11.3 CC-Integration: es gibt keine
SSN stellt **kein** CC:Tweaked-Peripheral bereit. Es gibt kein `ssn_bridge`, keine `craftItem`-Methode, keine Netzwerkabfrage per API. Wer eine solche API braucht, greift zu Refined Storage oder AE2 in Kombination mit Advanced Peripherals oder "Storage for ComputerCraft".

### 11.4 Was trotzdem funktioniert

**A) Generische Peripherie am Master.** Der Master-Block implementiert historisch einen Item-Handler (`MasterItemStackHandler`). Falls dieser auf 1.21.1 weiterhin exponiert wird, erscheint der Master als `inventory`-Peripherie und `list()` liefert den gesamten Netzwerkbestand. **[UNSICHER]** und unbedingt zu testen:

```lua
for _, name in ipairs(peripheral.getNames()) do
  if name:find("storagenetwork") then
    print(name, peripheral.getType(name), peripheral.hasType(name, "inventory"))
  end
end
```
Wenn es klappt, ist `list()` potenziell sehr groß und teuer. Ergebnisse cachen, nicht in einer engen Schleife abfragen.

**B) Puffer-Kisten als Brücke (robuste Standardlösung).** Dieses Muster funktioniert unabhängig von SSN-Interna:

1. Kiste A als Eingangspuffer mit **Import Cable** ans SSN anschließen. Alles, was hineinkommt, wandert ins Netz.
2. Kiste B als Ausgangspuffer mit **Export Cable** und Filter versorgen. Das Netz füllt sie nach.
3. Beide Kisten mit Wired Modem ans CC-Kabelnetz hängen.
4. Der Computer nutzt `pushItems` / `pullItems` gegen A und B.

```lua
local eingang  = peripheral.wrap("minecraft:chest_0")  -- Import Cable
local ausgang  = peripheral.wrap("minecraft:chest_1")  -- Export Cable
local puffer   = peripheral.wrap("minecraft:barrel_0")

-- Items ins SSN einlagern
for slot, item in pairs(puffer.list()) do
  puffer.pushItems(peripheral.getName(eingang), slot)
end

-- Items aus dem SSN entnehmen (Export Cable liefert nach)
local function warteAufItem(name, menge)
  local gesammelt = 0
  while gesammelt < menge do
    for slot, item in pairs(ausgang.list()) do
      if item.name == name then
        gesammelt = gesammelt + ausgang.pushItems(peripheral.getName(puffer), slot)
      end
    end
    if gesammelt < menge then sleep(1) end
  end
  return gesammelt
end
```

**C) Bestandsüberwachung.** Ohne Master-Peripherie lässt sich der Bestand nur indirekt bestimmen, indem alle über Storage Link Cables angeschlossenen Kisten **zusätzlich** ans CC-Kabelnetz gehängt und einzeln per `list()` abgefragt werden. Die Summe entspricht dem Netzwerkbestand. Aufwendig, aber verlässlich.

**D) Redstone-Steuerung.** Import- und Export-Kabel lassen sich per Redstone deaktivieren. Ein `redstone_relay` neben dem Kabel gibt dem Computer Kontrolle über den Materialfluss, ohne SSN-Interna zu kennen.

### 11.5 Bekannte Konflikte
* Kabel dürfen keine zwei Netze berühren, sonst wird ein Root zerstört. CC-Kabel sind davon nicht betroffen, sie sind ein separates System.
* SSN-Import-Kabel und CC-`pushItems` können um dieselben Slots konkurrieren. Race-Conditions abfangen, indem der Rückgabewert von `pushItems` ausgewertet und nicht auf `list()`-Momentaufnahmen vertraut wird.

---

## 12. Kombinationsmuster Create plus CC:Tweaked

### 12.1 Stress-Dashboard auf Monitor
```lua
local stresso = peripheral.find("Create_Stressometer")
local speedo  = peripheral.find("Create_Speedometer")
local mon     = peripheral.find("monitor")

mon.setTextScale(1)
term.redirect(mon)

while true do
  local su, cap = stresso.getStress(), stresso.getStressCapacity()
  local rpm = speedo.getSpeed()
  term.clear()
  term.setCursorPos(1, 1)
  print(("Stress   %.0f / %.0f SU"):format(su, cap))
  print(("Auslast. %.1f %%"):format(cap > 0 and su / cap * 100 or 0))
  print(("Speed    %.0f RPM"):format(rpm))
  os.pullEvent("stress_change")
end
```

### 12.2 Lastregelung per RSC
```lua
local stresso = peripheral.find("Create_Stressometer")
local rsc     = peripheral.find("Create_RotationSpeedController")

while true do
  local su, cap = stresso.getStress(), stresso.getStressCapacity()
  local last = cap > 0 and su / cap or 0
  local ziel = rsc.getTargetSpeed()
  if last > 0.9 and ziel > 16 then
    rsc.setTargetSpeed(ziel - 8)
  elseif last < 0.5 and ziel < 256 then
    rsc.setTargetSpeed(ziel + 8)
  end
  sleep(1)
end
```

### 12.3 Bahnhofsanzeige
```lua
local station = peripheral.find("Create_Station")
local dl      = peripheral.find("Create_DisplayLink")

while true do
  local e, stationName, trainName = os.pullEvent()
  local text
  if e == "train_imminent"  then text = trainName .. " naht" end
  if e == "train_arrival"   then text = trainName .. " haelt" end
  if e == "train_departure" then text = "Gleis frei" end
  if text then
    dl.clear()
    dl.setCursorPos(1, 1)
    dl.write(text)
    dl.update()
  end
end
```

### 12.4 Bestellterminal auf Stock Ticker
```lua
local st = peripheral.find("Create_StockTicker")

local function suche(muster)
  local treffer = {}
  for _, item in ipairs(st.stock(true)) do
    if item.displayName:lower():find(muster:lower(), 1, true) then
      treffer[#treffer + 1] = item
    end
  end
  return treffer
end

write("Suche: ")
for _, item in ipairs(suche(read())) do
  print(("%4d x %s"):format(item.count, item.displayName))
end

write("Item-ID: ") local id = read()
write("Menge:   ") local n  = tonumber(read())
print("Angefordert: " .. st.requestFiltered("terminal", { name = id, _requestCount = n }))
```

### 12.5 Paketsortierung nach Order Data
```lua
local frogport = peripheral.find("Create_Frogport")

while true do
  local _, pkg = os.pullEvent("package_received")
  local od = pkg.getOrderData()
  if od then
    print(("Bestellung %d, Teil %d/%s"):format(
      od.getOrderID(), od.getIndex(), od.isFinal() and "final" or "..."))
    if od.isFinal() and od.isFinalLink() then
      -- Bestellung vollstaendig, weiterverarbeiten
    end
  else
    print("Paket ohne Order Data (Redstone-Packager)")
  end
end
```

### 12.6 Zugfahrplan programmatisch setzen
```lua
local station = peripheral.find("Create_Station")

station.setSchedule({
  cyclic = true,
  entries = {
    {
      instruction = { id = "create:destination", data = { text = "Mine" } },
      conditions  = { { { id = "create:idle", data = { value = 5, time_unit = 1 } } } },
    },
    {
      instruction = { id = "create:destination", data = { text = "Basis" } },
      conditions  = { { { id = "create:item_threshold", data = {
        item = { id = "minecraft:cobblestone", count = 1 },
        threshold = 10, operator = 0, measure = 1,
      } } } },
    },
  },
})
```

---

## 13. Fallstricke und Betriebswissen

**Yielding.** Jede Schleife ohne `sleep`, `os.pullEvent` oder eine andere yieldende Funktion bricht nach wenigen Sekunden mit "Too long without yielding" ab. `sleep(0)` reicht als minimaler Yield.

**Peripherienamen.** Namen wie `minecraft:chest_3` bleiben stabil, ändern sich aber, wenn ein Modem deaktiviert und neu aktiviert wird oder der Block neu platziert wird. Programme sollten `peripheral.find` mit Filter nutzen oder Namen in `settings` ablegen.

**Chunkladung.** Peripherie in ungeladenen Chunks verschwindet aus dem Netz und löst `peripheral_detach` aus. Programme sollten `peripheral.isPresent` prüfen und Fehler abfangen. Create-Züge in ungeladenen Chunks reagieren nicht.

**`pcall` um Peripherieaufrufe.** Viele Create-Methoden werfen (Station ohne Gleis, kein Zug anwesend, Slot außerhalb des Bereichs). Ohne `pcall` stirbt das Programm.
```lua
local ok, err = pcall(function() return station.getTrainName() end)
```

**Dünn besetzte Tabellen.** `inventory.list()`, `packager.list()` und `stockTicker.list()` sind dünn besetzt. Mit `pairs` iterieren, niemals mit `ipairs`. Dagegen sind `stock()`, `package.list()` und `orderData.list()` dicht und für `ipairs` geeignet.

**Display Link braucht `update()`.** Ohne den Aufruf bleibt das Display leer, obwohl `write` erfolgreich war.

**`getSize()` des Display Link** liefert laut Dokumentation `height, width`, also in umgekehrter Reihenfolge zu `term.getSize()`. Bei quadratischen Displays fällt der Fehler nicht auf.

**Sequenced Gearshift und RSC** lassen sich nicht gleichzeitig per GUI und per Computer steuern. Die GUI wird bewusst gesperrt.

**Redstone Requester verliert Crafting-Kodierung**, sobald ein Spieler die GUI öffnet und schließt.

**Packager `setAddress` ist flüchtig.** Es wird vergessen, sobald ohne Computerverbindung ein Paket erzeugt wird. Für Dauerhaftigkeit in `startup.lua` setzen.

**Scroller Pane** löst `scroller_changed` nur bei Spielerinteraktion aus, nicht bei `setValue`.

**Animatronic `push()` setzt die gespeicherten Rotationen auf 0.** Vor jedem `push()` alle gewünschten Rotationen neu setzen, sonst fällt die Puppe in die Nullstellung.

**Nixie Tube `setSignal`** hat keine Standardwerte. Nicht gesetzte Felder behalten den alten Zustand, was zu unerwarteten Mischfarben führt.

**Turtle-Bewegung ist nicht garantiert.** `turtle.forward()` scheitert an Blöcken, Entities und bei fehlendem Treibstoff. Rückgabewert immer auswerten und bei Bedarf wiederholen.

**Modemreichweite.** Wireless Modems reichen standardmäßig 64 Blöcke, mehr in großer Höhe, weniger bei Gewitter. Ender Modems haben keine Beschränkung.

**HTTP** ist auf vielen Servern deaktiviert oder auf eine Allowlist beschränkt. `pastebin` und `wget` schlagen dann fehl.

**Speicherplatz.** Computer haben ein Limit (standardmäßig 1000 kB), Floppies 125 kB. `fs.getFreeSpace("/")` prüfen.

---

## 14. Schnellreferenz Peripherie-Erkennung

```lua
-- Alles auflisten, was der Computer sieht
for _, name in ipairs(peripheral.getNames()) do
  local types = { peripheral.getType(name) }
  print(name .. "  ->  " .. table.concat(types, ", "))
end

-- Methoden eines Geraets ausgeben
print(textutils.serialize(peripheral.getMethods("Create_StockTicker_0")))

-- Ergebnis einer Methode inspizieren
local pretty = require("cc.pretty")
pretty.pretty_print(peripheral.call("minecraft:chest_0", "getItemDetail", 1))
```

Dieses Snippet ist der schnellste Weg, jede der oben mit **[UNSICHER]** markierten Angaben im Spiel zu verifizieren.

---

## 15. Quellen

* CC:Tweaked Dokumentation: https://tweaked.cc/
* Create CC-Integration: https://wiki.createmod.net/users/cc-tweaked-integration/
* CC:C Bridge Dokumentation: https://cccbridge.tweaked-programs.cc/ (Spiegel: https://cccbridge.kleinbox.dev/)
* CC:C Bridge Quellcode: https://github.com/tweaked-programs/cccbridge
* Simple Storage Network: https://github.com/Lothrazar/Storage-Network
