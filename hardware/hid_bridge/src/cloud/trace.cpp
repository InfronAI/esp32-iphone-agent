#if CLOUD_AGENT
#include "trace.h"
#include <cJSON.h>
#include <esp_heap_caps.h>
#include <atomic>

namespace {
constexpr size_t CAPACITY=48;
struct Entry { uint32_t id,at,step,duration; char kind[20],title[80],detail[1401]; bool truncated; };
struct History { uint32_t run,started,count,head,total; char goal[1025]; Entry entries[CAPACITY]; };
History *history;
SemaphoreHandle_t mutex;
std::atomic<uint32_t> revision{0};
// Preserve UTF-8 boundaries even for unusually long provider responses.
void copyText(char *out,size_t cap,const String &text) {
  size_t n=min(cap-1,text.length());
  if(n<text.length())while(n&&(static_cast<unsigned char>(text[n])&0xc0)==0x80)--n;
  memcpy(out,text.c_str(),n);out[n]=0;
}
}
bool cloud_trace_begin(){mutex=xSemaphoreCreateMutex();history=static_cast<History *>(heap_caps_calloc(1,sizeof(History),MALLOC_CAP_SPIRAM));return mutex&&history;}
void cloud_trace_reset(uint32_t run,const String &goal){
  if(!history)return;
  xSemaphoreTake(mutex,portMAX_DELAY);
  memset(history,0,sizeof(*history));history->run=run;history->started=millis();copyText(history->goal,sizeof(history->goal),goal);++revision;
  xSemaphoreGive(mutex);
}
void cloud_trace_add(uint32_t run,const char *kind,const String &title,const String &detail,uint32_t step,uint32_t duration){
  if(!history)return;
  xSemaphoreTake(mutex,portMAX_DELAY);
  if(run && run!=history->run){xSemaphoreGive(mutex);return;}
  Entry &e=history->entries[history->head];e={};e.id=++revision;e.at=millis();e.step=step;e.duration=duration;
  copyText(e.kind,sizeof(e.kind),kind);copyText(e.title,sizeof(e.title),title);copyText(e.detail,sizeof(e.detail),detail);e.truncated=detail.length()>=sizeof(e.detail);
  history->head=(history->head+1)%CAPACITY;history->count=min(uint32_t(CAPACITY),history->count+1);++history->total;
  xSemaphoreGive(mutex);
}
uint32_t cloud_trace_revision(){return revision;}
void cloud_trace_send(WebServer &server){
  if(!history){server.send(503,"text/plain","Trace storage unavailable");return;}
  auto *snapshot=static_cast<History *>(heap_caps_malloc(sizeof(History),MALLOC_CAP_SPIRAM));
  if(!snapshot){server.send(503,"text/plain","Trace snapshot unavailable");return;}
  xSemaphoreTake(mutex,portMAX_DELAY);memcpy(snapshot,history,sizeof(History));uint32_t rev=revision;xSemaphoreGive(mutex);
  cJSON *j=cJSON_CreateObject();cJSON_AddNumberToObject(j,"revision",rev);cJSON_AddNumberToObject(j,"run_id",snapshot->run);
  cJSON_AddNumberToObject(j,"started_ms",snapshot->started);cJSON_AddStringToObject(j,"goal",snapshot->goal);
  cJSON_AddNumberToObject(j,"dropped",snapshot->total-snapshot->count);
  char *raw=cJSON_PrintUnformatted(j);cJSON_Delete(j);
  if(!raw){heap_caps_free(snapshot);server.send(503,"text/plain","Trace serialization unavailable");return;}
  raw[strlen(raw)-1]=0;
  server.sendHeader("Cache-Control","no-store");server.setContentLength(CONTENT_LENGTH_UNKNOWN);server.send(200,"application/json; charset=utf-8","");
  server.sendContent(raw);cJSON_free(raw);server.sendContent(",\"events\":[");
  bool first=true;
  for(uint32_t i=0;i<snapshot->count;++i){
    const Entry &e=snapshot->entries[(snapshot->head+CAPACITY-snapshot->count+i)%CAPACITY];
    j=cJSON_CreateObject();cJSON_AddNumberToObject(j,"id",e.id);cJSON_AddNumberToObject(j,"at_ms",e.at);cJSON_AddNumberToObject(j,"step",e.step);cJSON_AddNumberToObject(j,"duration_ms",e.duration);
    cJSON_AddStringToObject(j,"kind",e.kind);cJSON_AddStringToObject(j,"title",e.title);cJSON_AddStringToObject(j,"detail",e.detail);cJSON_AddBoolToObject(j,"truncated",e.truncated);
    raw=cJSON_PrintUnformatted(j);cJSON_Delete(j);
    if(!raw)continue;
    if(!first)server.sendContent(",");first=false;server.sendContent(raw);cJSON_free(raw);
  }
  server.sendContent("]}");server.sendContent("");heap_caps_free(snapshot);
}
#endif
