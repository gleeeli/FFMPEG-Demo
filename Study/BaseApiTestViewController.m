//
//  BaseApiTestViewController.m
//  SFFmpegIOSStreamer
//
//  Created by zqh on 2018/6/12.
//  Copyright © 2018年 Lei Xiaohua. All rights reserved.
//

#import "BaseApiTestViewController.h"
#include <libavformat/avformat.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/pixdesc.h>

@interface BaseApiTestViewController ()

@end

@implementation BaseApiTestViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    const char *path = "";
    AVFormatContext *formatCtx = avformat_alloc_context();
    
    //设置回调
    AVIOInterruptCB int_cb = {interrupt_callback, (__bridge void *)(self)};
    formatCtx->interrupt_callback = int_cb;
    
    avformat_open_input(&formatCtx, path, NULL, NULL);
    avformat_find_stream_info(formatCtx, NULL);
    
    int videoStreamIndex = -1;
    int audioStreamIndex = -1;
    AVCodecContext *videoCodecCtx = NULL;
    AVCodecContext *audioCodecCtx = NULL;
    SwrContext *swrContext = NULL;
    struct SwsContext *swsContent = NULL;
    AVPicture *picture = NULL;
    for (int i = 0; i < formatCtx ->nb_streams; i++)
    {
        AVStream *stream = formatCtx->streams[i];
        
        if (AVMEDIA_TYPE_VIDEO == stream->codec->codec_type)
        {
            //视频流
            videoStreamIndex = i;
            videoCodecCtx = [self parserVideoStream:stream];
            //先校验视频流是否格式合法,并初始化picture格式
            bool pictureValid = [self getAVPictueValidWithVideoCodecCtx:videoCodecCtx picture:picture];
            if (!pictureValid)
            {
                swsContent = NULL;
            }
            else
            {
                //设置需要的视频格式
               swsContent = [self parserVideoFormat:videoCodecCtx];
            }
            
        }
        else if (AVMEDIA_TYPE_AUDIO == stream->codec->codec_type)
        {
            //音频流
            audioStreamIndex = i;
            audioCodecCtx = [self parserAudioStream:stream];
            swrContext =[self parserAudioFormat:audioCodecCtx];
        }
    }
    
    //获取每一帧数据
    [self handleEveryFrameWithFormatCtx:formatCtx videoStreamIndex:videoStreamIndex audioStreamIndex:audioStreamIndex videoCodecCtx:videoCodecCtx audioCodecCtx:audioCodecCtx swrContext:swrContext swsContent:swsContent picture:picture];
}

/**
 获取每一帧数据
 */
- (void)handleEveryFrameWithFormatCtx:(AVFormatContext *)formatCtx videoStreamIndex:(int)videoStreamIndex audioStreamIndex:(int)audioStreamIndex videoCodecCtx:(AVCodecContext *)videoCodecCtx audioCodecCtx:(AVCodecContext *)audioCodecCtx swrContext:(SwrContext *)swrContext swsContent:(struct SwsContext *)swsContent picture:(AVPicture *)picture
{
    //处理每一帧数据
    AVPacket packet;
    int gotFrame = 0;
    while (true)
    {
        if (av_read_frame(formatCtx, &packet))
        {
            //读到文件末尾，av_read_frame返回0代表成功，非0则为文件末尾
            break;
        }
        
        int packetStreamIndex = packet.stream_index;
        if (packetStreamIndex == videoStreamIndex)
        {
            AVFrame *videoFrame = av_frame_alloc();
            //从packet里面 得到videoFrame
            int len = avcodec_decode_video2(videoCodecCtx, videoFrame, &gotFrame, &packet);
            if (len < 0)
            {
                break;
            }
            
            if (gotFrame)
            {
                [self handleVideoFrameWithVideoCodecCtx:videoCodecCtx videoFrame:videoFrame swsContext:swsContent picture:picture];
            }
        }
        else if(packetStreamIndex == audioStreamIndex)
        {
            //处理一帧音频数据
            AVFrame *audioFrame = av_frame_alloc();
            //从packet里面 得到audioFrame
            int len = avcodec_decode_audio4(audioCodecCtx, audioFrame, &gotFrame, &packet);
            
            if (len < 0)
            {
                break;
            }
            
            if (gotFrame)
            {
                [self handleAudioFrameWithSwrContext:swrContext audioFrame:audioFrame];
            }
        }
    }
}

/**
 网络延迟超时回调
 */
void interrupt_callback(void *sender)
{
    
}

#pragma mark 音频流
/**
 解析音频流
 */
- (AVCodecContext *)parserAudioStream:(AVStream *)audioStream
{
    AVCodecContext *audioCodecCtx = audioStream->codec;
    AVCodec *codec = avcodec_find_decoder(audioCodecCtx->codec_id);
    if (!codec) {
        printf("找不到对应的音频解码器");
    }
    
    int openCodecErrCode = 0;
    if ((openCodecErrCode = avcodec_open2(audioCodecCtx, codec, NULL)) < 0)
    {
        printf("打开音频解码器失败");
    }
    return audioCodecCtx;
}

/**
 解析音频格式
 */
- (SwrContext *)parserAudioFormat:(AVCodecContext *)audioCodecCtx
{
    //
    SwrContext *swrContext = NULL;
    
    if (audioCodecCtx->sample_fmt != AV_SAMPLE_FMT_S16)
    {
        //输出声道数
        int64_t outputChannel = 2;
        int outSampleRate = 0;
        int64_t in_ch_layout = 0;
        //输入音频格式
        enum AVSampleFormat in_samplet_fmt = audioCodecCtx->sample_fmt;
        int in_sample_rate = 0;
        int log_offset = 0;
        
        //设置转化器参数，将音频格式转成AV_SAMPLE_FMT_S16
        swrContext = swr_alloc_set_opts(NULL, outputChannel, AV_SAMPLE_FMT_S16, outSampleRate, in_ch_layout, in_samplet_fmt, in_sample_rate, log_offset, NULL);
        
        if (!swrContext || swr_init(swrContext))
        {
            if (swrContext)
            {
                swr_free(&swrContext);
            }
        }
    }
    
    return swrContext;
}


/**
 得到AV_SAMPLE_FMT_S16格式的音频裸数据
 */
- (void)handleAudioFrameWithSwrContext:(SwrContext *)swrContext audioFrame:(AVFrame *)audioFrame
{
    void *audioData;//最终得到的音频数据
    int numFrames;//每个声道的采样率
    void *swrBuffer;
    int swrBufferSize = 0;
    if (swrContext)//非AV_SAMPLE_FMT_S16格式
    {
        //双声道
        int nb_channels = 2;
        //总采样率
        int nb_samples = (int)(audioFrame->nb_samples * nb_channels);
        //获取一帧需要的缓存区大小
        int bufSize = av_samples_get_buffer_size(NULL, nb_channels, nb_samples, AV_SAMPLE_FMT_S16, 1);
        if (!swrBuffer || swrBufferSize < bufSize)
        {
            swrBufferSize = bufSize;
            //更改swrBuffer内存大小
            swrBuffer = realloc(swrBuffer, swrBufferSize);
        }
        Byte *outbuf[2] = {swrBuffer,0};
        int out_count = (int)(audioFrame->nb_samples * nb_channels);
        //原始数据
        const uint_fast8_t **uint8 = (const uint_fast8_t **)audioFrame->data;
        //一个通道有效的采样率
        int in_count = audioFrame->nb_samples;
        //按照swrContext设置的采样参数开始重采样
        numFrames = swr_convert(swrContext, outbuf, out_count, uint8, in_count);
        audioData = swrBuffer;
    }
    else//不需要转格式，已经是需要的格式
    {
        audioData = audioFrame->data[0];
        numFrames = audioFrame->nb_samples;
    }
}

#pragma mark 视频流
/**
 解析视频流
 */
- (AVCodecContext *)parserVideoStream:(AVStream *)videoStream
{
    AVCodecContext *videoCodecCtx = videoStream->codec;
    AVCodec *codec = avcodec_find_decoder(videoCodecCtx->codec_id);
    if (!codec) {
        printf("找不到对应的视频解码器");
    }
    
    int openCodecErrCode = 0;
    if ((openCodecErrCode = avcodec_open2(videoCodecCtx, codec, NULL)) < 0)
    {
        printf("打开视频解码器失败");
    }
    return videoCodecCtx;
}

- (bool)getAVPictueValidWithVideoCodecCtx:(AVCodecContext *)videoCodecCtx picture:(AVPicture *)picture
{
    bool pictureValid = avpicture_alloc(picture, PIX_FMT_YUV420P, videoCodecCtx->width, videoCodecCtx->height) == 0;
    if (!pictureValid)
    {
        printf("分配失败");
    }
    return pictureValid;
}

/**
 设置需要的视频格式
 */
- (struct SwsContext *)parserVideoFormat:(AVCodecContext *)videoCodecCtx
{
//    AVPicture picture ;
//    bool pictureValid = avpicture_alloc(&picture, PIX_FMT_YUV420P, videoCodecCtx->width, videoCodecCtx->height) == 0;
//    if (!pictureValid)
//    {
//        printf("分配失败");
//        return NULL;
//    }
    //转换图片格式和分辨率
    //SWS_FAST_BILINEAR:为某算法，此算法没有明显失真 详情：https://blog.csdn.net/leixiaohua1020/article/details/12029505
    struct SwsContext *swsContext = NULL;
    swsContext = sws_getCachedContext(swsContext, videoCodecCtx->width, videoCodecCtx->height, videoCodecCtx->pix_fmt, videoCodecCtx->width, videoCodecCtx->height, PIX_FMT_YUV420P, SWS_FAST_BILINEAR, NULL, NULL, NULL);
    return swsContext;
}

/**
 得到视频裸数据（YUV）
 */
- (void)handleVideoFrameWithVideoCodecCtx:(AVCodecContext *)videoCodecCtx videoFrame:(AVFrame *)videoFrame swsContext:(struct SwsContext *)swsContext picture:(AVPicture *)picture
{
    NSMutableData *luma;
    NSMutableData *chromaB;
    NSMutableData *chromaR;
    if (videoCodecCtx->pix_fmt == AV_PIX_FMT_YUV420P ||
        videoCodecCtx->pix_fmt == AV_PIX_FMT_YUVJ420P)
    {
        luma = copyFrameData(videoFrame->data[0],videoFrame->linesize[0],videoCodecCtx->width,videoCodecCtx->height);
        chromaB = copyFrameData(videoFrame->data[1],videoFrame->linesize[1],videoCodecCtx->width/2,videoCodecCtx->height/2);
        chromaR = copyFrameData(videoFrame->data[2],videoFrame->linesize[2],videoCodecCtx->width/2,videoCodecCtx->height/2);
    }
    else//转换YUV格式
    {
        sws_scale(swsContext, (const uint8_t **)videoFrame->data, videoFrame->linesize, 0, videoCodecCtx->height, picture->data, picture->linesize);
        
        luma = copyFrameData(picture->data[0],picture->linesize[0],videoCodecCtx->width,videoCodecCtx->height);
        chromaB = copyFrameData(picture->data[1],picture->linesize[1],videoCodecCtx->width/2,videoCodecCtx->height/2);
        chromaR = copyFrameData(picture->data[2],picture->linesize[2],videoCodecCtx->width/2,videoCodecCtx->height/2);
    }
}

static NSMutableData * copyFrameData(UInt8 *src, int linesize, int width, int height)
{
    width = MIN(linesize, width);
    NSMutableData *md = [NSMutableData dataWithLength: width * height];
    Byte *dst = md.mutableBytes;
    for (NSUInteger i = 0; i < height; ++i) {
        memcpy(dst, src, width);
        dst += width;
        src += linesize;
    }
    
    return md;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}



@end
