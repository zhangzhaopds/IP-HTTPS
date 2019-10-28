//
//  NetWorkRequestSerializer.m
//  IPHTTPS_Demo
//
//  Created by 张昭 on 2019/10/28.
//  Copyright © 2019 HeyFox. All rights reserved.
//

#import "NetWorkRequestSerializer.h"
#import "NetworkManager.h"

@implementation NetWorkRequestSerializer

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method URLString:(NSString *)URLString parameters:(id)parameters error:(NSError *__autoreleasing  _Nullable *)error {
    NSMutableURLRequest *request = [super requestWithMethod:method
                                                  URLString:URLString parameters:parameters error:error];
    BOOL isIP = [NetworkManager isIPadress:request.URL.host];
    NSString *host = @"dev.com";
    if (isIP) {
        [request setValue:host forHTTPHeaderField:@"host"];
        [self setValue:host forHTTPHeaderField:@"host"];
    }
    return request;
}

- (NSMutableURLRequest *)requestWithMultipartFormRequest:(NSURLRequest *)request writingStreamContentsToFile:(NSURL *)fileURL completionHandler:(void (^)(NSError * _Nullable))handler {
    NSMutableURLRequest *tmpRequest = [super requestWithMultipartFormRequest:request writingStreamContentsToFile:fileURL completionHandler:handler];
    BOOL isIP = [NetworkManager isIPadress:request.URL.host];
    NSString *host = @"dev.com";
    if (isIP) {
        [tmpRequest setValue:host forHTTPHeaderField:@"host"];
        [self setValue:host forHTTPHeaderField:@"host"];
    }
    return tmpRequest;
}

@end
