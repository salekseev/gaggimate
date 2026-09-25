# Expansion board template

Starting point for a GaggiMate I/O expansion. Fork this KiCad project, set an
address, wire your circuit to the expander's `EXT_*` nets, and the controller
firmware will identify your board by its I²C address.

**Envelope:** 28.16 × 31.00 mm, 2 layers, one M2.5 mounting hole. Passives are 0603,
the expander is VQFN-24 (4 × 4 mm), Q1 is SOT-23.

## What the template provides

| Part | Role |
|---|---|
| U1 `TCA9555RGER` | 16-bit I²C GPIO expander. Its 16 I/O appear as labels `EXT_0`…`EXT_15` — wire your payload to these. |
| JP1 / JP2 / JP3 `SolderJumper_3_Open` | A0 / A1 / A2. These set the I²C address, which **is** the board's identity. |
| Q1 `MMBT2222A` + R10 1K | Low-side switch on `EN_GND`, driven from the host's `EN` line. |
| R1 / R2 / R3 10K | Pull-ups for SDA, SCL and INT. |
| C1 0.1 µF | Expander decoupling. |
| J1 `PinSocket_1x10` | Mates the controller's 10-pin expansion header. |

`EN_GND` is worth understanding: it feeds the TCA9555's **GND pin and its EPAD**, plus
the low side of all three address jumpers. Q1 switches it. So an addon is electrically
inert — not loading the bus, not acknowledging its address — until the host asserts
`EN`. See the caveat below.

## Connector pinout

The addon carries the **socket**; the controller carries the pin header. They mate
pin N ↔ pin (11 − N), so the tables mirror each other:

| Controller header | | Addon `J1` | Net on the addon |
|---|---|---|---|
| 1 | ↔ | 10 | +5V |
| 2 | ↔ | 9 | +5V |
| 3 | ↔ | 8 | +3V3 |
| 4 | ↔ | 7 | **GPIO13** — spare direct MCU pin, no load on the template |
| 5 | ↔ | 6 | `INT` (controller GPIO12) |
| 6 | ↔ | 5 | `SDA` (controller GPIO8) |
| 7 | ↔ | 4 | `SCL` (controller GPIO2) |
| 8 | ↔ | 3 | `EN` (controller GPIO1) |
| 9 | ↔ | 2 | GND |
| 10 | ↔ | 1 | GND |

In firmware these are `ext1Pin`…`ext5Pin` = GPIO 1, 2, 8, 12, 13
(`lib/GaggiMateController/src/ControllerConfig.h`). Note the ordering: `ext2Pin` is
SCL and `ext3Pin` is SDA, per `Wire.begin(ext3Pin, ext2Pin, 400000)` in
`GaggiMateController::detectAddon()`.

> **Meter the SDA/SCL positions before wiring.** The table above comes from tracing
> `pcb/Gaggimate.kicad_sch`, which puts GPIO8 (SDA) on pin 6 and GPIO2 (SCL) on pin 7.
> The SPX Adapter Board BOM, an independently built design, instead lists `EXT-PIN 7` as
> SDA and `EXT-PIN 8` as SCL. Both sources agree pin 1 is +5V and pin 9 is GND, so this
> is not a systematic off-by-one — one of them is wrong about the middle pins, and it has
> not been resolved. Firmware is unambiguous that **SDA is GPIO8 and SCL is GPIO2**; it
> is the pin *positions* that are in doubt.

**Three of these are direct MCU pins, not expander pins** — GPIO1, GPIO12 and GPIO13.
That matters if your addon needs real-time I/O (a UART, a pulse input, an interrupt):
the TCA9555 is far too slow for bit-level timing, but those three pins are routed
straight to the ESP32-S3, and the GPIO matrix can map almost any peripheral onto them.
`ext4Pin` and `ext5Pin` (GPIO12, GPIO13) are currently unused by firmware.

## Address allocation

From the schematic's own table (`gaggimate-expansion-template.kicad_sch`):

| A2 A1 A0 | Address | Usage |
|---|---|---|
| L L L | `0x20` | Pressure + Dimmer |
| L L H | `0x21` | Dual Boiler |
| L H L | `0x22` | free |
| L H H | `0x23` | free |
| H L L | `0x24` | free |
| H L H | `0x25` | free |
| H H L | `0x26` | Velofuso Pump |
| H H H | `0x27` | reserved |

Only `0x26` is implemented today
(`lib/GaggiMateController/src/peripherals/addons/GearpumpAddon.*`). `detectAddon()`
scans the whole range and logs anything it finds, so an unrecognised board is visible
in the log before its driver exists.

## Firmware side

`GaggiMateController::detectAddon()` brings up `Wire` on the expansion pins at
400 kHz, probes `0x20`–`0x27`, and constructs a driver for each address it knows.
Adding an addon means adding a class under `peripherals/addons/` and a branch there.
`GearpumpAddon` is the reference: it takes `(addr, sda, scl, …)`, talks to its own
payload over a `SoftWire` bus, owns a FreeRTOS task, and has an
`ensureSafePowerOnState()` that programs a safe default into its DAC's EEPROM so a
power cycle cannot come up commanding output. Copy that last habit.

## Caveat: nothing drives `EN`

**A board built to this template verbatim will not enumerate.** `EN` is controller
GPIO1 = `ext1Pin`, and firmware never configures it as an output or drives it. Its
only use outside `ControllerConfig.h` is being passed as `GearpumpAddon`'s fourth
constructor argument, which is named `interrupt`, stored, and never read.

So `EN` floats, Q1 stays off, `EN_GND` never reaches ground, the TCA9555 has no ground
return, and it will not acknowledge its address. The shipped Velofuso addon presumably
ties `EN_GND` straight to `GND`.

Either workaround is fine, but pick one deliberately:

- **On your board:** omit Q1 and R10 and tie `EN_GND` to `GND`. Simplest, and it
  matches what evidently ships — but you lose the inert-until-enabled property.
- **In firmware:** assert it before probing, which is what the hardware intends:

  ```cpp
  pinMode(_config.ext1Pin, OUTPUT);
  digitalWrite(_config.ext1Pin, HIGH);
  delay(1);                        // let the expander's ground settle
  Wire.begin(_config.ext3Pin, _config.ext2Pin, 400000);
  ```

  If you also rename `GearpumpAddon`'s `interrupt` parameter to `enable`, the naming
  stops contradicting the schematic.
