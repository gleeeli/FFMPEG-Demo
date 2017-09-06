//
//  CameraViewController.m
//  SFFmpegIOSStreamer
//
//  Created by gleeeli on 2017/8/5.
//  Copyright © 2017年 Lei Xiaohua. All rights reserved.
//

#import "CameraViewController.h"
#import "AWAVConfig.h"
#import "AWEncoderManager.h"

//// 状态回调函数
//extern void aw_rtmp_state_changed_cb_in_oc(aw_rtmp_state old_state, aw_rtmp_state new_state){
//    NSLog(@"rtmp 状态回调：[OC] rtmp state changed from(%s), to(%s)", aw_rtmp_state_description(old_state), aw_rtmp_state_description(new_state));
//
//}

@interface CameraViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate>
//{
//    AVCaptureSession *_captureSession;
//    UIImageView *_imageView;
//    CALayer *_customLayer;
//    AVCaptureVideoPreviewLayer *_prevLayer;
//}
@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CALayer *customLayer;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *prevLayer;

@property (nonatomic, strong) AVCaptureDeviceInput *videoInputDevice;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;

@property (nonatomic, strong) AVCaptureDeviceInput *audioInputDevice;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;

//配置
@property (nonatomic, strong) AWAudioConfig *audioConfig;
@property (nonatomic, strong) AWVideoConfig *videoConfig;

//根据videoConfig获取当前CaptureSession preset分辨率
@property (nonatomic, readonly, copy) NSString *captureSessionPreset;

@property (nonatomic, copy) NSMutableArray *array;

//进入后台后，不推视频流
@property (nonatomic, unsafe_unretained) BOOL inBackground;

//是否将数据发送出去
@property (nonatomic, unsafe_unretained) BOOL isCapturing;

//编码管理
@property (nonatomic, strong) AWEncoderManager *encoderManager;

////编码器类型
//@property (nonatomic, unsafe_unretained) AWAudioEncoderType audioEncoderType;
//@property (nonatomic, unsafe_unretained) AWAudioEncoderType videoEncoderType;

//是否已发送了sps/pps
@property (nonatomic, unsafe_unretained) BOOL isSpsPpsAndAudioSpecificConfigSent;

//编码队列，发送队列
@property (nonatomic, strong) dispatch_queue_t encodeSampleQueue;
@property (nonatomic, strong) dispatch_queue_t sendSampleQueue;
@property (weak, nonatomic) IBOutlet UIButton *streamBtn;// 开始直播按钮

@end

// 服务器地址
const NSString *outputURL1 = @"rtmp://192.168.1.105:1935/zbcs/room";


@implementation CameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.imageView = nil;
    self.prevLayer = nil;
    self.customLayer = nil;
    

    
    // 初始化麦克风 摄像头
    [self initCapture];
    
    // 创建回话，回调数据
    [self createCaptureSession];
}

-(NSString *)captureSessionPreset{
    NSString *captureSessionPreset = nil;
    if(self.videoConfig.width == 480 && self.videoConfig.height == 640){
        captureSessionPreset = AVCaptureSessionPreset640x480;
    }else if(self.videoConfig.width == 540 && self.videoConfig.height == 960){
        captureSessionPreset = AVCaptureSessionPresetiFrame960x540;
    }else if(self.videoConfig.width == 720 && self.videoConfig.height == 1280){
        captureSessionPreset = AVCaptureSessionPreset1280x720;
    }
    return captureSessionPreset;
}

-(AWEncoderManager *)encoderManager{
    if (!_encoderManager) {
        _encoderManager = [[AWEncoderManager alloc] init];
        //设置编码器类型
        _encoderManager.audioEncoderType = AWAudioEncoderTypeSWFAAC;
        _encoderManager.videoEncoderType = AWVideoEncoderTypeHWH264;
    }
    return _encoderManager;
}

-(dispatch_queue_t)encodeSampleQueue{
    if (!_encodeSampleQueue) {
        _encodeSampleQueue = dispatch_queue_create("aw.encodesample.queue", DISPATCH_QUEUE_SERIAL);
    }
    return _encodeSampleQueue;
}

-(dispatch_queue_t)sendSampleQueue{
    if (!_sendSampleQueue) {
        _sendSampleQueue = dispatch_queue_create("aw.sendsample.queue", DISPATCH_QUEUE_SERIAL);
    }
    return _sendSampleQueue;
}

- (IBAction)streamBtnClick:(id)sender
{

}


-(void) stopCapture{
    self.isCapturing = NO;
    self.isSpsPpsAndAudioSpecificConfigSent = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_sync(self.sendSampleQueue, ^{
        aw_streamer_close();
    });
    dispatch_sync(self.encodeSampleQueue, ^{
        [weakSelf.encoderManager close];
    });
}

-(void) switchCamera{}

-(void) onStopCapture{}

-(void) onStartCapture{}

-(void)setisCapturing:(BOOL)isCapturing{
    if (_isCapturing == isCapturing) {
        return;
    }
    
    if (!isCapturing) {
        [self onStopCapture];
    }else{
        [self onStartCapture];
    }
    
    _isCapturing = isCapturing;
}


- (void)initCapture {
    // 初始化麦克风
    // 执行这几句代码后，系统会弹框提示：应用想要访问您的麦克风。请点击同意
    // 另外iOS10 需要在info.plist中添加字段NSMicrophoneUsageDescription。否则会闪退，具体请自行baidu。
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    self.audioInputDevice = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:nil];
    
    // 初始化前后摄像头
    // 执行这几句代码后，系统会弹框提示：应用想要访问您的相机。请点击同意
    // 另外iOS10 需要在info.plist中添加字段NSCameraUsageDescription。否则会闪退
    AVCaptureDevice *videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    self.videoInputDevice = [AVCaptureDeviceInput
                                          deviceInputWithDevice:videoDevice error:nil];
    dispatch_queue_t queue;
    queue = dispatch_queue_create("cameraQueue", NULL);
    
    //音频数据输出
    self.audioDataOutput = [[AVCaptureAudioDataOutput alloc] init];
    //设置代理，需要当前类实现protocol：AVCaptureAudioDataOutputSampleBufferDelegate
    [self.audioDataOutput setSampleBufferDelegate:self queue:queue];
    
    // 视频输出
    self.videoDataOutput = [[AVCaptureVideoDataOutput alloc]
                                               init];
    //抛弃过期帧，保证实时性
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = YES;
    //captureOutput.minFrameDuration = CMTimeMake(1, 10);
    
    
    [self.videoDataOutput setSampleBufferDelegate:self queue:queue];
//    dispatch_release(queue);
    NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
    NSNumber* value = [NSNumber
                       numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    
    NSDictionary* videoSettings = [NSDictionary
                                   dictionaryWithObject:value forKey:key];
    [self.videoDataOutput setVideoSettings:videoSettings];
    
    //设置输出格式为 yuv420
    [self.videoDataOutput setVideoSettings:@{
                                             (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
                                             }];
    
    self.captureSession = [[AVCaptureSession alloc] init];
    if (self.videoInputDevice == nil) {
        NSLog(@"获取摄像头出错");
        return;
    }
    [self.captureSession addInput:self.videoInputDevice];
    [self.captureSession addOutput:self.videoDataOutput];
    [self.captureSession startRunning];
    
    self.customLayer = [CALayer layer];
    self.customLayer.frame = self.view.bounds;
    self.customLayer.transform = CATransform3DRotate(
                                                     CATransform3DIdentity, M_PI/2.0f, 0, 0, 1);
    self.customLayer.contentsGravity = kCAGravityResizeAspectFill;
    [self.view.layer addSublayer:self.customLayer];
    
    self.imageView = [[UIImageView alloc] init];
    self.imageView.frame = CGRectMake(0, 0, 100, 100);
    [self.view addSubview:self.imageView];
    
    
    self.prevLayer = [AVCaptureVideoPreviewLayer
                      layerWithSession: self.captureSession]; 
    self.prevLayer.frame = CGRectMake(100, 0, 100, 100); 
    self.prevLayer.videoGravity = AVLayerVideoGravityResizeAspectFill; 
    [self.view.layer addSublayer: self.prevLayer]; 
}

// AVCaptureSession 创建逻辑很简单，它像是一个中介者，从音视频输入设备获取数据，处理后，传递给输出设备(数据代理/预览layer)。
-(void) createCaptureSession{
    //初始化
    self.captureSession = [AVCaptureSession new];
    
    //修改配置
    [self.captureSession beginConfiguration];
    
    //加入视频输入设备
    if ([self.captureSession canAddInput:self.videoInputDevice]) {
        [self.captureSession addInput:self.videoInputDevice];
    }
    
    //加入音频输入设备
    if ([self.captureSession canAddInput:self.audioInputDevice]) {
        [self.captureSession addInput:self.audioInputDevice];
    }
    
    //加入视频输出
    if([self.captureSession canAddOutput:self.videoDataOutput]){
        [self.captureSession addOutput:self.videoDataOutput];
        [self setVideoOutConfig];
    }
    
    //加入音频输出
    if([self.captureSession canAddOutput:self.audioDataOutput]){
        [self.captureSession addOutput:self.audioDataOutput];
    }
    
    //设置预览分辨率
    //这个分辨率有一个值得注意的点：
    //iphone4录制视频时 前置摄像头只能支持 480*640 后置摄像头不支持 540*960 但是支持 720*1280
    //诸如此类的限制，所以需要写一些对分辨率进行管理的代码。
    //目前的处理是，对于不支持的分辨率会抛出一个异常
    //但是这样做是不够、不完整的，最好的方案是，根据设备，提供不同的分辨率。
    //如果必须要用一个不支持的分辨率，那么需要根据需求对数据和预览进行裁剪，缩放。
    if (![self.captureSession canSetSessionPreset:self.captureSessionPreset]) {
        @throw [NSException exceptionWithName:@"Not supported captureSessionPreset" reason:[NSString stringWithFormat:@"captureSessionPreset is [%@]", self.captureSessionPreset] userInfo:nil];
    }
    
    self.captureSession.sessionPreset = self.captureSessionPreset;
    
    //提交配置变更
    [self.captureSession commitConfiguration];
    
    //开始运行，此时，CaptureSession将从输入设备获取数据，处理后，传递给输出设备。
    [self.captureSession startRunning];
}

-(void) setVideoOutConfig{
    for (AVCaptureConnection *conn in self.videoDataOutput.connections) {
        if (conn.isVideoStabilizationSupported) {
            [conn setPreferredVideoStabilizationMode:AVCaptureVideoStabilizationModeAuto];
        }
        if (conn.isVideoOrientationSupported) {
            [conn setVideoOrientation:AVCaptureVideoOrientationPortrait];
        }
        if (conn.isVideoMirrored) {
            [conn setVideoMirrored: YES];
        }
    }
}

#pragma mark //音频数据回调 //视频数据回调
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if ([self.videoDataOutput isEqual:captureOutput])
    {
        //捕获到视频数据，通过sendVideoSampleBuffer发送出去，后续文章会解释接下来的详细流程。
        [self sendVideoSampleBuffer:sampleBuffer];
        
    }else if([self.audioDataOutput isEqual:captureOutput])
    {
        //捕获到音频数据，通过sendVideoSampleBuffer发送出去
        [self sendAudioSampleBuffer:sampleBuffer];
    }
    
//    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
//    CVPixelBufferLockBaseAddress(imageBuffer,0);
//    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
//    size_t height = CVPixelBufferGetHeight(imageBuffer);
//    
//    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
//    CGContextRef newContext = CGBitmapContextCreate(baseAddress,
//                                                    width, height, 8, bytesPerRow, colorSpace,
//                                                    kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
//    CGImageRef newImage = CGBitmapContextCreateImage(newContext);
//    
//    CGContextRelease(newContext);
//    CGColorSpaceRelease(colorSpace);
//    
//    [self.customLayer performSelectorOnMainThread:@selector(setContents:)
//                                       withObject: (__bridge id) newImage waitUntilDone:YES];
//    
//    UIImage *image= [UIImage imageWithCGImage:newImage scale:1.0
//                                  orientation:UIImageOrientationRight];
//    
//    CGImageRelease(newImage);
//    
//    [self.imageView performSelectorOnMainThread:@selector(setImage:)
//                                     withObject:image waitUntilDone:YES];
//    
//    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
}

//使用rtmp协议发送数据
-(void) sendVideoSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    [self sendVideoSampleBuffer:sampleBuffer toEncodeQueue:self.encodeSampleQueue toSendQueue:self.sendSampleQueue];
}

-(void) sendAudioSampleBuffer:(CMSampleBufferRef) sampleBuffer{
    [self sendAudioSampleBuffer:sampleBuffer toEncodeQueue:self.encodeSampleQueue toSendQueue:self.sendSampleQueue];
}

//发送数据
-(void) sendVideoSampleBuffer:(CMSampleBufferRef) sampleBuffer toEncodeQueue:(dispatch_queue_t) encodeQueue toSendQueue:(dispatch_queue_t) sendQueue{
    if (_inBackground) {
        return;
    }
    CFRetain(sampleBuffer);
    __weak typeof(self) weakSelf = self;
    dispatch_async(encodeQueue, ^{
        if (weakSelf.isCapturing) {
            aw_flv_video_tag *video_tag = [weakSelf.encoderManager.videoEncoder encodeVideoSampleBufToFlvTag:sampleBuffer];
            [weakSelf sendFlvVideoTag:video_tag toSendQueue:sendQueue];
        }
        CFRelease(sampleBuffer);
    });
}

-(void) sendAudioSampleBuffer:(CMSampleBufferRef) sampleBuffer toEncodeQueue:(dispatch_queue_t) encodeQueue toSendQueue:(dispatch_queue_t) sendQueue{
    CFRetain(sampleBuffer);
    __weak typeof(self) weakSelf = self;
    dispatch_async(encodeQueue, ^{
        if (weakSelf.isCapturing) {
            aw_flv_audio_tag *audio_tag = [weakSelf.encoderManager.audioEncoder encodeAudioSampleBufToFlvTag:sampleBuffer];
            [weakSelf sendFlvAudioTag:audio_tag toSendQueue:sendQueue];
        }
        CFRelease(sampleBuffer);
    });
}


-(void) sendFlvVideoTag:(aw_flv_video_tag *)video_tag toSendQueue:(dispatch_queue_t) sendQueue{
    if (_inBackground) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    if (video_tag) {
        dispatch_async(sendQueue, ^{
            if(weakSelf.isCapturing){
                if (!weakSelf.isSpsPpsAndAudioSpecificConfigSent) {
                    [weakSelf sendSpsPpsAndAudioSpecificConfigTagToSendQueue:sendQueue];
                    free_aw_flv_video_tag((aw_flv_video_tag **)&video_tag);
                }else{
                    aw_streamer_send_video_data(video_tag);
                }
            }
        });
    }
}

-(void) sendFlvAudioTag:(aw_flv_audio_tag *)audio_tag toSendQueue:(dispatch_queue_t) sendQueue{
    __weak typeof(self) weakSelf = self;
    if(audio_tag){
        dispatch_async(sendQueue, ^{
            if(weakSelf.isCapturing){
                if (!weakSelf.isSpsPpsAndAudioSpecificConfigSent) {
                    [weakSelf sendSpsPpsAndAudioSpecificConfigTagToSendQueue:sendQueue];
                    free_aw_flv_audio_tag((aw_flv_audio_tag **)&audio_tag);
                }else{
                    aw_streamer_send_audio_data(audio_tag);
                }
            }
        });
    }
}

-(void) sendSpsPpsAndAudioSpecificConfigTagToSendQueue:(dispatch_queue_t) sendQueue{
    if (self.isSpsPpsAndAudioSpecificConfigSent) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(sendQueue, ^{
        if (!weakSelf.isCapturing || weakSelf.isSpsPpsAndAudioSpecificConfigSent) {
            return;
        }
        //video sps pps tag
        aw_flv_video_tag *spsPpsTag = [weakSelf.encoderManager.videoEncoder createSpsPpsFlvTag];
        if (spsPpsTag) {
            aw_streamer_send_video_sps_pps_tag(spsPpsTag);
        }
        //audio specific config tag
        aw_flv_audio_tag *audioSpecificConfigTag = [weakSelf.encoderManager.audioEncoder createAudioSpecificConfigFlvTag];
        if (audioSpecificConfigTag) {
            aw_streamer_send_audio_specific_config_tag(audioSpecificConfigTag);
        }
        weakSelf.isSpsPpsAndAudioSpecificConfigSent = spsPpsTag || audioSpecificConfigTag;
        
        aw_log("[D] is sps pps and audio sepcific config sent=%d", weakSelf.isSpsPpsAndAudioSpecificConfigSent);
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

-(void)dealloc
{
    self.imageView = nil;
    self.customLayer = nil;
    self.prevLayer = nil;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
