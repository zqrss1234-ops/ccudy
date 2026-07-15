#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LicenseManager : NSObject

+ (instancetype)sharedInstance;

- (void)checkLicense;
- (BOOL)isLicenseValid;
- (void)validateKey:(NSString *)key completion:(void (^)(BOOL valid, NSString *message))completion;

@end
