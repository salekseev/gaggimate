# Lelit Elizabeth PL92T — machine reference and bring-up notes

**Status:** reference. No firmware written. Waiting on a prototype of the GaggiMate
board revision that replaces the Gicar, at which point the open questions at the bottom
get answered from the hardware.

## Context

This started as a plan to keep the Lelit control board and replace only the LCC display
board. That approach is **superseded** — the maintainer is producing a full board
revision that replaces the Gicar outright and carries every connection it has, and
people buy the board matched to their machine rather than retrofitting. The reasoning
and the harness work are preserved in
[appendix-retained-gicar.md](appendix-retained-gicar.md).

What is left here is the part that was never about the Gicar: **what this machine is,
what constrains any controller driving it, and how to bring one up without damaging it
or yourself.** All of it applies to the replacement board.

## The machine

From `TECH_5200016EC_PL92T-120_REV00_PartDiagram.pdf` (p.3 control electronics, p.6
wiring and relays, p.7–8 boilers, p.10 hydraulics, p.15 pump):

| Part | Code | Role |
|---|---|---|
| POWER CARD PL92T 100-240Vac | 9600077 | Gicar **9.3.01.30G00** — mains switching + sensor front end. Potted module; HV on Faston tabs |
| DISPLAY LCC DUALBOILER | 9600148 | The brain: UI, PID, pre-infusion logic |
| FLAT CABLE DISPLAY LCC 6WAYS | 9600042 | The only link between them (CN10, 400 mm) |
| TEMPERATURE PROBE ×2 | 9600092 | 50 kΩ NTC, one per boiler |
| LEVEL PROBE 85MM | 9600105L1 | Capacitive, service boiler |
| SENSOR FOR GAUGE 59025-1-T-02-A | 9600009 | Hamlin reed float — tank level |
| SPARE KIT SILENT PUMP 120V | 4000040 | Vibration pump + damper |
| Service boiler | 2000008 | 600 ml, **1000 W**, 120 V (PDF p.7) |
| Brew boiler | MC752-110 | 300 ml, **1100 W**, 120 V (PDF p.8) |
| 4WAY CROSS FITTING | 2200110 | Transducer tap point — already feeds the manometer |
| Manometer | 3700006/32/34 | Mechanical gauge only; no electronic pressure sensor |
| OPV | MC931 | Adjustable; sets brew pressure today |
| Safety thermostats | MC032 / MC521 | 165 °C manual-rearm. **Leave these alone.** |
| Safety valve | 9700043 | 5.5 bar, service boiler. **Leave alone.** |
| Anti-vacuum valve | 9700052 | Service boiler. **Leave alone.** |

The brew/service attribution comes from which fittings share each page: p.7 carries the
5.5 bar safety valve, the anti-vacuum valve and the 85 mm level probe (service-boiler
parts), p.8 the brass diffuser, LELIT58 group gasket and boiler upper-part kit (the brew
group). It is consistent with CN9 driving brew and CN7 service across all three docs.
**Confirm it against your own machine before wiring** — published Elizabeth specs are
often quoted with a larger service boiler than 600 ml, and the interlock argument below
rests on these two numbers.

No flowmeter anywhere. **Both elements together exceed a 120 V / 15 A branch circuit, so
they can never run at once.** That is why the interlock below is a safety requirement,
not a nicety.

## Sensors, and what reads them today

| Sensor | Part | Interface | GaggiMate support today |
|---|---|---|---|
| Brew boiler temp | 9600092 | 50 kΩ NTC | Needs an NTC path; the Pro's stock temp input is K-type via MAX31855. `NtcThermistor` exists but is **never instantiated** and expects a 100 kΩ/B3950 NTC in a 10 kΩ divider read through an ADS ADC channel |
| Service boiler temp | 9600092 | 50 kΩ NTC | same |
| Service boiler level | 9600105L1, 85 mm | **probably conductive — unverified**, see below | **none — see below** |
| Tank level | 9600009 | Hamlin 59025 reed float | No reed input. GaggiMate's water level is optical: `TofMeasurement { distance }` from a VL53L0X, gated on `capabilities.tof` |
| Tank present | 9600010 | micro switch | none |
| Brew pressure | — | mechanical manometer only | Add a 0–1.6 MPa / 0.5–4.5 V transducer; the Pro reads it on an analog terminal block into an onboard ADS1115 |

### Level sensing is the real gap, and it is not just firmware

**First, the probe type is unverified.** The `gicar-8.5.04-protocol` docs call CN1
"capacitive", and this document repeated that. But the Silvia Pro X's equivalent is
explicitly a *conductive* probe — "Conductive Liquid Level sensor, 2 wire, probe +
boiler ground" — and that is the classic espresso autofill arrangement: a single rod
with the boiler shell as return. The Elizabeth's 9600105L1 is a single-rod probe with a
shell return, so **conductive is the more likely reading** and "capacitive" should be
treated as unconfirmed until someone measures it. It changes what front end is needed.

**Second, the reference adapter does not sense level electronically at all.** The SPX
Adapter Board BOM — the design the new GaggiMate board is reportedly based on —
delegates it entirely to a **GRL8-02 standalone AC liquid level controller**, a DIN-mount
module that reads the probe and switches the steam pump directly. GaggiMate never sees
the level; the AC wiring just routes `Steam Pump` to the controller's output contact.

The adapter's author flags this as the weak point themselves: the GRL8-02 is *"the
largest and most expensive part of this kit and would be a great thing to optimize or at
least find one in a small format"*. So a proper front end plus firmware support is
already something that design wants, not a new ask.

### The firmware side of the same gap

Searched the firmware: there is **no capacitive or conductive level sensing anywhere**.
No FDC1004, no capacitive driver, no conductivity driver. The only "conductivity" in the
tree is `PressureController`'s *puck* conductance, which is a hydraulic metaphor and
unrelated.

Two further things that are easy to assume wrongly:

- **`BoilerFillPlugin` is open-loop timers, not level sensing.** It runs
  `PumpProcess(getStartupFillTime())` when the controller becomes ready and
  `PumpProcess(getSteamFillTime())` on leaving steam mode. It never reads a level.
- **The protocol has no level field.** `gaggimate.proto` carries `TofMeasurement
  { distance }` and nothing else level-related.

So service-boiler autofill needs four things that do not exist: an analog front end, a
driver, a proto field, and the control logic. The proto field is the cheap one to get
agreed **before** the board is finalised.

For what the stock electronics do with this probe — a 3-byte value, roughly 128 when
full and 600+ when low — see [lelit-lcc-protocol.md](lelit-lcc-protocol.md). That is the
behaviour a replacement has to reproduce.

## Reference design: the SPX Adapter Board

The new GaggiMate board is reportedly based on the **Silvia Pro X adapter board**, so
its BOM is the best available preview of what to expect. Worth knowing, with the
Elizabeth differences called out:

| Function | SPX adapter | Elizabeth difference |
|---|---|---|
| Boiler temps | 10 kΩ B3950 NTC → 1 kΩ divider at 3.3 V → **ADS1115** channel | **50 kΩ β≈4018**. Same topology, different divider values, and `NtcThermistor`'s constants are hardcoded for neither |
| Heaters | 2× **Carlo Gavazzi RF1A23M25**, 9–18 VDC control, sunk by a **ULN2003AN** off a DC-DC boost to 12 V | Same need — two SSRs. Note these are 12 V-control, not the 3.3 V-logic SSR drive on a Standard board |
| Digital I/O | **PCF8575** I²C expander for tank level in and panel LED out | Elizabeth has three buttons, three button LEDs and a manometer lamp — more I/O, same approach |
| Tank level | vacuum switch, N.O., into the expander | Elizabeth uses a **reed float** (9600009) plus a tank-present microswitch |
| Steam boiler level | **GRL8-02 outboard AC controller** — see above | same probe class; same gap |
| Pump / valve | GaggiMate `P` and `V` outputs via a 7-pole Phoenix AC terminal | same |
| Pressure | transducer at the brew pump outlet | Elizabeth: tap the 4-way cross, part 2200110 |
| I²C + power | taken off the **expansion connector** (5 V, GND, SDA, SCL) | same — but see the pin-position caveat in `pcb/expansion-template/README.md` |

Two things the adapter's author already wants improved, which are therefore easy asks
rather than new ones: replacing the bulky DIN-mount level controller, and moving the
switches and SSR control onto the I²C expander.

## Constraints that bind any controller

These follow from the machine, not from any particular board.

### Both elements can never run together, and nothing backstops that

1000 W + 1100 W at 120 V is **17.5 A — 117 % of a 15 A breaker**. A UL 489 breaker is
not required to trip promptly at 1.17×; it may carry that for an hour or indefinitely.
And the 165 °C thermostats are **per-boiler thermal** cutouts: with both boilers sitting
at their normal temperatures, neither opens. So the failure is not a trip and not a
thermostat — it is the machine's inlet wiring, main switch and cord carrying a sustained
overload they were never sized for.

**There is no electrical backstop. The interlock is the only protection.** Consequences
for whatever drives the elements:

- Make "both" structurally unrepresentable — the two heaters resolve through one arbiter
  that can only return a single active-boiler value — rather than a runtime `if`.
- Assert on the **actual output state** immediately before it is applied, not on the
  arbiter's inputs.
- If the output path has a concurrency story (a shared cache, multiple writer tasks),
  state it: one writer, everyone else posts requests.

### Arbiter starvation causes overshoot

If the brew boiler takes priority during a shot, the service PID can be denied for the
whole shot. Its integral must be frozen or clamped while denied, or it slams the service
element to 100 % the instant brewing ends.

### The dangerous NTC failure is the open circuit, not the short

A **short** reads low resistance, i.e. hot, hits any upper limit and fails safe. An
**open** circuit reads as cold forever, so duty pins high and an upper limit never
trips. A ceiling alone cannot see this. Also covered by nothing: a stuck-but-plausible
reading, which arrives fresh and passes every freshness check while the PID commands
100 % indefinitely.

What actually catches these:

- A **lower** bound, not just an upper one.
- A rate-of-rise check — commanded duty above ~50 % for 30 s must produce ≥ 2 °C.
- Identical raw readings for N consecutive samples on a boiler that is actively heating
  is a fault; ADC noise guarantees the low bit moves.
- A physical-plausibility rate limit: a boiler cannot move more than a fraction of a °C
  in 100 ms.
- **Probe swap.** Both NTCs are the same part (9600092) and nothing forces orientation.
  Swapped, the brew loop regulates the brew element from the service boiler's
  temperature, and the two plausible ceilings are close enough that neither trips
  promptly. Heat exactly one boiler during bring-up and confirm the expected channel
  moves.

### Blast radius needs deciding, not defaulting

"Either boiler over its ceiling → whole machine safe" means one failed service NTC
disables the brew boiler too. That may be right, but it should be a stated decision with
a recovery path, or users will bypass it.

### A controller that is not co-powered with its I/O has a boot window

If the controller can reset while whatever holds the outputs keeps power, the outputs
hold their last state across the reset. On a cold power-up this is harmless, because
both sides lose power together. **Only a controller-only reset is dangerous** —
watchdog, brownout, USB replug, OTA. Whether this applies to the replacement board
depends on whether its output stage is on the same rail as its MCU; worth checking once
it arrives.

## Hydraulics

- **Pressure tap:** the **4-way cross fitting, part 2200110** already feeds the
  mechanical manometer and is the natural transducer point. Needs a tee and PTFE.
- **OPV:** MC931 is adjustable and currently sets brew pressure. Back it off to roughly
  11–12 bar once closed-loop pressure control is in play, or it clamps the profile.
- **Leave alone:** the 5.5 bar safety valve (9700043), the anti-vacuum valve (9700052)
  and both 165 °C manual-rearm thermostats (MC032 / MC521). Behind everything above,
  those are the last line.

## Bring-up ladder

Each step with the next step's loads physically disconnected. This ordering is the
single procedure — do not run a second one in parallel.

1. **Sensors only.** Both elements and the pump disconnected. Confirm both temperature
   channels read plausibly and track a reference thermometer, and that heating exactly
   one boiler moves the expected channel (probe-swap check).
2. **Low-voltage outputs only** — panel LEDs, manometer lamp. Confirms the output path
   with nothing dangerous energised.
3. **Solenoids**, water in tank, elements still disconnected. Confirm which output does
   what hydraulically rather than trusting a label.
4. **Pump**, no elements, blank basket. Confirm smooth modulation and that the
   transducer reads plausible bar against the mechanical manometer.
5. **One element at a time, the other disconnected.** PID settles; autotune runs.
   **Record steady-state stability** in °C peak-to-peak at the brew setpoint over 10
   minutes and again during a shot — it is the number that tells you whether the control
   path is good enough.
6. **Both elements connected.** Clamp-meter the supply and confirm total draw never
   shows both on, including with both loops saturated from cold. This is the step that
   validates the only protection the machine has.
7. **Full shot.** Pressure profile tracked, shot graph recorded, BLE scale stops on
   weight. Run the flow calibration.
8. **Fault injection.** Interrupt the link between controller and output stage mid-shot;
   confirm the machine ends up safe, **including that the pump stops**, and recovers.
9. **Warm reset, not a power cycle.** With a boiler commanded on, reset the controller
   alone while the output stage keeps power, and clamp-meter how long the element stays
   energised. A power cycle does not test this — it drops both sides.
10. **Restore stock** and confirm the machine still runs unmodified.

## Open questions for the prototype

1. **Level sensing** — is there any front end, or is the expectation an outboard
   controller as in the SPX adapter? And measure the 9600105L1 to settle conductive
   versus capacitive, since that decides the front end.
2. **Temperature front end** — the SPX adapter reads 10 kΩ/B3950 NTCs through a 1 kΩ
   divider at 3.3 V into an ADS1115, which is exactly the path `NtcThermistor` expects.
   But its constants are file-scope `constexpr` (`Rs=10000, Vs=5.0, Beta=3950,
   Ro=100000`), so they match neither the SPX divider nor the Elizabeth's **50 kΩ
   β≈4018** probes. Parameterising them per board is small and now demonstrably needed
   by two machines.
3. **Tank level** — reed float input, or is the expectation a ToF retrofit?
4. **Pump output** — is there a dimmer, and is it PSM like the Pro's?
5. **Pressure input** — analog terminal block as on the Pro?
6. **Output stage power domain** — same rail as the MCU, or can it hold state across a
   controller reset? Decides whether the boot window above applies.
7. **Connector pinouts** — the Molex Micro-Fit 3.0 2×12 and Hirose DF63 6P maps, for
   documenting the install.

## Related documents

- [appendix-retained-gicar.md](appendix-retained-gicar.md) — the superseded approach and
  why it was abandoned.
- [lelit-lcc-protocol.md](lelit-lcc-protocol.md) — stock LCC↔control-board wire format.
  Still the best record of what the stock electronics do, including the capacitive probe.
- [lelit-alternatives-considered.md](lelit-alternatives-considered.md) — why the stock
  bus cannot carry pump power, and why other open-hardware controllers were rejected.
