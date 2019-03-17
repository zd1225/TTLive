//
//  ViewController.h
//  Test
//
//  Created by 赵丹 on 2017/11/27.
//  Copyright © 2017年 赵丹. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "SearchDVS.h"
#import "ImageNotifyProtocol.h"
#import "SearchCameraResultProtocol.h"
#import "ParamNotifyProtocol.h"

#include "PPPP_API.h"
#include "PPPPChannelManagement.h"


@interface ViewController : UIViewController <ImageNotifyProtocol,SearchCameraResultProtocol,
            ParamNotifyProtocol,UIScrollViewDelegate>{
    
    CSearchDVS* dvs;
    
    //镜像参数
    int flip;
    CGPoint beginPoint;
}

@property (nonatomic, copy)   CPPPPChannelManagement  *m_PPPPChannelMgt;
@property (nonatomic, strong) NSTimer        *searchTimer;
@property (nonatomic, assign) CGPoint        beginPoint;
@property (nonatomic, strong) NSDictionary   *infoDic;


@end

