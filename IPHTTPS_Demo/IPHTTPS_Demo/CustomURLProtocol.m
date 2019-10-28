//
//  CustomURLProtocol.m
//  IPHTTPS_Demo
//
//  Created by 张昭 on 2019/10/28.
//  Copyright © 2019 HeyFox. All rights reserved.
//

#import "CustomURLProtocol.h"
#import "NetworkManager.h"

static NSString * const URLProtocolHandledKey = @"URLProtocolHandledKey";

@interface CustomURLProtocol ()<NSURLSessionTaskDelegate>

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionTask *task;

@end

@implementation CustomURLProtocol

// MARK: - overwrite method
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([request.URL.scheme isEqualToString:@"http"] || [request.URL.scheme isEqualToString:@"https"]) {
        NSString *pathExtension = request.URL.pathExtension;
        // 不拦截(忽略)类似图片,字体资源请求.
        if ([ignorePathExtension() containsObject:[pathExtension lowercaseString]]) {
            if (request.URL.pathExtension.length) {
                NSLog(@"canInitWithRequest url-->%@",request.URL.pathExtension);
            }
            return NO;
        }
        if ([NetworkManager isIPadress:request.URL.host] && request.URL.host.length) {
            return YES;
        } else {
            return NO;
        }
    }
    
    // 看看是否已经处理过了，防止无限循环
    if ([self.class propertyForKey:URLProtocolHandledKey inRequest:request]) {
        return NO;
    }
    
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    
    NSMutableURLRequest *request = [self.request mutableCopy];
    NetworkManager *mgr = [NetworkManager manager];
    
    // 标记当前传入的Request已经被拦截处理过，
    // 防止在最开始又继续拦截处理
    [self.class setProperty:@(YES) forKey:URLProtocolHandledKey inRequest:request];
    
    self.task = [mgr dataTaskWithRequest:request
                          uploadProgress:nil
                        downloadProgress:nil
                       completionHandler:^(NSURLResponse * _Nonnull response,
                                           id  _Nullable responseObject,
                                           NSError * _Nullable error) {
                           if (error) {
                               [self.client URLProtocol:self didFailWithError:error];
                           } else {
                               [self.client URLProtocolDidFinishLoading:self];
                           }
                       }];
    
    [mgr setDataTaskDidReceiveResponseBlock:^NSURLSessionResponseDisposition(NSURLSession * _Nonnull session, NSURLSessionDataTask * _Nonnull dataTask, NSURLResponse * _Nonnull response) {
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageAllowed];
        return NSURLSessionResponseAllow;
    }];
    
    [mgr setDataTaskDidReceiveDataBlock:^(NSURLSession * _Nonnull session, NSURLSessionDataTask * _Nonnull dataTask, NSData * _Nonnull data) {
        [self.client URLProtocol:self didLoadData:data];
    }];
    
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
    self.task = nil;
}

static inline NSSet *ignorePathExtension() {
    return [[NSSet alloc] initWithObjects:@"tif", @"tiff", @"jpg", @"jpeg", @"gif", @"png", @"ico", @"bmp", @"cur", @"apng", @"webp", @"woff", @"otf", nil];
}

@end
