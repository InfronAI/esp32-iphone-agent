# Testing the board from a Mac

`board_test.py` plays the iOS app over BLE (docs/ble-protocol.md); the Mac's own Screen
Mirroring feeds the board's AirPlay receiver, so AirPlay -> PSRAM GOP -> BLE -> H.264 can be
checked without the iPhone. Needs `uv`, `arduino-cli` with esp32 core 3.3.x, `ffmpeg`, and the BLE host
library (once): `arduino-cli lib install "NimBLE-Arduino"` (2.5.x). Always build with `hardware/flash.sh`:
it force-includes `hid_bridge/nimble_cfg.h` (NimBLE buffer sizes); a plain IDE build fails a static_assert.

## 1. Flash a test build (board plugged into the Mac)

```bash
cp hardware/hid_bridge/secrets.example.h hardware/hid_bridge/secrets.h   # once; fill in the Mac's Wi-Fi
hardware/flash.sh --sta --debug    # joins that Wi-Fi instead of opening its hotspot; logs on USB serial
```
Watch the log (AirPlay handshake steps, boot heap/PSRAM line):
```bash
arduino-cli monitor -p /dev/cu.usbmodem* -c baudrate=115200
```
Without `--sta` the board opens its own hotspot `ESP32Agent-XXXX` (password: `net` read below);
the Mac can join that instead, but then it has no internet.

## 2. BLE only (no mirroring yet)

```bash
uv run hardware/tools/board_test.py info        # pairs (macOS prompt), reads `net`, prints status
uv run hardware/tools/board_test.py bench --kb 512
uv run hardware/tools/board_test.py hid         # moves/clicks the Mac's pointer: board is a USB mouse
uv run hardware/tools/board_test.py stress --seconds 20 --kb 512   # bench filler + ping/move every 200 ms
```
`stress` prints reply latency p50/p95/max and missing replies (target: 0 missing, p95 < 500 ms);
`--load stream` uses `stream on` instead (needs mirroring). The Mac receives only ~100-200 kbps, so use the
iPhone for throughput: with `--debug`, send `N bench 512` on the USB serial; the result is echoed as
`video: N ok <ms>` (kbps = 512*8*1024/ms). A/B the radio: `N coex bt|balance|wifi` on serial, and
`hardware/flash.sh --ap-tune` (20 MHz hotspot, 300 TU beacons) vs a normal build.
`net` passwords are masked in the output.

## 3. AirPlay -> BLE

1. Control Center -> Screen Mirroring -> **ESP32 Agent** (the Mac must be on the same Wi-Fi).
   The serial log should show `GET /info`, `pair-setup`, `pair-verify 1/2`, `fp-setup 1/2`,
   `setup: mirror stream`, `mirror: data connection accepted`, `mirror: SPS ... PPS`.
2. Then:
```bash
uv run hardware/tools/board_test.py snap        # -> hardware/tools/out/snap.h264 + snap.png (snap latency)
uv run hardware/tools/board_test.py stream --seconds 20   # -> out/stream.h264 + stream.png, kbps, gaps
uv run hardware/tools/board_test.py all         # info, bench, snap, stream, hid, status
uv run hardware/tools/board_test.py cmd "res 480 1040" "fps 5"   # any command lines
```
`ffplay hardware/tools/out/stream.h264` plays the stream.

## 4. Back to the iPhone

Reflash without `--sta` (`hardware/flash.sh`), then plug the board into the iPhone.

## TODO / next optimizations (measured 2026-10-15, NimBLE-Arduino 2.5.1, board on the Mac + iPhone app connected)

- Throughput vs latency: `bench 512` to the iPhone (serial) was ~381 kbps (balance), ~412 (`coex bt`),
  ~364 (`coex wifi`) with only the msys reserve gate; 30 ms interval halved it (180 kbps). With the
  controller-credit cap while commands flow (VIDEO_CTRL_PKTS = 8, CMD_ACTIVE_MS = 1000) it is
  ~130-170 kbps, because the app's periodic pings keep the cap on. Mac stress (bench load, ping/move
  every 200 ms): 0 missing, p50 33-66 ms, p95 83-156 ms, max 93-262 ms (before the cap: p95 0.96-2.2 s).
  Next: cap per connection instead of globally, tune VIDEO_CTRL_PKTS/CMD_ACTIVE_MS on the iPhone, or
  ignore the app's keepalive pings when deciding "commands flow".
- L2CAP CoC for video (1 channel x 247 MPS is already configured, unused).
- Coex A/B on the iPhone with live mirroring (`coex`, `--ap-tune`); not measured with AirPlay running yet.
- Stream: IDR-only fallback (P-frames > 800 ms old are skipped) not yet exercised with live mirroring
  (`board_test.py stress --load stream`).

## Autonomous cloud firmware (experimental)

`hardware/flash.sh --cloud [port]` builds a separate mode in which the ESP32-S3
joins the router, receives AirPlay, decodes H.264, encodes grayscale JPEG, calls
an HTTPS vision API, and executes the returned action using USB HID. The iPhone
app and BLE video relay are not required in this mode. The original firmware
remains the default when `--cloud` is omitted.

1. Copy `hardware/hid_bridge/secrets.example.h` to `secrets.h` (git-ignored).
   Set `WIFI_SSID`, `WIFI_PASS`, `CLOUD_LLM_URL`, `CLOUD_LLM_MODEL`, and
   `CLOUD_LLM_KEY`. The model must accept OpenAI-compatible `image_url` input.
2. Build/flash with `hardware/flash.sh --cloud --debug [port]`. The decoder is
   built from a pinned Cisco OpenH264 commit; the source archive is checked
   against its SHA-256 before applying the ESP-IDF/Xtensa port adaptations.
3. Read USB serial at 115200 baud. Boot prints the local control URL and token.
   Serial commands: `1 agent status`, `2 agent token`, `3 agent test`,
   `4 agent start <goal>`, `5 agent stop`. Commands end with a newline.
   `7 agent vision-test` sends a fresh decoded screenshot to the cloud for a
   description only. It never schedules a HID action and needs no calibration.
   If Wi-Fi does not connect, `6 wifi-scan` lists visible 2.4 GHz networks,
   channels, signal strength, and authentication modes on serial. It refuses
   to interrupt an established Wi-Fi connection.
4. Join the iPhone to the same router's Wi-Fi, enable AssistiveTouch, and mirror
   to **ESP32 Agent**. The router must allow local clients/mDNS to communicate.
   ESP32-S3 requires a 2.4 GHz Wi-Fi network. This build uses station mode,
   **not** the board's former `ESP32Agent-XXXX` hotspot.
5. Connect the board's native USB port to the iPhone through an appropriate
   host adapter (Lightning camera adapter for iPhone 13). A normal Lightning
   charge/data cable does not make the iPhone a USB host. `usb: ok` means a host
   mounted USB; it cannot distinguish a Mac from an iPhone.
6. Complete phone setup in the iPhone app and confirm the physical USB connection
   there. Open `http://iphone-agent.local/` on the Mac and enter the control token.
   The dashboard prioritizes the live phone monitor; readiness tiles are read-only
   and phone settings guides are only in the iPhone app. Begin pointer calibration
   from the monitor, wait for the pointer to stop, then click its center in the image.
   Enter a task or choose an example. Stop remains available during model requests;
   a cancelled response cannot execute an action. Pending HTTPS can take up to 60 s.

The monitor fetches a fresh JPEG about every five seconds by default, including while tasks run.
It serializes image requests, supports 3/5/10-second intervals, pause/manual refresh/fullscreen, pauses in
background tabs, and clears old images when disconnected or mirroring becomes stale.
The snapshot API rejects frames older than five seconds and reports `X-Frame-Age-Ms`.
Calibration temporarily pauses automatic refresh so the pointer location stays stable.

The first desktop viewport places monitoring next to the execution timeline. Tasks
and examples sit below it; device health and model settings are last. Authenticated
`GET /api/trace` returns the latest task's input, request text/image metadata, public
model observation/reason, selected action parameters, execution feedback and timing.
The board retains at most 48 events in PSRAM, reports evicted/truncated records, and
clears the history on a new task or reboot. It does not expose API keys, image base64,
or provider reasoning fields. The page only reloads the log when `trace_revision`
changes; it supports expanding details and disabling follow-latest while reading.

Task execution uses a bounded Goal harness on the board. Each model call receives
the unchanged original Goal, the latest screenshot, a rolling progress summary,
current subgoal, expected result of the preceding action, harness feedback and up
to six recent actions with observations and HID acknowledgements. The model must
return one action plus `observation`, `summary`, `progress`, `reason`, and (for an
action) `subgoal` / `expected`. These fields are concise public explanations, not
internal reasoning. `done` requires a final `text` answer and visible `evidence`;
`blocked` reports an obstacle and becomes `paused`, never success.

The cycle is observe → decide → dispatch one action → wait for a newer, settled
frame → assess actual progress. HID acknowledgement alone is not task success.
The first `done` is provisional: the board obtains another screenshot and asks
for an independent completion check; a contrary observation resumes execution.
A small screen-body dHash helps detect substantial changes during inference or
before dispatch; stale proposals are discarded and replanned. This heuristic is
not a proof that two screens are identical or that a task succeeded.

Limits are 20 action attempts, 40 model calls and 10 minutes per Goal. The harness
allows two retries for transient HTTP/transport failures or malformed output,
with fresh screenshots and no replay of prior HID commands. Repeated ineffective
actions trigger replanning; four actions without confirmed visual progress, or
repeated rejected proposals, pause for user help. Partial/uncertain HID execution
also pauses rather than blindly resending. A stopped epoch cannot dispatch later
model responses. History is per task in PSRAM and clears on a new Goal/reboot.
`/api/status.harness` exposes phase, round, summary, subgoal, expected result,
retries and stagnation counts; the web timeline includes progress, verification,
replanning and the actual bounded context sent to the model. Existing iPhone
clients continue to use `/api/start`, `/api/stop`, state/detail and step counts.

Run `make -C hardware/tests harness` for native protocol and loop regressions with
address/undefined-behavior sanitizers. The test runner downloads checksum-pinned
cJSON 1.7.19 into ignored build storage; it never contacts an LLM or sends HID.

Video diagnostics distinguish `queue_ms`, `decode_ms`, `jpeg_ms`, `pipeline_ms`, and
HTTP transfer measured by the browser. `frame_age_ms` starts when the compressed
frame reaches the board, not when the iPhone captures it; it is not an end-to-end
latency measurement. Output timestamps follow OpenH264's YUV frame timestamp.
Every reference frame is decoded; independent JPEG exports can be skipped during
bursts to catch up. JPEG quality is 90, while source resolution remains constrained
by decoder PSRAM. The port uses upstream's `-fno-strict-aliasing` requirement; see
[OpenH264's GNU flags](https://github.com/cisco/openh264/blob/652bdb7719f30b52b08e506645a7322ff1b2cc6f/build/platform-gnu-chain.mk).

The port also fixes progressive long-term reference numbering for MMCO 3/6.
Upstream 2.6.0 stores the frame index but leaves the picture number unset; the
High-profile reference-list path then selects the wrong picture for AirPlay LTR
indices 1/2. This produced persistent ghosting even with no decode errors or
network backlog. A local 24-frame iPhone capture now matches FFmpeg's luma output
pixel-for-pixel. The live I/P path drains OpenH264's display queue after each access
unit, eliminating the otherwise unnecessary one-frame wait. B/SP/SI slices are
rejected rather than publishing pictures in the wrong order. The monitor remains
grayscale to fit decoder and cloud-request buffers into the board's 8 MiB PSRAM.

To repeat the decoder regression with a private local capture (do not commit phone
video), run `python3 hardware/tests/test_cloud_decoder.py --stream capture.h264
--packets packets.json`. The script checks pixels against FFmpeg and checks every
output timestamp against its input; `--unpatched` demonstrates the original
reference-frame failure. Packet metadata is an array of `size`, `at_ms`, `config`.
In a debug build, serial `0 agent capture on` / `off` enables/disables raw Annex-B
capture; it is disabled by default and has no HTTP route. Capture framing is
`\n@H264 <size> <millis> <is_config>\n`, payload bytes, then `\n@ENDH264\n`.


The iPhone app handles phone configuration, tasks, model configuration and status.
It does not request/display screenshots or perform pointer calibration. Send the task,
leave the app, and monitor from the Mac. See [the controller guide](../../ios/CLOUD_CONTROLLER.md).
The app does not perform inference or relay video in this mode.

The app and web share phone-host confirmation through authenticated
`POST /api/phone-host` with a boolean `confirmed`. `GET /api/status` reports
`phone_usb_confirmed`. Confirmation is volatile, clears when USB disconnects or the
board reboots, and is checked by firmware before HID actions. USB enumeration alone
cannot identify the host; confirmation requires the user's physical wiring check.

There are 12 phone examples and 13 web examples (including screen description).
They cover Wi-Fi, battery, storage, system version, alarms, world clock, calendar,
weather, display settings, language/region, Bluetooth, and Screen Time. Goals are
read-only and avoid configuration changes. Edit `shared/task-examples.json`
and run `node hardware/tools/task_examples.cjs` to regenerate both catalogs.

The web header, browser favicon, and iPhone home-screen bookmark reuse the iOS
app icon. They are served locally from flash without a control token. After
changing the app artwork, run `node hardware/tools/embed_web_icons.cjs` on macOS
to regenerate `src/cloud/control_icons.h`, then rebuild the firmware.

### Configure the cloud model from either controller

Use **模型配置** on the web dashboard, or **设置 → 云端模型配置** in the
iPhone app. Enter a full HTTPS Chat Completions endpoint, model name, and API
key. Both controllers read and write the same board configuration; the key
is never returned to the browser/app. Leaving the key blank preserves the
stored key. **保存并测试** saves first and then runs a text-only connection
test. Use **读懂当前屏幕** to check actual image support.

The authenticated `GET /api/config` returns `endpoint`, `model`, and `key_set`.
`POST /api/config` accepts `endpoint`, `model`, and optional `api_key` (empty
or absent preserves the current key). It refuses changes while model work
is in progress. URL/model/key are validated and saved together in one NVS
value before replacing the active configuration. Configuration persists
across reboot and overrides the initial values in `secrets.h`. API replies
never contain the cloud key. The local board control token remains separate.

The web dashboard has no CDN dependencies. Its assets are embedded in
`src/cloud/control_page.h`; rebuilding and flashing firmware updates the
page. Browser interaction checks (mocked APIs, no physical HID) can be run
with Playwright installed: `node hardware/tests/test_control_page.cjs`.
Set `CHROME_PATH` to an installed Chrome executable if needed. Checks cover
setup routing, examples, secret preservation/replacement, failure handling,
USB confirmation expiry, and mobile layout boundaries.

Limits and validation:

- The experimental OpenH264 port accepts **H.264 Baseline/Main/High** profiles.
  HEVC is not supported. Stream features, runtime memory, and decode speed must
  be checked with the actual iPhone. A build or API ping alone does not prove
  that its mirror stream can be decoded. Decode failures refuse task execution.
- Receiver advertisement is **640×360 at 1 fps**. AirPlay uses the advertised
  height to select the stream format and adjusts its aspect ratio. On the tested
  iPhone 13/iOS 27.0.1 this yields **334×720 High profile** in portrait orientation;
  that stream was decoded on the ESP32-S3 and its JPEG visually checked. Actual
  resolution/profile must still be verified on other devices. Images are grayscale.
- Wi-Fi/TLS, screen freshness, and USB must be valid before an action. Decoder
  overflow invalidates the frame until a new keyframe; restart mirroring if
  necessary. A run stops after 20 steps or 10 minutes. No automatic retry of
  failed model/HID actions is performed.
- Supported actions: normalized tap/swipe, ASCII typing (256 characters), an
  explicit key allowlist, home, wait, done. Invalid JSON/coordinates/actions
  cause a stop before HID. Calibration is approximate and must be repeated
  after changing iPhone pointer speed or the target phone.
- HTTPS verifies certificates using the ESP-IDF CA bundle and network time.
  API keys live only in the ignored local config and compiled firmware; neither
  the control page nor status replies expose them. Keep firmware binaries private.
- Host tests: `make -C hardware/tests`; cloud action validation:
  `make -C hardware/tests cloud`. Real mirror decoding and phone-side HID need
  a connected device and are separate from host tests.

The web console starts at a token login screen. It reveals the dashboard only
after an authenticated, valid `/api/status` response. An optional token in tab
session storage is revalidated before showing the dashboard on reload; logout
clears it. Invalid credentials return to login. Network failure or 8 seconds
without valid status clears live readings and disables task controls until
recovery. The dashboard shows the board's actual Wi-Fi SSID, IP and update time.
Logging out never sends a stop or HID command to the board.

Use `http://iphone-agent.local/` on a LAN with mDNS support. The ESP32 announces
this hostname and its HTTP service; DHCP may change its IP without changing the
name. The iOS login screen defaults to the same hostname and accepts a manual
private IP if the network blocks mDNS.

Public `GET /api/health` returns only the service name and `wifi_connected` for
the login page's reachability hint; it exposes no tasks, screenshots,
configuration or credentials. All other API calls require a board control
token. `agent token` is available on the physical USB serial interface.
Keep that token private, and use a trusted local Wi-Fi network.
