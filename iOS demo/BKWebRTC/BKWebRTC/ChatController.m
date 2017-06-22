//
//  ChatController.m
//  BKWebRTC
//
//  Created by 田进峰 on 2017/6/6.
//  Copyright © 2017年 CloudRoom. All rights reserved.
//

#import "ChatController.h"
#import "WebRTCHelper.h"
#import <WebRTC/WebRTC.h>

#define KScreenWidth [UIScreen mainScreen].bounds.size.width
#define KScreenHeight [UIScreen mainScreen].bounds.size.height

#define KVideoWidth KScreenWidth / 3.0
#define KVideoHeight KVideoWidth

@interface ChatController () <WebRTCHelperDelegate, RTCEAGLVideoViewDelegate>

@property (nonatomic, strong) RTCVideoTrack *localVideoTrack; /**< 本地摄像头追踪 */
@property (nonatomic, strong) NSMutableDictionary <NSString *, RTCVideoTrack *> *remoteVideoTracks; /**< 远程的视频追踪 */

- (IBAction)clickBtnForChat:(UIButton *)sender;

@end

@implementation ChatController
#pragma mark - life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
    [self _setupForChat];
}

#pragma mark - WebRTCHelperDelegate
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper setLocalStream:(RTCMediaStream *)stream
{
    BKLog(@"");
    RTCEAGLVideoView *localView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectMake(0, 20, KVideoWidth, KVideoHeight)];
    // 标记本地摄像头
    [localView setTag:10086];
    // FIXME: 实现本地/远程图像不被拉伸变形 201706201812 by king
    [localView setDelegate:self];
    _localVideoTrack = [stream.videoTracks lastObject];
    [_localVideoTrack addRenderer:localView];
    [self.view addSubview:localView];
}

- (void)webRTCHelper:(WebRTCHelper *)webRTChelper addRemoteStream:(RTCMediaStream *)stream connectionID:(NSString *)connectionID
{
    BKLog(@"connectionID:%@", connectionID);
    [_remoteVideoTracks setObject:[stream.videoTracks lastObject] forKey:connectionID];
    [self _refreshRemoteView];
}

- (void)webRTCHelper:(WebRTCHelper *)webRTChelper removeConnection:(NSString *)connectionID
{
    BKLog(@"connectionID:%@", connectionID);
    [_remoteVideoTracks removeObjectForKey:connectionID];
    [self _refreshRemoteView];
}

#pragma mark - RTCEAGLVideoViewDelegate
- (void)videoView:(RTCEAGLVideoView *)videoView didChangeVideoSize:(CGSize)size
{
    BKLog(@"videoView.tag:%zd size:%@", videoView.tag, NSStringFromCGSize(size));
    
    if (size.width > 0 && size.height > 0) {
        // Aspect fill remote video into bounds.
        CGRect bounds = videoView.bounds;
        CGRect videoFrame = AVMakeRectWithAspectRatioInsideRect(size, videoView.bounds);
        CGFloat scale = 1;
        
        if (videoFrame.size.width > videoFrame.size.height) {
            // Scale by height.
            scale = bounds.size.height / videoFrame.size.height;
        } else {
            // Scale by width.
            scale = bounds.size.width / videoFrame.size.width;
        }
        
        videoFrame.size.height *= scale;
        videoFrame.size.width *= scale;
        [videoView setBounds:(CGRect){0, 0, videoFrame.size.width, videoFrame.size.height}];
        [videoView setCenter:(CGPoint){videoView.center.x + (videoFrame.size.width - bounds.size.width) * 0.5, videoView.center.y + (videoFrame.size.height - bounds.size.height) * 0.5}];
    }
}

#pragma mark - selector
- (IBAction)clickBtnForChat:(UIButton *)sender
{
    [self dismissViewControllerAnimated:YES completion:^{
        [[WebRTCHelper shareInstance] close];
    }];
}

#pragma mark - private method
- (void)_setupForChat
{
    WebRTCHelper *webRTCHelper = [WebRTCHelper shareInstance];
    // 修改为自己的本地服务器地址
    [webRTCHelper connect:@"10.8.8.120" port:@"3000" room:@"100"];
    [webRTCHelper setDelegate:self];
    
    if (!_remoteVideoTracks) {
        _remoteVideoTracks = [NSMutableDictionary dictionary];
    }
}

- (void)_refreshRemoteView
{
    NSArray *views = self.view.subviews;
    
    for (NSInteger i = 0; i < [views count]; i++) {
        UIView *view = [views objectAtIndex:i];
        
        if ([view isKindOfClass:[RTCEAGLVideoView class]]) {
            // 本地的视频View和关闭按钮不做处理
            if (view.tag == 10086 ||view.tag == 10000) {
                continue;
            }
            
            // 其他的移除
            [view removeFromSuperview];
        }
    }
    
    __block int column = 1;
    __block int row = 0;
    // 再去添加
    [_remoteVideoTracks enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, RTCVideoTrack *remoteTrack, BOOL * _Nonnull stop) {
        RTCEAGLVideoView *remoteVideoView = [[RTCEAGLVideoView alloc] initWithFrame:CGRectMake(column * KVideoWidth, 20, KVideoWidth, KVideoHeight)];
        // FIXME: 实现本地/远程图像不被拉伸变形 201706201812 by king
        [remoteVideoView setDelegate:self];
        [remoteTrack addRenderer:remoteVideoView];
        [self.view addSubview:remoteVideoView];
        
        //列加1
        column++;
        //一行多余3个在起一行
        if (column > 3) {
            row ++;
            column = 0;
        }
    }];
}
@end
