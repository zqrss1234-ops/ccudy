#import <Foundation/Foundation.h>

static volatile BOOL glitchAnimationsDisabled = NO;

BOOL BHGlitchAnimationsDisabled(void) {
    return glitchAnimationsDisabled;
}

void BHSetGlitchAnimationsDisabled(BOOL disabled) {
    glitchAnimationsDisabled = disabled;
}

%hook MBProgressHUD

- (void)hideAnimated:(BOOL)animated afterDelay:(double)delay {
    if (BHGlitchAnimationsDisabled()) {
        delay = 0;
        animated = NO;
    }
    %orig(animated, delay);
}

- (void)hideAnimated:(BOOL)animated {
    if (BHGlitchAnimationsDisabled()) {
        animated = NO;
    }
    %orig(animated);
}

- (void)animateIn:(BOOL)animated withType:(long long)type completion:(id)completion {
    if (BHGlitchAnimationsDisabled()) {
        animated = NO;
        type = 0;
    }
    %orig(animated, type, completion);
}

- (long long)animationType {
    if (BHGlitchAnimationsDisabled()) {
        return 0;
    }
    return %orig;
}

- (void)setAnimationType:(long long)type {
    if (BHGlitchAnimationsDisabled()) {
        type = 0;
    }
    %orig(type);
}

- (void)hideUsingAnimation:(BOOL)animated {
    if (BHGlitchAnimationsDisabled()) {
        animated = NO;
    }
    %orig(animated);
}

%end
