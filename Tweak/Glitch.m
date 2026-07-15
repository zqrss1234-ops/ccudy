#import <Foundation/Foundation.h>
#import <substrate.h>

static volatile BOOL glitchAnimationsDisabled = NO;

BOOL BHGlitchAnimationsDisabled(void) {
    return glitchAnimationsDisabled;
}

void BHSetGlitchAnimationsDisabled(BOOL disabled) {
    glitchAnimationsDisabled = disabled;
}

static void (*orig_hideAnimated_afterDelay)(id, SEL, BOOL, double);
static void hook_hideAnimated_afterDelay(id self, SEL _cmd, BOOL animated, double delay) {
    if (BHGlitchAnimationsDisabled()) { delay = 0; animated = NO; }
    orig_hideAnimated_afterDelay(self, _cmd, animated, delay);
}

static void (*orig_hideAnimated)(id, SEL, BOOL);
static void hook_hideAnimated(id self, SEL _cmd, BOOL animated) {
    if (BHGlitchAnimationsDisabled()) { animated = NO; }
    orig_hideAnimated(self, _cmd, animated);
}

static void (*orig_hideUsingAnimation)(id, SEL, BOOL);
static void hook_hideUsingAnimation(id self, SEL _cmd, BOOL animated) {
    if (BHGlitchAnimationsDisabled()) { animated = NO; }
    orig_hideUsingAnimation(self, _cmd, animated);
}

static void (*orig_animateIn_withType_completion)(id, SEL, BOOL, long long, id);
static void hook_animateIn_withType_completion(id self, SEL _cmd, BOOL animated, long long type, id completion) {
    if (BHGlitchAnimationsDisabled()) { animated = NO; type = 0; }
    orig_animateIn_withType_completion(self, _cmd, animated, type, completion);
}

static long long (*orig_animationType)(id, SEL);
static long long hook_animationType(id self, SEL _cmd) {
    if (BHGlitchAnimationsDisabled()) return 0;
    return orig_animationType(self, _cmd);
}

static void (*orig_setAnimationType)(id, SEL, long long);
static void hook_setAnimationType(id self, SEL _cmd, long long type) {
    if (BHGlitchAnimationsDisabled()) { type = 0; }
    orig_setAnimationType(self, _cmd, type);
}

__attribute__((constructor)) static void initGlitch() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            @try {
                Class cls = objc_getClass("MBProgressHUD");
                if (!cls) return;
                MSHookMessageEx(cls, @selector(hideAnimated:afterDelay:), (IMP)hook_hideAnimated_afterDelay, (IMP *)&orig_hideAnimated_afterDelay);
                MSHookMessageEx(cls, @selector(hideAnimated:), (IMP)hook_hideAnimated, (IMP *)&orig_hideAnimated);
                MSHookMessageEx(cls, @selector(hideUsingAnimation:), (IMP)hook_hideUsingAnimation, (IMP *)&orig_hideUsingAnimation);
                MSHookMessageEx(cls, @selector(animateIn:withType:completion:), (IMP)hook_animateIn_withType_completion, (IMP *)&orig_animateIn_withType_completion);
                MSHookMessageEx(cls, @selector(animationType), (IMP)hook_animationType, (IMP *)&orig_animationType);
                MSHookMessageEx(cls, @selector(setAnimationType:), (IMP)hook_setAnimationType, (IMP *)&orig_setAnimationType);
            } @catch (NSException *e) {
                NSLog(@"[glitch] init error: %@", e);
            }
        }
    });
}
