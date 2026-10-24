#pragma once
#include <stddef.h>
#include <stdint.h>
#if CLOUD_AGENT
// Caller owns JPEG copy (free with heap_caps_free).
void cloud_video_capture(bool enabled);
bool cloud_jpeg(uint8_t **out, size_t *len, uint32_t *at, uint32_t *generation, uint64_t *signature=nullptr);
uint64_t cloud_video_signature();
const char *cloud_video_error();
uint32_t cloud_video_time();
uint32_t cloud_video_generation();
struct CloudVideoDiagnostics { uint32_t error, allocation, decode_ms, width, height;
  uint32_t queue_ms, jpeg_ms, pipeline_ms, queue_depth, frame_id, jpeg_bytes, received_frames, decoded_frames, skipped_jpegs; };
CloudVideoDiagnostics cloud_video_diagnostics();
void cloud_video_config(char *hex, size_t capacity);
#endif
