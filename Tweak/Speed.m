#import <Foundation/Foundation.h>

@interface Speed : NSObject

+ (float)defaultInterval;
+ (float)minimumInterval;
+ (float)maximumInterval;
+ (float)normalizedInterval:(float)interval;
+ (float)presetIntervalAtIndex:(NSInteger)index;
+ (float)tapsPerSecondForInterval:(float)interval;

@end

@implementation Speed

+ (float)defaultInterval {
    return 0.100f;
}

+ (float)minimumInterval {
    return 0.030f;
}

+ (float)maximumInterval {
    return 0.100f;
}

+ (float)normalizedInterval:(float)interval {
    return MIN(MAX(interval, [self minimumInterval]), [self maximumInterval]);
}

+ (float)presetIntervalAtIndex:(NSInteger)index {
    static const float presets[] = {0.100f, 0.050f, 0.030f};
    static const NSInteger presetCount = sizeof(presets) / sizeof(presets[0]);
    if (index < 0 || index >= presetCount) return [self defaultInterval];
    return presets[index];
}

+ (float)tapsPerSecondForInterval:(float)interval {
    float normalizedInterval = [self normalizedInterval:interval];
    return 1.0f / normalizedInterval;
}

@end
