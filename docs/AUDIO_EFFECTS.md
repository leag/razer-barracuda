# Optional audio effects

The widget's **Equalizer**, **Microphone** and **System** tabs add software controls inspired by
[Tarik Topalovic's Barracuda 2.4 project](https://github.com/TarikTopalovic/razer-barracuda-2.4-linux/tree/d1d1cc2861962a236be848a367b5b4db810cc135).
That project targets USB `1532:053c`; this implementation targets Barracuda X
(2022), USB `1532:0552`. Its device-write commands are not used.

## Included features

| Feature | Implementation here |
| --- | --- |
| Headphone EQ | Ten PipeWire biquad bands, 31 Hz–16 kHz, ±12 dB |
| Microphone EQ | Ten bands, 100 Hz–12 kHz, with a fixed 75 Hz high-pass |
| Presets | Twelve output and eight microphone starting-point curves |
| Custom profiles and favorites | Stored separately for output and microphone under XDG config |
| Sidetone | Software mic monitoring into the Barracuda, with adjustable gain |
| Mic mute and volume | Optional controls hidden by default; independent of the physical mute button |
| Latency | Optional session buffer: system default, 256, 512, or 1024 frames |
| Sample rate | Optional 48 kHz session rate |
| Suspend behavior | Optional keep-awake rule scoped to Barracuda audio nodes |
| Output cushion | Optional output-only headroom of 512, 1024, or 2048 frames |
| Battery, charging, pairing | Existing driver/KDE telemetry and validated pairing CLI |

Hardware sidetone, hardware power-saving (`0xac`), BLE hardware EQ (`0x93`),
THX and microphone noise cancellation are not exposed as working device controls.
Those HID/BLE writes have not been validated for `1532:0552`. No firmware commands,
parameter sweeps, OpenRazer replacement driver, or recording tools are installed.
The original project's device information and protocol findings do not establish
support on the X (2022).

The preset curves are reproduced under MIT, with attribution and license in
[LICENSES/TarikTopalovic-MIT.txt](../LICENSES/TarikTopalovic-MIT.txt). They are
listening starting points from a different model, not a measured calibration
for the Barracuda X. Implementation of the backend and native Plasma UI is local.

## Use

Install `barracuda-audio`, included in the Python package, plus `pipewire`,
`wireplumber` with smart-filter support, and `pactl` for the optional microphone
controls (`libpulse` on Arch). For a checkout installation:

```bash
python scripts/install.py --audio-controls
```

This installs the helpers only. It neither enables effects nor changes the audio
session. Ensure `~/.local/bin` is on the desktop session's `PATH`.

1. Open the widget and select **Equalizer**, **Microphone**, or **System**. Opening a settings tab reads device
   availability and saved settings; it does not enable processing.
2. Choose headphone or microphone EQ. The Microphone tab opens with sidetone;
   expand **Microphone equalizer** for its profiles. Enable the equalizer and select
   a preset, or expand **Adjust frequency bands** for the compact ten-band editor.
   Sliders and closed selectors do not change values when scrolling the panel;
   drag sliders or use their arrow keys to adjust them.
   Expand **Manage custom profiles** to add or delete your own curves.
   Custom profile names must be unique and no longer than 60 characters. The star
   marks favorites and sorts them first.
3. Choose **Save** in the fixed bottom toolbar. Existing equalizer nodes receive the new gains live;
   the same gains are saved for the next session. Positive gains automatically
   attenuate the preamp by the largest boost to leave headroom. This is not a limiter.
4. For enabling/disabling filters, sidetone, or changing system tuning, choose
   **Apply and restart…** and confirm. This restarts PipeWire, pipewire-pulse
   and WirePlumber, briefly interrupting playback and calls.
5. To revert, choose **Disable effects and use system tuning**, save, and apply.
   This empties only this project's fragments; it preserves custom profiles and
   other audio configuration.

The microphone must be exposed by the current card profile for sidetone or mic
volume/mute commands. The helper never changes that profile. If it is missing,
select a profile with input in KDE Sound settings yourself. Software mute controls
are hidden behind **Show software microphone controls**. They do not report or
synchronize the physical mute button. Mic volume changes require pressing the
separate **Set mic volume** button; moving that slider alone makes no change.

Sidetone explicitly targets the Barracuda source and sink found by device
properties. It does not fall back to laptop speakers or another microphone.
Both monitoring streams request a 128/48000 latency (2.67 ms per processing
block) while active, using PipeWire's `node.latency` negotiation. This may lower
the shared graph's quantum; a forced quantum or another scheduling constraint
can override the request. This is not the measured microphone-to-ear latency:
device buffers and the wireless round trip still add delay. Software monitoring
cannot guarantee the immediacy of hardware sidetone.
Enabling it requires both devices to exist. EQ uses WirePlumber's smart-filter
policy to process streams targeting the Barracuda; it does not set default devices
or move application streams manually. Other devices' processing is unchanged.

Buffer size and rate settings affect the entire PipeWire session. Keep-awake and
output headroom affect only the Barracuda. Smaller buffers can cause underruns;
these options are not asserted to cure radio interference, ADC clipping, or
kernel clock faults. There is no automatic ALSA capture-gain change.

## Persistence and ownership

Files are written only after an explicit save, respecting `$XDG_CONFIG_HOME`
(default `~/.config`):

- `barracuda-audio/settings.json`: profiles, favorites, gains and switches.
- `pipewire/pipewire.conf.d/90-barracuda-effects.conf`: enabled EQ/monitoring graphs.
- `pipewire/pipewire.conf.d/91-barracuda-latency.conf`: optional session tuning.
- `wireplumber/wireplumber.conf.d/90-barracuda-audio.conf`: device-scoped rules.

Fragments carry an ownership header. Existing foreign fragments at those paths
and symlinks are refused. Writes are staged; failed replacements roll back files.
A lock prevents simultaneous mutating helper calls. There is no Python daemon,
autostart entry, polling monitor, or new permanent service. PipeWire loads the
saved effects as part of its normal startup.

For scripting, the helper accepts JSON requests through `--request`; the default
request is read-only status. Audio restarts require `{"op":"apply","confirmed":true}`
and a previously saved configuration. UI errors are translated in English and
Spanish; command diagnostics are shown verbatim. Closing the widget does not
cancel an already requested audio operation.

## Validation

Tests mock audio commands, use temporary HOME/XDG directories, and exercise the
QML controls offscreen. A separate test loads the actual filters and changes their
controls in a private PipeWire server with no physical devices, no session manager,
and a separate runtime directory. This proves graph loading and control updates;
it is not a physical listening test or proof of routing in the user's session.

References: [PipeWire filter-chain](https://docs.pipewire.org/page_module_filter_chain.html),
[WirePlumber smart filters](https://pipewire.pages.freedesktop.org/wireplumber/policies/smart_filters.html).
