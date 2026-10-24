#pragma once
#include <stddef.h>
#include <stdint.h>
#include "openh264/codec_api.h"

// AirPlay's low-frame-rate live stream uses I/P pictures. Inspect the first two
// Exp-Golomb fields of every slice before draining the display reorder queue.
// B/SP/SI pictures must not silently appear out of presentation order.
enum class CloudH264Picture { None, IP, Unsupported };
inline CloudH264Picture cloud_h264_picture(const uint8_t *data, size_t size) {
  CloudH264Picture result=CloudH264Picture::None;
  for(size_t i=0;i+3<size;++i) {
    if(data[i] || data[i+1] || data[i+2]!=1)continue;
    size_t begin=i+3, end=begin+1;
    while(end+2<size && (data[end] || data[end+1] || data[end+2]!=1))++end;
    if(end+2>=size)end=size;
    uint8_t type=data[begin]&31;
    if(type>=2 && type<=4)return CloudH264Picture::Unsupported;
    if(type!=1 && type!=5)continue;
    uint8_t rbsp[16]{};size_t n=0;unsigned zeros=0;
    for(size_t p=begin+1;p<end && n<sizeof(rbsp);++p) {
      uint8_t b=data[p];
      if(zeros>=2 && b==3){zeros=0;continue;}
      rbsp[n++]=b;zeros=b==0?zeros+1:0;
    }
    size_t bit=0;
    auto ue=[&](uint32_t &value) {
      unsigned leading=0;
      while(bit<n*8 && !(rbsp[bit/8]&(0x80>>(bit%8)))){++bit;if(++leading>30)return false;}
      if(bit>=n*8)return false;
      ++bit;if(bit+leading>n*8)return false;
      value=1;
      for(unsigned j=0;j<leading;++j,++bit)value=(value<<1)|((rbsp[bit/8]>>(7-bit%8))&1);
      --value;return true;
    };
    uint32_t firstMB,slice;
    if(!ue(firstMB)||!ue(slice)||slice>9 || (slice%5!=0 && slice%5!=2))return CloudH264Picture::Unsupported;
    result=CloudH264Picture::IP;
  }
  return result;
}

inline int cloud_h264_decode_live(ISVCDecoder *decoder, const uint8_t *data, size_t size,
                                 uint8_t **planes, SBufferInfo *info) {
  auto picture=cloud_h264_picture(data,size);
  if(picture==CloudH264Picture::Unsupported)return dsBitstreamError;
  int result=decoder->DecodeFrameNoDelay(data,static_cast<int>(size),planes,info);
  if((result&~dsFramePending) || picture!=CloudH264Picture::IP)return result;
  int remaining=0;
  if(decoder->GetOption(DECODER_OPTION_NUM_OF_FRAMES_REMAINING_IN_BUFFER,&remaining))return dsBitstreamError;
  // With no B pictures, a decoded picture is ready for display immediately.
  // Preserve a valid output if FlushFrame reports no additional picture.
  while(remaining-->0) {
    uint8_t *next[3]{};SBufferInfo output{};
    int flushed=decoder->FlushFrame(next,&output);
    result|=flushed;
    if(flushed&~dsFramePending)break;
    if(output.iBufferStatus==1){*info=output;for(int i=0;i<3;++i)planes[i]=next[i];}
  }
  return result;
}
