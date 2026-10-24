#include "action.h"
#include <math.h>
#include <string.h>
static bool point(double x,double y) {return isfinite(x)&&isfinite(y)&&x>=0&&x<=1&&y>=0&&y<=1;}
bool cloud_action_valid(const cloud_action *a) {
  if(!a || a->kind<CA_TAP || a->kind>=CA_INVALID)return false;
  if((a->kind==CA_TAP || a->kind==CA_SWIPE) && !point(a->x,a->y))return false;
  if(a->kind==CA_SWIPE && (!point(a->x2,a->y2)||a->duration_ms<200||a->duration_ms>2000))return false;
  if(a->kind==CA_WAIT && (a->duration_ms<100||a->duration_ms>5000))return false;
  if(!memchr(a->text,0,sizeof(a->text)))return false;
  if(a->kind==CA_TYPE) {
    if(!a->text[0])return false;
    for(const unsigned char *p=(const unsigned char *)a->text;*p;p++)if(*p<32||*p>126)return false;
  }
  if(a->kind==CA_KEY) {
    const char *keys[]={"enter","esc","tab","backspace","space","up","down","left","right","cmd+h"};
    for(unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++)if(!strcmp(a->text,keys[i]))return true;
    return false;
  }
  return true;
}
