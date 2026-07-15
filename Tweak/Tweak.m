#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <substrate.h>
#import <signal.h>
#import <dlfcn.h>
#import <pthread.h>
#import <sys/stat.h>
#import <sys/utsname.h>
#import <unistd.h>
#import <stdio.h>
#import <string.h>
#import <errno.h>
#import <sys/sysctl.h>
#import <stdlib.h>

BOOL BHGlitchAnimationsDisabled(void);
void BHSetGlitchAnimationsDisabled(BOOL disabled);
static BOOL ylt_isLicenseValid(void);
static void ylt_checkLicense(void);
static void ylt_lockApp(void);
static void ylt_unlockApp(void);
static void ylt_showError(NSString *msg);
static void ylt_sendActivationRequest(NSString *key);
static void ylt_showPendingScreen(void);
static void ylt_retryActivation(void);

@interface YLTakeMicAlertButton : UIView
- (void)tapActin:(id)sender;
@end

@interface Speed : NSObject
+ (float)defaultInterval;
+ (float)minimumInterval;
+ (float)maximumInterval;
+ (float)normalizedInterval:(float)interval;
+ (float)presetIntervalAtIndex:(NSInteger)index;
+ (float)tapsPerSecondForInterval:(float)interval;
@end

static inline UIWindow *ylt_keyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            return [(UIWindowScene *)scene windows].firstObject;
        }
    }
    return nil;
}

#define SHARED_STATE @"/tmp/com.abdulilah.state.plist"

#define PRIMARY_COLOR    [UIColor colorWithRed:0.00 green:0.60 blue:1.00 alpha:1.0]
#define SUCCESS_COLOR    [UIColor colorWithRed:0.00 green:0.50 blue:1.00 alpha:1.0]
#define ERROR_COLOR      [UIColor colorWithRed:0.80 green:0.20 blue:0.30 alpha:1.0]
#define BG_DARK          [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:0.95]
#define BG_CARD          [UIColor colorWithRed:0.10 green:0.10 blue:0.15 alpha:0.90]
#define TEXT_PRIMARY     [UIColor whiteColor]
#define TEXT_SECONDARY   [UIColor colorWithRed:0.60 green:0.60 blue:0.70 alpha:1.0]

#define RGBA(r,g,b,a)    [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:a]

#define NUM_MICS 10

static const CGFloat oldMicPositions[NUM_MICS][2] = {
    {0.9, 0.22}, // مايك 1
    {0.7, 0.22}, // مايك 2
    {0.5, 0.22}, // مايك 3
    {0.3, 0.22}, // مايك 4
    {0.1, 0.22}, // مايك 5
    {0.9, 0.32}, // مايك 6
    {0.7, 0.32}, // مايك 7
    {0.5, 0.32}, // مايك 8
    {0.3, 0.32}, // مايك 9
    {0.1, 0.32}  // مايك 10
};

static const CGFloat newMicPositions[NUM_MICS][2] = {
    {0.9, 0.22},
    {0.7, 0.22},
    {0.5, 0.22},
    {0.3, 0.22},
    {0.1, 0.22},
    {0.9, 0.35},
    {0.7, 0.35},
    {0.5, 0.35},
    {0.3, 0.35},
    {0.1, 0.35}
};

static BOOL ylt_usesNewMicPositions(void) {
    static BOOL usesNewPositions;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        struct utsname systemInfo;
        if (uname(&systemInfo) != 0) return;

        NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];
        if (![machine hasPrefix:@"iPhone"]) return;

        NSString *modelNumber = [machine substringFromIndex:@"iPhone".length];
        NSInteger majorVersion = [[modelNumber componentsSeparatedByString:@","][0] integerValue];
        usesNewPositions = majorVersion >= 13;
    });
    return usesNewPositions;
}

#pragma mark - UDP IPC

static int udpSock = -1;
static int myPort = 0;
#define UDP_MIN 51551
#define UDP_MAX 51560

static void udpInit(void);
static void udpSend(NSString *msg);
static void sendAll(NSString *msg);

#pragma mark - Anti-Termination Hooks

static void (*orig_exit)(int);
static void ylt_hook_exit(int code) {}

static void (*orig_abort)(void);
static void ylt_hook_abort(void) {}

static void (*orig__exit)(int);
static void ylt_hook__exit(int code) {}

static int (*orig_pthread_cancel)(pthread_t);
static int ylt_hook_pthread_cancel(pthread_t t) { return -1; }

static int (*orig_kill)(pid_t, int);
static int ylt_hook_kill(pid_t pid, int sig) {
    if (sig == SIGKILL && pid == getpid()) return 0;
    return orig_kill(pid, sig);
}

static int (*orig_raise)(int);
static int ylt_hook_raise(int sig) {
    if (sig == SIGKILL) return 0;
    return orig_raise(sig);
}

static void (*orig_objc_exception_throw)(id);
static void ylt_hook_objc_exception_throw(id exc) {}

static void (*orig_cxa_throw)(void *, void *, void (*)(void *));
static void ylt_hook_cxa_throw(void *thrown, void *type, void (*dest)(void *)) {}

static void (*orig_cxa_rethrow)(void);
static void ylt_hook_cxa_rethrow(void) {}

static int (*orig_access)(const char *, int);
static int ylt_hook_access(const char *path, int mode) {
    if (path && strstr(path, "YLTool")) return -1;
    return orig_access(path, mode);
}

static void *(*orig_dlopen)(const char *, int);
static void *ylt_hook_dlopen(const char *path, int mode) {
    if (path && strstr(path, "YLTool")) return NULL;
    if (path && strstr(path, "Substrate")) return NULL;
    if (path && strstr(path, "substrate")) return NULL;
    return orig_dlopen(path, mode);
}

static void *(*orig_dlsym)(void *, const char *);
static void *ylt_hook_dlsym(void *handle, const char *symbol) {
    if (symbol && (strstr(symbol, "MSHook") || strstr(symbol, "Substrate") || strstr(symbol, "substrate") || strstr(symbol, "YLTool")))
        return NULL;
    return orig_dlsym(handle, symbol);
}

static int (*orig_dladdr)(const void *, Dl_info *);
static int ylt_hook_dladdr(const void *addr, Dl_info *info) {
    int ret = orig_dladdr(addr, info);
    if (ret && info && info->dli_fname && strstr(info->dli_fname, "YLTool"))
        return 0;
    return ret;
}

static FILE *(*orig_fopen)(const char *, const char *);
static FILE *ylt_hook_fopen(const char *path, const char *mode) {
    if (path && strstr(path, "YLTool")) { errno = ENOENT; return NULL; }
    return orig_fopen(path, mode);
}

#pragma mark - Background Task

static UIBackgroundTaskIdentifier bgTask = 0;

static void startBgTask(void) {
    if (bgTask != UIBackgroundTaskInvalid) return;
    __block UIBackgroundTaskIdentifier task = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"AbdulilahBg" expirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:task];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (bgTask == task) bgTask = UIBackgroundTaskInvalid;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                startBgTask();
            });
        });
    }];
    if (task != UIBackgroundTaskInvalid) {
        bgTask = task;
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            startBgTask();
        });
    }
}

static void startBgTaskRenewal(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), 10 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(t, ^{
            if (bgTask != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:bgTask];
                bgTask = UIBackgroundTaskInvalid;
            }
            startBgTask();
        });
        dispatch_resume(t);
    });
}

static BOOL ylt_hook_isBacEnabled(id self, SEL _cmd) { return NO; }
static NSInteger ylt_hook_appState(id self, SEL _cmd) { return 0; }
static void ylt_hook_terminate(id self, SEL _cmd) {}

static void startSilentAudio(void);

static void ylt_installBgHook(void) {
    Class app = objc_getClass("UIApplication");
    Method m;
    m = class_getInstanceMethod(app, sel_registerName("_isBackgroundTaskExpirationEnabled"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("applicationState"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_appState);
    m = class_getInstanceMethod(app, sel_registerName("terminateWithSuccess"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("terminate"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("_isBackgrounded"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("isBackground"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_isBacEnabled);
    m = class_getInstanceMethod(app, sel_registerName("_suspend"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("suspend"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("_handleApplicationEnterBackground"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
    m = class_getInstanceMethod(app, sel_registerName("_handleApplicationEnterBackground:"));
    if (m) method_setImplementation(m, (IMP)ylt_hook_terminate);
}

#pragma mark - Forward Declarations

@class AbdulilahManager;

#pragma mark - UDP Implementation

static void udpSend(NSString *m) {
    if (udpSock < 0 || !m || m.length == 0) return;
    const char *c = m.UTF8String; size_t l = strlen(c);
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    inet_aton("127.0.0.1", &sa.sin_addr);
    for (int p = UDP_MIN; p <= UDP_MAX; p++) {
        if (p == myPort) continue;
        sa.sin_port = htons(p);
        sendto(udpSock, c, l, 0, (struct sockaddr *)&sa, sizeof(sa));
    }
}

static void sendAll(NSString *msg) {
    udpSend(msg);
}

#pragma mark - Silent Audio

static AVAudioPlayer *silentPlayer = nil;

static void startSilentAudio(void) {
    @try {
        if (silentPlayer && silentPlayer.isPlaying) return;
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
        [session setActive:YES error:nil];
        int rate = 8000, dur = 60, ch = 1, bits = 16;
        int dataSz = rate * dur * ch * (bits / 8);
        int fileSz = 44 + dataSz;
        NSMutableData *d = [NSMutableData dataWithLength:fileSz];
        char *b = (char *)[d mutableBytes];
        memcpy(b, "RIFF", 4);
        uint32_t v = fileSz - 8; memcpy(b + 4, &v, 4);
        memcpy(b + 8, "WAVE", 4);
        memcpy(b + 12, "fmt ", 4); v = 16; memcpy(b + 16, &v, 4);
        uint16_t w = 1; memcpy(b + 20, &w, 2);
        w = ch; memcpy(b + 22, &w, 2);
        v = rate; memcpy(b + 24, &v, 4);
        w = ch * (bits / 8); v = rate * w; memcpy(b + 28, &v, 4); memcpy(b + 32, &w, 2);
        w = bits; memcpy(b + 34, &w, 2);
        memcpy(b + 36, "data", 4); v = dataSz; memcpy(b + 40, &v, 4);
        silentPlayer = [[AVAudioPlayer alloc] initWithData:d error:nil];
        if (!silentPlayer) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ startSilentAudio(); });
            return;
        }
        silentPlayer.numberOfLoops = -1;
        silentPlayer.volume = 0.01;
        [silentPlayer prepareToPlay];
        [silentPlayer play];
    } @catch (NSException *e) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ startSilentAudio(); });
    }
}

#pragma mark - Overlay Window

@interface AbdulilahOverlayWindow : UIWindow
@end
@implementation AbdulilahOverlayWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) return nil;
    return hit;
}
@end

#pragma mark - AbdulilahManager

@interface AbdulilahManager : NSObject

@property (nonatomic, strong) UIView *mainPanel;
@property (nonatomic, strong) UIButton *floatButton;
@property (nonatomic, strong) UIButton *toggleBtn;
@property (nonatomic, strong) UISlider *speedSlider;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UISwitch *glitchSwitch;
@property (nonatomic, assign) BOOL autoTapEnabled;
@property (nonatomic, assign) float currentSpeed;
@property (nonatomic, assign) BOOL glitchAnimationsDisabled;
@property (nonatomic, assign) BOOL isMenuVisible;
@property (nonatomic, assign) float transparencyValue;
@property (nonatomic, strong) NSTimer *uiGuardTimer;

@property (nonatomic, assign) NSInteger selectedMicIndex;
@property (nonatomic, assign) BOOL isCaptureMode;
@property (nonatomic, strong) UIView *captureDot;
@property (nonatomic, strong) NSMutableDictionary *capturedPositions;

@property (nonatomic, strong) AbdulilahOverlayWindow *overlayWindow;

@property (nonatomic, weak) UIView *cachedTapTarget;
@property (nonatomic, weak) UIWindow *cachedGameWindow;
@property (nonatomic, assign) NSUInteger tapGeneration;
@property (nonatomic, strong) NSObject *tapTimerLock;
@property (nonatomic, strong) dispatch_source_t tapTimer;

@property (nonatomic, strong) CADisplayLink *fastTapLink;
@property (nonatomic, assign) CFTimeInterval fastTapAccumulator;

+ (instancetype)shared;
- (void)showFloatingButton;
- (void)toggleMenu;
- (void)saveInstanceState;
- (void)loadInstanceState;
- (void)selectMicAtIndex:(NSInteger)index;
- (void)confirmAndTapMic:(NSInteger)index;
- (void)startTap;
- (void)stopTap;
- (void)showToast:(NSString *)message;
- (void)performMetaTouchDownAtPoint:(CGPoint)pt;
- (void)performMetaTouchUpAtPoint:(CGPoint)pt;

@end

@interface UITouch (FakePrivate)
- (void)setView:(UIView *)v;
- (void)setWindow:(UIWindow *)w;
- (void)setTapCount:(NSUInteger)c;
- (void)setTimestamp:(NSTimeInterval)t;
- (void)setPhase:(UITouchPhase)p;
@end

@implementation AbdulilahManager

+ (instancetype)shared {
    static AbdulilahManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AbdulilahManager alloc] init];
        instance.currentSpeed = [Speed defaultInterval];
        instance.transparencyValue = 1.0;
        instance.selectedMicIndex = 0;
        instance.isCaptureMode = NO;
        instance.capturedPositions = [NSMutableDictionary dictionary];
        [instance startUIGuard];
        [instance loadInstanceState];
    });
    return instance;
}

- (AbdulilahOverlayWindow *)overlayWindow {
    if (!_overlayWindow) {
        _overlayWindow = [[AbdulilahOverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        _overlayWindow.windowLevel = 2100.0;
        _overlayWindow.backgroundColor = [UIColor clearColor];
        _overlayWindow.userInteractionEnabled = YES;
        _overlayWindow.rootViewController = [[UIViewController alloc] init];
        _overlayWindow.rootViewController.view.userInteractionEnabled = NO;
        _overlayWindow.hidden = NO;
    }
    return _overlayWindow;
}

- (void)setGlitchAnimationsDisabled:(BOOL)glitchAnimationsDisabled {
    _glitchAnimationsDisabled = glitchAnimationsDisabled;
    BHSetGlitchAnimationsDisabled(glitchAnimationsDisabled);
    self.glitchSwitch.on = glitchAnimationsDisabled;
}

- (void)startUIGuard {
    self.uiGuardTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(checkUI) userInfo:nil repeats:YES];
}

- (void)checkUI {
    [self overlayWindow];
    self.overlayWindow.windowLevel = 2100.0;
    if (!self.floatButton || self.floatButton.superview != self.overlayWindow) {
        [self showFloatingButton];
    } else {
        [self.overlayWindow bringSubviewToFront:self.floatButton];
    }
    if (self.isMenuVisible && self.mainPanel) {
        if (self.mainPanel.superview != self.overlayWindow) {
            [self.overlayWindow addSubview:self.mainPanel];
        }
        [self.overlayWindow bringSubviewToFront:self.mainPanel];
    }
    if (self.isCaptureMode && (!self.captureDot || self.captureDot.superview != self.overlayWindow)) {
        [self showCaptureDot];
    }
    if (!silentPlayer || !silentPlayer.isPlaying) {
        startSilentAudio();
    }
    if (bgTask == UIBackgroundTaskInvalid) {
        startBgTask();
    }
    static int hb = 0; hb++;
    if (hb % 5 == 0) {
        sendAll([NSString stringWithFormat:@"SYNC:%ld,%d,%.3f,%d",
                (long)self.selectedMicIndex, self.autoTapEnabled, self.currentSpeed,
                self.glitchAnimationsDisabled]);
    }
}

- (CGPoint)selectedMicPosition {
    return [self positionForMic:self.selectedMicIndex];
}

#pragma mark - Floating Button

- (void)showFloatingButton {
    if (!ylt_isLicenseValid()) {
        ylt_checkLicense();
        return;
    }

    if (self.floatButton) {
        [self.floatButton.superview removeFromSuperview];
        self.floatButton = nil;
    }
    UIWindow *w = self.overlayWindow;
    CGFloat fbSize = 40;
    self.floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatButton.frame = CGRectMake(20, 150, fbSize, fbSize);
    self.floatButton.backgroundColor = [UIColor blackColor];
    self.floatButton.layer.cornerRadius = fbSize / 2;
    self.floatButton.clipsToBounds = YES;
    self.floatButton.layer.borderWidth = 2;
    self.floatButton.layer.borderColor = PRIMARY_COLOR.CGColor;
    [self.floatButton setTitle:@"ع" forState:UIControlStateNormal];
    self.floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatButton.layer.shadowOffset = CGSizeMake(0, 4);
    self.floatButton.layer.shadowRadius = 10;
    self.floatButton.layer.shadowOpacity = 0.5;
    [self.floatButton addTarget:self action:@selector(handleFloatTap) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatButton addGestureRecognizer:pan];
    [w addSubview:self.floatButton];
    self.floatButton.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{ self.floatButton.alpha = 1; }];
}

- (void)handleFloatTap {
    [self toggleMenu];
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
}

- (void)toggleMenu {
    if (!self.mainPanel) [self buildMainPanel];
    self.isMenuVisible = !self.isMenuVisible;
    if (self.isMenuVisible) {
        self.mainPanel.hidden = NO;
        self.mainPanel.alpha = 0;
        [UIView animateWithDuration:0.2 animations:^{
            self.mainPanel.alpha = self.transparencyValue;
            self.floatButton.alpha = 0.3;
        }];
    } else {
        [UIView animateWithDuration:0.15 animations:^{
            self.mainPanel.alpha = 0;
            self.floatButton.alpha = 1;
        } completion:^(BOOL finished) {
            self.mainPanel.hidden = YES;
        }];
    }
}

#pragma mark - Tap Dot & Mic Selection

- (CGPoint)positionForMic:(NSInteger)index {
    NSValue *val = self.capturedPositions[@(index)];
    if (val) return [val CGPointValue];
    CGSize sz = [UIScreen mainScreen].bounds.size;
    const CGFloat (*micPositions)[2] = ylt_usesNewMicPositions() ? newMicPositions : oldMicPositions;
    CGFloat x = sz.width * micPositions[index][0];
    CGFloat y = sz.height * micPositions[index][1];
    return CGPointMake(x, y);
}

#pragma mark - Capture Mode

- (void)showCaptureDot {
    UIWindow *w = self.overlayWindow;
    if (self.captureDot) {
        [self.captureDot removeFromSuperview];
        self.captureDot = nil;
    }
    CGPoint pos = [self positionForMic:self.selectedMicIndex];
    CGFloat cs = 36;
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(pos.x - cs/2, pos.y - cs/2, cs, cs)];
    dot.backgroundColor = [UIColor clearColor];
    dot.layer.cornerRadius = cs / 2;
    dot.layer.borderWidth = 2.5;
    dot.layer.borderColor = [UIColor yellowColor].CGColor;
    dot.userInteractionEnabled = YES;

    UILabel *cross = [[UILabel alloc] initWithFrame:dot.bounds];
    cross.text = @"+";
    cross.textColor = [UIColor yellowColor];
    cross.font = [UIFont boldSystemFontOfSize:20];
    cross.textAlignment = NSTextAlignmentCenter;
    [dot addSubview:cross];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleCaptureDotPan:)];
    [dot addGestureRecognizer:pan];

    [w addSubview:dot];
    self.captureDot = dot;
    [self showToast:@"اسحب النقطة على المايك واضغط رقمه"];
}

- (void)hideCaptureDot {
    if (self.captureDot) {
        [self.captureDot removeFromSuperview];
        self.captureDot = nil;
    }
}

- (void)handleCaptureDotPan:(UIPanGestureRecognizer *)p {
    UIView *v = p.view;
    CGPoint t = [p translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [p setTranslation:CGPointZero inView:v.superview];
    if (p.state == UIGestureRecognizerStateEnded) {
        self.cachedTapTarget = nil;
        self.cachedGameWindow = nil;
    }
}

- (void)toggleCaptureMode {
    self.isCaptureMode = !self.isCaptureMode;
    if (self.isCaptureMode) {
        [self showCaptureDot];
    } else {
        [self hideCaptureDot];
        [self saveInstanceState];
    }
    [self updatePanelMicDisplay];
}

- (void)glitchSwitchChanged:(UISwitch *)sender {
    self.glitchAnimationsDisabled = sender.isOn;
    [self saveInstanceState];
    sendAll([NSString stringWithFormat:@"GLITCH:%d", self.glitchAnimationsDisabled]);
}

#pragma mark - Selection & Activation

- (void)selectMicAtIndex:(NSInteger)index {
    if (index < 0 || index >= NUM_MICS) return;
    if (self.selectedMicIndex == index) return;
    self.selectedMicIndex = index;
    sendAll([NSString stringWithFormat:@"MIC:%ld", (long)index]);
    self.cachedTapTarget = nil;
    self.cachedGameWindow = nil;
    [self updatePanelMicDisplay];
    [self saveInstanceState];
}

- (void)confirmAndTapMic:(NSInteger)index {
    if (index < 0 || index >= NUM_MICS) return;

    [self selectMicAtIndex:index];
    [self triggerTapPulse];
    [self showToast:[NSString stringWithFormat:@"تم اختيار المايك %ld", (long)(index + 1)]];
}

- (void)updatePanelMicDisplay {
    if (!self.mainPanel) return;
    for (int i = 0; i < NUM_MICS; i++) {
        UIButton *nb = (UIButton *)[self.mainPanel viewWithTag:(i + 100)];
        if (nb) {
            if (i == self.selectedMicIndex) {
                nb.backgroundColor = PRIMARY_COLOR;
                [nb setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            } else {
                nb.backgroundColor = BG_CARD;
                [nb setTitleColor:PRIMARY_COLOR forState:UIControlStateNormal];
            }
        }
    }
    UIButton *captBtn = (UIButton *)[self.mainPanel viewWithTag:200];
    if (captBtn) {
        captBtn.backgroundColor = self.isCaptureMode ? [UIColor orangeColor] : BG_CARD;
        [captBtn setTitleColor:self.isCaptureMode ? [UIColor whiteColor] : [UIColor orangeColor] forState:UIControlStateNormal];
    }
}

- (void)updateSpeedLabelDisplay {
    if (self.speedLabel) {
        self.speedLabel.text = [NSString stringWithFormat:@"سرعة الضغط: %.3f ثانية", self.currentSpeed];
    }
}

- (void)showToast:(NSString *)msg {
    UIWindow *w = ylt_keyWindow();
    if (!w) return;
    UILabel *toast = [[UILabel alloc] init];
    toast.text = msg;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    toast.font = [UIFont boldSystemFontOfSize:13];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 15;
    toast.clipsToBounds = YES;
    
    CGSize sz = [msg sizeWithAttributes:@{NSFontAttributeName: toast.font}];
    toast.frame = CGRectMake((w.bounds.size.width - sz.width - 30)/2, w.bounds.size.height * 0.8, sz.width + 30, 30);
    [w addSubview:toast];
    
    [UIView animateWithDuration:0.3 delay:1.2 options:UIViewAnimationOptionCurveEaseIn animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

#pragma mark - Persistence

- (void)saveInstanceState {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"micIdx"] = @(self.selectedMicIndex);
    dict[@"tapOn"] = @(self.autoTapEnabled);
    dict[@"speed"] = @(self.currentSpeed);
    dict[@"glitchDisabled"] = @(self.glitchAnimationsDisabled);
    if (self.capturedPositions.count > 0) {
        NSMutableDictionary *posDict = [NSMutableDictionary dictionary];
        for (NSNumber *key in self.capturedPositions) {
            CGPoint pt = [self.capturedPositions[key] CGPointValue];
            posDict[[key stringValue]] = @[@(pt.x), @(pt.y)];
        }
        dict[@"calibrated"] = posDict;
    }
    [dict writeToFile:SHARED_STATE atomically:YES];
}

- (void)loadInstanceState {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:SHARED_STATE];
    if (!dict) return;
    self.glitchAnimationsDisabled = [dict[@"glitchDisabled"] boolValue];
    NSNumber *mi = dict[@"micIdx"];
    if (mi) {
        NSInteger idx = [mi integerValue];
        if (idx >= 0 && idx < NUM_MICS) {
            self.selectedMicIndex = idx;
        }
    }
    NSDictionary *cal = dict[@"calibrated"];
    if (cal) {
        [self.capturedPositions removeAllObjects];
        for (NSString *key in cal) {
            NSArray *arr = cal[key];
            if (arr.count == 2) {
                CGPoint pt = CGPointMake([arr[0] floatValue], [arr[1] floatValue]);
                self.capturedPositions[@([key integerValue])] = [NSValue valueWithCGPoint:pt];
            }
        }
    }
    float spd = [Speed normalizedInterval:[dict[@"speed"] floatValue]];
    if (spd > 0) {
        self.currentSpeed = spd;
    }
    BOOL shouldTap = [dict[@"tapOn"] boolValue];
    if (shouldTap && !self.autoTapEnabled) {
        [self startTap];
    } else if (!shouldTap && self.autoTapEnabled) {
        [self stopTap];
    }
}

#pragma mark - Main Panel

- (void)buildMainPanel {
    if (self.mainPanel) return;
    UIWindow *w = self.overlayWindow;
    CGFloat pw = 220;
    CGFloat px = (w.bounds.size.width - pw) / 2;
    CGFloat py = 60;
    self.mainPanel = [[UIView alloc] initWithFrame:CGRectMake(px, py, pw, 190)];
    self.mainPanel.backgroundColor = BG_DARK;
    self.mainPanel.layer.cornerRadius = 20;
    self.mainPanel.clipsToBounds = YES;
    self.mainPanel.alpha = 0;
    self.mainPanel.hidden = YES;
    self.mainPanel.layer.borderWidth = 1;
    self.mainPanel.layer.borderColor = [PRIMARY_COLOR colorWithAlphaComponent:0.3].CGColor;
    [w addSubview:self.mainPanel];

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, pw, 36)];
    header.backgroundColor = PRIMARY_COLOR;
    [self.mainPanel addSubview:header];

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(12, 7, 160, 18)];
    titleLbl.text = @"عبدالإله";
    titleLbl.textColor = TEXT_PRIMARY;
    titleLbl.font = [UIFont boldSystemFontOfSize:15];
    [header addSubview:titleLbl];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(pw - 32, 6, 24, 24);
    closeBtn.layer.cornerRadius = 12;
    closeBtn.backgroundColor = [ERROR_COLOR colorWithAlphaComponent:0.2];
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:ERROR_COLOR forState:UIControlStateNormal];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:closeBtn];

    CGFloat y = 42;
    CGFloat mx = 12;
    CGFloat cw = pw - 24;

    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.toggleBtn.frame = CGRectMake(mx, y, cw, 38);
    self.toggleBtn.backgroundColor = SUCCESS_COLOR;
    self.toggleBtn.layer.cornerRadius = 19;
    [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.toggleBtn addTarget:self action:@selector(toggleStartStop) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:self.toggleBtn];
    y += 44;

    self.speedLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y, cw, 16)];
    self.speedLabel.textColor = TEXT_PRIMARY;
    self.speedLabel.font = [UIFont systemFontOfSize:10];
    [self.mainPanel addSubview:self.speedLabel];
    [self updateSpeedLabelDisplay];
    y += 18;

    self.speedSlider = [[UISlider alloc] initWithFrame:CGRectMake(mx, y, cw, 20)];
    self.speedSlider.minimumValue = [Speed minimumInterval];
    self.speedSlider.maximumValue = [Speed maximumInterval];
    self.speedSlider.value = self.currentSpeed;
    self.speedSlider.tintColor = PRIMARY_COLOR;
    self.speedSlider.minimumTrackTintColor = PRIMARY_COLOR;
    self.speedSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1];
    [self.speedSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mainPanel addSubview:self.speedSlider];
    y += 24;

    CGFloat btnW = (cw - 10) / 3;
    NSString *presetLabels[3] = {@"عادي x1", @"وسط", @"عالي"};
    for (int i = 0; i < 3; i++) {
        UIButton *pb = [UIButton buttonWithType:UIButtonTypeCustom];
        pb.frame = CGRectMake(mx + (btnW + 5) * i, y, btnW, 20);
        pb.backgroundColor = BG_CARD;
        pb.layer.cornerRadius = 6;
        pb.titleLabel.font = [UIFont systemFontOfSize:9];
        [pb setTitle:presetLabels[i] forState:UIControlStateNormal];
        [pb setTitleColor:PRIMARY_COLOR forState:UIControlStateNormal];
        pb.tag = i;
        [pb addTarget:self action:@selector(speedPresetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.mainPanel addSubview:pb];
    }
    y += 26;

    UILabel *micLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y, cw, 14)];
    micLabel.text = @"اختيار المايك:";
    micLabel.textColor = TEXT_PRIMARY;
    micLabel.font = [UIFont systemFontOfSize:10];
    [self.mainPanel addSubview:micLabel];
    y += 18;

    CGFloat gBtnW = (cw - 16) / 5;
    for (int i = 0; i < NUM_MICS; i++) {
        int col = i % 5;
        int row = i / 5;
        UIButton *nb = [UIButton buttonWithType:UIButtonTypeCustom];
        nb.frame = CGRectMake(mx + (gBtnW + 4) * col, y + (24 + 4) * row, gBtnW, 24);
        nb.backgroundColor = (i == self.selectedMicIndex) ? PRIMARY_COLOR : BG_CARD;
        nb.layer.cornerRadius = 6;
        nb.titleLabel.font = [UIFont boldSystemFontOfSize:11];
        [nb setTitle:[NSString stringWithFormat:@"%d", i + 1] forState:UIControlStateNormal];
        [nb setTitleColor:(i == self.selectedMicIndex) ? [UIColor whiteColor] : PRIMARY_COLOR forState:UIControlStateNormal];
        nb.tag = i + 100;
        [nb addTarget:self action:@selector(micNumberTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.mainPanel addSubview:nb];
    }
    y += 56;

    UIButton *captBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    captBtn.frame = CGRectMake(mx, y, cw, 28);
    captBtn.backgroundColor = self.isCaptureMode ? [UIColor orangeColor] : BG_CARD;
    captBtn.layer.cornerRadius = 14;
    [captBtn setTitle:@"📍 تصوير موقع المايكات" forState:UIControlStateNormal];
    [captBtn setTitleColor:self.isCaptureMode ? [UIColor whiteColor] : [UIColor orangeColor] forState:UIControlStateNormal];
    captBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    captBtn.tag = 200;
    [captBtn addTarget:self action:@selector(toggleCaptureMode) forControlEvents:UIControlEventTouchUpInside];
    [self.mainPanel addSubview:captBtn];
    y += 34;

    UILabel *glitchLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y, cw - 54, 28)];
    glitchLabel.text = @"Glitch: إيقاف الحركات";
    glitchLabel.textColor = TEXT_PRIMARY;
    glitchLabel.font = [UIFont systemFontOfSize:11];
    [self.mainPanel addSubview:glitchLabel];

    self.glitchSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(mx + cw - 50, y, 50, 28)];
    self.glitchSwitch.onTintColor = PRIMARY_COLOR;
    self.glitchSwitch.on = self.glitchAnimationsDisabled;
    [self.glitchSwitch addTarget:self action:@selector(glitchSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mainPanel addSubview:self.glitchSwitch];
    y += 32;

    UILabel *mergeLabel = [[UILabel alloc] initWithFrame:CGRectMake(mx, y, cw, 14)];
    mergeLabel.text = @"تم ربط الحسابات تلقائياً";
    mergeLabel.textColor = [UIColor greenColor];
    mergeLabel.font = [UIFont systemFontOfSize:9];
    mergeLabel.textAlignment = NSTextAlignmentCenter;
    [self.mainPanel addSubview:mergeLabel];
    y += 18;

    UIView *creditBox = [[UIView alloc] initWithFrame:CGRectMake(mx, y, cw, 24)];
    creditBox.backgroundColor = BG_CARD;
    creditBox.layer.cornerRadius = 12;
    [self.mainPanel addSubview:creditBox];
    UILabel *creditLbl = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, cw - 16, 24)];
    creditLbl.text = @"حقوق عبدالإله فقط.";
    creditLbl.textColor = [PRIMARY_COLOR colorWithAlphaComponent:0.7];
    creditLbl.font = [UIFont boldSystemFontOfSize:8];
    creditLbl.textAlignment = NSTextAlignmentCenter;
    [creditBox addSubview:creditLbl];
    y += 30;

    CGRect f = self.mainPanel.frame;
    f.size.height = y + 8;
    self.mainPanel.frame = f;

    UIPanGestureRecognizer *panP = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.mainPanel addGestureRecognizer:panP];
}

#pragma mark - UI Actions

- (void)micNumberTapped:(UIButton *)sender {
    NSInteger index = sender.tag - 100;
    if (self.isCaptureMode) {
        CGPoint currentDotPos = self.captureDot.center;
        self.capturedPositions[@(index)] = [NSValue valueWithCGPoint:currentDotPos];
        [self saveInstanceState];
        [self showToast:[NSString stringWithFormat:@"تم حفظ موقع مايك %ld بنجاح", (long)(index + 1)]];
    } else {
        [self confirmAndTapMic:index];
    }
}

#pragma mark - Tap Engine

- (void)sliderChanged:(UISlider *)sender {
    self.currentSpeed = [Speed normalizedInterval:sender.value];
    sender.value = self.currentSpeed;
    [self updateSpeedLabelDisplay];
    if (self.autoTapEnabled) [self restartTapWithSpeed:self.currentSpeed];
    sendAll([NSString stringWithFormat:@"SPEED:%.3f", self.currentSpeed]);
    [self saveInstanceState];
}

- (void)speedPresetTapped:(UIButton *)sender {
    int idx = (int)sender.tag;
    if (idx < 0 || idx > 2) return;
    self.currentSpeed = [Speed presetIntervalAtIndex:idx];
    self.speedSlider.value = self.currentSpeed;
    [self updateSpeedLabelDisplay];
    if (self.autoTapEnabled) [self restartTapWithSpeed:self.currentSpeed];
    sendAll([NSString stringWithFormat:@"SPEED:%.3f", self.currentSpeed]);
    [self saveInstanceState];
}

- (void)restartTapWithSpeed:(float)speed {
    self.tapGeneration++;
    [self startTapWithSpeed:speed];
}

- (void)toggleStartStop {
    @try {
        if (self.autoTapEnabled) {
            sendAll(@"STOP");
            [self stopTap];
        } else {
            sendAll(@"RUN");
            [self startTapInternal];
            [self saveInstanceState];
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] toggleStartStop exception: %@", e);
    }
}

- (void)startTap {
    @try {
        if (self.autoTapEnabled) return;
        [self startTapInternal];
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] startTap exception: %@", e);
    }
}

- (void)startTapInternal {
    @try {
        if (self.autoTapEnabled) return;
        self.autoTapEnabled = YES;
        self.cachedTapTarget = nil;
        self.cachedGameWindow = nil;
        [self startTapWithSpeed:self.currentSpeed];
        if (self.toggleBtn) {
            [self.toggleBtn setTitle:@"إيقاف" forState:UIControlStateNormal];
            self.toggleBtn.backgroundColor = ERROR_COLOR;
        }
    } @catch (NSException *e) {
        NSLog(@"[عبدالإله] startTapInternal exception: %@", e);
    }
}

- (void)stopTap {
    self.autoTapEnabled = NO;
    [self stopTapTimer];
    if (self.toggleBtn) {
        [self.toggleBtn setTitle:@"تشغيل" forState:UIControlStateNormal];
        self.toggleBtn.backgroundColor = SUCCESS_COLOR;
    }
    [self saveInstanceState];
}

- (void)startTapWithSpeed:(float)speed {
    speed = [Speed normalizedInterval:speed];
    self.currentSpeed = speed;
    [self stopTapTimer];
    [self stopFastTapLink];
    self.tapGeneration++;
    [self startFastTapLinkWithSpeed:speed];
}

- (void)stopTapTimer {
    if (self.tapTimer) {
        dispatch_source_cancel(self.tapTimer);
        self.tapTimer = NULL;
    }
    [self stopFastTapLink];
}

#pragma mark - CADisplayLink Fast Engine

- (void)startFastTapLinkWithSpeed:(float)speed {
    [self stopFastTapLink];
    self.fastTapAccumulator = 0;
    self.fastTapLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(fastTapLinkCallback:)];
    [self.fastTapLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopFastTapLink {
    if (self.fastTapLink) {
        [self.fastTapLink invalidate];
        self.fastTapLink = nil;
    }
}

- (void)fastTapLinkCallback:(CADisplayLink *)link {
    if (!self.autoTapEnabled) {
        [self stopFastTapLink];
        return;
    }
    CFTimeInterval elapsed = link.duration;
    self.fastTapAccumulator += elapsed;
    if (self.fastTapAccumulator >= self.currentSpeed) {
        self.fastTapAccumulator = 0;
        [self triggerTapPulse];
    }
}

- (void)triggerTapPulse {
    @try {
        CGPoint pt = [self selectedMicPosition];
        if (pt.x <= 0 || pt.y <= 0) return;
        
        [self performMetaTouchDownAtPoint:pt];
        [self performMetaTouchUpAtPoint:pt];
        
        UIWindow *w = ylt_keyWindow();
        if (w) {
            UIView *hv = [w hitTest:pt withEvent:nil];
            if (hv && hv != w) {
                [self performRealTapOnView:hv atPoint:pt];
            }
        }
    } @catch (NSException *e) {
    }
}

- (void)performRealTapOnView:(UIView *)targetView atPoint:(CGPoint)pt {
    if (!targetView) return;
    if ([targetView isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)targetView;
        [btn sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else if ([targetView isKindOfClass:[YLTakeMicAlertButton class]]) {
        YLTakeMicAlertButton *ylb = (YLTakeMicAlertButton *)targetView;
        [ylb tapActin:nil];
    } else {
        for (UIGestureRecognizer *g in targetView.gestureRecognizers) {
            if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                UITapGestureRecognizer *tg = (UITapGestureRecognizer *)g;
                if (tg.enabled) {
                    SEL sel = NSSelectorFromString(@"_handleTap:");
                    if ([tg respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [tg performSelector:sel withObject:tg];
#pragma clang diagnostic pop
                    }
                }
            }
        }
    }
}

- (void)performMetaTouchDownAtPoint:(CGPoint)pt {
}

- (void)performMetaTouchUpAtPoint:(CGPoint)pt {
}

@end

#pragma mark - UDP Socket Listener Loop

static void udpInit(void) {
    udpSock = socket(AF_INET, SOCK_DGRAM, 0);
    if (udpSock < 0) return;
    
    int opt = 1;
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    setsockopt(udpSock, SOL_SOCKET, SO_REUSEPORT, &opt, sizeof(opt));
    
    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = INADDR_ANY;
    
    for (int p = UDP_MIN; p <= UDP_MAX; p++) {
        sa.sin_port = htons(p);
        if (bind(udpSock, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
            myPort = p;
            break;
        }
    }
    
    if (myPort == 0) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        char buf[512];
        struct sockaddr_in from;
        socklen_t fromLen = sizeof(from);
        while (1) {
            ssize_t len = recvfrom(udpSock, buf, sizeof(buf)-1, 0, (struct sockaddr *)&from, &fromLen);
            if (len > 0) {
                buf[len] = '\0';
                NSString *msg = [NSString stringWithUTF8String:buf];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([msg hasPrefix:@"MIC:"]) {
                        NSInteger idx = [[msg substringFromIndex:4] integerValue];
                        [[AbdulilahManager shared] selectMicAtIndex:idx];
                    } else if ([msg isEqualToString:@"RUN"]) {
                        [[AbdulilahManager shared] startTap];
                    } else if ([msg isEqualToString:@"STOP"]) {
                        [[AbdulilahManager shared] stopTap];
                    } else if ([msg hasPrefix:@"SPEED:"]) {
                        float spd = [Speed normalizedInterval:[[msg substringFromIndex:6] floatValue]];
                        [AbdulilahManager shared].currentSpeed = spd;
                        [AbdulilahManager shared].speedSlider.value = spd;
                        [[AbdulilahManager shared] updateSpeedLabelDisplay];
                        if ([AbdulilahManager shared].autoTapEnabled) {
                            [[AbdulilahManager shared] restartTapWithSpeed:spd];
                        }
                    } else if ([msg hasPrefix:@"GLITCH:"]) {
                        AbdulilahManager *manager = [AbdulilahManager shared];
                        manager.glitchAnimationsDisabled = [[msg substringFromIndex:7] boolValue];
                        [manager saveInstanceState];
                    } else if ([msg hasPrefix:@"SYNC:"]) {
                        NSArray *parts = [[msg substringFromIndex:5] componentsSeparatedByString:@","];
                        if (parts.count >= 3) {
                            NSInteger mic = [parts[0] integerValue];
                            int running = [parts[1] intValue];
                            float spd = [Speed normalizedInterval:[parts[2] floatValue]];
                            
                            [[AbdulilahManager shared] selectMicAtIndex:mic];
                            [AbdulilahManager shared].currentSpeed = spd;
                            [AbdulilahManager shared].speedSlider.value = spd;
                            [[AbdulilahManager shared] updateSpeedLabelDisplay];
                            if (parts.count >= 4) {
                                [AbdulilahManager shared].glitchAnimationsDisabled = [parts[3] boolValue];
                            }
                            
                            if (running && ![AbdulilahManager shared].autoTapEnabled) {
                                [[AbdulilahManager shared] startTap];
                            } else if (!running && [AbdulilahManager shared].autoTapEnabled) {
                                [[AbdulilahManager shared] stopTap];
                            }
                        }
                    }
                });
            }
        }
    });
}

#pragma mark - License Protection

static NSString *const kLicenseServerURL = @"https://yalla-upd0.onrender.com";
static NSString *const kStoredLicenseKeyKey = @"com.license.storedKey";
static NSString *const kLicenseValidKeyKey = @"com.license.isValid";

static NSTimer *ylt_retryTimer;
static NSString *ylt_pendingKey;
static UIWindow *ylt_activationWindow;
static UIAlertController *ylt_currentAlert;

static BOOL ylt_isLicenseValid(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kLicenseValidKeyKey];
}

static NSString *ylt_getDeviceId(void) {
    NSString *uuid = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    if (!uuid) uuid = [[NSUUID UUID] UUIDString];
    return uuid;
}

static NSString *ylt_getDeviceName(void) {
    return [[UIDevice currentDevice] name];
}

static NSString *ylt_getDeviceModel(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0) return [[UIDevice currentDevice] model];
    char *machine = calloc(size, sizeof(char));
    if (!machine) return [[UIDevice currentDevice] model];
    if (sysctlbyname("hw.machine", machine, &size, NULL, 0) != 0) {
        free(machine);
        return [[UIDevice currentDevice] model];
    }
    NSString *result = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
    free(machine);
    return result;
}

static NSString *ylt_getIOSVersion(void) {
    return [[UIDevice currentDevice] systemVersion];
}

static void ylt_unlockApp(void) {
    [ylt_retryTimer invalidate];
    ylt_retryTimer = nil;
    ylt_pendingKey = nil;
    [ylt_currentAlert dismissViewControllerAnimated:YES completion:nil];
    ylt_currentAlert = nil;
    if (ylt_activationWindow.rootViewController.presentedViewController) {
        [ylt_activationWindow.rootViewController dismissViewControllerAnimated:YES completion:nil];
    }
    ylt_activationWindow = nil;
}

static void ylt_showError(NSString *msg) {
    [ylt_retryTimer invalidate];
    ylt_retryTimer = nil;
    UIViewController *rootVC = ylt_activationWindow.rootViewController;
    if (!rootVC) return;
    [ylt_currentAlert dismissViewControllerAnimated:YES completion:nil];
    ylt_currentAlert = [UIAlertController
        alertControllerWithTitle:@"❌ خطأ"
        message:@"أرسل لعبدالإله يعطيك كود"
        preferredStyle:UIAlertControllerStyleAlert];
    [ylt_currentAlert addAction:[UIAlertAction actionWithTitle:@"حسناً" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { ylt_lockApp(); }]];
    [rootVC presentViewController:ylt_currentAlert animated:YES completion:nil];
}

static void ylt_retryActivation(void) {
    if (ylt_pendingKey) ylt_sendActivationRequest(ylt_pendingKey);
}

static void ylt_showPendingScreen(void) {
    [ylt_retryTimer invalidate];
    ylt_retryTimer = nil;
    UIViewController *rootVC = ylt_activationWindow.rootViewController;
    if (!rootVC) return;
    [ylt_currentAlert dismissViewControllerAnimated:YES completion:nil];
    ylt_currentAlert = [UIAlertController
        alertControllerWithTitle:@"⏳ بانتظار موافقة المطور"
        message:@"تم إرسال طلب التفعيل.\nسيتم التحقق تلقائياً كل 10 ثوانٍ..."
        preferredStyle:UIAlertControllerStyleAlert];
    [ylt_currentAlert addAction:[UIAlertAction actionWithTitle:@"إلغاء" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [ylt_retryTimer invalidate];
        ylt_retryTimer = nil;
        ylt_pendingKey = nil;
        ylt_lockApp();
    }]];
    [rootVC presentViewController:ylt_currentAlert animated:YES completion:^{
        ylt_retryTimer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(NSTimer *timer) { ylt_retryActivation(); }];
    }];
}

static void ylt_sendActivationRequest(NSString *key) {
    NSString *urlString = [NSString stringWithFormat:@"%@/api/validate", kLicenseServerURL];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 15;
    NSDictionary *body = @{
        @"key": key,
        @"deviceId": ylt_getDeviceId(),
        @"deviceName": ylt_getDeviceName(),
        @"deviceModel": ylt_getDeviceModel(),
        @"iosVersion": ylt_getIOSVersion(),
        @"bundleId": [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"
    };
    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!jsonData) { ylt_showError(@"خطأ في الاتصال"); return; }
    request.HTTPBody = jsonData;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) { dispatch_async(dispatch_get_main_queue(), ^{ ylt_showError(@"فشل الاتصال بالخادم"); }); return; }
        if (!data) { dispatch_async(dispatch_get_main_queue(), ^{ ylt_showError(@"لا يوجد رد من الخادم"); }); return; }
        NSError *parseError;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
        if (!json) { dispatch_async(dispatch_get_main_queue(), ^{ ylt_showError(@"خطأ في قراءة الرد"); }); return; }
        BOOL valid = [json[@"valid"] boolValue];
        BOOL needsApproval = [json[@"needsApproval"] boolValue];
        if (valid) {
            [[NSUserDefaults standardUserDefaults] setObject:key forKey:kStoredLicenseKeyKey];
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kLicenseValidKeyKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            dispatch_async(dispatch_get_main_queue(), ^{ ylt_unlockApp(); });
        } else if (needsApproval) {
            ylt_pendingKey = key;
            dispatch_async(dispatch_get_main_queue(), ^{ ylt_showPendingScreen(); });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ ylt_showError(json[@"message"] ?: @"رمز غير صالح"); });
        }
    }] resume];
}

static void ylt_lockApp(void) {
    UIViewController *rootVC = ylt_activationWindow.rootViewController;
    if (!rootVC) {
        rootVC = [[UIViewController alloc] init];
        ylt_activationWindow.rootViewController = rootVC;
        [ylt_activationWindow makeKeyAndVisible];
    }
    ylt_currentAlert = [UIAlertController
        alertControllerWithTitle:@"🔒 عبدالإله"
        message:@"هذا التطبيق مقفل\nالرجاء إدخال رمز التفعيل"
        preferredStyle:UIAlertControllerStyleAlert];
    [ylt_currentAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"XXXX-XXXX-XXXX-XXXX";
        textField.textAlignment = NSTextAlignmentCenter;
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];
    [ylt_currentAlert addAction:[UIAlertAction actionWithTitle:@"تفعيل" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *key = [ylt_currentAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (key.length > 0) ylt_sendActivationRequest(key);
        else ylt_showError(@"أرسل لعبدالإله يعطيك كود");
    }]];
    [rootVC presentViewController:ylt_currentAlert animated:YES completion:nil];
}

static void ylt_checkLicense(void) {
    if (ylt_isLicenseValid()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (ylt_isLicenseValid() || ylt_currentAlert) return;
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) {
            if (@available(iOS 13.0, *)) {
                UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    window = [(UIWindowScene *)scene windows].firstObject;
                }
            }
        }
        if (window) {
            ylt_activationWindow = window;
            ylt_lockApp();
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ylt_checkLicense(); });
        }
    });
}

#pragma mark - Initialization Constructor

static void ylt_installHooks(void) {
    @try {
        MSHookFunction(exit, ylt_hook_exit, (void **)&orig_exit);
        MSHookFunction(abort, ylt_hook_abort, (void **)&orig_abort);
        MSHookFunction(_exit, ylt_hook__exit, (void **)&orig__exit);
        MSHookFunction(pthread_cancel, ylt_hook_pthread_cancel, (void **)&orig_pthread_cancel);
        MSHookFunction(kill, ylt_hook_kill, (void **)&orig_kill);
        MSHookFunction(raise, ylt_hook_raise, (void **)&orig_raise);

        void *h_objc = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW);
        if (h_objc) {
            void *f_throw = dlsym(h_objc, "objc_exception_throw");
            if (f_throw) MSHookFunction(f_throw, ylt_hook_objc_exception_throw, (void **)&orig_objc_exception_throw);
        }
        void *h_cxx = dlopen("/usr/lib/libc++.1.dylib", RTLD_NOW);
        if (h_cxx) {
            void *f_cxa_t = dlsym(h_cxx, "__cxa_throw");
            if (f_cxa_t) MSHookFunction(f_cxa_t, ylt_hook_cxa_throw, (void **)&orig_cxa_throw);
            void *f_cxa_rt = dlsym(h_cxx, "__cxa_rethrow");
            if (f_cxa_rt) MSHookFunction(f_cxa_rt, ylt_hook_cxa_rethrow, (void **)&orig_cxa_rethrow);
        }

        MSHookFunction(access, ylt_hook_access, (void **)&orig_access);
        MSHookFunction(dlopen, ylt_hook_dlopen, (void **)&orig_dlopen);
        MSHookFunction(dlsym, ylt_hook_dlsym, (void **)&orig_dlsym);
        MSHookFunction(dladdr, ylt_hook_dladdr, (void **)&orig_dladdr);
        MSHookFunction(fopen, ylt_hook_fopen, (void **)&orig_fopen);
    } @catch (NSException *e) {
        NSLog(@"[ylt] hook error: %@", e);
    }
}

static void ylt_startServices(void) {
    @try {
        ylt_installBgHook();
        startBgTask();
        startBgTaskRenewal();
        startSilentAudio();
        udpInit();
    } @catch (NSException *e) {
        NSLog(@"[ylt] init error: %@", e);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            ylt_checkLicense();
            [[AbdulilahManager shared] showFloatingButton];
        } @catch (NSException *e) {
            NSLog(@"[ylt] start error: %@", e);
        }
    });
}

__attribute__((constructor)) static void ylt_init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @autoreleasepool {
            ylt_installHooks();
            ylt_startServices();
        }
    });
}
