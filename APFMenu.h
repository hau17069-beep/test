#import <UIKit/UIKit.h>

@interface APFMenu : NSObject
+ (void)presentMenu;
+ (void)notifyMatchDetail:(NSDictionary *)order;
+ (void)notifySuccessDetail:(NSString *)orderInfo price:(NSInteger)price;
+ (void)notifyPickFailed:(NSString *)reason;
+ (void)requestNotificationPermission;
+ (void)showSystemNotification:(NSString *)title body:(NSString *)body id:(NSString *)ident;
+ (void)setTestFreePickCallback:(void (^)(void))cb;
+ (void)setTestMPickCallback:(void (^)(void))cb;
+ (void)testFreePick;
+ (void)testMPick;
@end