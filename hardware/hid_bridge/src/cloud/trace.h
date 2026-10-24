#pragma once
#include <Arduino.h>
#include <WebServer.h>
#if CLOUD_AGENT
bool cloud_trace_begin();
void cloud_trace_reset(uint32_t run, const String &goal);
void cloud_trace_add(uint32_t run, const char *kind, const String &title, const String &detail,
                     uint32_t step=0, uint32_t duration=0);
uint32_t cloud_trace_revision();
void cloud_trace_send(WebServer &server);
#endif
