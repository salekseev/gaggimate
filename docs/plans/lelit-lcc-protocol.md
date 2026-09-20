# Lelit LCC ↔ Gicar 8.5.04 protocol reference

Reference for the serial bus between a Lelit machine's front display board (the
"LCC") and its Gicar 8.5.04 power card. Written for the **Elizabeth PL92T**, whose
power card is Lelit part **9600077** and whose stock display board is **9600148**.

This document is the wire-format reference. For the build that uses it, see
[lelit-elizabeth-gaggimate.md](lelit-elizabeth-gaggimate.md).

## Provenance

| Source | What it is | Trust |
|---|---|---|
| [`4ndrey/lelit-elizabeth-protocol`](https://github.com/4ndrey/lelit-elizabeth-protocol) | Working ESP32/Arduino library for the Elizabeth **V3**. Both LCC-master and man-in-the-middle modes. | Primary. It is executable, not prose. |
| [`variegated-coffee/gicar-8.5.04-protocol`](https://github.com/variegated-coffee/gicar-8.5.04-protocol) | Protocol/pinout docs for the Gicar family. Its `lelit-elizabeth.md` is headed **"(speculative)"** with question marks on three of four FA lines. | Corroborating. Distrust its FA labels. |
| [`variegated-coffee/open-lcc-rp2040-bianca`](https://github.com/variegated-coffee/open-lcc-rp2040-bianca) | Shipping LCC-replacement firmware for the Bianca. Field-proven master implementation, safety interlocks, timing. | Primary for timing and safety patterns. |
| [`magnusnordlander/lelit-bianca-protocol`](https://github.com/magnusnordlander/lelit-bianca-protocol) | The Bianca equivalent. Same framing, different bit assignments. | Useful for contrast. |

**Bit positions are stable across all sources. FA *labels* are not.** Where they
disagree, trust the two code implementations: both put the **pump on SR2 bit 4**,
while the `gicar-8.5.04-protocol` prose table puts FA7 on SR1 bit 4.

## Architecture

The Gicar is not a controller. It is a **dumb I/O expander**: an STM8S003F3P6 plus
two daisy-chained STPIC6C595 open-drain power shift registers, an ADC front end for
the thermistors and level probe, and the mains switching. Every decision — PID,
pre-infusion timing, autofill, UI — lives in the LCC. Replacing the LCC means taking
over all of it.

```mermaid
flowchart LR
  subgraph LCC["LCC display board (the brain)"]
    UI["UI + PID + pre-infusion + autofill"]
  end
  subgraph GICAR["Gicar 8.5.04 (I/O expander)"]
    SR["2x STPIC6C595<br/>open-drain shift registers"]
    ADC["STM8 ADC front end"]
  end
  UI -->|"0x80: 5 bytes, actuator bitmap"| SR
  ADC -->|"0x81: 18 bytes, sensor readings"| UI
  SR --> HEAT["CN9 brew SSR<br/>CN7 service SSR"]
  SR --> SOL["FA7 pump<br/>FA8 / FA9 / FA10 solenoids"]
  SR --> LED["Panel LEDs + manometer light"]
  NTC["2x 50k NTC"] --> ADC
  LVL["Capacitive level probe"] --> ADC
  TANK["Tank reed float"] --> ADC
```

## Electrical

Connector **CN10**, 6-way 2.54 mm. The stock cable is Lelit **9600042**
(6-way, 28 AWG, 400 mm); **the red wire is pin 6**, which is how you establish
orientation.

| Pin | Signal | Level | Notes |
|---|---|---|---|
| 1 | +12 V | 12.6 V measured | Powered the stock OLED |
| 2 | TX → Gicar | **3V3** | Driven by the LCC |
| 3 | RX ← Gicar | **5 V** | Must be attenuated or buffered before any 3V3 GPIO |
| 4 | GND | — | |
| 5 | 3V3 (OLED) | 3.1 V measured | Do not draw a replacement board's supply from here |
| 6 | 3V3 (MCU) | 3.1 V measured | Same warning — see below |

**UART 9600 8N1 with inverted signalling.** The LCC is bus master. On an ESP32 the
inversion is a `begin()` flag, not external hardware:

```cpp
Serial1.begin(9600, SERIAL_8N1, /*rx=*/44, /*tx=*/43, /*invert=*/true);
```

> **Do not power a replacement board from pins 5/6.** Relying on the Gicar's 3V3
> rails is what made Open LCC revision R1A *"NOT RECOMMENDED for any purpose"* —
> they cannot supply the current. Take 12 V from pin 1 into your own regulator, or
> power the board independently and share only GND.

## Frames

Strict request/response. The master writes 0x80 and reads 0x81.

### LCC → Gicar — 5 bytes, header `0x80`

```
80  ii  jj  bb  zz
    |   |   |   +-- CheckSum8 mod 128
    |   |   +------ front panel buttons echoed back
    |   +---------- shift register 1 bitmap
    +-------------- shift register 2 bitmap
```

`bb`: `0x08` = minus, `0x04` = plus, `0x0B` = both.

**Safe state is `80 00 00 00 00`.**

### Gicar → LCC — 18 bytes, header `0x81`

```
81  uu  cc cc cc  ss ss ss  CC CC CC  SS SS SS  tt tt tt  zz
    |   |         |         |         |         |         +-- CheckSum8 mod 128
    |   |         |         |         |         +------------ service boiler level
    |   |         |         |         +---------------------- service temp, HIGH gain
    |   |         |         +-------------------------------- brew temp, HIGH gain
    |   |         +------------------------------------------ service temp, LOW gain
    |   +---------------------------------------------------- brew temp, LOW gain
    +-------------------------------------------------------- status / buttons
```

### Checksum

Sum of bytes, `& 0x7F`. The header drops out if you seed `0x00` for 0x80 frames and
`0x01` for 0x81 frames, which is why reference implementations do exactly that
(`0x80 mod 128 == 0`, `0x81 mod 128 == 1`).

### The 3-byte "triplet" encoding

Payload is 7-bit-clean because `0x80` and `0x81` are reserved as headers. Byte 2 is a
flag carrying bit 7 of the low byte:

```c
if (b2 == 0x7F) return (b1 | 0x80) + (b0 << 8);
if (b2 == 0x00) return  b1         + (b0 << 8);
return 0xFFFF;   // unknown - treat as sensor error
```

## Bit maps (Elizabeth)

### Shift register 1 — byte `jj`

| Bit | Mask | Function |
|---|---|---|
| 0 | `0x01` | CN6_1 top button LED |
| 1 | `0x02` | CN6_3 bottom (water) button LED |
| 2 | `0x04` | CN6_5 middle button LED |
| 3 | `0x08` | **CN9 brew boiler SSR** |
| 4 | `0x10` | **FA8 coffee / 3-way solenoid** |
| 5 | `0x20` | **FA10 inlet solenoid (pre-infusion)** |
| 6 | `0x40` | OLED 12 V disable (unverified) |
| 7 | `0x80` | OLED 3V3 disable (unverified) |

### Shift register 2 — byte `ii`

| Bit | Mask | Function |
|---|---|---|
| 0 | `0x01` | CN5 manometer light |
| 1 | `0x02` | **CN7 service boiler SSR** — see caveat below |
| 4 | `0x10` | **FA7 pump** |
| 5 | `0x20` | **FA9 water-dispense solenoid** |

Bits 2, 3, 6, 7 are unconnected.

> **Elizabeth-specific caveat:** CN7 is **not** a shift-register drain. It is a
> direct STM8 GPIO with a 5 V pull-up, configured as an *output* on the Elizabeth and
> an *input* on the Bianca. Expect its behaviour to differ from the other bits and
> verify it on the bench.

### Status byte `uu`

| Mask | Meaning |
|---|---|
| `0x08` | Top button pressed |
| `0x10` | Middle button pressed |
| `0x20` | Bottom (water) button pressed |
| `0x40` | **Water tank empty** |

The Bianca firmware rejects the Elizabeth's button bits (`flags & 0xBD` →
`UNEXPECTED_FLAGS`) and reads brew demand from `flags & 0x02`, the brew-lever
microswitch. The Elizabeth has no brew lever; demand arrives as a button bit.

## Sensor conversion

### Temperature

Two 50 kΩ NTCs, each reported at two ADC gains. Prefer the high-gain channel. Two
equivalent conversions are in circulation:

- **Steinhart-Hart**, R25 = 50 kΩ, β ≈ 4018 — used by `gicar-8.5.04-protocol` and the
  Bianca firmware, via ADC → ohms → temperature.
- **Direct cubic polynomials** on the raw ADC — used by the `4ndrey` Elizabeth library
  (`adcToTempLo` / `adcToTempHi`).

Implement one and unit-test it against the other. They should agree across the
working range; a divergence means you have the gain selection wrong.

### Service boiler level

Capacitive probe on CN1, reported as a triplet. Roughly **128 when full**, **600+ when
low**. The Bianca firmware thresholds at `> 256`.

There is **no brew boiler level sensor**. Tank level is the single `0x40` status bit.

## Timing

The reference master writes 0x80, then does a blocking 18-byte read with a **100 ms
timeout that doubles as the cycle period** — so roughly **10 Hz**. Before the system
is started it sends safe packets at 1 Hz.

That 100 ms tick is also the SSR time-slice quantum. The Bianca firmware runs a
25-slot window = **2.5 s soft-PWM period**, which is the practical resolution you get
for heater duty over this bus: 25 steps, or 4 %.

```mermaid
sequenceDiagram
    autonumber
    participant M as LCC (master)
    participant G as Gicar 8.5.04
    loop every 100 ms
        M->>G: 0x80 ii jj bb zz  (5 bytes, actuator bitmap)
        G-->>M: 0x81 ... zz      (18 bytes, sensors + buttons)
        Note over M: validate header + checksum<br/>decode triplets<br/>run PID slice<br/>assemble next bitmap
    end
    Note over M,G: on bail: keep sending 80 00 00 00 00.<br/>Going silent latches the last state.
```

## Safety behaviour

Three properties of the Gicar that any master must design around.

**1. It boots safe but does not fail safe.** The Gicar comes up with all relays off
and all solenoids closed, but **it does not revert to a safe state if the LCC stops
transmitting** — outputs latch in their last commanded state. A master that crashes
with the pump bit or a heater bit set leaves that load energized indefinitely.

Consequences for firmware:
- Send the safe packet as the **very first** thing at boot, before anything else, so a
  watchdog reset clears a latched output.
- On any bail condition, **keep transmitting the safe packet**. Do not stop talking.
- Send it explicitly before any intentional disconnect.

**2. There is no command channel.** The 0x80 frame carries an actuator bitmap and two
button bits — nothing else. There are no temperature setpoints, no timers, no
pre-infusion parameters and no error codes on this bus. Everything is the master's
job. Pre-infusion is expressed only as the master's own timing of the pump and
solenoid bits.

**3. Pump power is a single bit.** `SR2 & 0x10`, a `bool`. The frame is fixed at five
bytes with no spare field, and the bytes are shift-register drain bitmaps clocked into
open-drain latches — DC on or off per drain, with no per-bit timing. Variable pump
power is not expressible on this protocol at any version. See
[lelit-alternatives-considered.md](lelit-alternatives-considered.md).

## Interlocks worth copying

From `open-lcc-rp2040-bianca`, which has these in the field:

| Interlock | Rationale |
|---|---|
| **Never both boiler SSR bits in one frame** | Two elements on one branch circuit. On a 120 V Elizabeth that is 1000 W + 1100 W. |
| Temperature ceilings → safe state | 140 °C brew, 150 °C service. |
| Invalid or stale 0x81 → safe state | |
| Master unresponsive → safe state | |
| Power sharing between boilers | Brew priority; brew takes 100 % of slots while brewing. |

One to **not** copy blindly: open-lcc forbids "solenoid open without pump". On the
Elizabeth, FA8 is the 3-way/drain and that combination is legitimate. Confirm the
hydraulics before adding it.
