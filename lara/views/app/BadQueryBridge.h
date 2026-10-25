#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BadQueryLease : NSObject
@property (nonatomic, copy, readonly) NSString *targetPath;
@property (nonatomic, readonly, getter=isActive) BOOL active;

+ (nullable instancetype)leaseForPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (void)invalidate;
@end

FOUNDATION_EXPORT BOOL BadQueryBridgeAvailable(void);

NS_ASSUME_NONNULL_END