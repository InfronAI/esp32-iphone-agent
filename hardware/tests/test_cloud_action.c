#include "../hid_bridge/src/cloud/action.h"
#include <assert.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
int main(void) {
 cloud_action a={.kind=CA_TAP,.x=.5,.y=.5};assert(cloud_action_valid(&a));
 a.x=NAN;assert(!cloud_action_valid(&a));a.x=INFINITY;assert(!cloud_action_valid(&a));
 a.x=-.01;assert(!cloud_action_valid(&a));a.x=1.01;assert(!cloud_action_valid(&a));a.x=0;
 a.kind=CA_SWIPE;a.x2=.5;a.y2=.2;a.duration_ms=700;assert(cloud_action_valid(&a));
 a.y2=2;assert(!cloud_action_valid(&a));a.y2=.2;a.duration_ms=100000;assert(!cloud_action_valid(&a));
 a.kind=CA_TYPE;strcpy(a.text,"Hello 123");assert(cloud_action_valid(&a));
 strcpy(a.text,"你好");assert(!cloud_action_valid(&a));strcpy(a.text,"hello\n");assert(!cloud_action_valid(&a));
 memset(a.text,'x',sizeof(a.text));assert(!cloud_action_valid(&a));
 a.kind=CA_KEY;strcpy(a.text,"cmd+h");assert(cloud_action_valid(&a));strcpy(a.text,"cmd+q");assert(!cloud_action_valid(&a));
 a.kind=CA_WAIT;a.duration_ms=0;assert(!cloud_action_valid(&a));a.duration_ms=1000;assert(cloud_action_valid(&a));
 a.kind=CA_INVALID;assert(!cloud_action_valid(&a));
 puts("cloud action bounds/encoding/key allowlist tests passed");
}
