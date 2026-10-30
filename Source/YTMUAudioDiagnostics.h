#ifndef YTMU_AUDIO_DIAGNOSTICS_H
#define YTMU_AUDIO_DIAGNOSTICS_H

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>


#define YTMU_AUDIO_LOG(fmt, ...) \
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, \
                     "[YTMU-AUDIO] " fmt, ##__VA_ARGS__)

static id YTMUSafeValue(id object, NSString *key) {
    if (!object || !key) return nil;

    @try {
        return [object valueForKey:key];
    }
    @catch (NSException *exception) {
        return nil;
    }
}

static void YTMUDumpAudioProperties(id object,
                                    NSString *path,
                                    NSInteger depth) {
    if (!object || depth > 2) return;

    unsigned int count = 0;
    objc_property_t *properties =
        class_copyPropertyList([object class], &count);

    for (unsigned int i = 0; i < count; i++) {
        NSString *key = [NSString stringWithUTF8String:
                         property_getName(properties[i])];

        NSString *lower = [key lowercaseString];

        BOOL relevant =
            [lower containsString:@"audio"] ||
            [lower containsString:@"quality"] ||
            [lower containsString:@"bitrate"] ||
            [lower containsString:@"codec"] ||
            [lower containsString:@"bandwidth"] ||
            [lower containsString:@"saver"] ||
            [lower containsString:@"format"] ||
            [lower containsString:@"stream"];

        if (!relevant) continue;

        id value = YTMUSafeValue(object, key);

        if (!value || value == [NSNull null]) continue;

        NSString *fullPath =
            [path stringByAppendingFormat:@".%@", key];

        if ([value isKindOfClass:[NSNumber class]]) {

            YTMU_AUDIO_LOG(
                "%{public}s = %{public}lld",
                [fullPath UTF8String],
                [value longLongValue]
            );

        } else if ([value isKindOfClass:[NSString class]]) {

            if ([lower containsString:@"url"] ||
                [lower containsString:@"token"] ||
                [lower containsString:@"auth"] ||
                [lower containsString:@"cookie"]) {
                continue;
            }

            NSString *string = value;

            if ([string length] > 120) {
                string = [string substringToIndex:120];
            }

            YTMU_AUDIO_LOG(
                "%{public}s = %{public}s",
                [fullPath UTF8String],
                [string UTF8String]
            );

        } else if (depth < 2 &&
                   ![value isKindOfClass:[NSArray class]] &&
                   ![value isKindOfClass:[NSDictionary class]]) {

            YTMUDumpAudioProperties(
                value,
                fullPath,
                depth + 1
            );
        }
    }

    free(properties);
}

static void YTMURunAudioDiagnostics(id data) {
    
    static BOOL didRun = NO;
    static NSObject *lock = nil;

    @synchronized([NSObject class]) {
        if (!lock) {
            lock = [NSObject new];
        }
    }

    @synchronized(lock) {
        if (didRun) return;
        didRun = YES;
    }

    @try {

        id response = YTMUSafeValue(data, @"playerResponse");
        id playerData = YTMUSafeValue(response, @"playerData");

        if (!playerData) {
            YTMU_AUDIO_LOG("playerData unavailable");
            return;
        }

        YTMU_AUDIO_LOG("===== FULL DIAGNOSTICS =====");

        id playerConfig =
            YTMUSafeValue(playerData, @"playerConfig");

        NSArray *configNames = @[
            @"audioConfig",
            @"mediaCommonConfig",
            @"iosPlayerConfig",
            @"iosAvPlayerConfig",
            @"dataSaverConfig",
            @"iosBandwidthEstimatorConfig"
        ];

        for (NSString *name in configNames) {

            id config = YTMUSafeValue(playerConfig, name);

            YTMU_AUDIO_LOG(
                "CONFIG %{public}s: %{public}s",
                [name UTF8String],
                config ? "PRESENT" : "NIL"
            );

            if (config) {
                YTMUDumpAudioProperties(config, name, 0);
            }
        }

        id streamingData =
            YTMUSafeValue(playerData, @"streamingData");

        id formats =
            YTMUSafeValue(streamingData, @"adaptiveFormatsArray");

        if ([formats isKindOfClass:[NSArray class]]) {

            YTMU_AUDIO_LOG(
                "TOTAL FORMATS: %{public}lu",
                (unsigned long)[formats count]
            );

            for (id format in formats) {

                id itag = YTMUSafeValue(format, @"itag");
                id bitrate = YTMUSafeValue(format, @"bitrate");
                id averageBitrate =
                    YTMUSafeValue(format, @"averageBitrate");
                id mimeType =
                    YTMUSafeValue(format, @"mimeType");

                NSString *mime =
                    [mimeType isKindOfClass:[NSString class]]
                    ? mimeType : @"unknown";

                YTMU_AUDIO_LOG(
                    "FORMAT itag=%{public}lld "
                    "bitrate=%{public}lld "
                    "average=%{public}lld "
                    "mime=%{public}s",
                    (long long)[itag longLongValue],
                    (long long)[bitrate longLongValue],
                    (long long)[averageBitrate longLongValue],
                    [mime UTF8String]
                );
            }
        } else {
            YTMU_AUDIO_LOG("adaptiveFormatsArray unavailable");
        }

        YTMU_AUDIO_LOG("===== END DIAGNOSTICS =====");

    }
    @catch (NSException *exception) {

        YTMU_AUDIO_LOG(
            "DIAGNOSTICS ERROR: %{public}s",
            [[exception name] UTF8String]
        );
    }
}


// Discovery only: print property names, never values or streaming URLs.
static void YTMUDiscoverPlayerProperties(id object, const char *label) {
    if (!object) return;

    YTMU_AUDIO_LOG(
        "DISCOVERY %{public}s class=%{public}s",
        label,
        class_getName(object_getClass(object))
    );

    unsigned int printed = 0;

    for (Class cls = object_getClass(object);
         cls && printed < 45;
         cls = class_getSuperclass(cls)) {

        unsigned int count = 0;
        objc_property_t *props = class_copyPropertyList(cls, &count);

        for (unsigned int i = 0; i < count && printed < 45; i++) {
            const char *raw = property_getName(props[i]);
            if (!raw) continue;

            NSString *name = [NSString stringWithUTF8String:raw];
            NSString *lower = name.lowercaseString;

            if ([lower containsString:@"format"] ||
                [lower containsString:@"audio"] ||
                [lower containsString:@"quality"] ||
                [lower containsString:@"stream"] ||
                [lower containsString:@"track"] ||
                [lower containsString:@"player"] ||
                [lower containsString:@"bitrate"] ||
                [lower containsString:@"adaptive"]) {

                YTMU_AUDIO_LOG(
                    "DISCOVERY %{public}s property=%{public}s",
                    label,
                    raw
                );

                printed++;
            }
        }

        free(props);
    }
}

static void YTMUDiscoverPlayerOnce(
    id viewController,
    id playbackController
) {
    static BOOL didDiscover = NO;

    @synchronized([NSObject class]) {
        if (didDiscover) return;
        didDiscover = YES;
    }

    YTMU_AUDIO_LOG("===== PLAYER PROPERTY DISCOVERY =====");

    YTMUDiscoverPlayerProperties(
        viewController,
        "viewController"
    );

    YTMUDiscoverPlayerProperties(
        playbackController,
        "playbackController"
    );

    YTMU_AUDIO_LOG("===== END PLAYER PROPERTY DISCOVERY =====");
}




#endif
