# BKWebRTC
基于开源框架`WebRTC`实现的iOS demo

# 如何运行
首先,[下载源码](https://github.com/BossKing/BKWebRTC)  
其次,启动服务器(`cd 当前server.js目录`):  
`node server.js`  
最后,  
iOS真机:  
修改代码`[webRTCHelper connect:@"10.8.8.120" port:@"3000" room:@"100"]; // 修改为自己的本地服务器地址`  
运行项目`iOS demo/BKWebRTC/BKWebRTC.xcodeproj`可看效果  
浏览器:  
输入:`http://localhost:3000/#100`可看效果

# 相关问题
[iOS8 devide runtime error MetalKit Reason:imagenot found after the version M58](https://bugs.chromium.org/p/webrtc/issues/detail?id=7899#c3)