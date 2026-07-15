#import "LicenseManager.h"
#import <sys/sysctl.h>

#define X(k) ((k)^0xAA)

static unsigned char _e_srv[] = {194,222,222,218,217,144,133,133,211,203,198,198,203,135,223,218,206,154,132,197,196,216,207,196,206,207,216,132,201,197,199};
static unsigned char _e_val[] = {133,203,218,195,133,220,203,198,195,206,203,222,207};
static unsigned char _e_key[] = {193,207,211};
static unsigned char _e_did[] = {206,207,220,195,201,207,227,206};
static unsigned char _e_dnm[] = {206,207,220,195,201,207,228,203,199,207};
static unsigned char _e_dmo[] = {206,207,220,195,201,207,231,197,206,207,198};
static unsigned char _e_iov[] = {195,197,217,252,207,216,217,195,197,196};
static unsigned char _e_bid[] = {200,223,196,206,198,207,227,206};
static unsigned char _e_unk[] = {223,196,193,196,197,221,196};
static unsigned char _e_vld[] = {220,203,198,195,206};
static unsigned char _e_nap[] = {196,207,207,206,217,235,218,218,216,197,220,203,198};
static unsigned char _e_msg[] = {199,207,217,217,203,205,207};
static unsigned char _e_stk[] = {201,197,199,132,198,195,201,207,196,217,207,132,217,222,197,216,207,206,225,207,211};
static unsigned char _e_vlk[] = {201,197,199,132,198,195,201,207,196,217,207,132,195,217,252,203,198,195,206};

static NSString* _d(unsigned char *e, size_t l) {
    static NSMutableDictionary *c;
    static dispatch_once_t o;
    dispatch_once(&o, ^{ c = [NSMutableDictionary dictionary]; });
    @synchronized(c) {
        NSNumber *k = @((intptr_t)e);
        NSString *r = c[k];
        if (r) return r;
        char buf[l+1];
        for (size_t i = 0; i < l; i++) buf[i] = X(e[i]);
        buf[l] = 0;
        r = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
        c[k] = r;
        return r;
    }
}

static id observerToken = nil;

__attribute__((constructor))
static void onDylibLoad() {
    observerToken = [[NSNotificationCenter defaultCenter]
        addObserverForName:UIApplicationDidFinishLaunchingNotification
        object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            [[LicenseManager sharedInstance] checkLicense];
        }];
}

@interface LicenseManager ()
@property (nonatomic, strong) NSTimer *retryTimer;
@property (nonatomic, copy) NSString *pendingKey;
@property (nonatomic, strong) UIWindow *activationWindow;
@property (nonatomic, strong) UIAlertController *currentAlert;
@end

@implementation LicenseManager

+ (instancetype)sharedInstance {
    static LicenseManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
    }
    return self;
}

- (BOOL)isLicenseValid {
    return [[NSUserDefaults standardUserDefaults] boolForKey:_d(_e_vlk, sizeof(_e_vlk))];
}

- (NSString *)getDeviceId {
    NSString *uuid = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    if (!uuid) uuid = [[NSUUID UUID] UUIDString];
    return uuid;
}

- (NSString *)getDeviceName {
    return [[UIDevice currentDevice] name];
}

- (NSString *)getDeviceModel {
    NSString *machine = [self getSysInfoByName:"hw.machine"];
    return machine ?: [[UIDevice currentDevice] model];
}

- (NSString *)getIOSVersion {
    return [[UIDevice currentDevice] systemVersion];
}

- (NSString *)getSysInfoByName:(const char *)typeSpecifier {
    size_t size;
    sysctlbyname(typeSpecifier, NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname(typeSpecifier, machine, &size, NULL, 0);
    NSString *result = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
    free(machine);
    return result;
}

- (void)checkLicense {
    if ([self isLicenseValid]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window) {
            if (@available(iOS 13.0, *)) {
                UIScene *scene = [UIApplication sharedApplication].connectedScenes.anyObject;
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    UIWindowScene *ws = (UIWindowScene *)scene;
                    window = ws.windows.firstObject;
                }
            }
        }
        if (window) {
            self.activationWindow = window;
            [self lockApp];
        } else {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC),
                dispatch_get_main_queue(), ^{
                [self checkLicense];
            });
        }
    });
}

- (void)lockApp {
    UIViewController *rootVC = self.activationWindow.rootViewController;
    if (!rootVC) {
        UIViewController *vc = [[UIViewController alloc] init];
        self.activationWindow.rootViewController = vc;
        [self.activationWindow makeKeyAndVisible];
        rootVC = vc;
    }

    self.currentAlert = [UIAlertController
        alertControllerWithTitle:@"🔒 عبدالإله"
        message:@"هذا التطبيق مقفل\nالرجاء إدخال رمز التفعيل"
        preferredStyle:UIAlertControllerStyleAlert];

    [self.currentAlert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"XXXX-XXXX-XXXX-XXXX";
        textField.textAlignment = NSTextAlignmentCenter;
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];

    UIAlertAction *activateAction = [UIAlertAction
        actionWithTitle:@"تفعيل"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSString *key = [self.currentAlert.textFields.firstObject.text
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (key.length > 0) {
                [self sendActivationRequest:key];
            } else {
                [self showContactError];
            }
        }];

    [self.currentAlert addAction:activateAction];
    [rootVC presentViewController:self.currentAlert animated:YES completion:nil];
}

- (void)sendActivationRequest:(NSString *)key {
    NSString *urlString = [NSString stringWithFormat:@"%@%@", _d(_e_srv, sizeof(_e_srv)), _d(_e_val, sizeof(_e_val))];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 15;

    NSDictionary *body = @{
        _d(_e_key, sizeof(_e_key)): key,
        _d(_e_did, sizeof(_e_did)): [self getDeviceId],
        _d(_e_dnm, sizeof(_e_dnm)): [self getDeviceName],
        _d(_e_dmo, sizeof(_e_dmo)): [self getDeviceModel],
        _d(_e_iov, sizeof(_e_iov)): [self getIOSVersion],
        _d(_e_bid, sizeof(_e_bid)): [[NSBundle mainBundle] bundleIdentifier] ?: _d(_e_unk, sizeof(_e_unk))
    };

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!jsonData) {
        [self showContactError];
        return;
    }
    request.HTTPBody = jsonData;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showContactError];
                });
                return;
            }
            if (!data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showContactError];
                });
                return;
            }

            NSError *parseError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                options:0 error:&parseError];
            if (!json) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showContactError];
                });
                return;
            }

            BOOL valid = [json[_d(_e_vld, sizeof(_e_vld))] boolValue];
            BOOL needsApproval = [json[_d(_e_nap, sizeof(_e_nap))] boolValue];

            if (valid) {
                [[NSUserDefaults standardUserDefaults] setObject:key forKey:_d(_e_stk, sizeof(_e_stk))];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:_d(_e_vlk, sizeof(_e_vlk))];
                [[NSUserDefaults standardUserDefaults] synchronize];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self unlockApp];
                });
            } else if (needsApproval) {
                self.pendingKey = key;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showPendingScreen];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showContactError];
                });
            }
        }];
    [task resume];
}

- (void)showPendingScreen {
    [self.retryTimer invalidate];
    self.retryTimer = nil;

    UIViewController *rootVC = self.activationWindow.rootViewController;
    if (!rootVC) return;

    [self.currentAlert dismissViewControllerAnimated:YES completion:nil];

    self.currentAlert = [UIAlertController
        alertControllerWithTitle:@"⏳ بانتظار الموافقة"
        message:@"تم الإرسال\nسيتم التحقق كل 10 ثوانٍ"
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction
        actionWithTitle:@"إلغاء"
        style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *action) {
            [self.retryTimer invalidate];
            self.retryTimer = nil;
            self.pendingKey = nil;
            [self lockApp];
        }];
    [self.currentAlert addAction:cancelAction];

    [rootVC presentViewController:self.currentAlert animated:YES completion:^{
        self.retryTimer = [NSTimer scheduledTimerWithTimeInterval:10.0
            target:self selector:@selector(retryActivation)
            userInfo:nil repeats:YES];
    }];
}

- (void)retryActivation {
    if (self.pendingKey) {
        [self sendActivationRequest:self.pendingKey];
    }
}

- (void)unlockApp {
    [self.retryTimer invalidate];
    self.retryTimer = nil;
    self.pendingKey = nil;

    UIViewController *rootVC = self.activationWindow.rootViewController;
    [self.currentAlert dismissViewControllerAnimated:YES completion:nil];
    self.currentAlert = nil;

    if (rootVC.presentedViewController) {
        [rootVC dismissViewControllerAnimated:YES completion:nil];
    }

    self.activationWindow = nil;
}

- (void)showContactError {
    [self.retryTimer invalidate];
    self.retryTimer = nil;

    UIViewController *rootVC = self.activationWindow.rootViewController;
    if (!rootVC) return;

    [self.currentAlert dismissViewControllerAnimated:YES completion:nil];

    self.currentAlert = [UIAlertController
        alertControllerWithTitle:@"❌ خطأ"
        message:@"أرسل لعبدالإله يعطيك كود"
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:@"حسناً"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            [self lockApp];
        }];
    [self.currentAlert addAction:okAction];

    [rootVC presentViewController:self.currentAlert animated:YES completion:nil];
}

@end
