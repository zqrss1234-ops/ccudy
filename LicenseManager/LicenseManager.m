#import "LicenseManager.h"
#import <sys/sysctl.h>

NSString *const kLicenseServerURL = @"https://yalla-upd0.onrender.com";
static NSString *const kStoredLicenseKey = @"com.license.storedKey";
static NSString *const kLicenseValidKey = @"com.license.isValid";

@interface LicenseManager ()
@property (nonatomic, strong) UIWindow *activationWindow;
@property (nonatomic, strong) NSTimer *retryTimer;
@property (nonatomic, copy) NSString *pendingKey;
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
        _serverURL = kLicenseServerURL;
        _bundleId = [[NSBundle mainBundle] bundleIdentifier];
    }
    return self;
}

- (NSString *)getDeviceId {
    NSString *uuid = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    if (!uuid) {
        uuid = [[NSUUID UUID] UUIDString];
    }
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

- (BOOL)isLicenseValid {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kLicenseValidKey];
}

- (void)checkLicenseWithWindow:(UIWindow *)window {
    if ([self isLicenseValid]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        self.activationWindow = window;
        [self showActivationScreen];
    });
}

- (void)showActivationScreen {
    UIViewController *rootVC = self.activationWindow.rootViewController;
    if (!rootVC) {
        rootVC = [[UIViewController alloc] init];
        self.activationWindow.rootViewController = rootVC;
        [self.activationWindow makeKeyAndVisible];
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"IMpossible"
        message:@"الرجاء إدخال رمز التفعيل"
        preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"XXXX-XXXX-XXXX-XXXX";
        textField.textAlignment = NSTextAlignmentCenter;
        textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    }];

    UIAlertAction *activateAction = [UIAlertAction
        actionWithTitle:@"تأكيد"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            NSString *key = [alert.textFields.firstObject.text
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (key.length > 0) {
                [self sendActivationRequest:key];
            } else {
                [self showError:@"الرجاء إدخال رمز صالح"];
            }
        }];

    [alert addAction:activateAction];
    [rootVC presentViewController:alert animated:YES completion:nil];
}

- (void)sendActivationRequest:(NSString *)key {
    NSString *urlString = [NSString stringWithFormat:@"%@/api/validate", self.serverURL];
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
        @"bundleId": self.bundleId ?: @"unknown"
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
                    [self showSuccessAndDismiss];
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

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"⚠️ بانتظار موافقة المطور"
        message:@"تم إرسال طلب التفعيل للمطور.\nسيتم التحقق تلقائياً كل 10 ثوانٍ..."
        preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *retryAction = [UIAlertAction
        actionWithTitle:@"إعادة المحاولة الآن"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            if (self.pendingKey) {
                [self sendActivationRequest:self.pendingKey];
            }
        }];
    [alert addAction:retryAction];

    [rootVC presentViewController:alert animated:YES completion:^{
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

- (void)showSuccessAndDismiss {
    [self.retryTimer invalidate];
    self.retryTimer = nil;
    self.pendingKey = nil;

    if (self.activationWindow) {
        [self.activationWindow.rootViewController dismissViewControllerAnimated:YES completion:nil];
        self.activationWindow.hidden = YES;
        self.activationWindow = nil;
    }

    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (keyWindow && keyWindow.rootViewController) {
        UIAlertController *successAlert = [UIAlertController
            alertControllerWithTitle:@"✅ تم التفعيل"
            message:@"تم تفعيل التطبيق بنجاح"
            preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"بدء الاستخدام"
            style:UIAlertActionStyleDefault handler:nil]];
        [keyWindow.rootViewController presentViewController:successAlert animated:YES completion:nil];
    }
}

- (void)showError:(NSString *)message {
    [self.retryTimer invalidate];
    self.retryTimer = nil;

    UIViewController *rootVC = self.activationWindow.rootViewController;
    if (!rootVC) return;

    UIAlertController *errorAlert = [UIAlertController
        alertControllerWithTitle:@"❌ خطأ"
        message:message
        preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *retryAction = [UIAlertAction
        actionWithTitle:@"إعادة المحاولة"
        style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) {
            [self showActivationScreen];
        }];
    [errorAlert addAction:retryAction];
    [rootVC presentViewController:errorAlert animated:YES completion:nil];
}

@end
