#include "harness.h"
#include <cJSON.h>
#include <cmath>
#include <cstring>
#include <cstdio>

namespace {
void copy(char *out,size_t capacity,const char *text) {
  size_t length=strlen(text),n=length<capacity?length:capacity-1;
  if(n<length)while(n&&(static_cast<unsigned char>(text[n])&0xc0)==0x80)--n;
  memcpy(out,text,n);out[n]=0;
}
bool same(const cloud_action &a,const cloud_action &b) {
  if(a.kind!=b.kind)return false;
  switch(a.kind) {
    case CA_TAP:return fabs(a.x-b.x)<.025&&fabs(a.y-b.y)<.025;
    case CA_SWIPE:return fabs(a.x-b.x)<.025&&fabs(a.y-b.y)<.025&&fabs(a.x2-b.x2)<.025&&fabs(a.y2-b.y2)<.025;
    case CA_TYPE:case CA_KEY:return !strcmp(a.text,b.text);
    default:return true;
  }
}
}
unsigned cloud_screen_distance(uint64_t a,uint64_t b) {
  uint64_t bits=a^b;unsigned n=0;while(bits){bits&=bits-1;++n;}return n;
}
const char *cloud_progress_name(CloudProgress p) {
  switch(p){case CloudProgress::Advanced:return "advanced";case CloudProgress::Unchanged:return "unchanged";
    case CloudProgress::Regressed:return "regressed";default:return "unknown";}
}
bool cloud_decision_parse(const char *json,CloudDecision &d,char *error,size_t cap) {
  d={};d.action.kind=CA_INVALID;d.action.x=d.action.y=d.action.x2=d.action.y2=NAN;
  cJSON *root=cJSON_ParseWithOpts(json,nullptr,true);
  auto fail=[&](const char *why){copy(error,cap,why);cJSON_Delete(root);return false;};
  if(!cJSON_IsObject(root))return fail("Return one JSON object without markdown.");
  // Ambiguous duplicate fields must never choose an unexpected HID operation.
  for(auto *a=root->child;a;a=a->next)for(auto *b=a->next;b;b=b->next)
    if(!strcmp(a->string,b->string))return fail("Duplicate JSON fields are not allowed.");
  auto text=[&](const char *key,char *out,size_t size,bool required) {
    auto *v=cJSON_GetObjectItemCaseSensitive(root,key);
    if(!v)return !required;
    if(!cJSON_IsString(v)||strlen(v->valuestring)>=size || (required&&!v->valuestring[0]))return false;
    strcpy(out,v->valuestring);return true;
  };
  auto *kind=cJSON_GetObjectItemCaseSensitive(root,"action");
  const char *names[]={"tap","swipe","type","key","home","wait","done","blocked"};
  if(cJSON_IsString(kind))for(unsigned i=0;i<8;++i)if(!strcmp(kind->valuestring,names[i]))d.action.kind=static_cast<cloud_action_kind>(i);
  auto number=[&](const char *key,double &out) {
    auto *v=cJSON_GetObjectItemCaseSensitive(root,key);if(!v)return true;
    if(!cJSON_IsNumber(v)||!std::isfinite(v->valuedouble))return false;
    out=v->valuedouble;return true;
  };
  if(!number("x",d.action.x)||!number("y",d.action.y)||!number("x2",d.action.x2)||!number("y2",d.action.y2))return fail("Coordinates must be finite numbers between 0 and 1.");
  auto *duration=cJSON_GetObjectItemCaseSensitive(root,"duration_ms");
  if(duration) {
    if(!cJSON_IsNumber(duration)||!std::isfinite(duration->valuedouble)||duration->valuedouble<0||duration->valuedouble>5000||floor(duration->valuedouble)!=duration->valuedouble)return fail("Invalid duration_ms.");
    d.action.duration_ms=duration->valueint;
  }
  bool terminal=d.action.kind==CA_DONE||d.action.kind==CA_BLOCKED;
  if(!text("text",d.action.text,sizeof(d.action.text),terminal)||!cloud_action_valid(&d.action))return fail("Invalid action, coordinates, key, or ASCII typing text.");
  if(!text("observation",d.observation,sizeof(d.observation),true)||!text("summary",d.summary,sizeof(d.summary),true)||
     !text("reason",d.reason,sizeof(d.reason),true)||!text("subgoal",d.subgoal,sizeof(d.subgoal),!terminal)||
     !text("expected",d.expected,sizeof(d.expected),!terminal)||!text("evidence",d.evidence,sizeof(d.evidence),d.action.kind==CA_DONE))
    return fail("Provide concise observation, summary, reason; actions need subgoal/expected; done needs visible evidence and text.");
  auto *progress=cJSON_GetObjectItemCaseSensitive(root,"progress");
  const char *progressNames[]={"advanced","unchanged","regressed","unknown"};bool found=false;
  if(cJSON_IsString(progress))for(unsigned i=0;i<4;++i)if(!strcmp(progress->valuestring,progressNames[i])){d.progress=static_cast<CloudProgress>(i);found=true;}
  if(!found)return fail("progress must be advanced, unchanged, regressed, or unknown.");
  cJSON_Delete(root);error[0]=0;return true;
}
void cloud_harness_init(CloudHarness &h,uint32_t now){memset(&h,0,sizeof(h));h.started=now;h.last_action.kind=CA_INVALID;}
bool cloud_harness_budget(const CloudHarness &h,uint32_t now){return h.rounds<CLOUD_ROUND_LIMIT&&uint32_t(now-h.started)<CLOUD_RUN_MS;}
CloudReview cloud_harness_review(CloudHarness &h,const CloudDecision &d,uint32_t now,uint32_t at,uint32_t gen,uint64_t image) {
  // A final verification is allowed after the last action, but never beyond time/call budgets.
  if(uint32_t(now-h.started)>=CLOUD_RUN_MS)return CloudReview::Limit;
  h.consecutive_errors=0;
  copy(h.summary,sizeof(h.summary),d.summary);copy(h.subgoal,sizeof(h.subgoal),d.subgoal);copy(h.observation,sizeof(h.observation),d.observation);
  if(h.actions>h.evaluated_actions) {
    bool changed=!h.has_image||cloud_screen_distance(h.image,image)>1;
    h.stalled=d.progress==CloudProgress::Advanced&&changed?0:h.stalled+1;
    h.evaluated_actions=h.actions;
  }
  if(d.action.kind==CA_BLOCKED){h.verifying=false;copy(h.feedback,sizeof(h.feedback),d.action.text);return CloudReview::Blocked;}
  if(d.action.kind==CA_DONE) {
    if(h.verifying && gen==h.verify_gen && int32_t(at-h.verify_at)>0){h.verifying=false;h.feedback[0]=0;return CloudReview::Complete;}
    h.verifying=true;h.verify_at=at;h.verify_gen=gen;
    copy(h.feedback,sizeof(h.feedback),"Completion is provisional. Independently verify the whole Goal on the next fresh screenshot; do not repeat it blindly.");
    return CloudReview::Verify;
  }
  h.verifying=false;
  if(h.actions>=CLOUD_ACTION_LIMIT){copy(h.feedback,sizeof(h.feedback),"Action limit reached without verified completion.");return CloudReview::Limit;}
  if(h.stalled>=4){copy(h.feedback,sizeof(h.feedback),"Four actions produced no verified visual progress. User help is required.");return CloudReview::Blocked;}
  if(h.stalled>=2&&same(d.action,h.last_action)) {
    copy(h.feedback,sizeof(h.feedback),"The same action failed to make progress twice. Choose a different strategy or report blocked; do not resend it.");
    return ++h.replans>2?CloudReview::Blocked:CloudReview::Replan;
  }
  h.feedback[0]=0;h.replans=0;h.image=image;h.has_image=true;
  copy(h.expected,sizeof(h.expected),d.expected);
  return CloudReview::Execute;
}
void cloud_harness_record(CloudHarness &h,const CloudDecision &d,bool ok,const char *result) {
  ++h.actions;h.repeated=same(d.action,h.last_action)?h.repeated+1:1;h.last_action=d.action;
  auto &entry=h.history[h.history_head];entry={};entry.round=h.rounds;entry.decision=d;entry.action_ok=ok;copy(entry.result,sizeof(entry.result),result);
  h.history_head=(h.history_head+1)%CLOUD_HISTORY;if(h.history_count<CLOUD_HISTORY)++h.history_count;
}
bool cloud_harness_retry(CloudHarness &h,const char *error,bool transient) {
  copy(h.feedback,sizeof(h.feedback),error);
  if(!transient || h.consecutive_errors>=2)return false;
  ++h.consecutive_errors;++h.retries;return true;
}
