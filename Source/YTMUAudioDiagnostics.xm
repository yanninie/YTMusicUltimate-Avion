#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void YTMUDumpProperties(id object, NSString *path, NSInteger depth) {
    if (!object || depth > 3) return;

    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList([object class], &count);

    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(properties[i]);
        NSString *key = [NSString stringWithUTF8String:name];
        NSString *fullPath = [path stringByAppendingFormat:@".%@", key];

        NSString *lower = [key lowercaseString];

        BOOL relevant =
            [lower containsString:@"audio"] ||
            [lower containsString:@"quality"] ||
            [lower containsString:@"bitrate"] ||
            [lower containsString:@"codec"] ||
            [lower containsString:@"premium"] ||
            [lower containsString:@"stream"] ||
            [lower containsString:@"bandwidth"] ||
            [lower containsString:@"saver"] ||
            [lower containsString:@"format"];

        @try {
            id value = [object valueForKey:key];

            if (!value || value == [NSNull null]) continue;

            if ([value isKindOfClass:[NSNumber class]]) {
                if (relevant) {
                    NSLog(@"[YTMU-AUDIO] %s = %s",
                          [fullPath UTF8String],
                          [[value description] UTF8String]);
                }
            } else if ([value isKindOfClass:[NSString class]]) {
                if (relevant &&
                    ![lower containsString:@"url"] &&
                    ![lower containsString:@"token"]) {
                    NSLog(@"[YTMU-AUDIO] %s = %s",
                          [fullPath UTF8String],
                          [value UTF8String]);
                }
            } else if (depth < 3 &&
                       ![value isKindOfClass:[NSArray class]] &&
                       ![value isKindOfClass:[NSDictionary class]]) {
                YTMUDumpProperties(value, fullPath, depth + 1);
            }
        } @catch (NSException *exception) {
            NSLog(@"[YTMU-AUDIO] Cannot inspect %s",
                  [fullPath UTF8String]);
        }
    }

    free(properties);
}

static void YTMURunAudioDiagnostics(id data) {
    static BOOL didRun = NO;

    @synchronized([NSObject class]) {
        if (didRun) return;
        didRun = YES;
    }

    @try {
        id response = [data valueForKey:@"playerResponse"];
        id playerData = [response valueForKey:@"playerData"];

        if (!playerData) {
            NSLog(@"[YTMU-AUDIO] playerData unavailable");
            return;
        }

        NSLog(@"[YTMU-AUDIO] ===== FULL DIAGNOSTICS =====");

        id playerConfig = [playerData valueForKey:@"playerConfig"];

        NSArray *configNames = @[
            @"audioConfig",
            @"mediaCommonConfig",
            @"iosPlayerConfig",
            @"iosAvPlayerConfig",
            @"dataSaverConfig",
            @"iosBandwidthEstimatorConfig"
        ];

        for (NSString *name in configNames) {
            @try {
                id config = [playerConfig valueForKey:name];

                NSLog(@"[YTMU-AUDIO] CONFIG %s: %s",
                      [name UTF8String],
                      config ? "PRESENT" : "NIL");

                if (config) {
                    YTMUDumpProperties(config, name, 0);
                }
            } @catch (NSException *exception) {
                NSLog(@"[YTMU-AUDIO] CONFIG %s ERROR",
                      [name UTF8String]);
            }
        }

        id streamingData = [playerData valueForKey:@"streamingData"];
        id formats = [streamingData valueForKey:@"adaptiveFormatsArray"];

        if ([formats isKindOfClass:[NSArray class]]) {
            NSLog(@"[YTMU-AUDIO] TOTAL FORMATS: %lu",
                  (unsigned long)[formats count]);

            for (id format in formats) {
                @try {
                    id itag = [format valueForKey:@"itag"];
                    id bitrate = [format valueForKey:@"bitrate"];
                    id averageBitrate = [format valueForKey:@"averageBitrate"];
                    id mimeType = [format valueForKey:@"mimeType"];

                    NSString *mime = [mimeType isKindOfClass:[NSString class]]
                        ? mimeType : @"unknown";

                    NSLog(@"[YTMU-AUDIO] FORMAT itag=%s bitrate=%s average=%s mime=%s",
                          [[itag description] UTF8String],
                          [[bitrate description] UTF8String],
                          [[averageBitrate description] UTF8String],
                          [mime UTF8String]);
                } @catch (NSException *exception) {
                    NSLog(@"[YTMU-AUDIO] FORMAT ERROR");
                }
            }
        }

        NSLog(@"[YTMU-AUDIO] ===== END DIAGNOSTICS =====");

    } @catch (NSException *exception) {
        NSLog(@"[YTMU-AUDIO] DIAGNOSTICS ERROR: %@",
              exception);
    }
}
