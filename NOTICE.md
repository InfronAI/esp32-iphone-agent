# Source provenance and third-party notices

This repository derives from https://github.com/onehumanbeing/esp32-iphone-agent,
upstream base commit `67da886` (2026). Copyright notices for Henry Yuan are retained.
InfronAI's modifications add the autonomous ESP32 cloud mode, Wi-Fi controllers,
board-side decoder integration, Goal harness, documentation and reproducible demo.

The target repository's initial InfronAI MIT notice is retained alongside the upstream
MIT notice in `LICENSE`. This is a current source snapshot, with the upstream base
identified here; it does not import private development logs or historical secrets.

| Component | Source / license material |
|---|---|
| Main project | `LICENSE` |
| AirPlay receiver port | `hardware/hid_bridge/src/airplay/LICENSE-GPL.md`, original per-file notices; derived from UxPlay |
| playfair | `hardware/hid_bridge/src/airplay/playfair/LICENSE.md` and per-file notices |
| OpenH264 API headers | `hardware/hid_bridge/src/cloud/openh264/LICENSE` |
| OpenH264 decoder source | Cisco OpenH264 2.6.0, pinned commit `652bdb7719f30b52b08e506645a7322ff1b2cc6f`; fetched and verified by `hardware/tools/cloud_deps.py` |
| Arduino ESP32 / TinyUSB / NimBLE | Installed build dependencies; retain their upstream license terms |
| cJSON | ESP-IDF dependency; native harness tests fetch checksum-pinned cJSON 1.7.19 into ignored build storage |
| Playwright | Development-only demo/test dependency, declared in `tools/demo/package.json` |

The root MIT file is not a replacement for the component-specific notices above.
The demo's phone screens and task responses are generated fixtures, not private phone recordings.
