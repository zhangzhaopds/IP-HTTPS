//
//  NetworkManager.h
//  IPHTTPS_Demo
//
//  Created by 张昭 on 2019/10/28.
//  Copyright © 2019 HeyFox. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>

NS_ASSUME_NONNULL_BEGIN

@interface NetworkManager : AFHTTPSessionManager

- (nullable NSURLSessionDataTask *)NetGET:(NSString *)path
                               parameters:(nullable id)parameters
                                  success:(nullable void (^)(NSURLSessionDataTask *task, id _Nullable responseObject))success
                                  failure:(nullable void (^)(NSURLSessionDataTask * _Nullable task, NSError *error))failure;
- (nullable NSURLSessionDataTask *)NetPOST:(NSString *)URLString
                                parameters:(nullable id)parameters
                                   success:(nullable void (^)(NSURLSessionDataTask *task, id responseObject))success
                                   failure:(nullable void (^)(NSURLSessionDataTask * __nullable task, NSError *error))failure;

+ (BOOL)isIPadress:(NSString *)host;

@end

NS_ASSUME_NONNULL_END
