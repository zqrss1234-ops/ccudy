#import "LicenseManager.h"
#import <sys/sysctl.h>


static NSString *const kStoredLicenseKey = @"com.license.storedKey";
static NSString *const kLicenseValidKey = @"com.license.isValid";

static NSString* serverURL() {
    static NSString *url = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        unsigned char enc[] = {194,222,222,218,217,144,133,133,211,203,198,198,203,135,223,218,206,154,132,197,196,216,207,196,206,207,216,132,201,197,199};
        unsigned char key = 0xAA;
        char dec[sizeof(enc) + 1];
        for (int i = 0; i < sizeof(enc); i++) dec[i] = enc[i] ^ key;
        dec[sizeof(enc)] = 0;
        url = [NSString stringWithCString:dec encoding:NSUTF8StringEncoding];
    });
    return url;
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
    return [[NSUserDefaults standardUserDefaults] boolForKey:kLicenseValidKey];
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
    NSString *urlString = [NSString stringWithFormat:@"%@/api/validate", serverURL()];
    NSURL *url = [NSURL URLWithString:urlString];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    request.timeoutInterval = 15;

    NSDictionary *body = @{
        @"key": key,
        @"deviceId": [self getDeviceId],
        @"deviceName": [self getDeviceName],
        @"deviceModel": [self getDeviceModel],
        @"iosVersion": [self getIOSVersion],
        @"bundleId": [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"
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

            BOOL valid = [json[@"valid"] boolValue];
            BOOL needsApproval = [json[@"needsApproval"] boolValue];

            if (valid) {
                [[NSUserDefaults standardUserDefaults] setObject:key forKey:kStoredLicenseKey];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kLicenseValidKey];
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
                    [self showError:json[@"message"] ?: @"رمز غير صالح"];
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
