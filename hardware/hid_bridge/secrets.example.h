// Copy to secrets.h (git-ignored). --cloud joins this 2.4 GHz network automatically.
// --sta also uses these credentials for legacy/diagnostic station-mode builds.
#define WIFI_SSID "your-wifi"
#define WIFI_PASS "your-password"

// Current autonomous build: hardware/flash.sh --cloud
// Connect the iPhone to this same Wi-Fi and mirror to ESP32 Agent.
#define CLOUD_LLM_URL "https://your-provider.example/v1/chat/completions"
#define CLOUD_LLM_MODEL "your-vision-model"
#define CLOUD_LLM_KEY "your-api-key"
