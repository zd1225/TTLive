//
//  ViewController.m
//  Test
//
//  Created by 赵丹 on 2017/11/27.
//  Copyright © 2017年 赵丹. All rights reserved.
//


/************************************************************
 直播原理：
 推流:（采集视频流/图像->编码->推流）
 服务端：转码->截图->审核
 播放端：拉流->解码->展示
 
 本demo返回的是以图片帧的形式返回，故而播放端需要对图片进行处理
 ***************************************************************/


#import "ViewController.h"

#import "PPPPDefine.h"
#import "obj_common.h"
#import "SearchDVS.h"
#import "CustomAVRecorder.h"
#import "RecPathManagement.h"

#include "MyAudioSession.h"
#include "APICommon.h"

@interface ViewController ()
{
    UIView *sheetView;
    UIScrollView *scrollV;
    UIActivityIndicatorView *activityV;
    UIButton *cancleBtn;
}


@property (nonatomic, retain) NSCondition           *m_PPPPChannelMgtCondition;
@property (nonatomic, retain) NSString              *cameraID;
@property (nonatomic, assign) BOOL                  m_bPtzIsUpDown;
@property (nonatomic, assign) BOOL                  m_bPtzIsLeftRight;
@property (nonatomic, assign) NSTimeInterval        recTime;
@property (nonatomic, strong) CCustomAVRecorder     *m_pCustomRecorder;
@property (nonatomic, strong) NSString              *recordFileName;
@property (nonatomic, retain) NSRecursiveLock       *m_RecordLock;
@property (nonatomic, retain) RecPathManagement     *m_recPathMgt;
@property (nonatomic, assign) NSInteger             cameraStatus;


@end

@implementation ViewController


#pragam mark -- 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    self.cancleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.cancleBtn setImage:[UIImage imageNamed:@"videoback"] forState:UIControlStateNormal];
    self.cancleBtn.frame = CGRectMake(0, 20, 65, 62);
    [self.cancleBtn addTarget:self action:@selector(clickDissmissBtn:) forControlEvents:UIControlEventTouchUpInside];
    self.cancleBtn.enabled = NO;
    [self.view addSubview:cancleBtn];
    
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [self beginPaly];
    });
}


- (void)viewDidDisappear:(BOOL)animated{
    [_m_PPPPChannelMgtCondition lock];
    if (_m_PPPPChannelMgt == NULL) {
        [_m_PPPPChannelMgtCondition unlock];
        return;
    }
    _m_PPPPChannelMgt->StopAll();
    [_m_PPPPChannelMgtCondition unlock];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - 调用直播摄像头

//初始化摄像头
- (void)cameraInit{
    
    PPPP_Initialize((char*)[@"ADCBBFAOPPJAHGJGBBGLFLAGDBJJHNJGGMBFBKHIBBNKOKLDHOBHCBOEHOKJJJKJBPMFLGCPPJMJAPDOIPNL" UTF8String]);
    st_PPPP_NetInfo NetInfo;
    PPPP_NetworkDetect(&NetInfo, 0);
    
    [self connectCamera];
}

//连接相机
- (void)connectCamera{
    
    [_m_PPPPChannelMgtCondition lock];
    if (_m_PPPPChannelMgt == NULL) {
        [_m_PPPPChannelMgtCondition unlock];
        return;
    }
    _m_PPPPChannelMgt->StopAll();
    dispatch_async(dispatch_get_main_queue(),^{
        _playView.image = nil;
    });
    
    NSString *cameraIDS = [_infoDic objectForKey:@"introduce"];
    _cameraID = cameraIDS;//JPEG

    
    [self performSelector:@selector(startPPPP:) withObject:_cameraID];
    [_m_PPPPChannelMgtCondition unlock];

}

//摄像
- (void)startVideo{
    if (_m_PPPPChannelMgt != NULL) {
        if (_m_PPPPChannelMgt->StartPPPPLivestream([_cameraID UTF8String], 10, self) == 0) {
            _m_PPPPChannelMgt->StopPPPPAudio([_cameraID UTF8String]);
            _m_PPPPChannelMgt->StopPPPPLivestream([_cameraID UTF8String]);
        }
        
        _m_PPPPChannelMgt->GetCGI([_cameraID UTF8String], CGI_IEGET_CAM_PARAMS);
    }
}

//进入后台
- (void)didEnterBackground{
    [_m_PPPPChannelMgtCondition lock];
    if (_m_PPPPChannelMgt == NULL) {
        [_m_PPPPChannelMgtCondition unlock];
        return;
    }
    _m_PPPPChannelMgt->StopAll();
    [_m_PPPPChannelMgtCondition unlock];
}


- (void)handleTimer:(NSTimer *)timer{
    
    [self stopSearch];
}

- (void) stopSearch
{
    if (dvs != NULL) {
        SAFE_DELETE(dvs);
    }
}

- (void) startPPPP:(NSString*) camID{
    NSString *userS = [_infoDic objectForKey:@"username"];
    NSString *password = [_infoDic objectForKey:@"password"];
    _m_PPPPChannelMgt->Start([camID UTF8String], [userS UTF8String], [password UTF8String]);
}


//ImageNotifyProtocol
- (void)ImageNotify: (UIImage *)image timestamp: (NSInteger)timestamp DID:(NSString *)did{
    [self performSelector:@selector(refreshImage:) withObject:image];
}


- (void)YUVNotify: (Byte*) yuv length:(int)length width: (int) width height:(int)height timestamp:(unsigned int)timestamp DID:(NSString *)did{
    UIImage* image = [APICommon YUV420ToImage:yuv width:width height:height];
    [self performSelector:@selector(refreshImage:) withObject:image];
}


- (void) H264Data: (Byte*) h264Frame length: (int) length type: (int) type timestamp: (NSInteger) timestamp{
    //写入录像数据
    [_m_RecordLock lock];
    if (_m_pCustomRecorder != nil) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        unsigned int unTimestamp = 0;
        struct timeval tv;
        struct timezone tz;
        gettimeofday(&tv, &tz);
        unTimestamp = tv.tv_usec / 1000 + tv.tv_sec * 1000 ;
        //NSLog(@"unTimestamp: %d", unTimestamp);
        _m_pCustomRecorder->SendOneFrame((char*)h264Frame, length, unTimestamp, type);
        [pool release];
    }
    [_m_RecordLock unlock];
}


//PPPPStatusDelegate
- (void)PPPPStatus: (NSString*) strDID statusType:(NSInteger) statusType status:(NSInteger) status{
    cancleBtn.enabled = YES;
    NSString* strPPPPStatus;
    switch (status) {
        case PPPP_STATUS_UNKNOWN:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusUnknown", @STR_LOCALIZED_FILE_NAME, nil);
            break;
        case PPPP_STATUS_CONNECTING:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusConnecting", @STR_LOCALIZED_FILE_NAME, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = NO;
            });
            break;
        case PPPP_STATUS_INITIALING:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusInitialing", @STR_LOCALIZED_FILE_NAME, nil);
            break;
        case PPPP_STATUS_CONNECT_FAILED:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusConnectFailed", @STR_LOCALIZED_FILE_NAME, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = YES;
                [ProgressHUD showError:@"摄像机连接失败~"];
            });
            break;
        case PPPP_STATUS_DISCONNECT:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusDisconnected", @STR_LOCALIZED_FILE_NAME, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = NO;
            });
            break;
        case PPPP_STATUS_INVALID_ID:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusInvalidID", @STR_LOCALIZED_FILE_NAME, nil);
            break;
        case PPPP_STATUS_ON_LINE:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusOnline", @STR_LOCALIZED_FILE_NAME, nil);
            [self startVideo];
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = YES;
            });
            break;
        case PPPP_STATUS_DEVICE_NOT_ON_LINE:
            strPPPPStatus = NSLocalizedStringFromTable(@"CameraIsNotOnline", @STR_LOCALIZED_FILE_NAME, nil);
            [ProgressHUD showError:@""];
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = YES;
                [ProgressHUD showError:@"摄像机未联网~"];
            });
            break;
        case PPPP_STATUS_CONNECT_TIMEOUT:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusConnectTimeout", @STR_LOCALIZED_FILE_NAME, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = YES;
                [ProgressHUD showError:@"摄像机链接超时~"];
            });
            break;
        case PPPP_STATUS_INVALID_USER_PWD:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusInvaliduserpwd", @STR_LOCALIZED_FILE_NAME, nil);
            break;
        default:
            strPPPPStatus = NSLocalizedStringFromTable(@"PPPPStatusUnknown", @STR_LOCALIZED_FILE_NAME, nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                activityV.hidden = YES;
                [ProgressHUD showError:@"摄像机未知错误~"];
            });
            break;
    }
    _cameraStatus = status;
    NSLog(@"PPPPStatus  %@",strPPPPStatus);
}

//refreshImage
- (void) refreshImage:(UIImage* ) image{
    if (image != nil) {
        dispatch_async(dispatch_get_main_queue(),^{
            _playView.image = image;
        });
    }
}


#pragma mark -- TouchEvent
- (void)PlayViewtouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSLog(@"touchesBegan");
    beginPoint = [[touches anyObject] locationInView:self.playView];
    
}

- (void)PlayViewtouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    
    UITouch *touch = [touches anyObject];
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    
    if (touch.tapCount ==1) {
        if (UIInterfaceOrientationPortrait == orientation || UIInterfaceOrientationPortraitUpsideDown == orientation) {
            //[mytoast showWithText:NSLocalizedStringFromTable(@"单击", @STR_LOCALIZED_FILE_NAME, nil)];
            [self performSelector:@selector(TransitionToOrientation:) withObject:nil];
        }else
        {
            [self performSelector:@selector(playViewTouch:) withObject:nil afterDelay:0.3];
        }
    }
    

    //云台
    
    CGPoint currPoint = [[touches anyObject] locationInView:self.playView];
    const int EVENT_PTZ = 1;
    int curr_event = EVENT_PTZ;
    
    int x1 = beginPoint.x;
    int y1 = beginPoint.y;
    int x2 = currPoint.x;
    int y2 = currPoint.y;
    
    int view_width = self.playView.frame.size.width;
    int _width1 = 0;
    int _width2 = view_width  ;
    
    if(x1 >= _width1 && x1 <= _width2)
    {
        curr_event = EVENT_PTZ;
    }
    else
    {
        return;
    }
    
    const int MIN_X_LEN = 60;
    const int MIN_Y_LEN = 60;
    
    int len = (x1 > x2) ? (x1 - x2) : (x2 - x1) ;
    BOOL b_x_ok = (len >= MIN_X_LEN ) ? YES : NO ;
    len = (y1 > y2) ? (y1 - y2) : (y2 - y1) ;
    BOOL b_y_ok = (len > MIN_Y_LEN) ? YES : NO;
    
    BOOL bUp = NO;
    BOOL bDown = NO;
    BOOL bLeft = NO;
    BOOL bRight = NO;
    
    bDown = (y1 > y2) ? NO : YES;
    bUp = !bDown;
    bRight = (x1 > x2) ? NO : YES;
    bLeft = !bRight;
    
    int command = 0;
    
    switch (curr_event)
    {
        case EVENT_PTZ:
        {
            
            if (b_x_ok == YES)
            {
                if (bLeft == NO)
                {
                    NSLog(@"left");
                    command = CMD_PTZ_LEFT;
                    //command = CMD_PTZ_RIGHT;
                }
                else
                {
                    NSLog(@"right");
                    command = CMD_PTZ_RIGHT;
                    //command = CMD_PTZ_LEFT;
                }
                
                
                _m_PPPPChannelMgt->PTZ_Control([_cameraID UTF8String], command);
                _m_PPPPChannelMgt->PTZ_Control([_cameraID UTF8String], command + 1);
            }
            
            if (b_y_ok == YES)
            {
                
                if (bUp == NO)
                {
                    NSLog(@"up");
                    command = CMD_PTZ_UP;
                    //command = CMD_PTZ_DOWN;
                }
                else
                {
                    NSLog(@"down");
                    command = CMD_PTZ_DOWN;
                    //command = CMD_PTZ_UP;
                }
                
                _m_PPPPChannelMgt->PTZ_Control([_cameraID UTF8String], command);
                _m_PPPPChannelMgt->PTZ_Control([_cameraID UTF8String], command + 1);
            }
        }
            break;
            
        default:
            return ;
    }
    
}

- (void)PlayViewtouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    NSLog(@"touchesCancelled");
}


#pragma mark -- ParamNotifyProtocol
- (void) ParamNotify: (int) paramType params:(void*) params{
    if (paramType == CGI_IEGET_CAM_PARAMS) {
        PSTRU_CAMERA_PARAM param = (PSTRU_CAMERA_PARAM) params;
        flip = param->flip;
    }
}


#pragma mark- private methond

- (void)beginPaly{
    _m_PPPPChannelMgtCondition = [[NSCondition alloc] init];
    
    _m_PPPPChannelMgt = new CPPPPChannelManagement();
    _m_PPPPChannelMgt->pCameraViewController = self;
    _m_bPtzIsUpDown = NO;
    _m_bPtzIsLeftRight = NO;
    _m_RecordLock = [[NSRecursiveLock alloc] init];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(willEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    self.playView.userInteractionEnabled = YES;
    
    InitAudioSession();
    
    [self cameraInit];
}

@end


