#include "h264_live.h"
#include <cassert>
#include <cstdio>
#include <vector>

int main(int argc,char **argv) {
  const uint8_t p[]={0,0,0,1,0x41,0xc0}, i[]={0,0,1,0x65,0xb0};
  const uint8_t b[]={0,0,1,0x41,0xa0}, truncated[]={0,0,1,0x41,0};
  const uint8_t mixed[]={0,0,1,0x41,0xc0,0,0,1,0x41,0xa0};
  const uint8_t sei[]={0,0,1,6,0x80};
  assert(cloud_h264_picture(p,sizeof(p))==CloudH264Picture::IP);
  assert(cloud_h264_picture(i,sizeof(i))==CloudH264Picture::IP);
  assert(cloud_h264_picture(b,sizeof(b))==CloudH264Picture::Unsupported);
  assert(cloud_h264_picture(truncated,sizeof(truncated))==CloudH264Picture::Unsupported);
  assert(cloud_h264_picture(mixed,sizeof(mixed))==CloudH264Picture::Unsupported);
  assert(cloud_h264_picture(sei,sizeof(sei))==CloudH264Picture::None);
  assert(cloud_h264_picture(nullptr,0)==CloudH264Picture::None);
  if(argc!=5)return 2;
  FILE *input=fopen(argv[1],"rb"),*sizes=fopen(argv[2],"r"),*out=fopen(argv[3],"wb"),*meta=fopen(argv[4],"w");
  if(!input||!sizes||!out||!meta)return 3;
  ISVCDecoder *decoder=nullptr;
  if(WelsCreateDecoder(&decoder)||!decoder)return 4;
  SDecodingParam params{};params.eEcActiveIdc=ERROR_CON_DISABLE;params.sVideoProperty.eVideoBsType=VIDEO_BITSTREAM_AVC;
  if(decoder->Initialize(&params))return 5;
  unsigned size,at,config;
  while(fscanf(sizes,"%u %u %u",&size,&at,&config)==3) {
    std::vector<uint8_t> data(size);
    if(fread(data.data(),1,size,input)!=size)return 6;
    uint8_t *planes[3]{};SBufferInfo info{};info.uiInBsTimeStamp=at;
    int result=cloud_h264_decode_live(decoder,data.data(),data.size(),planes,&info);
    if(result&~dsFramePending)return 7;
    if(info.iBufferStatus==1) {
      int w=info.UsrData.sSystemBuffer.iWidth,h=info.UsrData.sSystemBuffer.iHeight;
      fprintf(meta,"%d %d %llu\n",w,h,info.uiOutYuvTimeStamp);
      for(int y=0;y<h;++y)fwrite(planes[0]+y*info.UsrData.sSystemBuffer.iStride[0],1,w,out);
    }
  }
  decoder->Uninitialize();WelsDestroyDecoder(decoder);
  fclose(input);fclose(sizes);fclose(out);fclose(meta);
}
