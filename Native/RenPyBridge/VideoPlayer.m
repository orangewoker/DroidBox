#include <stdio.h>

@import UIKit;
@import AVFoundation;
@import Dispatch;

@interface VideoPlayerView : UIView
@property(nonatomic) AVPlayer *player;
@end

@interface VideoPlayer : NSObject {
    UIWindow *window;
    AVPlayer *player;
    VideoPlayerView *playerView;
    BOOL playing;
    BOOL paused;
}
- (id)initWithFile:(char *)filename;
- (int)isPlaying;
- (void)stop;
- (void)pause;
- (void)unpause;
- (void)periodic;
@end

@implementation VideoPlayer
- (id)initWithFile:(char *)filename {
    self = [super init];
    if (!self) return nil;

    for (UIWindow *candidate in UIApplication.sharedApplication.windows) {
        if (candidate.isKeyWindow) {
            window = candidate;
            break;
        }
    }
    window = window ?: UIApplication.sharedApplication.windows.firstObject;
    NSString *path = [NSString stringWithUTF8String:filename];
    player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
    playerView = [[VideoPlayerView alloc] initWithFrame:window.bounds];
    playerView.player = player;
    playerView.opaque = YES;
    playerView.backgroundColor = UIColor.blackColor;
    [window.rootViewController.view addSubview:playerView];
    [player play];
    playing = YES;
    paused = NO;
    return self;
}

- (int)isPlaying { return playing; }

- (void)periodic {
    if (!playing || paused) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->playerView.frame = self->window.bounds;
    });
    if (!player.rate || player.error) [self stop];
}

- (void)stop {
    [player pause];
    [playerView removeFromSuperview];
    playing = NO;
    paused = NO;
}

- (void)pause {
    [player pause];
    paused = YES;
}

- (void)unpause {
    [player play];
    paused = NO;
}
@end

@implementation VideoPlayerView
+ (Class)layerClass { return AVPlayerLayer.class; }
- (AVPlayer *)player { return [(AVPlayerLayer *)self.layer player]; }
- (void)setPlayer:(AVPlayer *)player { [(AVPlayerLayer *)self.layer setPlayer:player]; }
@end
