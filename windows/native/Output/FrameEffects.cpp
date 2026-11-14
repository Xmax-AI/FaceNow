//
//  FrameEffects.cpp
//  FaceNow
//

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <cstdint>
#include "../CameraSource/CenterFill.h"
extern "C" __declspec(dllexport) int FaceNowCompose(const uint8_t* source,uint32_t sourceWidth,uint32_t sourceHeight,uint32_t sourceStride,uint8_t* output,uint32_t width,uint32_t height,const uint8_t* overlay) {
    if(!source||!output||!sourceWidth||!sourceHeight||sourceWidth>4096||sourceHeight>2160||sourceStride<sourceWidth*4||sourceStride>32768||!width||!height||width>4096||height>2160) return -1;
    FaceNowFrames::CenterFill(source,sourceWidth,sourceHeight,sourceStride,output,width,height,int64_t(width)*4);
    if(overlay) for(size_t i=0;i<size_t(width)*height*4;i+=4) {
        const unsigned a=overlay[i+3]; if(!a) continue;
        for(int c=0;c<3;++c) output[i+c]=uint8_t((unsigned(overlay[i+c])*a+unsigned(output[i+c])*(255-a)+127)/255);
        output[i+3]=255;
    }
    return 0;
}
