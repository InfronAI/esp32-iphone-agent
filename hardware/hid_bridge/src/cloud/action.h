#pragma once
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef enum { CA_TAP, CA_SWIPE, CA_TYPE, CA_KEY, CA_HOME, CA_WAIT, CA_DONE, CA_BLOCKED, CA_INVALID } cloud_action_kind;
typedef struct {
  cloud_action_kind kind;
  double x,y,x2,y2;
  int duration_ms;
  char text[257];
} cloud_action;
bool cloud_action_valid(const cloud_action *a);
#ifdef __cplusplus
}
#endif
