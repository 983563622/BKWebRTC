//
//  WebRTCHelper.h
//  BKWebRTC
//
//  Created by 田进峰 on 2017/6/2.
//  Copyright © 2017年 CloudRoom. All rights reserved.
//

#import <Foundation/Foundation.h>

@class WebRTCHelper;
@class RTCMediaStream;

@protocol WebRTCHelperDelegate <NSObject>

@optional
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper setLocalStream:(RTCMediaStream *)stream;
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper addRemoteStream:(RTCMediaStream *)stream connectionID:(NSString *)connectionID;
- (void)webRTCHelper:(WebRTCHelper *)webRTChelper removeConnection:(NSString *)connectionID;

@end

@interface WebRTCHelper : NSObject

@property (nonatomic, weak) id <WebRTCHelperDelegate> delegate;

+ (instancetype)shareInstance;

- (void)connect:(NSString *)host port:(NSString *)port room:(NSString *)room;
- (void)close;

@end
