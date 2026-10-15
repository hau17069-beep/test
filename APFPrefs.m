#import "APFPrefs.h"

#define kSuiteName @"vn.foody.autopick"

@implementation APFPrefs

+ (instancetype)shared {
    static APFPrefs *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inst = [[APFPrefs alloc] init];
        [inst setDefaults];
        [inst load];
    });
    return inst;
}

- (NSUserDefaults *)defaults {
    NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
    if (!ud) ud = [NSUserDefaults standardUserDefaults];
    return ud;
}

- (void)setDefaults {
    _enabled = YES;
    _autoRefresh = YES;
    _autoPick = YES;
    _stopAfterPick = NO;
    _systemNotify = YES;
    _notifyOnMatch = YES;
    _notifyOnSuccess = YES;
    _soundOnMatch = YES;
    _vibrateOnMatch = YES;
    _refreshIntervalMs = 2000;
    _maxRequestAge = 25;
    _requestMaxDistance = 4000;
    _minPrice = 0;
    _maxPrice = 0;
    _minDistance = 0;
    _maxDistance = 50000;
    _minCOD = 0;
    _maxCOD = 0;
    _maxOrdersPerSession = 5;
    _cooldown = 1.5;
    _preferredCategories = @[@(6)];
    _preferredDistricts = @[];
    _districtFilterMode = 0;
}

- (void)load {
    NSUserDefaults *ud = [self defaults];
    id v;
    v = [ud objectForKey:@"enabled"]; if (v) _enabled = [v boolValue];
    v = [ud objectForKey:@"autoRefresh"]; if (v) _autoRefresh = [v boolValue];
    v = [ud objectForKey:@"autoPick"]; if (v) _autoPick = [v boolValue];
    v = [ud objectForKey:@"stopAfterPick"]; if (v) _stopAfterPick = [v boolValue];
    v = [ud objectForKey:@"systemNotify"]; if (v) _systemNotify = [v boolValue];
    v = [ud objectForKey:@"notifyOnMatch"]; if (v) _notifyOnMatch = [v boolValue];
    v = [ud objectForKey:@"notifyOnSuccess"]; if (v) _notifyOnSuccess = [v boolValue];
    v = [ud objectForKey:@"soundOnMatch"]; if (v) _soundOnMatch = [v boolValue];
    v = [ud objectForKey:@"vibrateOnMatch"]; if (v) _vibrateOnMatch = [v boolValue];
    v = [ud objectForKey:@"refreshIntervalMs"]; if (v) _refreshIntervalMs = [v integerValue];
    v = [ud objectForKey:@"maxRequestAge"]; if (v) _maxRequestAge = [v integerValue];
    v = [ud objectForKey:@"requestMaxDistance"]; if (v) _requestMaxDistance = [v integerValue];
    v = [ud objectForKey:@"minPrice"]; if (v) _minPrice = [v integerValue];
    v = [ud objectForKey:@"maxPrice"]; if (v) _maxPrice = [v integerValue];
    v = [ud objectForKey:@"minDistance"]; if (v) _minDistance = [v integerValue];
    v = [ud objectForKey:@"maxDistance"]; if (v) _maxDistance = [v integerValue];
    v = [ud objectForKey:@"minCOD"]; if (v) _minCOD = [v integerValue];
    v = [ud objectForKey:@"maxCOD"]; if (v) _maxCOD = [v integerValue];
    v = [ud objectForKey:@"maxOrders"]; if (v) _maxOrdersPerSession = [v integerValue];
    v = [ud objectForKey:@"cooldown"]; if (v) _cooldown = [v doubleValue];
    v = [ud objectForKey:@"preferredCategories"]; if (v) _preferredCategories = v;
    v = [ud objectForKey:@"preferredDistricts"]; if (v) _preferredDistricts = v;
    v = [ud objectForKey:@"districtFilterMode"]; if (v) _districtFilterMode = [v integerValue];
    
    if (_refreshIntervalMs < 100) _refreshIntervalMs = 100;
    if (_refreshIntervalMs > 10000) _refreshIntervalMs = 10000;
    if (_requestMaxDistance < 500) _requestMaxDistance = 500;
    if (_requestMaxDistance > 50000) _requestMaxDistance = 50000;
}

- (void)save {
    NSUserDefaults *ud = [self defaults];
    [ud setBool:_enabled forKey:@"enabled"];
    [ud setBool:_autoRefresh forKey:@"autoRefresh"];
    [ud setBool:_autoPick forKey:@"autoPick"];
    [ud setBool:_stopAfterPick forKey:@"stopAfterPick"];
    [ud setBool:_systemNotify forKey:@"systemNotify"];
    [ud setBool:_notifyOnMatch forKey:@"notifyOnMatch"];
    [ud setBool:_notifyOnSuccess forKey:@"notifyOnSuccess"];
    [ud setBool:_soundOnMatch forKey:@"soundOnMatch"];
    [ud setBool:_vibrateOnMatch forKey:@"vibrateOnMatch"];
    [ud setInteger:_refreshIntervalMs forKey:@"refreshIntervalMs"];
    [ud setInteger:_maxRequestAge forKey:@"maxRequestAge"];
    [ud setInteger:_requestMaxDistance forKey:@"requestMaxDistance"];
    [ud setInteger:_minPrice forKey:@"minPrice"];
    [ud setInteger:_maxPrice forKey:@"maxPrice"];
    [ud setInteger:_minDistance forKey:@"minDistance"];
    [ud setInteger:_maxDistance forKey:@"maxDistance"];
    [ud setInteger:_minCOD forKey:@"minCOD"];
    [ud setInteger:_maxCOD forKey:@"maxCOD"];
    [ud setInteger:_maxOrdersPerSession forKey:@"maxOrders"];
    [ud setDouble:_cooldown forKey:@"cooldown"];
    [ud setObject:_preferredCategories ?: @[] forKey:@"preferredCategories"];
    [ud setObject:_preferredDistricts ?: @[] forKey:@"preferredDistricts"];
    [ud setInteger:_districtFilterMode forKey:@"districtFilterMode"];
    [ud synchronize];
}

- (void)reset {
    [self setDefaults];
    [self save];
}

@end