#import "LicenseManager.h"
#import <sys/sysctl.h>


#define XOR_KEY 0xAA

#define EX(name, data, len) static unsigned char _e_##name[] = data; static NSString* _s_##name() { static NSString *s; static dispatch_once_t o; dispatch_once(&o, ^{ char d[len+1]; for(int i=0;i<len;i++) d[i]=_e_##name[i]^XOR_KEY; d[len]=0; s=[NSString stringWithCString:d encoding:NSUTF8StringEncoding]; }); return s; }

EX(SRV, {194,222,222,218,217,144,133,133,211,203,198,198,203,135,223,218,206,154,132,197,196,216,207,196,206,207,216,132,201,197,199}, 31)
EX(VAL, {133,203,218,195,133,220,203,198,195,206,203,222,207}, 13)
EX(STK, {201,197,199,132,198,195,201,207,196,217,207,132,217,222,197,216,207,206,225,207,211}, 21)
EX(VLK, {201,197,199,132,198,195,201,207,196,217,207,132,195,217,252,203,198,195,206}, 19)
EX(KEY, {197,207,211}, 3)
EX(DID, {206,207,220,195,201,207,227,206}, 8)
EX(DNM, {206,207,220,195,201,207,228,203,199,207}, 10)
EX(DMO, {206,207,220,195,201,207,231,197,206,207,198}, 11)
EX(IOV, {195,197,217,252,207,216,217,195,197,196}, 10)
EX(BID, {200,223,196,206,198,207,227,206}, 8)
EX(VLD, {220,203,198,195,206}, 5)
EX(NAP, {196,207,207,206,217,235,218,218,216,197,220,203,198}, 13)
EX(MSG, {199,207,217,217,203,205,207}, 7)
EX(UNK, {223,196,195,197,220,207,196}, 7)

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
    return [[NSUserDefaults standardUserDefaults] boolForKey:_s_VLK()];
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
                [self showError:@"الرجاء إدخال رمز صالح"];
            }
        }];

    [self.currentAlert addAction:activateAction];
    [rootVC presentViewController:self.currentAlert animated:YES completion:nil];
}

- (void)sendActivationRequest:(NSString *)key {
    NSString *urlString = [NSString stringWithFormat:@"%@%@", _s_SRV(), _s_VAL()];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 15;

    NSDictionary *body = @{
        _s_KEY(): key,
        _s_DID(): [self getDeviceId],
        _s_DNM(): [self getDeviceName],
        _s_DMO(): [self getDeviceModel],
        _s_IOV(): [self getIOSVersion],
        _s_BID(): [[NSBundle mainBundle] bundleIdentifier] ?: _s_UNK()
    };

    NSError *jsonError;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
    if (!jsonData) {
        [self showError:@"خطأ في الاتصال"];
        return;
    }
    request.HTTPBody = jsonData;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showError:@"فشل الاتصال بالخادم"];
                });
                return;
            }
            if (!data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showError:@"لا يوجد رد من الخادم"];
                });
                return;
            }

            NSError *parseError;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                options:0 error:&parseError];
            if (!json) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self showError:@"خطأ في قراءة الرد"];
                });
                return;
            }

            BOOL valid = [json[_s_VLD()] boolValue];
            BOOL needsApproval = [json[_s_NAP()] boolValue];

            if (valid) {
                [[NSUserDefaults standardUserDefaults] setObject:key forKey:_s_STK()];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:_s_VLK()];
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
                    [self showError:json[_s_MSG()] ?: @"رمز غير صالح"];
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
        alertControllerWithTitle:@"⏳ بانتظار موافقة المطور"
        message:@"تم إرسال طلب التفعيل.\nسيتم التحقق تلقائياً كل 10 ثوانٍ..."
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

- (void)showError:(NSString *)message {
    [self.retryTimer invalidate];
    self.retryTimer = nil;

    UIViewController *rootVC = self.activationWindow.rootViewController;
    if (!rootVC) return;

    [self.currentAlert dismissViewControllerAnimated:YES completion:nil];

    self.currentAlert = [UIAlertController
        alertControllerWithTitle:@"❌ خطأ"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *retryAction = [UIAlertAction
        actionWithTitle:@"إعادة المحاولة"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            [self lockApp];
        }];
    [self.currentAlert addAction:retryAction];

    [rootVC presentViewController:self.currentAlert animated:YES completion:nil];
}

@end
