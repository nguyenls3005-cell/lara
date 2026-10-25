#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GestaltAccess : NSObject
+ (instancetype)shared;
+ (BOOL)isRunningSupportedOS;
+ (NSString *)currentOSBuild;
- (BOOL)connectWithError:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary *)readGestaltWithError:(NSError * _Nullable * _Nullable)error;
- (nullable NSData *)readGestaltDataWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)saveGestalt:(NSDictionary *)plist error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END