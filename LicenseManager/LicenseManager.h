#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

extern NSString *const kLicenseServerURL;

@interface LicenseManager : NSObject

@property (nonatomic, copy) NSString *serverURL;
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) void (^onValidated)(BOOL valid, NSString *message);

+ (instancetype)sharedInstance;

- (void)checkLicenseWithWindow:(UIWindow *)window;
- (BOOL)isLicenseValid;
- (void)validateKey:(NSString *)key completion:(void (^)(BOOL valid, NSString *message))completion;
- (NSString *)getDeviceId;

@end
