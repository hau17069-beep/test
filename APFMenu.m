#import "APFMenu.h"
#import "APFPrefs.h"
#import <AudioToolbox/AudioToolbox.h>
#import <UserNotifications/UserNotifications.h>

static NSString *fmtPrice(NSInteger price) {
    if (price >= 1000000) return [NSString stringWithFormat:@"%.1fM", (double)price/1000000];
    if (price >= 1000) return [NSString stringWithFormat:@"%.1fk", (double)price/1000];
    return [NSString stringWithFormat:@"%ldđ", (long)price];
}

static void (^gTestFreePickCB)(void) = nil;
static void (^gTestMPickCB)(void) = nil;

@implementation APFMenu

+ (UIWindow *)keyWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
            if ([s isKindOfClass:[UIWindowScene class]])
                for (UIWindow *w in ((UIWindowScene *)s).windows) if (w.isKeyWindow) return w;
    }
    return nil;
}

+ (UIViewController *)topVC {
    UIWindow *w = [self keyWindow]; if (!w) return nil;
    UIViewController *t = w.rootViewController;
    while (t.presentedViewController) t = t.presentedViewController;
    return t;
}

+ (void)requestNotificationPermission {
    UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
    [c requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
        completionHandler:^(BOOL granted, NSError *e) { NSLog(@"[AutoPick] 🔔 Permission: %@", granted ? @"OK" : @"NO"); }];
}

+ (void)showSystemNotification:(NSString *)title body:(NSString *)body id:(NSString *)ident {
    @try {
        UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body = body;
        content.sound = [UNNotificationSound defaultSound];
        UNTimeIntervalNotificationTrigger *t = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1 repeats:NO];
        UNNotificationRequest *req = [UNNotificationRequest requestWithIdentifier:(ident ?: [[NSUUID UUID] UUIDString]) content:content trigger:t];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req withCompletionHandler:^(NSError *e) {}];
    } @catch(NSException *e) {}
}

+ (void)presentSheet:(UIAlertController *)s {
    UIViewController *t = [self topVC]; if (!t) return;
    s.popoverPresentationController.sourceView = t.view;
    s.popoverPresentationController.sourceRect = CGRectMake(t.view.bounds.size.width/2, t.view.bounds.size.height/2, 1, 1);
    [t presentViewController:s animated:YES completion:nil];
}

+ (void)presentMenu {
    APFPrefs *p = [APFPrefs shared];
    UIAlertController *s = [UIAlertController alertControllerWithTitle:@"⚡ AutoPick VIP v15"
        message:[NSString stringWithFormat:@"Trạng thái: %@", p.enabled ? @"BẬT" : @"TẮT"]
        preferredStyle:UIAlertControllerStyleActionSheet];
    [s addAction:[UIAlertAction actionWithTitle:(p.enabled ? @"🔴 TẮT AutoPick" : @"🟢 BẬT AutoPick")
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { p.enabled = !p.enabled; [p save]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"⚙️ Cấu hình" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self detailMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"🎯 Bộ lọc" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self filterMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"🔔 Thông báo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self notifyMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"🧪 Test Free-Pick" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self testFreePick]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"🧪 Test MPick" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self testMPick]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"🔄 Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [p reset]; [self toast:@"Đã reset"]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:s];
}

+ (void)setTestFreePickCallback:(void (^)(void))cb { gTestFreePickCB = [cb copy]; }
+ (void)setTestMPickCallback:(void (^)(void))cb { gTestMPickCB = [cb copy]; }

+ (void)testFreePick {
    UIViewController *t = [self topVC]; if (!t) return;
    UIAlertController *w = [UIAlertController alertControllerWithTitle:@"🧪 Test Free-Pick"
        message:@"Gửi request pick đến /pick với ID giả.\nTiếp tục?"
        preferredStyle:UIAlertControllerStyleAlert];
    [w addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [w addAction:[UIAlertAction actionWithTitle:@"Test" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (gTestFreePickCB) { gTestFreePickCB(); [self toast:@"Đã gửi test"]; }
    }]];
    [t presentViewController:w animated:YES completion:nil];
}

+ (void)testMPick {
    UIViewController *t = [self topVC]; if (!t) return;
    UIAlertController *w = [UIAlertController alertControllerWithTitle:@"🧪 Test MPick"
        message:@"Gửi request pick đến /mpick với pre_group_code giả.\nTiếp tục?"
        preferredStyle:UIAlertControllerStyleAlert];
    [w addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [w addAction:[UIAlertAction actionWithTitle:@"Test" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        if (gTestMPickCB) { gTestMPickCB(); [self toast:@"Đã gửi test"]; }
    }]];
    [t presentViewController:w animated:YES completion:nil];
}

+ (void)detailMenu {
    APFPrefs *p = [APFPrefs shared];
    UIAlertController *s = [UIAlertController alertControllerWithTitle:@"⚙️ Cấu hình" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Auto refresh: %@", p.autoRefresh ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.autoRefresh = !p.autoRefresh; [p save]; [self detailMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Auto pick: %@", p.autoPick ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.autoPick = !p.autoPick; [p save]; [self detailMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Dừng sau pick: %@", p.stopAfterPick ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.stopAfterPick = !p.stopAfterPick; [p save]; [self detailMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"⏱ Chu kỳ: %ldms", (long)p.refreshIntervalMs]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Chu kỳ refresh (100-10000ms)" val:p.refreshIntervalMs min:100 max:10000 cb:^(NSInteger v) {
            p.refreshIntervalMs = v; [p save]; [self detailMenu];
        }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📡 Bán kính server: %ldm", (long)p.requestMaxDistance]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Bán kính (500-50000m)" val:p.requestMaxDistance min:500 max:50000 cb:^(NSInteger v) {
            p.requestMaxDistance = v; [p save]; [self detailMenu];
        }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Số đơn tối đa: %ld", (long)p.maxOrdersPerSession]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Số đơn" val:p.maxOrdersPerSession min:1 max:100 cb:^(NSInteger v) { p.maxOrdersPerSession = v; [p save]; [self detailMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Cooldown: %.1fs", p.cooldown]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Cooldown x10" val:(NSInteger)(p.cooldown*10) min:5 max:100 cb:^(NSInteger v) { p.cooldown = v/10.0; [p save]; [self detailMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:@"⬅️ Quay lại" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { [self presentMenu]; }]];
    [self presentSheet:s];
}

+ (void)filterMenu {
    APFPrefs *p = [APFPrefs shared];
    UIAlertController *s = [UIAlertController alertControllerWithTitle:@"🎯 Bộ lọc" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"💰 Giá min: %@", fmtPrice(p.minPrice)]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Giá min" val:p.minPrice min:0 max:10000000 cb:^(NSInteger v) { p.minPrice = v; [p save]; [self filterMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"💰 Giá max: %@", p.maxPrice > 0 ? fmtPrice(p.maxPrice) : @"off"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Giá max (0=off)" val:p.maxPrice min:0 max:10000000 cb:^(NSInteger v) { p.maxPrice = v; [p save]; [self filterMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📏 Km min: %.1f", (double)p.minDistance/1000]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Km min (m)" val:p.minDistance min:0 max:100000 cb:^(NSInteger v) { p.minDistance = v; [p save]; [self filterMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📏 Km max: %.1f", (double)p.maxDistance/1000]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"Km max (m)" val:p.maxDistance min:0 max:200000 cb:^(NSInteger v) { p.maxDistance = v; [p save]; [self filterMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"💵 COD min: %@", fmtPrice(p.minCOD)]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"COD min" val:p.minCOD min:0 max:100000000 cb:^(NSInteger v) { p.minCOD = v; [p save]; [self filterMenu]; }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"💵 COD max: %@", p.maxCOD > 0 ? fmtPrice(p.maxCOD) : @"off"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self numberInput:@"COD max (0=off)" val:p.maxCOD min:0 max:100000000 cb:^(NSInteger v) { p.maxCOD = v; [p save]; [self filterMenu]; }];
    }]];
    NSString *catStr = p.preferredCategories.count > 0 ? [[p.preferredCategories valueForKey:@"description"] componentsJoinedByString:@","] : @"tất cả";
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📦 Loại: %@", catStr]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self textInput:@"Loại (số,phẩy | 'tất cả')" val:catStr cb:^(NSString *v) {
            if ([v isEqualToString:@"tất cả"] || v.length == 0) p.preferredCategories = @[];
            else {
                NSMutableArray *arr = [NSMutableArray array];
                for (NSString *x in [v componentsSeparatedByString:@","]) [arr addObject:@([x integerValue])];
                p.preferredCategories = arr;
            }
            [p save]; [self filterMenu];
        }];
    }]];
    NSString *districtStr = p.preferredDistricts.count > 0 ? [p.preferredDistricts componentsJoinedByString:@", "] : @"(tất cả)";
    NSString *modeStr = @"off";
    if (p.districtFilterMode == 1) modeStr = @"điểm lấy";
    else if (p.districtFilterMode == 2) modeStr = @"điểm giao";
    else if (p.districtFilterMode == 3) modeStr = @"cả 2";
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📍 Quận: %@", districtStr]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self textInput:@"Quận (cách phẩy)" val:districtStr cb:^(NSString *v) {
            if ([v isEqualToString:@"(tất cả)"] || v.length == 0) p.preferredDistricts = @[];
            else {
                NSMutableArray *arr = [NSMutableArray array];
                for (NSString *x in [v componentsSeparatedByString:@","]) {
                    NSString *trim = [x stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    if (trim.length > 0) [arr addObject:trim];
                }
                p.preferredDistricts = arr;
            }
            [p save]; [self filterMenu];
        }];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"🔍 Lọc theo: %@", modeStr]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        UIAlertController *m = [UIAlertController alertControllerWithTitle:@"Lọc quận theo" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [m addAction:[UIAlertAction actionWithTitle:@"❌ Tắt" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { p.districtFilterMode = 0; [p save]; [self filterMenu]; }]];
        [m addAction:[UIAlertAction actionWithTitle:@"📍 Điểm lấy" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { p.districtFilterMode = 1; [p save]; [self filterMenu]; }]];
        [m addAction:[UIAlertAction actionWithTitle:@"🏁 Điểm giao" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { p.districtFilterMode = 2; [p save]; [self filterMenu]; }]];
        [m addAction:[UIAlertAction actionWithTitle:@"✅ Cả 2" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { p.districtFilterMode = 3; [p save]; [self filterMenu]; }]];
        [m addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [self presentSheet:m];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:@"⬅️ Quay lại" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { [self presentMenu]; }]];
    [self presentSheet:s];
}

+ (void)notifyMenu {
    APFPrefs *p = [APFPrefs shared];
    UIAlertController *s = [UIAlertController alertControllerWithTitle:@"🔔 Thông báo" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📱 Hệ thống: %@", p.systemNotify ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        p.systemNotify = !p.systemNotify; [p save];
        if (p.systemNotify) [self requestNotificationPermission];
        [self notifyMenu];
    }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"💬 Popup app: %@", p.notifyOnMatch ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.notifyOnMatch = !p.notifyOnMatch; [p save]; [self notifyMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"✅ Pick OK: %@", p.notifyOnSuccess ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.notifyOnSuccess = !p.notifyOnSuccess; [p save]; [self notifyMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"🔊 Âm thanh: %@", p.soundOnMatch ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.soundOnMatch = !p.soundOnMatch; [p save]; [self notifyMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"📳 Rung: %@", p.vibrateOnMatch ? @"✅" : @"❌"]
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { p.vibrateOnMatch = !p.vibrateOnMatch; [p save]; [self notifyMenu]; }]];
    [s addAction:[UIAlertAction actionWithTitle:@"🧪 Test thông báo"
        style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self requestNotificationPermission];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showSystemNotification:@"⚡ AutoPick Test" body:@"Đây là thông báo test" id:@"test"];
        });
    }]];
    [s addAction:[UIAlertAction actionWithTitle:@"⬅️ Quay lại" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) { [self presentMenu]; }]];
    [self presentSheet:s];
}

+ (void)numberInput:(NSString *)title val:(NSInteger)v min:(NSInteger)min max:(NSInteger)max cb:(void (^)(NSInteger))cb {
    UIViewController *t = [self topVC]; if (!t) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:[NSString stringWithFormat:@"(%ld - %ld)", (long)min, (long)max] preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.keyboardType = UIKeyboardTypeNumberPad; tf.text = [NSString stringWithFormat:@"%ld", (long)v]; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSInteger n = [a.textFields.firstObject.text integerValue];
        if (n < min) n = min;
        if (n > max) n = max;
        cb(n);
    }]];
    [t presentViewController:a animated:YES completion:nil];
}

+ (void)textInput:(NSString *)title val:(NSString *)v cb:(void (^)(NSString *))cb {
    UIViewController *t = [self topVC]; if (!t) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = v; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { cb(a.textFields.firstObject.text ?: @""); }]];
    [t presentViewController:a animated:YES completion:nil];
}

+ (void)toast:(NSString *)msg {
    UIViewController *t = [self topVC]; if (!t) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"AutoPick" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [t presentViewController:a animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
    }];
}

+ (void)notifyMatchDetail:(NSDictionary *)order {
    APFPrefs *p = [APFPrefs shared];
    if (!p.notifyOnMatch && !p.systemNotify) return;
    @try {
        NSInteger earn = [order[@"total_earnings_amount"] integerValue];
        NSInteger dist = [order[@"delivery_distance"] integerValue];
        NSArray *dos = order[@"delivery_orders"];
        NSInteger count = dos.count;
        if (count == 0) return;
        NSString *groupCode = order[@"pre_group_code"];
        BOOL isGroup = (groupCode != nil && count > 1);
        NSInteger totalCOD = 0;
        NSArray *innerOrders = order[@"orders"];
        if ([innerOrders isKindOfClass:[NSArray class]])
            for (NSDictionary *io in innerOrders) totalCOD += [io[@"cod_amount"] integerValue];
        NSString *pickupShop = @"?", *pickupAddr = @"?";
        NSDictionary *first = dos[0];
        NSDictionary *pu = first[@"pickup_address_info"];
        if ([pu isKindOfClass:[NSDictionary class]]) { pickupShop = pu[@"contact_name"] ?: @"?"; pickupAddr = pu[@"address"] ?: @"?"; }
        NSString *dropoffAddr = @"?";
        NSDictionary *do_ = dos[count-1][@"dropoff_address_info"];
        if ([do_ isKindOfClass:[NSDictionary class]]) dropoffAddr = do_[@"address"] ?: @"?";
        NSString *(^shorten)(NSString *, NSInteger) = ^(NSString *s, NSInteger max) {
            if (!s || s.length <= max) return s ?: @"?";
            return [NSString stringWithFormat:@"%@...", [s substringToIndex:max - 3]];
        };
        NSString *title = isGroup ? [NSString stringWithFormat:@"🎯 CHÙM %ld ĐƠN KHỚP!", (long)count] : @"🎯 ĐƠN KHỚP!";
        NSMutableString *body = [NSMutableString string];
        if (isGroup) [body appendFormat:@"📦 %ld đơn  |  💰 %@  |  📏 %.1fkm", (long)count, fmtPrice(earn), (double)dist/1000.0];
        else [body appendFormat:@"💰 %@  |  📏 %.1fkm", fmtPrice(earn), (double)dist/1000.0];
        if (totalCOD > 0) [body appendFormat:@"  |  💵 COD %@", fmtPrice(totalCOD)];
        [body appendFormat:@"\n📍 %@", shorten(pickupShop, 30)];
        [body appendFormat:@"\n%@", shorten(pickupAddr, 55)];
        [body appendFormat:@"\n🏁 %@", shorten(dropoffAddr, 55)];
        NSString *orderId = groupCode ? groupCode : [NSString stringWithFormat:@"%ld", (long)[dos[0][@"delivery_order_id"] integerValue]];
        if (p.soundOnMatch) AudioServicesPlaySystemSound(1057);
        if (p.vibrateOnMatch) AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        if (p.systemNotify) [self showSystemNotification:title body:body id:[NSString stringWithFormat:@"m_%@_%ld", orderId, (long)[[NSDate date] timeIntervalSince1970]]];
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateActive && p.notifyOnMatch) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIViewController *t = [self topVC]; if (!t) return;
                UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [t presentViewController:a animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
                }];
            });
        }
    } @catch(NSException *e) {}
}

+ (void)notifySuccessDetail:(NSString *)orderInfo price:(NSInteger)price {
    APFPrefs *p = [APFPrefs shared];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (p.soundOnMatch) AudioServicesPlaySystemSound(1007);
        if (p.vibrateOnMatch) AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        NSString *title = @"✅ PICK THÀNH CÔNG";
        NSString *body = price > 0 ? [NSString stringWithFormat:@"%@\n💰 Tổng nhận: %@", orderInfo, fmtPrice(price)] : orderInfo;
        if (p.systemNotify) [self showSystemNotification:title body:body id:[NSString stringWithFormat:@"s_%ld", (long)[[NSDate date] timeIntervalSince1970]]];
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateActive && p.notifyOnSuccess) {
            UIViewController *t = [self topVC]; if (!t) return;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
            [t presentViewController:a animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
            }];
        }
    });
}

+ (void)notifyPickFailed:(NSString *)reason {
    APFPrefs *p = [APFPrefs shared];
    dispatch_async(dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(1053);
        if (p.vibrateOnMatch) AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        NSString *title = @"❌ PICK THẤT BẠI";
        NSString *body = reason ?: @"Không rõ lý do";
        if (p.systemNotify) [self showSystemNotification:title body:body id:[NSString stringWithFormat:@"fail_%ld", (long)[[NSDate date] timeIntervalSince1970]]];
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateActive && p.notifyOnMatch) {
            UIViewController *t = [self topVC]; if (!t) return;
            UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:body preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [t presentViewController:a animated:YES completion:^{
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [a dismissViewControllerAnimated:YES completion:nil]; });
            }];
        }
    });
}

@end