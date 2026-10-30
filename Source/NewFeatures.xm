#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "Headers/YTPlayerViewController.h"
#import "Headers/YTMToastController.h"
#import "Headers/Localization.h"
#include "YTMUAudioDiagnostics.h"

#pragma mark - Helpers

static BOOL YTMU(NSString *key) {
    NSDictionary *dict =
        [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"YTMUltimate"];
    return [dict[key] boolValue];
}

#pragma mark - Always High Audio Quality

%hook YTMMediaQualityController

- (NSInteger)audioQuality {
    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"alwaysHighQuality")) {
        return 2;
    }
    return %orig;
}

- (void)setAudioQuality:(NSInteger)quality {
    %orig(YTMU(@"alwaysHighQuality") ? 2 : quality);
}

%end

#pragma mark - Skip Disliked Songs

%hook YTMQueueController

%new
- (void)checkAndSkipDislikedSong {
    SEL valueForKeySel = @selector(valueForKey:);
    id currentItem =
        ((id (*)(id, SEL, id))objc_msgSend)(self, valueForKeySel, @"_currentItem");

    if (!currentItem) return;

    SEL likeStatusSel = NSSelectorFromString(@"likeStatus");
    if (!class_getInstanceMethod(object_getClass(currentItem), likeStatusSel)) return;

    NSInteger status =
        ((NSInteger (*)(id, SEL))objc_msgSend)(currentItem, likeStatusSel);

    if (status == 2) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[%c(YTMToastController) alloc]
                showMessage:LOC(@"SKIPPED_DISLIKED")];
        });

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            SEL nextSel = @selector(advanceToNextItem);
            if (class_getInstanceMethod(object_getClass(self), nextSel)) {
                ((void (*)(id, SEL))objc_msgSend)(self, nextSel);
            }
        });
    }
}

- (void)advanceToNextItem {
    %orig;

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"skipDislikedSongs")) {
        SEL checkSel = @selector(checkAndSkipDislikedSong);
        if (class_getInstanceMethod(object_getClass(self), checkSel)) {
            ((void (*)(id, SEL))objc_msgSend)(self, checkSel);
        }
    }
}

%end

#pragma mark - Discord Presence (storage only)

@interface YTMUDiscordRPC : NSObject
+ (instancetype)sharedInstance;
- (void)updatePresenceWithTitle:(NSString *)title artist:(NSString *)artist;
- (void)clearPresence;
@end

%subclass YTMUDiscordRPC : NSObject

+ (instancetype)sharedInstance {
    static YTMUDiscordRPC *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

%new
- (void)updatePresenceWithTitle:(NSString *)title artist:(NSString *)artist {
    if (!YTMU(@"YTMUltimateIsEnabled") || !YTMU(@"discordRPC")) return;

    // Ensure we have non-nil string values
    NSString *safeTitle = (title && [title isKindOfClass:[NSString class]]) ? title : @"";
    NSString *safeArtist = (artist && [artist isKindOfClass:[NSString class]]) ? artist : @"";

    // Double-check that we have valid strings (should never be nil at this point)
    if (!safeTitle) safeTitle = @"";
    if (!safeArtist) safeArtist = @"";

    NSDictionary *nowPlaying = @{
        @"title": safeTitle,
        @"artist": safeArtist
    };

    // Ensure the dictionary was created successfully before storing
    if (nowPlaying) {
        [[NSUserDefaults standardUserDefaults]
            setObject:nowPlaying
               forKey:@"YTMUltimate_NowPlaying"];
    }
}

%new
- (void)clearPresence {
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:@"YTMUltimate_NowPlaying"];
}

%end

#pragma mark - Player Hooks

%hook YTPlayerViewController

- (void)playbackController:(id)controller
        didActivateVideo:(id)video
       withPlaybackData:(id)data {

    %orig;



YTMURunAudioDiagnostics(data);
YTMUDiscoverPlayerOnce(self, controller);

NSArray *audioKeys = @[
    @"musicKit_playerResponseItem_nowPlayingAudioFormat",
    @"musicKit_nowPlayingInfoAudioFormat_badging"
];

for (NSString *key in audioKeys) {
    id value = YTMUSafeValue(controller, key);

    YTMU_AUDIO_LOG(
        "SELECTED AUDIO %{public}s class=%{public}s",
        key.UTF8String,
        value ? class_getName(object_getClass(value)) : "nil"
    );

    if ([value isKindOfClass:[NSNumber class]]) {
        YTMU_AUDIO_LOG(
            "SELECTED AUDIO value=%{public}s",
            [[value description] UTF8String]
        );
    } else if ([value isKindOfClass:[NSString class]]) {
        YTMU_AUDIO_LOG(
            "SELECTED AUDIO value=%{public}s",
            [value UTF8String]
        );
    }
}





    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"discordRPC")) {
        @try {
            YTPlayerResponse *response = self.playerResponse;
            if (!response || !response.playerData) return;
            
            id videoDetails = response.playerData.videoDetails;
            if (!videoDetails || ![videoDetails respondsToSelector:@selector(valueForKey:)]) return;
            
            id titleObj = [videoDetails valueForKey:@"title"];
            id authorObj = [videoDetails valueForKey:@"author"];
            
            // Ensure we have valid string objects (not NSNull or other types)
            NSString *title = nil;
            NSString *author = nil;
            
            if (titleObj && titleObj != [NSNull null] && [titleObj isKindOfClass:[NSString class]]) {
                title = titleObj;
            }
            
            if (authorObj && authorObj != [NSNull null] && [authorObj isKindOfClass:[NSString class]]) {
                author = authorObj;
            }
            
            // Only update if we have at least one valid value
            if (title || author) {
                [[%c(YTMUDiscordRPC) sharedInstance]
                    updatePresenceWithTitle:title
                                     artist:author];
            }
        } @catch (NSException *exception) {
            NSLog(@"[YTMusicUltimate] Discord RPC error: %@", exception);
        }
    }
}

- (void)playbackControllerDidStopPlaying:(id)controller {
    %orig;

    if (YTMU(@"YTMUltimateIsEnabled") && YTMU(@"discordRPC")) {
        [[%c(YTMUDiscordRPC) sharedInstance] clearPresence];
    }
}

%end

#pragma mark - Defaults

%ctor {
    NSMutableDictionary *dict =
        [NSMutableDictionary dictionaryWithDictionary:
            [[NSUserDefaults standardUserDefaults]
                dictionaryForKey:@"YTMUltimate"] ?: @{}];

    NSDictionary *defaults = @{
        @"alwaysHighQuality": @NO,
        @"skipDislikedSongs": @NO,
        @"discordRPC": @NO
    };

    for (NSString *key in defaults) {
        if (!dict[key]) {
            dict[key] = defaults[key];
        }
    }

    [[NSUserDefaults standardUserDefaults]
        setObject:dict
           forKey:@"YTMUltimate"];
}
