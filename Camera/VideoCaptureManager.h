//
//  VideoCaptureManager.h
//  SFFmpegIOSStreamer
//
//  Created by gleeeli on 2017/8/23.
//  Copyright © 2017年 Lei Xiaohua. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ViewController.h"

@interface VideoCaptureManager : NSObject
-(instancetype) initWithViewController:(ViewController *)viewCtl;

-(void) onLayout;
@end
