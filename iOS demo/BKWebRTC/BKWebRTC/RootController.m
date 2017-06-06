//
//  RootController.m
//  BKWebRTC
//
//  Created by 田进峰 on 2017/6/6.
//  Copyright © 2017年 CloudRoom. All rights reserved.
//

#import "RootController.h"

@interface RootController ()

- (IBAction)clickBtnForRoot:(UIButton *)sender;
@end

@implementation RootController
#pragma mark - life cycle
- (void)viewDidLoad
{
    [super viewDidLoad];
}

#pragma mark - selector
- (IBAction)clickBtnForRoot:(UIButton *)sender
{
    UIStoryboard *main = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *chatVC = [main instantiateViewControllerWithIdentifier:@"ChatController"];
    
    if (chatVC) {
        [self presentViewController:chatVC animated:YES completion:nil];
    }
}
@end
