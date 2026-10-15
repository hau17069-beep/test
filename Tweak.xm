#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>
#import <zlib.h>
#import "APFPrefs.h"
#import "APFFilter.h"
#import "APFMenu.h"

@interface RCTHTTPRequestHandler : NSObject
- (id)sendRequest:(NSURLRequest *)request withDelegate:(id)delegate;
- (void)shpNetworkingModule:(id)module shpRequest:(id)request didReceiveData:(NSData *)data;
@end

static RCTHTTPRequestHandler *gHandler = nil;
static id gDelegate = nil;
static NSMutableURLRequest *gSavedRequest = nil;
static NSDate *gSavedTime = nil;
static dispatch_source_t gTimerSource = nil;
static NSInteger gRefreshCount = 0;
static NSInteger gPickedCount = 0;
static NSDate *gLastPickTime = nil;
static NSMutableSet *gPickedIds = nil;
static BOOL gStopped = NO;
static NSMutableString *gResponseBuffer = nil;
static NSString *gLastUrl = nil;
static NSInteger gResponseIndex = 0;
static NSString *gLastPickedInfo = nil;
static NSInteger gLastPickedPrice = 0;

// ⭐ TEST MODE: 0=off, 1=free-pick, 2=mpick
static NSInteger gTestMode = 0;

static NSString *kGetOrderUrl = @"https://gpartner.deliverynow.vn/api/v6/free-pick/get-order-list";
static NSString *kPickUrl = @"https://gpartner.deliverynow.vn/api/v6/free-pick/pick";
static NSString *kMPickUrl = @"https://gpartner.deliverynow.vn/api/v6/free-pick/mpick";

// ===== LOG =====
static void APFLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[AutoPick] %@", msg);
}

static NSString *fmtPrice(NSInteger price) {
    if (price >= 1000000) return [NSString stringWithFormat:@"%.1fM", (double)price/1000000];
    if (price >= 1000) return [NSString stringWithFormat:@"%.1fk", (double)price/1000];
    return [NSString stringWithFormat:@"%ldđ", (long)price];
}

// ===== GZIP =====
static NSData *gunzipData(NSData *data) {
    if (!data || data.length < 2) return data;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    if (bytes[0] != 0x1f || bytes[1] != 0x8b) return data;
    z_stream strm = {0};
    strm.next_in = (Bytef *)bytes;
    strm.avail_in = (uInt)data.length;
    strm.zalloc = Z_NULL; strm.zfree = Z_NULL;
    if (inflateInit2(&strm, 16 + MAX_WBITS) != Z_OK) return nil;
    NSMutableData *output = [NSMutableData dataWithCapacity:data.length * 4];
    uint8_t buffer[16384];
    int ret;
    do {
        strm.next_out = buffer;
        strm.avail_out = sizeof(buffer);
        ret = inflate(&strm, Z_NO_FLUSH);
        if (ret == Z_STREAM_ERROR || ret == Z_NEED_DICT || ret == Z_DATA_ERROR || ret == Z_MEM_ERROR) {
            inflateEnd(&strm); return nil;
        }
        NSUInteger have = sizeof(buffer) - strm.avail_out;
        if (have > 0) [output appendBytes:buffer length:have];
    } while (ret != Z_STREAM_END && strm.avail_in > 0);
    inflateEnd(&strm);
    return ret == Z_STREAM_END ? output : nil;
}

// ===== TIMESTAMP =====
static NSString *updateLocationTimestamp(NSString *location) {
    if (!location || location.length == 0) return location;
    @try {
        NSArray *parts = [location componentsSeparatedByString:@","];
        if (parts.count < 4) return location;
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Ho_Chi_Minh"];
        fmt.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
        return [NSString stringWithFormat:@"%@,%@,%@,%@", parts[0], parts[1], parts[2], [fmt stringFromDate:[NSDate date]]];
    } @catch(NSException *e) { return location; }
}

static NSDictionary *refreshHeadersWithCurrentTime(NSDictionary *origHeaders) {
    if (!origHeaders) return origHeaders;
    NSMutableDictionary *nh = [NSMutableDictionary dictionaryWithDictionary:origHeaders];
    NSString *loc = nh[@"x-foody-location"];
    if (loc) nh[@"x-foody-location"] = updateLocationTimestamp(loc);
    return nh;
}

// ===== MODIFY BODY IN-PLACE =====
static BOOL modifyRequestInPlace(NSURLRequest *request) {
    @try {
        APFPrefs *p = [APFPrefs shared];
        if (p.requestMaxDistance < 500) return NO;
        
        NSData *bodyData = request.HTTPBody;
        if (!bodyData || bodyData.length < 5) return NO;
        
        NSError *err = nil;
        id json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&err];
        if (!json || err || ![json isKindOfClass:[NSDictionary class]]) return NO;
        
        NSMutableDictionary *body = [json mutableCopy];
        NSInteger oldDist = [body[@"max_distance"] integerValue];
        if (oldDist == 0) return NO;
        
        body[@"max_distance"] = @(p.requestMaxDistance);
        if (p.preferredCategories && p.preferredCategories.count > 0) {
            body[@"ref_order_category_list"] = p.preferredCategories;
        }
        
        NSData *newBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        if (!newBody) return NO;
        
        if ([request isKindOfClass:[NSMutableURLRequest class]]) {
            NSMutableURLRequest *mutableReq = (NSMutableURLRequest *)request;
            [mutableReq setHTTPBody:newBody];
            [mutableReq setValue:[NSString stringWithFormat:@"%lu", (unsigned long)newBody.length] forHTTPHeaderField:@"Content-Length"];
            
            if (oldDist != p.requestMaxDistance) {
                APFLog(@"🔧 Modify IN-PLACE: %ldm → %ldm", (long)oldDist, (long)p.requestMaxDistance);
            }
            return YES;
        }
        return NO;
    } @catch(NSException *e) {
        APFLog(@"❌ modifyRequestInPlace lỗi: %@", e);
        return NO;
    }
}

// ===== SEND VIA HANDLER =====
static void sendViaHandler(NSString *url, NSDictionary *bodyDict) {
    if (!gHandler || !gSavedRequest) {
        APFLog(@"❌ Không có handler/template");
        return;
    }
    @try {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        req.HTTPMethod = @"POST";
        req.timeoutInterval = 10.0;
        NSDictionary *oh = [gSavedRequest allHTTPHeaderFields];
        NSDictionary *nh = refreshHeadersWithCurrentTime(oh);
        for (NSString *k in nh) [req setValue:nh[k] forHTTPHeaderField:k];
        
        NSData *bd = [NSJSONSerialization dataWithJSONObject:bodyDict options:0 error:nil];
        req.HTTPBody = bd;
        [req setValue:[NSString stringWithFormat:@"%lu", (unsigned long)bd.length] forHTTPHeaderField:@"Content-Length"];
        
        [gHandler sendRequest:req withDelegate:gDelegate];
    } @catch(NSException *e) {
        APFLog(@"❌ sendViaHandler exception: %@", e);
    }
}

// ===== TEST FREE-PICK =====
static void testFreePick(void) {
    if (!gHandler || !gSavedRequest) {
        APFLog(@"❌ TEST: Chưa sẵn sàng — vào Free Pick trước");
        return;
    }
    APFLog(@"═══════════════════════════");
    APFLog(@"🧪 TEST FREE-PICK (/pick)");
    APFLog(@"═══════════════════════════");
    gTestMode = 1;
    NSInteger fakeOrderId = 999999999;
    NSDictionary *body = @{@"delivery_order_id": @(fakeOrderId)};
    APFLog(@"📤 Body: %@", body);
    sendViaHandler(kPickUrl, body);
}

// ===== TEST MPICK =====
static void testMPick(void) {
    if (!gHandler || !gSavedRequest) {
        APFLog(@"❌ TEST: Chưa sẵn sàng — vào Free Pick trước");
        return;
    }
    APFLog(@"═══════════════════════════");
    APFLog(@"🧪 TEST MPICK (/mpick)");
    APFLog(@"═══════════════════════════");
    gTestMode = 2;
    NSString *fakeGroupCode = [NSString stringWithFormat:@"TESTFAKE%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSArray *fakeIds = @[@(999999991), @(999999992), @(999999993)];
    NSDictionary *body = @{
        @"pre_group_code": fakeGroupCode,
        @"delivery_order_ids": fakeIds
    };
    APFLog(@"📤 Body: %@", body);
    sendViaHandler(kMPickUrl, body);
}

// ===== PICK SINGLE =====
static void sendPickSingle(NSInteger deliveryOrderId, NSInteger price) {
    if (!gHandler) { [APFMenu notifyPickFailed:@"Không có handler"]; return; }
    if (!gSavedRequest) { [APFMenu notifyPickFailed:@"Chưa capture request"]; return; }
    @try {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kPickUrl]];
        req.HTTPMethod = @"POST";
        req.timeoutInterval = 10.0;
        NSDictionary *oh = [gSavedRequest allHTTPHeaderFields];
        NSDictionary *nh = refreshHeadersWithCurrentTime(oh);
        for (NSString *k in nh) [req setValue:nh[k] forHTTPHeaderField:k];
        NSData *bd = [NSJSONSerialization dataWithJSONObject:@{@"delivery_order_id": @(deliveryOrderId)} options:0 error:nil];
        req.HTTPBody = bd;
        [req setValue:[NSString stringWithFormat:@"%lu", (unsigned long)bd.length] forHTTPHeaderField:@"Content-Length"];
        gLastPickedInfo = [NSString stringWithFormat:@"Đơn #%ld", (long)deliveryOrderId];
        gLastPickedPrice = price;
        [gHandler sendRequest:req withDelegate:gDelegate];
        APFLog(@"🎯 PICK SINGLE — #%ld (%@)", (long)deliveryOrderId, fmtPrice(price));
    } @catch(NSException *e) {}
}

// ===== PICK GROUP =====
static void sendPickGroup(NSString *preGroupCode, NSArray *ids, NSInteger price, NSInteger count) {
    if (!gHandler || !gSavedRequest) { [APFMenu notifyPickFailed:@"Chưa sẵn sàng"]; return; }
    @try {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kMPickUrl]];
        req.HTTPMethod = @"POST";
        req.timeoutInterval = 10.0;
        NSDictionary *oh = [gSavedRequest allHTTPHeaderFields];
        NSDictionary *nh = refreshHeadersWithCurrentTime(oh);
        for (NSString *k in nh) [req setValue:nh[k] forHTTPHeaderField:k];
        NSDictionary *body = @{@"pre_group_code": preGroupCode, @"delivery_order_ids": ids};
        NSData *bd = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        req.HTTPBody = bd;
        [req setValue:[NSString stringWithFormat:@"%lu", (unsigned long)bd.length] forHTTPHeaderField:@"Content-Length"];
        gLastPickedInfo = [NSString stringWithFormat:@"Chùm %ld đơn", (long)count];
        gLastPickedPrice = price;
        [gHandler sendRequest:req withDelegate:gDelegate];
        APFLog(@"🎯 MPICK — %@ (%ld đơn, %@)", preGroupCode, (long)count, fmtPrice(price));
    } @catch(NSException *e) {}
}

// ===== RESEND =====
static void resendRequest(void) {
    APFPrefs *p = [APFPrefs shared];
    if (!p.enabled || !p.autoRefresh || gStopped) return;
    if (!gHandler || !gSavedRequest) return;
    NSTimeInterval age = -[gSavedTime timeIntervalSinceNow];
    if (age > p.maxRequestAge) return;
    @try {
        NSMutableURLRequest *copy = [gSavedRequest mutableCopy];
        NSDictionary *oh = [gSavedRequest allHTTPHeaderFields];
        NSDictionary *nh = refreshHeadersWithCurrentTime(oh);
        for (NSString *k in nh) [copy setValue:nh[k] forHTTPHeaderField:k];
        NSData *bodyData = gSavedRequest.HTTPBody;
        if (bodyData && bodyData.length > 5) {
            NSError *err = nil;
            id json = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:&err];
            if (json && !err && [json isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *body = [json mutableCopy];
                body[@"max_distance"] = @(p.requestMaxDistance);
                if (p.preferredCategories && p.preferredCategories.count > 0) {
                    body[@"ref_order_category_list"] = p.preferredCategories;
                }
                NSData *newBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
                copy.HTTPBody = newBody;
                [copy setValue:[NSString stringWithFormat:@"%lu", (unsigned long)newBody.length] forHTTPHeaderField:@"Content-Length"];
            }
        }
        [gHandler sendRequest:copy withDelegate:gDelegate];
        gRefreshCount++;
        APFLog(@"🔄 Refresh #%ld (age %.1fs) — dist=%ldm", (long)gRefreshCount, age, (long)p.requestMaxDistance);
    } @catch(NSException *e) {}
}

static void stopTimer(void) {
    if (gTimerSource) {
        dispatch_source_cancel(gTimerSource);
        gTimerSource = nil;
        APFLog(@"⏹ Timer OFF");
    }
}

static void startTimer(void) {
    if (gTimerSource) return;
    if (!gSavedRequest) return;
    APFPrefs *p = [APFPrefs shared];
    uint64_t intervalMs = p.refreshIntervalMs;
    if (intervalMs < 100) intervalMs = 100;
    if (intervalMs > 10000) intervalMs = 10000;
    uint64_t intervalNs = intervalMs * NSEC_PER_MSEC;
    gTimerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gTimerSource, dispatch_time(DISPATCH_TIME_NOW, intervalNs), intervalNs, NSEC_PER_MSEC * 10);
    dispatch_source_set_event_handler(gTimerSource, ^{ resendRequest(); });
    dispatch_resume(gTimerSource);
    APFLog(@"⏱ Timer ON — %llums", intervalMs);
}

static void checkAndStartTimer(void) {
    APFPrefs *p = [APFPrefs shared];
    if (!gSavedRequest || gStopped) return;
    if (!p.enabled || !p.autoRefresh) return;
    if (!gTimerSource) startTimer();
}

// ===== PROCESS ORDER LIST =====
static void processOrderList(NSData *data) {
    APFPrefs *p = [APFPrefs shared];
    @try {
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:[NSDictionary class]]) { APFLog(@"❌ JSON lỗi"); return; }
        NSDictionary *d = json[@"data"];
        if (![d isKindOfClass:[NSDictionary class]]) { APFLog(@"❌ Không có data"); return; }
        NSArray *orders = d[@"orders"];
        if (![orders isKindOfClass:[NSArray class]]) { APFLog(@"📭 orders không phải array"); return; }
        
        NSUInteger count = orders.count;
        if (count == 0) { APFLog(@"📭 0 đơn"); return; }
        APFLog(@"📋 %lu đơn — quét filter (autoPick:%d)", (unsigned long)count, p.autoPick);
        
        NSDictionary *bestOrder = nil;
        NSInteger bestEarn = 0;
        NSInteger bestDist = 0;
        NSInteger passCount = 0, failCount = 0;
        
        for (NSDictionary *o in orders) {
            @try {
                NSString *reason = [APFFilter checkOrder:o];
                NSArray *dos = o[@"delivery_orders"];
                if (![dos isKindOfClass:[NSArray class]] || dos.count == 0) continue;
                
                NSInteger oid = [dos[0][@"delivery_order_id"] integerValue];
                NSInteger earn = [o[@"total_earnings_amount"] integerValue];
                NSInteger dist = [o[@"delivery_distance"] integerValue];
                NSInteger subCount = dos.count;
                NSString *groupCode = o[@"pre_group_code"];
                NSString *typeStr = (groupCode && subCount > 1) ? [NSString stringWithFormat:@"CHÙM %ld", (long)subCount] : @"lẻ";
                
                if (reason) {
                    failCount++;
                    APFLog(@"  ✗ %ld (%@, %@) — %@", (long)oid, fmtPrice(earn), typeStr, reason);
                    continue;
                }
                passCount++;
                APFLog(@"  ✅ PASS: %ld (%@, %@) / %.1fkm", (long)oid, fmtPrice(earn), typeStr, (double)dist/1000.0);
                
                NSInteger score = earn;
                if (groupCode && subCount > 1) score += 50000;
                if (score > bestEarn) {
                    bestOrder = o;
                    bestEarn = score;
                    bestDist = dist;
                }
            } @catch(NSException *e) {}
        }
        
        APFLog(@"📊 Kết quả: %ld pass / %ld fail", (long)passCount, (long)failCount);
        
        if (passCount == 0 || !bestOrder) { APFLog(@"⚠️ Không có đơn khớp"); return; }
        
        NSArray *dos = bestOrder[@"delivery_orders"];
        NSString *groupCode = bestOrder[@"pre_group_code"];
        NSInteger subCount = dos.count;
        NSInteger bestOid = [dos[0][@"delivery_order_id"] integerValue];
        BOOL isGroup = (groupCode != nil && subCount > 1);
        
        APFLog(@"  ✅ CHỌN: %@ / %.1fkm / %@",
               isGroup ? [NSString stringWithFormat:@"CHÙM %ld ĐƠN", (long)subCount] : [NSString stringWithFormat:@"ĐƠN #%ld", (long)bestOid],
               (double)bestDist/1000.0, fmtPrice(bestEarn));
        
        [APFMenu notifyMatchDetail:bestOrder];
        
        if (!p.autoPick) { APFLog(@"  ⏸ autoPick TẮT"); return; }
        if (!p.enabled || gStopped) return;
        if (gPickedCount >= p.maxOrdersPerSession) { APFLog(@"  ⏸ Đạt max đơn"); return; }
        if (gLastPickTime) {
            NSTimeInterval e = -[gLastPickTime timeIntervalSinceNow];
            if (e < p.cooldown) { APFLog(@"  ⏸ Cooldown %.1fs", e); return; }
        }
        
        NSString *key = isGroup ? groupCode : [NSString stringWithFormat:@"%ld", (long)bestOid];
        if ([gPickedIds containsObject:key]) { APFLog(@"  ⏭ Đã pick rồi"); return; }
        [gPickedIds addObject:key];
        
        if (isGroup) {
            NSMutableArray *ids = [NSMutableArray array];
            for (NSDictionary *d in dos) {
                [ids addObject:@([d[@"delivery_order_id"] integerValue])];
            }
            sendPickGroup(groupCode, ids, bestEarn, subCount);
        } else {
            sendPickSingle(bestOid, bestEarn);
        }
    } @catch(NSException *e) { APFLog(@"❌ Parse: %@", e); }
}

// ===== HOOK RCTHTTPRequestHandler =====
%hook RCTHTTPRequestHandler

- (id)sendRequest:(NSURLRequest *)request withDelegate:(id)delegate {
    @try {
        if (!gHandler) { gHandler = (RCTHTTPRequestHandler *)self; APFLog(@"✅ Handler"); }
        if (!gDelegate && delegate) gDelegate = delegate;
        
        if (request && [request isKindOfClass:[NSURLRequest class]]) {
            NSString *url = request.URL.absoluteString;
            if ([url containsString:@"free-pick/get-order-list"]) {
                BOOL isOurs = NO;
                if (gSavedRequest && (__bridge void *)gSavedRequest == (__bridge void *)request) {
                    isOurs = YES;
                }
                if ([request isKindOfClass:[NSMutableURLRequest class]]) {
                    modifyRequestInPlace(request);
                }
                if (!isOurs) {
                    gSavedRequest = [request mutableCopy];
                    gSavedTime = [NSDate date];
                    APFLog(@"📥 Capture request (%lu headers)", (unsigned long)[gSavedRequest allHTTPHeaderFields].count);
                    checkAndStartTimer();
                }
            }
        }
    } @catch(NSException *e) {}
    return %orig;
}

- (void)shpNetworkingModule:(id)module shpRequest:(id)request didReceiveData:(NSData *)data {
    %orig;
    @try {
        if (!data || data.length == 0) return;
        NSString *url = nil;
        NSInteger status = 0;
        @try {
            if ([request respondsToSelector:@selector(response)]) {
                id resp = [request response];
                if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
                    url = [(NSHTTPURLResponse *)resp URL].absoluteString;
                    status = [(NSHTTPURLResponse *)resp statusCode];
                }
            }
        } @catch(NSException *e) {}
        if (!url) return;
        
        if ([url containsString:@"free-pick/get-order-list"]) {
            gResponseIndex++;
            APFLog(@"📦 Response #%ld [%ld] %lu bytes", (long)gResponseIndex, (long)status, (unsigned long)data.length);
            if (status != 200) return;
            
            NSData *decoded = gunzipData(data);
            if (!decoded) return;
            if (decoded.length != data.length) {
                APFLog(@"🔓 Giải nén: %lu → %lu bytes", (unsigned long)data.length, (unsigned long)decoded.length);
            }
            NSString *c = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
            if (!c) return;
            
            if (![gLastUrl isEqualToString:url] || decoded.length < 500) {
                gResponseBuffer = [NSMutableString string];
                gLastUrl = url;
            }
            if (!gResponseBuffer) gResponseBuffer = [NSMutableString string];
            [gResponseBuffer appendString:c];
            
            NSString *trimmed = [gResponseBuffer stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (trimmed.length > 0 && [trimmed hasSuffix:@"}"]) {
                NSData *full = [gResponseBuffer dataUsingEncoding:NSUTF8StringEncoding];
                NSError *err = nil;
                id json = [NSJSONSerialization JSONObjectWithData:full options:0 error:&err];
                if (json && !err) {
                    [gResponseBuffer setString:@""];
                    processOrderList(full);
                }
            }
        } else if ([url containsString:@"free-pick/pick"] || [url containsString:@"free-pick/mpick"]) {
            @try {
                NSData *decoded = gunzipData(data);
                if (!decoded) decoded = data;
                
                BOOL isMPick = [url containsString:@"mpick"];
                NSString *endpointName = isMPick ? @"MPICK" : @"FREE-PICK";
                
                // ⭐ TEST MODE
                if (gTestMode > 0) {
                    NSString *responseStr = [[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding];
                    APFLog(@"═══════════════════════════");
                    APFLog(@"🧪 TEST %@ RESPONSE [%ld]:", endpointName, (long)status);
                    APFLog(@"%@", responseStr);
                    APFLog(@"═══════════════════════════");
                    
                    NSDictionary *testJson = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
                    NSInteger bizCode = [testJson[@"code"] integerValue];
                    NSString *bizMsg = testJson[@"msg"] ?: @"?";
                    
                    if (status == 200 && bizCode == 0) {
                        APFLog(@"✅✅✅ TEST PASS — endpoint %@ OK", endpointName);
                    } else if ([bizMsg isEqualToString:@"error_order_not_found"]) {
                        APFLog(@"✅✅✅ TEST PASS — endpoint %@ OK (đơn giả không tồn tại)", endpointName);
                    } else if (bizCode == 100000) {
                        APFLog(@"❌ TEST FAIL — body sai format");
                    } else if (status == 404) {
                        APFLog(@"❌ TEST FAIL — endpoint không tồn tại");
                    } else {
                        APFLog(@"⚠️ TEST: status=%ld, code=%ld, msg=%@", (long)status, (long)bizCode, bizMsg);
                    }
                    
                    gTestMode = 0;
                    return;
                }
                
                // Pick bình thường
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:nil];
                NSInteger code = [json[@"code"] integerValue];
                NSString *msg = json[@"msg"] ?: @"?";
                
                if (status != 200) {
                    NSString *reason = [NSString stringWithFormat:@"Server lỗi [%ld]", (long)status];
                    APFLog(@"❌ HTTP fail [%ld]", (long)status);
                    [APFMenu notifyPickFailed:reason];
                    return;
                }
                if (code == 0) {
                    APFLog(@"✅✅✅ PICK OK!");
                    gPickedCount++;
                    gLastPickTime = [NSDate date];
                    APFPrefs *p = [APFPrefs shared];
                    [APFMenu notifySuccessDetail:gLastPickedInfo ?: @"Đơn đã pick" price:gLastPickedPrice];
                    if (p.stopAfterPick) { gStopped = YES; stopTimer(); }
                } else {
                    NSString *reason = msg.length > 0 ? msg : [NSString stringWithFormat:@"Code %ld", (long)code];
                    APFLog(@"❌ Pick fail: %@", reason);
                    [APFMenu notifyPickFailed:reason];
                }
            } @catch(NSException *e) {}
        }
    } @catch(NSException *e) {}
}
%end

// ===== GESTURE MENU =====
%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    id r = %orig;
    UIWindow *w = (UIWindow *)r;
    if (w && ![NSStringFromClass(w.class) containsString:@"InAppMessage"]) {
        BOOL has = NO;
        for (UIGestureRecognizer *g in w.gestureRecognizers) {
            if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
                UITapGestureRecognizer *t = (UITapGestureRecognizer *)g;
                if (t.numberOfTouchesRequired == 3 && t.numberOfTapsRequired == 2) { has = YES; break; }
            }
        }
        if (!has) {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[APFMenu class] action:@selector(presentMenu)];
            tap.numberOfTouchesRequired = 3;
            tap.numberOfTapsRequired = 2;
            tap.cancelsTouchesInView = NO;
            [w addGestureRecognizer:tap];
        }
    }
    return r;
}
%end

// ===== APP LIFECYCLE =====
%hook UIApplication
- (void)applicationDidBecomeActive:(UIApplication *)app {
    %orig;
    static BOOL asked = NO;
    if (!asked) { asked = YES; [APFMenu requestNotificationPermission]; }
    [[APFPrefs shared] load];
    APFPrefs *p = [APFPrefs shared];
    gStopped = NO;
    gPickedCount = 0;
    [gPickedIds removeAllObjects];
    APFLog(@"▶️ Active | dist=%ldm, refresh=%ldms", (long)p.requestMaxDistance, (long)p.refreshIntervalMs);
    checkAndStartTimer();
}
- (void)applicationWillResignActive:(UIApplication *)app {
    %orig;
    [[APFPrefs shared] save];
}
- (void)applicationWillTerminate:(UIApplication *)app {
    %orig;
    [[APFPrefs shared] save];
}
%end

// ===== INIT =====
%ctor {
    gPickedIds = [NSMutableSet set];
    gResponseBuffer = [NSMutableString string];
    @try {
        [[APFPrefs shared] load];
        APFPrefs *p = [APFPrefs shared];
        APFLog(@"⚡ AutoPick v15 | dist=%ldm refresh=%ldms", (long)p.requestMaxDistance, (long)p.refreshIntervalMs);
        
        // ⭐ Đăng ký callback test
        [APFMenu setTestFreePickCallback:^{
            dispatch_async(dispatch_get_main_queue(), ^{ testFreePick(); });
        }];
        [APFMenu setTestMPickCallback:^{
            dispatch_async(dispatch_get_main_queue(), ^{ testMPick(); });
        }];
    } @catch(NSException *e) {}
}