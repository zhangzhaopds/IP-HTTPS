//
//  NetworkManager.m
//  IPHTTPS_Demo
//
//  Created by 张昭 on 2019/10/28.
//  Copyright © 2019 HeyFox. All rights reserved.
//

#import "NetworkManager.h"
#import <AFNetworking/AFNetworking.h>
#import "NetWorkRequestSerializer.h"

@implementation NetworkManager

- (instancetype)initWithBaseURL:(NSURL *)url sessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super initWithBaseURL:url sessionConfiguration:configuration];
    if (self) {
        self.requestSerializer = [NetWorkRequestSerializer serializer];
        self.responseSerializer = [AFHTTPResponseSerializer serializer];
        [self setupAuthAndRedirectionBlock];
    }
    return self;
}

- (void)setupAuthAndRedirectionBlock {
    __weak typeof(self) weakSelf = self;
    [self setSessionDidReceiveAuthenticationChallengeBlock:^NSURLSessionAuthChallengeDisposition(NSURLSession * _Nonnull session, NSURLAuthenticationChallenge * _Nonnull challenge, NSURLCredential *__autoreleasing  _Nullable * _Nullable credential) {
        if (!challenge) {
            return NSURLSessionAuthChallengePerformDefaultHandling;
        }
        NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        /*
         * 获取原始域名信息。
         */
        NSString *host = [weakSelf.requestSerializer.HTTPRequestHeaders objectForKey:@"host"];
        if (host) {
            NSLog(@"++++++++++++++host: %@", host);
        } else {
            host = challenge.protectionSpace.host;
        }
        
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            if ([weakSelf.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
                disposition = NSURLSessionAuthChallengeUseCredential;
            } else {
                disposition = NSURLSessionAuthChallengePerformDefaultHandling;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
        return disposition;
    }];
    
    [self setTaskDidReceiveAuthenticationChallengeBlock:^NSURLSessionAuthChallengeDisposition(NSURLSession * _Nonnull session, NSURLSessionTask * _Nonnull task, NSURLAuthenticationChallenge * _Nonnull challenge, NSURLCredential *__autoreleasing  _Nullable * _Nullable credential) {
        if (!challenge) {
            return NSURLSessionAuthChallengePerformDefaultHandling;
        }
        NSURLSessionAuthChallengeDisposition disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        /*
         * 获取原始域名信息。
         */
        NSString *host = [[task.currentRequest allHTTPHeaderFields] objectForKey:@"host"];
        if (host) {
            NSLog(@"++++++++++++++host: %@", host);
        } else {
            host = challenge.protectionSpace.host;
        }
        
        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
            *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            if ([weakSelf.securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:host]) {
                disposition = NSURLSessionAuthChallengeUseCredential;
            } else {
                disposition = NSURLSessionAuthChallengePerformDefaultHandling;
            }
        } else {
            disposition = NSURLSessionAuthChallengePerformDefaultHandling;
        }
        return disposition;
    }];
}

// MARK: - public request methods
- (nullable NSURLSessionDataTask *)NetGET:(NSString *)path
                               parameters:(nullable id)parameters
                                  success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                  failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure {
    NSMutableDictionary *parametersDict = [NSMutableDictionary dictionary];
    [parameters enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:NSDictionary.class]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
            NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [parametersDict setObject:json forKey:key];
        } else {
            [parametersDict setObject:obj forKey:key];
        }
    }];
    return [self GET:path parameters:[self queryDict:parametersDict] progress:nil success:success failure:failure];
}

- (nullable NSURLSessionDataTask *)NetGET:(NSString *)path
                               parameters:(nullable id)parameters
                                 progress:(nullable void (^)(NSProgress *downloadProgress))downloadProgress
                                  success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                  failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure{
    NSMutableDictionary *parametersDict = [NSMutableDictionary dictionary];
    [parameters enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if ([obj isKindOfClass:NSDictionary.class]) {
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
            NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            [parametersDict setObject:json forKey:key];
        } else {
            [parametersDict setObject:obj forKey:key];
        }
    }];
    return [self GET:path parameters:[self queryDict:parametersDict] progress:downloadProgress success:success failure:failure];
}

- (nullable NSURLSessionDataTask *)NetPOST:(NSString *)URLString
                                parameters:(nullable id)parameters
                                   success:(nullable void (^)(NSURLSessionDataTask *task, id responseObject))success
                                   failure:(nullable void (^)(NSURLSessionDataTask * __nullable task, NSError *error))failure {
    return [self POST:URLString parameters:[self queryDict:parameters] progress:nil success:success failure:failure];
}

// MARK: - Tools method and getters..

- (NSDictionary *)queryDict:(NSDictionary *)queryDict {
    NSMutableDictionary *paramDic = [NSMutableDictionary dictionary];
    [queryDict enumerateKeysAndObjectsUsingBlock:^(id _Nonnull key,
                                                   id _Nonnull obj,
                                                   BOOL *_Nonnull stop) {
        if (validString(obj) && validString(key)) {
            [paramDic setObject:obj forKey:key];
        }
    }];
    return paramDic;
}

static inline NSString *validString(NSString *para) {
    return [para isKindOfClass:NSString.class] && para.length ? para : nil;
}

// 证书校验
- (BOOL)evaluateServerTrust:(SecTrustRef)serverTrust
                  forDomain:(NSString *)domain {
    /*
     * 创建证书校验策略
     */
    NSMutableArray *policies = [NSMutableArray array];
    if (domain) {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateSSL(true, (__bridge CFStringRef)domain)];
    } else {
        [policies addObject:(__bridge_transfer id)SecPolicyCreateBasicX509()];
    }
    /*
     * 绑定校验策略到服务端的证书上
     */
    SecTrustSetPolicies(serverTrust, (__bridge CFArrayRef)policies);
    /*
     * 评估当前serverTrust是否可信任，
     * 官方建议在result = kSecTrustResultUnspecified 或 kSecTrustResultProceed
     * 的情况下serverTrust可以被验证通过，https://developer.apple.com/library/ios/technotes/tn2232/_index.html
     * 关于SecTrustResultType的详细信息请参考SecTrust.h
     */
    SecTrustResultType result;
    SecTrustEvaluate(serverTrust, &result);
    return (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);
}

// 校验host是否是ip地址.
+ (BOOL)isIPadress:(NSString *)host {
    /*
     IPv4:唯一标准格式 -> 0-255.0-255.0-255.0-255
     IPv6: 标  准  格  式 -> abcd:abcd:abcd:abcd:abcd:abcd:abcd:abcd
     IPv6  压  缩  格  式 -> abcd::abcd:abcd:abcd:abcd
     ::abcd:abcd:abcd
     abcd:abcd:abcd:abcd:abcd::
     ::1
     ::
     IPv6压缩规则：必需至少两个全0块才可以压缩,且每个IPv6地址只能压缩一次,存在多个可以压缩的位置优先压缩左边的全0块
     */
    if (host.length) {
        // IPV4正则
        NSString *urlRegEx = @"^(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)(\\.(25[0-5]|2[0-4]\\d|[0-1]?\\d?\\d)){3}$";
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", urlRegEx];
        BOOL isOK = [predicate evaluateWithObject:host];
        if (!isOK) {
            // 开始验证是否为IPV6
            NSInteger count = [host componentsSeparatedByString:@":"].count;
            if ((count == 0) || (count > 8)) {// 0 个: 或 大于7个 : 直接返回NO!
                return nil;
            }
            
            // 功能:标准的IPV6地址(IPV6_COMPRESS_REGEX)
            // abcd:abcd:abcd:abcd:abcd:abcd:abcd:abcd
            urlRegEx = @"(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$";
            predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", urlRegEx];
            if ([predicate evaluateWithObject:host]) {
                return YES;
            }
            
            // 判断是否为压缩的IPV6地址
            if (count == 8) {
                /*由于IPv6压缩规则是必须要大于等于2个全0块才能压缩
                 不合法压缩 ： fe80:0000:8030:49ec:1fc6:57fa:ab52:fe69
                 ->           fe80::8030:49ec:1fc6:57fa:ab52:fe69
                 该不合法压缩地址直接压缩了处于第二个块的单独的一个全0块，
                 上述不合法地址不能通过一般情况的压缩正则表达式IPV6_COMPRESS_REGEX判断出其不合法
                 所以定义了如下专用于判断边界特殊压缩的正则表达式
                 (边界特殊压缩：开头或末尾为两个全0块，该压缩由于处于边界，且只压缩了2个全0块，不会导致':'数量变少)*/
                // 功能：抽取特殊的边界压缩情况
                urlRegEx = @"^(::(?:[0-9A-Fa-f]{1,4})(?::[0-9A-Fa-f]{1,4}){5})|((?:[0-9A-Fa-f]{1,4})(?::[0-9A-Fa-f]{1,4}){5}::)$";
            } else {
                // 功能：判断一般情况压缩的IPv6正则表达式
                urlRegEx = @"^((?:[0-9A-Fa-f]{1,4}(:[0-9A-Fa-f]{1,4})*)?)::((?:([0-9A-Fa-f]{1,4}:)*[0-9A-Fa-f]{1,4})?)$";
            }
            predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", urlRegEx];
            isOK = [predicate evaluateWithObject:host];
            if ([predicate evaluateWithObject:host]) {
                return YES;
            }
            return NO;
        } else {
            return YES;
        }
    }
    return NO;
}

@end
