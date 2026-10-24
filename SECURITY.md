# Security

Current scope includes the token-gated LAN HTTP API, AirPlay input and decoder,
cloud response validation, task cancellation, HID host confirmation, and handling
of local credentials. The legacy BLE service and iPhone-side agent remain in the source.

The default LAN console uses HTTP, not HTTPS. Keep it on a trusted LAN and do not
port-forward it to the internet. The cloud API uses TLS certificate verification.
Default builds do not enable encrypted NVS. A control token is not a guarantee
against a compromised LAN or physical access to the board.

Do not publish `secrets.h`, `Local.xcconfig`, API keys, control tokens, NVS dumps,
private screen recordings, signed installation files, or firmware built with real credentials.
The repository's demo uses synthetic data.

Report a suspected vulnerability privately to support@infron.ai with a description,
reproduction steps, and the tested commit. Do not include credentials or personal phone data.
See [data flow](docs/guide/data-flow.md) and [privacy](docs/privacy.md).
