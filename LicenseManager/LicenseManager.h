#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LicenseManager : NSObject

+ (instancetype)sharedInstance;

- (void)checkLicense;
- (BOOL)isLicenseValid;

@end
