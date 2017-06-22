//
//  WebRTCHelper.m
//  BKWebRTC
//
//  Created by 田进峰 on 2017/6/2.
//  Copyright © 2017年 CloudRoom. All rights reserved.
//

/*
 本端担任两种角色:
 RoleCaller:A
    _sendOffers
    _receiveAnswer
 RoleCalled:B
    _newOffer
 
 注意:
 1. 新加入房间的成员要发送 offer
 2. answerForConstraints:/offerForConstraints:都是针对"本端"而言
 */

#import "WebRTCHelper.h"
#import "SocketRocket.h"
#import <WebRTC/WebRTC.h>
#import "MJExtension.h"

// google提供的
static NSString *const RTCSTUNServerURL = @"stun:stun.l.google.com:19302";
static NSString *const RTCSTUNServerURL2 = @"stun:23.21.150.121";

typedef NS_ENUM(NSInteger, RoleType)
{
    RoleCaller, /**< 发送者 */
    RoleCalled /**< 被发送者 */
};

@interface WebRTCHelper () <SRWebSocketDelegate, RTCPeerConnectionDelegate>

@property (nonatomic, copy) NSString *host; /**< 服务器地址 */
@property (nonatomic, copy) NSString *port; /**< 端口号 */
@property (nonatomic, copy) NSString *room; /**< 房间号 */
@property (nonatomic, strong) SRWebSocket *socket; /**< socket */
@property (nonatomic, strong) RTCPeerConnectionFactory *factory; /**< 点对点工厂 */
@property (nonatomic, strong) RTCMediaStream *localStream; /**< 本地流 */
@property (nonatomic, strong) NSMutableArray <RTCIceServer *> *iceServers;
@property (nonatomic, assign) RoleType role;
@property (nonatomic, strong) NSMutableArray <NSString *> *peerConnectionIDS; /**< 对端ID集合 */
@property (nonatomic, strong) NSMutableDictionary <NSString *, RTCPeerConnection *> *peerConnections; /**< 连接集合 */

@end

@implementation WebRTCHelper
#pragma mark - singleton
static WebRTCHelper *shareInstance;
+ (instancetype)shareInstance
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [[self alloc] init];
    });
    return shareInstance;
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shareInstance = [super allocWithZone:zone];
    });
    return shareInstance;
}

#pragma mark - life cycle
- (instancetype)init
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    [self _setup];
    
    return self;
}

#pragma mark - SRWebSocketDelegate
- (void)webSocketDidOpen:(SRWebSocket *)webSocket
{
    BKLog(@"");
    
    /** 2. 发送一个加入聊天室的信令(join),信令中需要包含用户所进入的聊天室名称 */
    [self _join:_room];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error
{
    BKLog(@"");
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean
{
    BKLog(@"");
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message
{
    BKLog(@"%@", message);
    
    NSMutableDictionary *resultDic = [message mj_JSONObject];
    NSString *eventName = resultDic[@"eventName"];
    
    if ([eventName isEqualToString:@"_peers"]) {
        /** 3. 服务器根据用户所加入的房间,发送一个其他用户信令(peers),信令中包含聊天室中其他用户的信息,客户端根据信息来逐个构建与其他用户的点对点连接*/
        [self _sendOffers:resultDic];
    }
    else if ([eventName isEqualToString:@"_offer"]) {
        [self _receiveOffer:resultDic];
    }
    else if ([eventName isEqualToString:@"_answer"]) {
        [self _receiveAnswer:resultDic];
    }
    else if ([eventName isEqualToString:@"_ice_candidate"]) { // 接收到新加入的人发了ICE候选,(即经过ICEServer而获取到的地址)
        [self _setCandidateToConnection:resultDic];
    }
    else if ([eventName isEqualToString:@"_new_peer"]) {
        /** 5. 若有新用户加入,服务器发送一个用户加入信令(new_peer),信令中包含新加入的用户的信息,客户端根据信息来建立与这个新用户的点对点连接 */
        [self _memberEnter:resultDic];
    }
    else if ([eventName isEqualToString:@"_remove_peer"]) {
        /** 4. 若有用户离开,服务器发送一个用户离开信令(remove_peer),信令中包含离开的用户的信息,客户端根据信息关闭与离开用户的信息,并作相应的清除操作 */
        [self _memberLeave:resultDic];
    }
}

#pragma mark - RTCPeerConnectionDelegate
/** Called when the SignalingState changed. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged
{
    BKLog(@"");
}

/** Called when media is received on a new stream from remote peer. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didAddStream:(RTCMediaStream *)stream
{
    BKLog(@"");
    NSString *connectionID = [self _findConnectionID:peerConnection];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:addRemoteStream:connectionID:)]) {
            [_delegate webRTCHelper:self addRemoteStream:stream connectionID:connectionID];
        }
    });
}

/** Called when a remote peer closes a stream. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveStream:(RTCMediaStream *)stream
{
    BKLog(@"");
}

/** Called when negotiation is needed, for example ICE has restarted. */
- (void)peerConnectionShouldNegotiate:(RTCPeerConnection *)peerConnection
{
    BKLog(@"");
}

/** Called any time the IceConnectionState changes. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState
{
    BKLog(@"");
}

/** Called any time the IceGatheringState changes. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState
{
    BKLog(@"");
}

/** New ice candidate has been found. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didGenerateIceCandidate:(RTCIceCandidate *)candidate
{
    BKLog(@"");
    /* 把自己的网络地址通过 socket 转发给对端*/
    NSString *connectionID = [self _findConnectionID:peerConnection];
    NSDictionary *dic = @{@"eventName": @"__ice_candidate", @"data": @{@"id":candidate.sdpMid,@"label": [NSNumber numberWithInteger:candidate.sdpMLineIndex], @"candidate": candidate.sdp, @"socketId": connectionID}};
    
    if (_socket.readyState == SR_OPEN) {
        [_socket send:[dic mj_JSONData]];
    }
}

/** Called when a group of local Ice candidates have been removed. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didRemoveIceCandidates:(NSArray<RTCIceCandidate *> *)candidates
{
    BKLog(@"");
}

/** New data channel has been opened. */
- (void)peerConnection:(RTCPeerConnection *)peerConnection didOpenDataChannel:(RTCDataChannel *)dataChannel
{
    BKLog(@"");
}

#pragma mark - public method
/** 1. 客户端与服务器建立WebSocket连接 */
- (void)connect:(NSString *)host port:(NSString *)port room:(NSString *)room
{
    BKLog(@"");
    NSParameterAssert(host);
    NSParameterAssert(port);
    NSParameterAssert(room);
    
    _host = host;
    _port = port;
    _room = room;
    
    [self _setupForSocket];
}

/** 6. 用户离开页面,关闭WebSocket连接 */
- (void)close
{
    BKLog(@"");
    _localStream = nil;
    [_peerConnectionIDS enumerateObjectsUsingBlock:^(NSString *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [self _closeConnection:obj];
    }];
    [_socket close];
}

#pragma mark - private method
- (void)_setup
{
    BKLog(@"");
    
    if (!_peerConnections) {
        _peerConnections = [NSMutableDictionary dictionary];
    }
    
    if (!_peerConnectionIDS) {
        _peerConnectionIDS = [NSMutableArray array];
    }
    
    // 设置SSL传输
    RTCInitializeSSL();
}

- (void)_setupForSocket
{
    BKLog(@"");
    
    if (_socket) {
        [_socket close];
        _socket = nil;
    }
    
    NSString *str = [NSString stringWithFormat:@"ws://%@:%@", _host, _port];
    NSURL *url = [NSURL URLWithString:str];
    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
    _socket = [[SRWebSocket alloc] initWithURLRequest:request];
    [_socket setDelegate:self];
    [_socket open];
}

- (void)_setupForFactory
{
    BKLog(@"");
    
    if (!_factory) {
        _factory = [[RTCPeerConnectionFactory alloc] init];
    }
}

- (void)_setupForLocalStream
{
    BKLog(@"");
    
    if (!_localStream) {
        // 设置点对点工厂
        [self _setupForFactory];
        
        RTCAudioTrack *audioTrack = [_factory audioTrackWithTrackId:@"ARDAMSa0"];
        AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        NSArray<AVCaptureDevice *> *devices;
        
        _localStream = [_factory mediaStreamWithStreamId:@"ARDAMS"];
        // 添加音频轨迹
        [_localStream addAudioTrack:audioTrack];
        
        if(authStatus == AVAuthorizationStatusRestricted || authStatus == AVAuthorizationStatusDenied) { // 摄像头权限
            BKLog(@"相机访问受限");
            if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:)]) {
                [_delegate webRTCHelper:self setLocalStream:nil];
            }
        }
        else {
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 100000
            if ([AVCaptureDeviceDiscoverySession class]) {
                AVCaptureDeviceDiscoverySession *deviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
                devices = [deviceDiscoverySession devices];
            }
            else {
                devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
            }
#else
            AVCaptureDeviceDiscoverySession *deviceDiscoverySession = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
            devices = [deviceDiscoverySession devices];
#endif
            
            AVCaptureDevice *device = [devices lastObject];
            
            if (device) {
                RTCAVFoundationVideoSource *videoSource = [_factory avFoundationVideoSourceWithConstraints:[self _setupForLocalVideoConstraints]];
                [videoSource setUseBackCamera:NO];
                RTCVideoTrack *videoTrack = [_factory videoTrackWithSource:videoSource trackId:@"ARDAMSv0"];
                
                // 添加视频轨迹
                [_localStream addVideoTrack:videoTrack];
                
                if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:)]) {
                    [_delegate webRTCHelper:self setLocalStream:_localStream];
                }
            }
            else {
                BKLog(@"该设备不能打开摄像头");
                if ([_delegate respondsToSelector:@selector(webRTCHelper:setLocalStream:)]) {
                    [_delegate webRTCHelper:self setLocalStream:nil];
                }
            }
        }
    }
}

- (RTCMediaConstraints *)_setupForLocalVideoConstraints
{
    BKLog(@"");
    NSDictionary *mandatory = @{kRTCMediaConstraintsMaxWidth : @"640",
                                kRTCMediaConstraintsMinWidth : @"640",
                                kRTCMediaConstraintsMaxHeight : @"480",
                                kRTCMediaConstraintsMinHeight : @"480",
                                kRTCMediaConstraintsMinFrameRate : @"25"};
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:nil];
    return constraints;
}

- (RTCMediaConstraints *)_setupForPeerVideoConstraints
{
    BKLog(@"");
    NSDictionary *mandatory = @{kRTCMediaConstraintsMaxWidth : @"640",
                                kRTCMediaConstraintsMinWidth : @"640",
                                kRTCMediaConstraintsMaxHeight : @"480",
                                kRTCMediaConstraintsMinHeight : @"480",
                                kRTCMediaConstraintsMinFrameRate : @"25"};
    NSDictionary *optional = @{@"DtlsSrtpKeyAgreement" : kRTCMediaConstraintsValueTrue};
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:optional];
    return constraints;
}

- (RTCMediaConstraints *)_setupForOfferOrAnswerConstraint
{
    BKLog(@"");
    NSDictionary *mandatory = @{kRTCMediaConstraintsOfferToReceiveAudio : kRTCMediaConstraintsValueTrue,
                                kRTCMediaConstraintsOfferToReceiveVideo : kRTCMediaConstraintsValueTrue};
    RTCMediaConstraints *constraints = [[RTCMediaConstraints alloc] initWithMandatoryConstraints:mandatory optionalConstraints:nil];
    return constraints;
}

- (void)_setupForConnections
{
    BKLog(@"");
    [_peerConnectionIDS enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        RTCPeerConnection *connection = [self _createConnection:obj];
        [_peerConnections setObject:connection forKey:obj];
    }];
}

- (void)_setupForIceServers
{
    BKLog(@"");
    
    if (!_iceServers) {
        _iceServers = [NSMutableArray array];
        [_iceServers addObject:[self _setupForIceServer:RTCSTUNServerURL ]];
        [_iceServers addObject:[self _setupForIceServer:RTCSTUNServerURL2]];
    }
}

- (RTCIceServer *)_setupForIceServer:(NSString *)stunURL
{
    BKLog(@"");
    return [[RTCIceServer alloc] initWithURLStrings:@[stunURL] username:@"" credential:@""];
}

- (RTCPeerConnection *)_createConnection:(NSString *)connectionID
{
    BKLog(@"");
    [self _setupForFactory];
    [self _setupForIceServers];
    RTCConfiguration *configuration = [[RTCConfiguration alloc] init];
    [configuration setIceServers:_iceServers];
    return [_factory peerConnectionWithConfiguration:configuration constraints:[self _setupForPeerVideoConstraints] delegate:self];
}

- (void)_closeConnection:(NSString *)connectionID
{
    BKLog(@"");
    RTCPeerConnection *connection = [_peerConnections objectForKey:connectionID];
    
    if (connection) {
        [connection close];
    }
    
    [_peerConnectionIDS removeObject:connectionID];
    [_peerConnections removeObjectForKey:connectionID];
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([_delegate respondsToSelector:@selector(webRTCHelper:removeConnection:)]) {
            [_delegate webRTCHelper:self removeConnection:connectionID];
        }
    });
}

- (void)_join:(NSString *)room
{
    BKLog(@"");
    
    if (_socket.readyState == SR_OPEN) {
        NSDictionary *dic = @{@"eventName": @"__join", @"data": @{@"room": room}};
        NSData *para = [dic mj_JSONData];
        // 发送加入房间的数据
        [_socket send:para];
    }
}

- (void)_addToConnectionIDS:(NSArray *)connections
{
    BKLog(@"");
    [connections enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        BKLog(@"%@", obj);
    }];
    [_peerConnectionIDS addObjectsFromArray:connections];
}

- (void)_addLocalStreamToConnections
{
    BKLog(@"");
    [_peerConnections enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RTCPeerConnection * _Nonnull obj, BOOL * _Nonnull stop) {
        [self _setupForLocalStream];
        [obj addStream:_localStream];
    }];
}

- (void)_sendSDPOffersToConnections
{
    BKLog(@"");
    [_peerConnections enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RTCPeerConnection * _Nonnull obj, BOOL * _Nonnull stop) {
        [self _sendSDPOfferToConnection:obj];
    }];
}

- (void)_sendSDPOfferToConnection:(RTCPeerConnection *)connection
{
    BKLog(@"");
    _role = RoleCaller;
    /** Generate an SDP offer. */
    [connection offerForConstraints:[self _setupForOfferOrAnswerConstraint] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
        if (error) {
            BKLog(@"offerForConstraints error");
            return;
        }
        
        if (sdp.type == RTCSdpTypeOffer) {
            __weak __typeof(connection) wConnection = connection;
            /** Apply the supplied RTCSessionDescription as the local description. */
            // A:设置连接本端 SDP
            [connection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                if (error) {
                    BKLog(@"setLocalDescription error");
                    return;
                }
                
                [self _didSetSessionDescription:wConnection];
            }];
        }
    }];
}

- (NSString *)_findConnectionID:(RTCPeerConnection *)connection
{
    __block NSString *connectionID;
    
    [_peerConnections enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RTCPeerConnection * _Nonnull obj, BOOL * _Nonnull stop) {
        if ([connection isEqual:obj]) {
            connectionID = key;
            *stop = YES;
        }
    }];
    
    return connectionID;
}

- (RTCSdpType)_typeForString:(NSString *)string
{
    RTCSdpType sdpType = RTCSdpTypeOffer;
    
    if ([string isEqualToString:@"answer"]) {
        sdpType = RTCSdpTypeAnswer;
    }
    else if ([string isEqualToString:@"offer"]) {
        sdpType = RTCSdpTypeOffer;
    }
    
    return sdpType;
}

- (void)_didSetSessionDescription:(RTCPeerConnection *)connection
{
    BKLog(@"signalingState:%zd role:%zd", connection.signalingState, _role);
    NSString *connectionID = [self _findConnectionID:connection];

    if (connection.signalingState == RTCSignalingStateHaveRemoteOffer) { // 新人进入房间就调(远端发起 offer)
        /** Generate an SDP answer. */
        [connection answerForConstraints:[self _setupForOfferOrAnswerConstraint] completionHandler:^(RTCSessionDescription * _Nullable sdp, NSError * _Nullable error) {
            if (error) {
                BKLog(@"answerForConstraints error");
                return;
            }
            
            if (sdp.type == RTCSdpTypeAnswer) {
                __weak __typeof(connection) wConnection = connection;
                // B:设置连接本端 SDP
                [connection setLocalDescription:sdp completionHandler:^(NSError * _Nullable error) {
                    if (error) {
                        BKLog(@"setLocalDescription error");
                        return;
                    }
                    
                    [self _didSetSessionDescription:wConnection];
                }];
            }
        }];
    }
    else if (connection.signalingState == RTCSignalingStateHaveLocalOffer) { // 本地发送 offer
        if (_role == RoleCaller) {
            NSDictionary *dic = @{@"eventName": @"__offer",
                                  @"data": @{@"sdp": @{@"type": @"offer",
                                                       @"sdp": connection.localDescription.sdp
                                                       },
                                             @"socketId": connectionID
                                             }
                                  };
            
            if (_socket.readyState == SR_OPEN) {
                [_socket send:[dic mj_JSONData]];
            }
        }
    }
    else if (connection.signalingState == RTCSignalingStateStable) { // 本地发送 answer
        if (_role == RoleCalled) {
            NSDictionary *dic = @{@"eventName": @"__answer",
                                  @"data": @{@"sdp": @{@"type": @"answer",
                                                       @"sdp": connection.localDescription.sdp
                                                       },
                                             @"socketId": connectionID
                                             }
                                  };
            
            if (_socket.readyState == SR_OPEN) {
                [_socket send:[dic mj_JSONData]];
            }
        }
    }
}

// TODO:六大事件
/**
 本端群发 offer
 */
- (void)_sendOffers:(NSMutableDictionary *)resultDic
{
    BKLog(@"");
    NSDictionary *dataDic = resultDic[@"data"];
    // 记录所有对端连接ID
    [self _addToConnectionIDS:dataDic[@"connections"]];
    // 建立本地流信息
    [self _setupForLocalStream];
    // 建立所有连接
    [self _setupForConnections];
    // 所有连接添加本地流信息
    [self _addLocalStreamToConnections];
    // 所有连接发送 SDP offer
    [self _sendSDPOffersToConnections];
}

/**
 远端发来 offer
 */
- (void)_receiveOffer:(NSMutableDictionary *)resultDic
{
    BKLog(@"");
    // 设置当前角色状态为被呼叫,(被发offer）
    _role = RoleCalled;
    NSDictionary *dataDic = resultDic[@"data"];
    NSDictionary *sdpDic = dataDic[@"sdp"];
    // 拿到SDP
    NSString *sdp = sdpDic[@"sdp"];
    NSString *type = sdpDic[@"type"];
    NSString *connectionID = dataDic[@"socketId"];
    RTCSdpType sdpType = [self _typeForString:type];
    // 拿到这个点对点的连接
    RTCPeerConnection *connection = [_peerConnections objectForKey:connectionID];
    // 根据类型和SDP 生成SDP描述对象
    RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdp];
    
    if (sdpType == RTCSdpTypeOffer) {
        // 设置给这个点对点连接
        __weak __typeof(connection) wConnection = connection;
        // B:设置连接对端 SDP
        [connection setRemoteDescription:remoteSdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                BKLog(@"setRemoteDescription error");
            }
            
            [self _didSetSessionDescription:wConnection];
        }];
    }
}

/**
 远端发来 answer
 */
- (void)_receiveAnswer:(NSMutableDictionary *)resultDic
{
    BKLog(@"");
    NSDictionary *dataDic = resultDic[@"data"];
    NSDictionary *sdpDic = dataDic[@"sdp"];
    NSString *sdp = sdpDic[@"sdp"];
    NSString *type = sdpDic[@"type"];
    NSString *connectionID = dataDic[@"socketId"];
    RTCSdpType sdpType = [self _typeForString:type];
    RTCPeerConnection *connection = [_peerConnections objectForKey:connectionID];
    RTCSessionDescription *remoteSdp = [[RTCSessionDescription alloc] initWithType:sdpType sdp:sdp];
    
    if (sdpType == RTCSdpTypeAnswer) {
        __weak __typeof(connection) wConnection = connection;
        /** Apply the supplied RTCSessionDescription as the remote description. */
        // A:设置连接对端 SDP
        [connection setRemoteDescription:remoteSdp completionHandler:^(NSError * _Nullable error) {
            if (error) {
                BKLog(@"setRemoteDescription error");
            }
            
            [self _didSetSessionDescription:wConnection];
        }];
    }
}

/**
 设置连接 candidate
 对端的网络地址通过 socket 转发给本端
 */
- (void)_setCandidateToConnection:(NSMutableDictionary *)resultDic
{
    BKLog(@"");
    NSDictionary *dataDic = resultDic[@"data"];
    NSString *connectionID = dataDic[@"socketId"];
    NSString *sdpMid = dataDic[@"id"];
    NSInteger sdpMLineIndex = [dataDic[@"label"] integerValue];
    NSString *sdp = dataDic[@"candidate"];
    // 生成远端网络地址对象
    RTCIceCandidate *candidate = [[RTCIceCandidate alloc] initWithSdp:sdp sdpMLineIndex:(int)sdpMLineIndex sdpMid:sdpMid];
    // 拿到当前对应的点对点连接
    RTCPeerConnection *connection = [_peerConnections objectForKey:connectionID];
    // 添加到点对点连接中
    [connection addIceCandidate:candidate];
}

/**
 成员进入
 */
- (void)_memberEnter:(NSMutableDictionary *)resultDic
{
    BKLog(@"");
    NSDictionary *dataDic = resultDic[@"data"];
    // 拿到新人的ID
    NSString *connectionID = dataDic[@"socketId"];
    [self _setupForLocalStream];
    // 再去创建一个连接
    RTCPeerConnection *connection = [self _createConnection:connectionID];
    // 把本地流加到连接中去
    [connection addStream:_localStream];
    // 新加一个远端连接ID
    [_peerConnectionIDS addObject:connectionID];
    // 并且设置到Dic中去
    [_peerConnections setObject:connection forKey:connectionID];
}

/**
 成员离开
 */
- (void)_memberLeave:(NSMutableDictionary *)resultDic
{
    BKLog(@"");
    NSDictionary *dataDic = resultDic[@"data"];
    NSString *connectionID = dataDic[@"socketId"];
    [self _closeConnection:connectionID];
}
@end
