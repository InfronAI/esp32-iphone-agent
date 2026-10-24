#include "../hid_bridge/src/cloud/harness.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <fstream>
#include <iterator>

CloudDecision parse(const std::string &action,const char *progress="unknown") {
  std::string json="{"+action+",\"observation\":\"Settings screen\",\"summary\":\"Opened Settings\",\"subgoal\":\"Open Battery\",\"expected\":\"Battery screen\",\"reason\":\"Read battery for Goal\",\"progress\":\""+progress+"\"}";
  CloudDecision d{};char error[256];assert(cloud_decision_parse(json.c_str(),d,error,sizeof(error)));return d;
}
void invalid(const char *json){CloudDecision d;char error[256];assert(!cloud_decision_parse(json,d,error,sizeof(error)));assert(error[0]);}
int main(int argc,char **argv) {
  if(argc==2) {
    std::ifstream input(argv[1]);assert(input.good());
    std::string response((std::istreambuf_iterator<char>(input)),std::istreambuf_iterator<char>());
    CloudDecision d;char error[256];
    bool ok=cloud_decision_parse(response.c_str(),d,error,sizeof(error));
    if(!ok)fprintf(stderr,"Provider response rejected: %s\n",error);
    assert(ok);assert(d.action.kind==CA_DONE&&d.evidence[0]);
    puts("PASS: real provider decision accepted by the firmware parser (synthetic observation, no HID).");
    return 0;
  }
  auto tap=parse("\"action\":\"tap\",\"x\":0.5,\"y\":0.4");
  auto home=parse("\"action\":\"home\"","advanced");
  auto done=parse("\"action\":\"done\",\"text\":\"Battery is 70%\",\"evidence\":\"Visible Battery 70%\"","advanced");
  auto blocked=parse("\"action\":\"blocked\",\"text\":\"Phone is locked; please unlock\"");
  invalid("{\"action\":\"done\",\"text\":\"finished\"}"); // No visible evidence.
  invalid("{\"action\":\"tap\",\"action\":\"home\"}");
  invalid("```json\n{}\n```");invalid("{} trailing");
  auto valid=std::string("{\"action\":\"wait\",\"duration_ms\":1000,\"observation\":\"loading\",\"summary\":\"loading\",\"subgoal\":\"wait\",\"expected\":\"loaded\",\"reason\":\"loading\",\"progress\":\"unknown\"}");
  CloudDecision d;char error[256];assert(cloud_decision_parse(valid.c_str(),d,error,sizeof(error)));
  auto bad=valid;bad.replace(bad.find("1000"),4,"\"1000\"");invalid(bad.c_str());
  bad=valid;bad.replace(bad.find("1000"),4,"1.5");invalid(bad.c_str());
  bad=valid;bad.replace(bad.find("unknown"),7,"invented");invalid(bad.c_str());
  bad=valid;bad.replace(bad.find("loading"),7,std::string(500,'a'));invalid(bad.c_str());

  CloudHarness h;cloud_harness_init(h,100);h.rounds=1;
  assert(cloud_harness_review(h,tap,200,150,1,0)==CloudReview::Execute);
  cloud_harness_record(h,tap,true,"sent, UI not yet verified");assert(h.actions==1&&h.history_count==1);
  ++h.rounds;assert(cloud_harness_review(h,home,300,250,1,255)==CloudReview::Execute);
  assert(h.stalled==0);cloud_harness_record(h,home,true,"sent");
  ++h.rounds;assert(cloud_harness_review(h,done,400,350,1,65535)==CloudReview::Verify);
  assert(h.verifying);assert(cloud_harness_review(h,done,401,350,1,65535)==CloudReview::Verify); // Same frame cannot finish.
  assert(cloud_harness_review(h,done,500,450,1,65535)==CloudReview::Complete);
  assert(cloud_harness_review(h,blocked,510,460,1,65535)==CloudReview::Blocked);

  cloud_harness_init(h,0);assert(cloud_harness_review(h,done,20,10,1,0)==CloudReview::Verify);
  assert(cloud_harness_review(h,home,30,25,1,255)==CloudReview::Execute);assert(!h.verifying); // Failed verification resumes planning.
  cloud_harness_init(h,0);
  for(unsigned i=0;i<2;++i){++h.rounds;assert(cloud_harness_review(h,tap,100+i,50+i,1,0)==CloudReview::Execute);cloud_harness_record(h,tap,true,"sent");}
  assert(cloud_harness_review(h,tap,200,150,1,0)==CloudReview::Replan);assert(h.actions==2);
  assert(cloud_harness_review(h,tap,201,151,1,0)==CloudReview::Replan);
  assert(cloud_harness_review(h,tap,202,152,1,0)==CloudReview::Blocked);assert(h.actions==2); // Rejected proposals never reach HID.
  cloud_harness_init(h,0);
  for(unsigned i=0;i<4;++i){auto next=i%2?home:tap;next.progress=CloudProgress::Unchanged;
    assert(cloud_harness_review(h,next,100+i,50+i,1,0)==CloudReview::Execute);cloud_harness_record(h,next,true,"sent");}
  assert(cloud_harness_review(h,tap,200,150,1,0)==CloudReview::Blocked); // Oscillation.

  cloud_harness_init(h,0);assert(cloud_harness_retry(h,"503",true));assert(cloud_harness_retry(h,"timeout",true));
  assert(!cloud_harness_retry(h,"still unavailable",true));assert(h.actions==0);
  cloud_harness_init(h,0);assert(!cloud_harness_retry(h,"401",false));
  assert(cloud_harness_retry(h,"bad JSON",true));cloud_harness_review(h,tap,20,10,1,0);assert(h.consecutive_errors==0);
  h.actions=CLOUD_ACTION_LIMIT;assert(cloud_harness_review(h,tap,30,20,1,0)==CloudReview::Limit);
  assert(cloud_harness_review(h,done,40,30,1,0)==CloudReview::Verify);assert(cloud_harness_review(h,done,50,40,1,0)==CloudReview::Complete);
  h.rounds=CLOUD_ROUND_LIMIT;assert(!cloud_harness_budget(h,60));
  cloud_harness_init(h,0);assert(!cloud_harness_budget(h,CLOUD_RUN_MS));assert(cloud_harness_review(h,tap,CLOUD_RUN_MS,10,1,0)==CloudReview::Limit);
  cloud_harness_init(h,UINT32_MAX-100);assert(cloud_harness_budget(h,50));
  for(unsigned i=0;i<20;++i){h.rounds=i+1;cloud_harness_record(h,tap,true,"sent");}
  assert(h.history_count==CLOUD_HISTORY);assert(h.history[h.history_head].round==15);
  assert(cloud_screen_distance(0,0xffff)==16);
  printf("PASS: strict protocol, Goal loop, fresh completion verification, correction, repetition/oscillation limits, retries, bounded history and budgets. Memory: %zu bytes.\n",sizeof(h));
}
