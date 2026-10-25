#import "GestaltAccess.h"
#import "BadQueryBridge.h"
#import <sys/sysctl.h>
#import <fcntl.h>
#import <unistd.h>

static NSString * const kGestaltPlistFileName = @"com.apple.MobileGestalt.plist";
static NSString * const kMobileGestaltCacheDirectory = @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches";
static NSString * const kBadQueryMobileGestaltCacheDirectory = @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches";

static NSError *GestaltError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.gestaltedit.access" code:code userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL GestaltCanOpenReadWrite(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return NO;
    close(fd);
    return YES;
}

static BOOL GestaltWriteAll(int fd, NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    while (remaining > 0) {
        ssize_t written = write(fd, bytes, remaining);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return NO;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    return YES;
}

@interface GestaltAccess ()
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, copy) NSString *plistPath;
@property (nonatomic, assign) NSPropertyListFormat lastReadFormat;
@end

@implementation GestaltAccess {
    BadQueryLease *_activeBadQueryLease;
}

+ (instancetype)shared {
    static GestaltAccess *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ shared = [GestaltAccess new]; });
    return shared;
}

+ (NSString *)currentOSBuild {
    size_t length = 0;
    if (sysctlbyname("kern.osversion", NULL, &length, NULL, 0) != 0 || length == 0) return @"";
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (sysctlbyname("kern.osversion", data.mutableBytes, &length, NULL, 0) != 0) return @"";
    return [NSString stringWithUTF8String:data.bytes] ?: @"";
}

+ (BOOL)isRunningSupportedOS {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *build = self.currentOSBuild;
    return version.majorVersion == 27 && (
        [build isEqualToString:@"24A5355q"] ||
        [build isEqualToString:@"24A5370h"] ||
        [build isEqualToString:@"24A5380h"] ||
        [build isEqualToString:@"24A5380i"] ||
        [build isEqualToString:@"24A5380l"] ||
        [build isEqualToString:@"24A5390f"]
    );
}

- (BOOL)connectWithError:(NSError * _Nullable * _Nullable)error {
    if (!GestaltAccess.isRunningSupportedOS) {
        if (error) *error = GestaltError(0, @"GestaltAccess supports only iOS/iPadOS 27 beta 1–4.");
        return NO;
    }
    if (self.isConnected && _activeBadQueryLease.isActive && self.plistPath.length > 0) {
        if (error) *error = nil; return YES;
    }
    if (!BadQueryBridgeAvailable()) {
        if (error) *error = GestaltError(1, @"bad_query is unavailable.");
        return NO;
    }
    
    [_activeBadQueryLease invalidate];
    _activeBadQueryLease = nil;
    self.isConnected = NO;
    self.plistPath = nil;
    
    NSString *badQueryTarget = [kBadQueryMobileGestaltCacheDirectory stringByAppendingPathComponent:kGestaltPlistFileName];
    NSString *badQueryPlist = [kMobileGestaltCacheDirectory stringByAppendingPathComponent:kGestaltPlistFileName];
    NSError *badQueryDetail = nil;
    BadQueryLease *badQueryLease = [BadQueryLease leaseForPath:badQueryTarget error:&badQueryDetail];
    
    if (!badQueryLease) {
        if (error) *error = GestaltError(2, badQueryDetail.localizedDescription ?: @"bad_query failed.");
        return NO;
    }
    if (!GestaltCanOpenReadWrite(badQueryPlist)) {
        [badQueryLease invalidate];
        if (error) *error = GestaltError(3, @"bad_query acquired a sandbox extension, but the plist is not writable.");
        return NO;
    }
    
    _activeBadQueryLease = badQueryLease;
    self.isConnected = YES;
    self.plistPath = badQueryPlist;
    if (error) *error = nil;
    return YES;
}

- (NSData *)readGestaltDataWithError:(NSError * _Nullable * _Nullable)error {
    if (![self connectWithError:error]) return nil;
    NSData *data = [NSData dataWithContentsOfFile:self.plistPath options:NSDataReadingMappedIfSafe error:error];
    if (!data) return nil;
    if (error) *error = nil;
    return data;
}

- (NSDictionary *)readGestaltWithError:(NSError * _Nullable * _Nullable)error {
    NSData *data = [self readGestaltDataWithError:error];
    if (!data) return nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:&format error:error];
    if (![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = GestaltError(5, @"The plist top level is not a dictionary.");
        return nil;
    }
    self.lastReadFormat = format;
    return plist;
}

- (BOOL)saveGestalt:(NSDictionary *)plist error:(NSError * _Nullable * _Nullable)error {
    if (![self connectWithError:error]) return NO;
    if (![plist isKindOfClass:NSDictionary.class]) {
        if (error) *error = GestaltError(6, @"The content to save is not a dictionary.");
        return NO;
    }
    
    NSPropertyListFormat format = self.lastReadFormat;
    if (format != NSPropertyListXMLFormat_v1_0 && format != NSPropertyListBinaryFormat_v1_0)
        format = NSPropertyListBinaryFormat_v1_0;
    
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:format options:0 error:error];
    if (!data) return NO;
    
    NSString *targetPath = self.plistPath;
    NSData *original = [NSData dataWithContentsOfFile:targetPath options:0 error:error];
    if (!original) return NO;
    
    int fd = open(targetPath.fileSystemRepresentation, O_WRONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) {
        if (error) *error = GestaltError(9, [NSString stringWithFormat:@"Failed to open the plist (errno=%d).", errno]);
        return NO;
    }
    
    BOOL wrote = ftruncate(fd, 0) == 0 &&
                 lseek(fd, 0, SEEK_SET) == 0 &&
                 GestaltWriteAll(fd, data) &&
                 fsync(fd) == 0;
    int writeErrno = errno;
    
    if (!wrote) {
        ftruncate(fd, 0);
        lseek(fd, 0, SEEK_SET);
        GestaltWriteAll(fd, original);
        fsync(fd);
        close(fd);
        if (error) *error = GestaltError(10, [NSString stringWithFormat:@"Failed to write the plist (errno=%d).", writeErrno]);
        return NO;
    }
    
    close(fd);
    
    NSData *verification = [NSData dataWithContentsOfFile:targetPath];
    if (![verification isEqualToData:data]) {
        if (error) *error = GestaltError(11, @"Post-write verification failed.");
        return NO;
    }
    
    if (error) *error = nil;
    return YES;
}
@end