#pragma once
#include <Arduino.h>
#if CLOUD_AGENT
void cloud_begin();
void cloud_poll();
String cloud_command(const String &line);
bool cloud_cancelled();
#endif
