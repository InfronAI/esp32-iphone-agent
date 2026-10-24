#pragma once
#include "action.h"
#include <stddef.h>
#include <stdint.h>

constexpr unsigned CLOUD_ACTION_LIMIT=20, CLOUD_ROUND_LIMIT=40, CLOUD_HISTORY=6;
constexpr uint32_t CLOUD_RUN_MS=10*60*1000;
enum class CloudProgress { Advanced, Unchanged, Regressed, Unknown };
struct CloudDecision {
  cloud_action action;
  CloudProgress progress;
  char observation[385],summary[385],subgoal[193],expected[193],reason[257],evidence[385];
};
struct CloudTurn {
  unsigned round;
  CloudDecision decision;
  bool action_ok;
  char result[129];
};
struct CloudHarness {
  uint32_t started,verify_at,verify_gen;
  unsigned rounds,actions,stalled,repeated,evaluated_actions,retries,consecutive_errors,replans;
  unsigned history_count,history_head;
  bool verifying,has_image;
  uint64_t image;
  char summary[385],subgoal[193],expected[193],observation[385],feedback[385];
  cloud_action last_action;
  CloudTurn history[CLOUD_HISTORY];
};
enum class CloudReview { Execute, Verify, Complete, Blocked, Replan, Limit };
bool cloud_decision_parse(const char *json,CloudDecision &out,char *error,size_t capacity);
void cloud_harness_init(CloudHarness &h,uint32_t now);
bool cloud_harness_budget(const CloudHarness &h,uint32_t now);
CloudReview cloud_harness_review(CloudHarness &h,const CloudDecision &d,uint32_t now,
                                uint32_t frame_at,uint32_t generation,uint64_t image);
void cloud_harness_record(CloudHarness &h,const CloudDecision &d,bool ok,const char *result);
bool cloud_harness_retry(CloudHarness &h,const char *error,bool transient);
unsigned cloud_screen_distance(uint64_t a,uint64_t b);
const char *cloud_progress_name(CloudProgress progress);
