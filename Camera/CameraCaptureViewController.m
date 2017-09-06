//
//  CameraCaptureViewController.m
//  SFFmpegIOSStreamer
//
//  Created by gleeeli on 2017/8/23.
//  Copyright © 2017年 Lei Xiaohua. All rights reserved.
//

#import "CameraCaptureViewController.h"
#import "VideoCaptureManager.h"

@interface CameraCaptureViewController ()
@property (nonatomic, strong) VideoCaptureManager *testVideoCapture;
@end

@implementation CameraCaptureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.testVideoCapture = [[VideoCaptureManager alloc] initWithViewController:self];
}

-(void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    [self.testVideoCapture onLayout];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
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
