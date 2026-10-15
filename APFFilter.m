#import "APFFilter.h"
#import "APFPrefs.h"

static NSString *fmtPrice(NSInteger price) {
    if (price >= 1000000) return [NSString stringWithFormat:@"%.1fM", (double)price/1000000];
    if (price >= 1000) return [NSString stringWithFormat:@"%.1fk", (double)price/1000];
    return [NSString stringWithFormat:@"%ldđ", (long)price];
}

@implementation APFFilter

+ (NSString *)normalize:(NSString *)str {
    if (!str || str.length == 0) return @"";
    NSMutableString *result = [NSMutableString stringWithString:str];
    CFStringTransform((__bridge CFMutableStringRef)result, NULL, kCFStringTransformStripDiacritics, NO);
    return [[result lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (BOOL)address:(NSString *)addr matchesDistricts:(NSArray *)districts {
    if (!addr || districts.count == 0) return NO;
    NSString *normAddr = [self normalize:addr];
    if (normAddr.length == 0) return NO;
    for (NSString *d in districts) {
        if (![d isKindOfClass:[NSString class]]) continue;
        NSString *normD = [self normalize:d];
        if (normD.length == 0) continue;
        if ([normAddr containsString:normD]) return YES;
    }
    return NO;
}

+ (NSString *)checkOrder:(NSDictionary *)order {
    APFPrefs *p = [APFPrefs shared];
    @try {
        NSInteger earnings = [order[@"total_earnings_amount"] integerValue];
        NSInteger distance = [order[@"delivery_distance"] integerValue];
        if (earnings < p.minPrice) return [NSString stringWithFormat:@"Giá thấp"];
        if (p.maxPrice > 0 && earnings > p.maxPrice) return @"Giá cao";
        if (distance < p.minDistance) return @"Quá gần";
        if (p.maxDistance > 0 && distance > p.maxDistance) return [NSString stringWithFormat:@"Xa quá"];
        NSInteger cod = 0;
        NSArray *inner = order[@"orders"];
        if ([inner isKindOfClass:[NSArray class]] && inner.count > 0) cod = [inner[0][@"cod_amount"] integerValue];
        if (cod < p.minCOD) return @"COD thấp";
        if (p.maxCOD > 0 && cod > p.maxCOD) return @"COD cao";
        if (p.preferredCategories.count > 0) {
            NSArray *dos = order[@"delivery_orders"];
            NSInteger cat = 0;
            if ([dos isKindOfClass:[NSArray class]] && dos.count > 0) {
                id c = dos[0][@"ref_order_category"];
                if (c) cat = [c integerValue];
            }
            BOOL found = NO;
            for (NSNumber *n in p.preferredCategories) if ([n integerValue] == cat) { found = YES; break; }
            if (!found) return [NSString stringWithFormat:@"Loại %ld", (long)cat];
        }
        if (p.districtFilterMode > 0 && p.preferredDistricts.count > 0) {
            NSArray *dos = order[@"delivery_orders"];
            if ([dos isKindOfClass:[NSArray class]] && dos.count > 0) {
                NSString *pickupAddr = nil;
                NSDictionary *pu = dos[0][@"pickup_address_info"];
                if ([pu isKindOfClass:[NSDictionary class]]) pickupAddr = pu[@"address"];
                NSString *dropoffAddr = nil;
                NSDictionary *last = dos[dos.count - 1];
                NSDictionary *do_ = last[@"dropoff_address_info"];
                if ([do_ isKindOfClass:[NSDictionary class]]) dropoffAddr = do_[@"address"];
                BOOL puM = [self address:pickupAddr matchesDistricts:p.preferredDistricts];
                BOOL doM = [self address:dropoffAddr matchesDistricts:p.preferredDistricts];
                BOOL pass = NO;
                if (p.districtFilterMode == 1) pass = puM;
                else if (p.districtFilterMode == 2) pass = doM;
                else if (p.districtFilterMode == 3) pass = puM || doM;
                if (!pass) return @"Quận khác";
            }
        }
        return nil;
    } @catch(NSException *e) { return @"Lỗi"; }
}
@end