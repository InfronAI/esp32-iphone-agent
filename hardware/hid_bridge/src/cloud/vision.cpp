#if CLOUD_AGENT
#include "../../video_link.h"
#include "vision.h"
#include "openh264/codec_api.h"
#include "h264_live.h"
#include "img_converters.h"
#include <esp_heap_caps.h>
#include <atomic>

// Decode continuously: P frames depend on every preceding frame. Queue overflow
// invalidates the image and waits for a new IDR; stale images never drive actions.
namespace {
constexpr size_t MAX_AU = 256 * 1024, JPEG_CAP = 192 * 1024;
struct Packet { uint8_t *data; size_t len; uint32_t at, gen; bool config, idr; };
QueueHandle_t queue;
SemaphoreHandle_t lock;
uint8_t *jpeg;
size_t jpegLen;
uint32_t jpegAt;
uint64_t jpegSignature;
std::atomic<uint32_t> generation{0}, imageGeneration{0}, videoAt{0};
std::atomic<bool> lost{true}, supported{false};
std::atomic<const char *> problem{"Start Screen Mirroring to ESP32 Agent"};
uint8_t config[512]; size_t configLen;
uint8_t diagnosticConfig[512];size_t diagnosticConfigLen;
std::atomic<uint32_t> decodeError{0}, failedAllocation{0}, decodeMs{0}, decodedWidth{0}, decodedHeight{0};
std::atomic<uint32_t> frames{0}, bytes{0}, decodedFrames{0}, skippedJpegs{0};
std::atomic<uint32_t> queueMs{0}, jpegMs{0}, pipelineMs{0}, frameID{0}, publishedBytes{0};
uint32_t statAt, prevFrames, prevBytes;
std::atomic<bool> capturing{false};
void capturePacket(const uint8_t *data,size_t len,bool config) {
#if DEBUG_SERIAL
  if(!capturing)return;
  Serial.printf("\n@H264 %u %lu %u\n",(unsigned)len,millis(),config?1:0);
  Serial.write(data,len);Serial.print("\n@ENDH264\n");
#endif
}

void invalidate(const char *why) {
  lost = true; videoAt = 0; ++generation; problem = why;
}
void enqueue(const uint8_t *data, size_t len, bool cfg, bool idr) {
  if (!queue || !len || len > MAX_AU) { invalidate("Video packet too large"); return; }
  Packet p{static_cast<uint8_t *>(heap_caps_malloc(len, MALLOC_CAP_SPIRAM)), len, millis(), generation.load(), cfg, idr};
  if (!p.data) { invalidate("No PSRAM for video packet"); return; }
  memcpy(p.data, data, len);
  if (xQueueSend(queue, &p, 0) != pdTRUE) {
    heap_caps_free(p.data); invalidate("Decoder queue overflow; restart Screen Mirroring");
  }
}
void decodeTask(void *) {
  ISVCDecoder *decoder = nullptr;
  uint32_t decoderGen = 0, lastJPEG=0;
  auto reset = [&]() {
    if (decoder) { decoder->Uninitialize(); WelsDestroyDecoder(decoder); decoder=nullptr; }
    if(WelsCreateDecoder(&decoder) || !decoder)return false;
    int trace=WELS_LOG_ERROR;decoder->SetOption(DECODER_OPTION_TRACE_LEVEL,&trace);
    SDecodingParam cfg{};
    cfg.eEcActiveIdc=ERROR_CON_DISABLE;
    cfg.sVideoProperty.eVideoBsType=VIDEO_BITSTREAM_AVC;
    if(decoder->Initialize(&cfg)){WelsDestroyDecoder(decoder);decoder=nullptr;return false;}
    decoderGen = generation;
    return decoder != nullptr;
  };
  // Working JPEG is private to this task. The published JPEG is protected by lock.
  uint8_t *work = static_cast<uint8_t *>(heap_caps_malloc(JPEG_CAP, MALLOC_CAP_SPIRAM));
  uint8_t *luma=nullptr;size_t lumaCap=0;
  if (!work) { problem = "No PSRAM for JPEG encoder"; vTaskDelete(nullptr); }
  for (;;) {
    Packet p;
    if (xQueueReceive(queue, &p, portMAX_DELAY) != pdTRUE) continue;
    if (p.gen != generation) { heap_caps_free(p.data); continue; }
    if (p.config) {
      configLen = p.len;
      memcpy(config, p.data, configLen);
      problem = "Waiting for H.264 keyframe";
    }
    if (!supported || (!p.config && lost && !p.idr)) { heap_caps_free(p.data); continue; }
    if (!p.config && p.idr && (lost || !decoder)) {
      if (!reset()) { invalidate("No PSRAM for H.264 decoder"); heap_caps_free(p.data); continue; }
      uint8_t *planes[3]{};SBufferInfo info{};
      int rc=configLen?decoder->DecodeFrameNoDelay(config,configLen,planes,&info):dsInvalidArgument;
      decodeError=rc;
      bool configOK=(rc&~dsFramePending)==0;
      if (!configOK) {
        invalidate("H.264 configuration rejected"); heap_caps_free(p.data); continue;
      }
      lost = false;
    }
    if (!p.config && decoder && !lost) {
      do {
        uint8_t *planes[3]{};SBufferInfo info{};
        uint32_t began=millis();queueMs=began-p.at;
        info.uiInBsTimeStamp=p.at;
        int result=cloud_h264_decode_live(decoder,p.data,p.len,planes,&info);
        decodeError=result;decodeMs=millis()-began;
        if (result&~dsFramePending) {
          Serial.printf("cloud: H.264 decode error 0x%x, free PSRAM %u\n",result,(unsigned)heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
          invalidate((result&dsOutOfMemory)?"Not enough memory for H.264 frame":"H.264 decode failed; restart Screen Mirroring");break;
        }
        if (info.iBufferStatus==1 && planes[0]) {
          uint32_t w=info.UsrData.sSystemBuffer.iWidth,h=info.UsrData.sSystemBuffer.iHeight;
          decodedWidth=w;decodedHeight=h;++decodedFrames;
          // Always decode reference frames; only the independent JPEG export is throttled.
          // During bursts, catch up to recent frames instead of encoding every queued image.
          uint32_t now=millis();
          if(lastJPEG && (now-lastJPEG<900 || (uxQueueMessagesWaiting(queue)>0 && now-lastJPEG<1500))){++skippedJpegs;break;}
          uint32_t encodeBegan=now;
          int stride=info.UsrData.sSystemBuffer.iStride[0];
          if (!w || !h || w>720 || h>1280) { invalidate("Decoded resolution exceeds board limit"); break; }
          if(stride<int(w)){invalidate("Invalid decoded stride");break;}
          if(w*h>lumaCap) {
            heap_caps_free(luma);lumaCap=0;
            luma=static_cast<uint8_t *>(heap_caps_malloc(w*h,MALLOC_CAP_SPIRAM));
            if(!luma){invalidate("No PSRAM for grayscale frame");break;}
            lumaCap=w*h;
          }
          for(uint32_t y=0;y<h;++y)memcpy(luma+y*w,planes[0]+y*stride,w);
          // Grayscale JPEG from I420 luma avoids an extra RGB frame allocation.
          struct Output { uint8_t *data; size_t size; bool ok; } out{work,0,true};
          auto cb=[](void *arg,size_t index,const void *data,size_t len)->size_t {
            auto *o=static_cast<Output *>(arg);
            if(index+len>JPEG_CAP){o->ok=false;return 0;}
            if(len)memcpy(o->data+index,data,len);
            if(index+len>o->size)o->size=index+len;
            return len;
          };
          bool ok=fmt2jpg_cb(luma,w*h,w,h,PIXFORMAT_GRAYSCALE,90,cb,&out);
          if(ok && out.ok && out.size && !lost && decoderGen==generation) {
            xSemaphoreTake(lock,portMAX_DELAY);
            memcpy(jpeg,work,out.size); jpegLen=out.size;
            // A small dHash of the screen body ignores status-bar clock changes.
            // Use it only as a scene-change/stagnation hint, never proof of success.
            uint64_t signature=0;
            for(unsigned row=0;row<8;++row) {
              unsigned y=h/10+row*(h*8/10)/8,previous=0;
              for(unsigned col=0;col<9;++col) {
                unsigned x=(2*col+1)*w/18,sum=0;
                for(unsigned dy=0;dy<4;++dy)for(unsigned dx=0;dx<4;++dx)
                  sum+=luma[min(uint32_t(y+dy),h-1)*w+min(uint32_t(x+dx),w-1)];
                if(col)signature=(signature<<1)|(previous>sum);
                previous=sum;
              }
            }
            jpegSignature=signature;
            // Use the output frame timestamp: decoder buffering must not make an old image look new.
            jpegAt=info.uiOutYuvTimeStamp?uint32_t(info.uiOutYuvTimeStamp):p.at;
            imageGeneration=decoderGen; videoAt=jpegAt;
            lastJPEG=millis();jpegMs=lastJPEG-encodeBegan;pipelineMs=lastJPEG-jpegAt;publishedBytes=out.size;++frameID;
            xSemaphoreGive(lock); problem="";
            static bool first=true;
            if(first){first=false;Serial.printf("cloud: decoded %ux%u JPEG %u bytes in %lu ms\n",w,h,(unsigned)out.size,millis()-began);}
          } else if (!ok || !out.ok) invalidate("JPEG encoding failed");
        }
      } while(false);
    }
    heap_caps_free(p.data);
    vTaskDelay(1);
  }
}
}
bool video_begin() {
  lock=xSemaphoreCreateMutex(); queue=xQueueCreate(6,sizeof(Packet));
  jpeg=static_cast<uint8_t *>(heap_caps_malloc(JPEG_CAP,MALLOC_CAP_SPIRAM));
  return lock && queue && jpeg && xTaskCreatePinnedToCore(decodeTask,"h264",20*1024,nullptr,1,nullptr,0)==pdPASS;
}
void video_on_config(const uint8_t *data,size_t len) {
  capturePacket(data,len,true);
  invalidate("Waiting for H.264 keyframe");
  decodeError=0;failedAllocation=0;decodeMs=0;decodedWidth=0;decodedHeight=0;queueMs=0;jpegMs=0;pipelineMs=0;publishedBytes=0;
  if(lock){
    xSemaphoreTake(lock,portMAX_DELAY);
    diagnosticConfigLen=min(len,sizeof(diagnosticConfig));
    memcpy(diagnosticConfig,data,diagnosticConfigLen);
    xSemaphoreGive(lock);
  }
  // avcC -> Annex-B starts with SPS (67), followed by profile_idc.
  supported = len>=8 && len<=sizeof(config) && (data[4]&31)==7 && (data[5]==66||data[5]==77||data[5]==100);
  Serial.printf("cloud: H.264 profile %u\n",len>5?data[5]:0);
  Serial.print("cloud: H.264 config ");
  for(size_t i=0;i<len && i<sizeof(config);++i)Serial.printf("%02x",data[i]);
  Serial.println();
  if(!supported){problem="Unsupported AirPlay codec/profile";return;}
  enqueue(data,len,true,false);
}
void video_on_au(const uint8_t *data,size_t len,bool idr) {
  capturePacket(data,len,false);
  ++frames; bytes+=len;
  if(supported)enqueue(data,len,false,idr);
}
void video_stream(bool) {}
void video_snap(const String &) {}
void video_bench(const String &,uint32_t) {}
VideoStats video_stats() {
  uint32_t now=millis(),f=frames,b=bytes,dt=now-statAt;
  static VideoStats stats{};
  if(dt>=1000){stats={uint32_t((b-prevBytes)*8/dt),0,0,(f-prevFrames)*1000.0f/dt};statAt=now;prevFrames=f;prevBytes=b;}
  return stats;
}
void cloud_video_capture(bool enabled){capturing=enabled;}
bool cloud_jpeg(uint8_t **out,size_t *len,uint32_t *at,uint32_t *gen,uint64_t *signature) {
  *out=nullptr;
  if(!lock || lost || !videoAt)return false;
  xSemaphoreTake(lock,portMAX_DELAY);
  bool ok=jpegLen && !lost && imageGeneration==generation;
  if(ok){*out=static_cast<uint8_t *>(heap_caps_malloc(jpegLen,MALLOC_CAP_SPIRAM));ok=*out!=nullptr;}
  if(ok){memcpy(*out,jpeg,jpegLen);*len=jpegLen;*at=jpegAt;*gen=imageGeneration;if(signature)*signature=jpegSignature;}
  xSemaphoreGive(lock);return ok;
}
uint64_t cloud_video_signature(){if(!lock)return 0;xSemaphoreTake(lock,portMAX_DELAY);uint64_t value=jpegSignature;xSemaphoreGive(lock);return value;}
const char *cloud_video_error(){return problem;}
uint32_t cloud_video_time(){return videoAt;}
uint32_t cloud_video_generation(){return generation;}
extern "C" void cloud_decoder_allocation_failed(unsigned size){failedAllocation=size;}
CloudVideoDiagnostics cloud_video_diagnostics(){return {decodeError,failedAllocation,decodeMs,decodedWidth,decodedHeight,queueMs,jpegMs,pipelineMs,queue?uint32_t(uxQueueMessagesWaiting(queue)):0,frameID,publishedBytes,frames,decodedFrames,skippedJpegs};}
void cloud_video_config(char *hex,size_t capacity){
  if(!capacity)return;
  hex[0]=0;if(!lock)return;
  xSemaphoreTake(lock,portMAX_DELAY);
  size_t n=min(diagnosticConfigLen,(capacity-1)/2);
  for(size_t i=0;i<n;++i){hex[i*2]="0123456789abcdef"[diagnosticConfig[i]>>4];hex[i*2+1]="0123456789abcdef"[diagnosticConfig[i]&15];}
  hex[n*2]=0;xSemaphoreGive(lock);
}
#endif
