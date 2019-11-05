//
//  CustomURLProtocol.m
//  oupai
//
//  Created by zhangzhao on 2019/11/5.
//  Copyright © 2019 yizhibo. All rights reserved.
//

#import "CustomURLProtocol.h"
#import <objc/runtime.h>
#import "NSObject+Extension.h"
#import "oupai-Swift.h"

static NSString * const URLProtocolHandledKey = @"URLProtocolHandledKey";

static char * const kHasEvaluatedStream = "com.easylive.httpdns.stream";

@interface CustomURLProtocol()<NSStreamDelegate>

@property(nonatomic, strong) NSMutableURLRequest *mutableRequest;
@property(nonatomic, strong) NSInputStream *inputStream;
@property(nonatomic, strong) NSRunLoop *runloop;

@end

@implementation CustomURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([self.class propertyForKey:URLProtocolHandledKey inRequest:request]) {
        return NO;
    }
    BOOL isHttps = [request.URL.scheme isEqualToString:@"https"];
    BOOL isIPRequest = [CCFunctions isIPadress:request.URL.host];
    NSString *domain = [[APIController shared] domainPathForKey:request.URL.host];
    return isHttps && isIPRequest && [domain isNotEmpty];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    NSMutableURLRequest * req = [request mutableCopy];
    if ([request.HTTPMethod isEqualToString:@"POST"]) {
        if (!request.HTTPBody) {
            NSInteger maxLength = 1024;
            uint8_t d[maxLength];
            NSInputStream *stream = request.HTTPBodyStream;
            NSMutableData *data = [[NSMutableData alloc] init];
            [stream open];
            BOOL endOfStreamReached = NO;
            while (!endOfStreamReached) {
                NSInteger bytesRead = [stream read:d maxLength:maxLength];
                if (bytesRead == 0) {
                    endOfStreamReached = YES;
                } else if (bytesRead == -1) {
                    endOfStreamReached = YES;
                } else if (stream.streamError == nil) {
                    [data appendBytes:(void *)d length:bytesRead];
                }
            }
            req.HTTPBody = [data copy];
            [stream close];
        }
    }
    return req;
}

- (void)startLoading {
    NSMutableURLRequest *request = [[self request] mutableCopy];
    NSString *host = [[APIController shared] domainPathForKey:request.URL.host];
    [request setValue:host forHTTPHeaderField:@"Host"];
    // Accept-Encoding会导致获取到的NSStream无法解析成JSON数据
    [request setValue:nil forHTTPHeaderField:@"Accept-Encoding"];
    if (![request.allHTTPHeaderFields cc_objectWithKey:@"Content-Type"]) {
        [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    }
    [self.class setProperty:@(YES) forKey:URLProtocolHandledKey inRequest:request];
    self.mutableRequest = request;
    [self startRequest:request];
}

- (void)stopLoading {
    if (self.inputStream.streamStatus == NSStreamStatusOpen) {
        [self closeInputStream];
    }
}

#pragma mark - Request
- (void)startRequest:(NSMutableURLRequest *)request {
    // 创建请求
    CFHTTPMessageRef requestRef = [self createCFRequest:request];
    CFAutorelease(requestRef);
    
    // 添加请求头
    [self addHeadersToRequestRef:requestRef headerFields:request.allHTTPHeaderFields];
    
    // 添加请求体
    [self addBodyToRequestRef:requestRef request:request];
    
    // 创建CFHTTPMessage对象的输入流
    CFReadStreamRef readStream = CFReadStreamCreateForHTTPRequest(kCFAllocatorDefault, requestRef);
    NSInputStream *inputStream = (__bridge_transfer NSInputStream *)readStream;
    self.inputStream = inputStream;
    
    // 设置SNI
    [self setupSNIWithRequest:request stream:inputStream];

    // 设置Runloop
    [self setupRunloop];
    
    // 打开输入流
    [inputStream open];
}

- (CFHTTPMessageRef)createCFRequest:(NSMutableURLRequest *)request {
    // 创建url
    CFStringRef urlStringRef = (__bridge CFStringRef) [request.URL absoluteString];
    CFURLRef urlRef = CFURLCreateWithString(kCFAllocatorDefault, urlStringRef, NULL);
    CFAutorelease(urlRef);
    
    // 读取HTTP method
    CFStringRef methodRef = (__bridge CFStringRef) request.HTTPMethod;
    
    // 创建request
    CFHTTPMessageRef requestRef = CFHTTPMessageCreateRequest(kCFAllocatorDefault, methodRef, urlRef, kCFHTTPVersion1_1);
    return requestRef;
}

- (void)addHeadersToRequestRef:(CFHTTPMessageRef)requestRef headerFields:(NSDictionary *)headFields {
    // 遍历请求头，将数据塞到requestRef
    // 不包含POST请求时存放在header的body信息
    for (NSString *header in headFields) {
        if (![header isEqualToString:@"originalBody"]) {
            CFStringRef requestHeader = (__bridge CFStringRef) header;
            CFStringRef requestHeaderValue = (__bridge CFStringRef) [headFields valueForKey:header];
            CFHTTPMessageSetHeaderFieldValue(requestRef, requestHeader, requestHeaderValue);
        }
    }
}

- (void)addBodyToRequestRef:(CFHTTPMessageRef)requestRef request:(NSMutableURLRequest *)request {
    NSDictionary *headFields = request.allHTTPHeaderFields;
    NSData *data;
    if (request.HTTPBody && request.HTTPBody.length > 0) {
        data = request.HTTPBody;
    } else if (headFields[@"originalBody"]) {
        NSData *temp = [headFields[@"originalBody"] dataUsingEncoding:NSUTF8StringEncoding];
        if (temp && temp.length) {
            data = temp;
        }
    }
    if (!data) {
        return;
    }
    
    // POST请求时，将原始HTTPBody从header中取出
    CFStringRef requestBody = CFSTR("");
    CFDataRef bodyDataRef = CFStringCreateExternalRepresentation(kCFAllocatorDefault, requestBody, kCFStringEncodingUTF8, 0);
    bodyDataRef = (__bridge_retained CFDataRef)data;
    
    // 将body数据塞到requestRef
    CFHTTPMessageSetBody(requestRef, bodyDataRef);
    
    CFRelease(bodyDataRef);
}

- (void)setupSNIWithRequest:(NSMutableURLRequest *)request stream:(NSInputStream *)inputStream {
    
    NSString *domain = [[APIController shared] domainPathForKey:request.URL.host];
    
    // 设置HTTPS的校验策略
    [inputStream setProperty:NSStreamSocketSecurityLevelNegotiatedSSL forKey:NSStreamSocketSecurityLevelKey];
    NSDictionary *sslProperties = @{ (__bridge id) kCFStreamSSLPeerName : domain };
    [inputStream setProperty:sslProperties forKey:(__bridge_transfer NSString *) kCFStreamPropertySSLSettings];
    [inputStream setDelegate:self];
}

- (void)setupRunloop {
    // 保存当前线程的runloop，这对于重定向的请求很关键
    if (!self.runloop) {
        self.runloop = [NSRunLoop currentRunLoop];
    }
    
    // 将请求放入当前runloop的事件队列
    [self.inputStream scheduleInRunLoop:self.runloop forMode:NSRunLoopCommonModes];
}

#pragma mark - Response

- (void)endResponse {
    // 读取响应头部信息
    CFReadStreamRef readStream = (__bridge CFReadStreamRef) self.inputStream;
    CFHTTPMessageRef messageRef = (CFHTTPMessageRef) CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
    CFAutorelease(messageRef);
    
    // 头部信息不完整，关闭inputstream，通知client
    if (!CFHTTPMessageIsHeaderComplete(messageRef)) {
        [self closeInputStream];
        [self.client URLProtocolDidFinishLoading:self];
        return;
    }
    
    // 把当前请求关闭
    [self closeInputStream];
    
    // 通知上层响应结束
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)doRedirect:(NSDictionary *)headDict {
    // 读取重定向的location，设置成新的url
    NSString *location = headDict[@"Location"];
    if (!location) {
        location = headDict[@"location"];
    }
    NSURL *url = [[NSURL alloc] initWithString:location];
    self.mutableRequest.URL = url;
    
    // 根据RFC文档，当重定向请求为POST请求时，要将其转换为GET请求
    if ([[self.mutableRequest.HTTPMethod lowercaseString] isEqualToString:@"post"]) {
        self.mutableRequest.HTTPMethod = @"GET";
        self.mutableRequest.HTTPBody = nil;
    }
    [self startRequest:self.mutableRequest];
}

- (void)closeInputStream {
    [self closeStream:self.inputStream];
}

- (void)closeStream:(NSStream *)aStream {
    [aStream removeFromRunLoop:self.runloop forMode:NSRunLoopCommonModes];
    [aStream setDelegate:nil];
    [aStream close];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventHasBytesAvailable: {
            
            if (![aStream isKindOfClass:[NSInputStream class]]) {
                break;
            }
            
            NSInputStream *inputStream = (NSInputStream *) aStream;
            CFReadStreamRef readStream = (__bridge CFReadStreamRef) inputStream;
            
            // 响应头完整性校验
            CFHTTPMessageRef messageRef = (CFHTTPMessageRef) CFReadStreamCopyProperty(readStream, kCFStreamPropertyHTTPResponseHeader);
            CFAutorelease(messageRef);
            if (!CFHTTPMessageIsHeaderComplete(messageRef)) {
                CFRelease(messageRef);
                return;
            }
            CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(messageRef);
            NSURL *url = (__bridge NSURL *)(CFHTTPMessageCopyRequestURL(messageRef));
            NSLog(@"SNI: URL %@, StatusCode %ld", url.absoluteString, statusCode);
            // https校验过了，直接读取数据
            if ([self hasEvaluatedStreamSuccess:aStream]) {
                [self readStreamData:inputStream];
            } else {
                // 添加校验标记
                objc_setAssociatedObject(aStream,
                                         kHasEvaluatedStream,
                                         @(YES),
                                         OBJC_ASSOCIATION_RETAIN);
                
                if ([self evaluateStreamSuccess:aStream]) {     // 校验成功，则读取数据
                    // 非重定向
                    if (![self isRedirectCode:statusCode]) {
                        // 读取响应头
                        [self readStreamHeader:messageRef];
                        
                        // 读取响应数据
                        [self readStreamData:inputStream];
                    } else {    // 重定向
                        // 关闭流
                        [self closeStream:aStream];
                        
                        // 处理重定向
                        [self handleRedirect:messageRef];
                    }
                } else {
                    // 校验失败，关闭stream
                    [self closeStream:aStream];
                    [self.client URLProtocol:self didFailWithError:[[NSError alloc] initWithDomain:@"fail to evaluate the server trust" code:-1 userInfo:nil]];
                }
            }
        }
            break;
            
        case NSStreamEventErrorOccurred: {
            [self closeStream:aStream];
            
            // 通知client发生错误了
            [self.client URLProtocol:self didFailWithError:[aStream streamError]];
        }
            break;
        
        case NSStreamEventEndEncountered: {
            [self endResponse];
        }
            break;
            
        default:
            break;
    }
}

- (BOOL)hasEvaluatedStreamSuccess:(NSStream *)aStream {
    NSNumber *hasEvaluated = objc_getAssociatedObject(aStream, kHasEvaluatedStream);
    if (hasEvaluated && hasEvaluated.boolValue) {
        return YES;
    }
    return NO;
}

- (void)readStreamHeader:(CFHTTPMessageRef )message {
    // 读取响应头
    CFDictionaryRef headerFieldsRef = CFHTTPMessageCopyAllHeaderFields(message);
    NSDictionary *headDict = (__bridge_transfer NSDictionary *)headerFieldsRef;
    
    // 读取http version
    CFStringRef httpVersionRef = CFHTTPMessageCopyVersion(message);
    NSString *httpVersion = (__bridge_transfer NSString *)httpVersionRef;
    
    // 读取状态码
    CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(message);
    
    // 非重定向的数据，才上报
    if (![self isRedirectCode:statusCode]) {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.mutableRequest.URL statusCode:statusCode HTTPVersion: httpVersion headerFields:headDict];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    }
}

- (BOOL)evaluateStreamSuccess:(NSStream *)aStream {
    // 证书相关数据
    SecTrustRef trust = (__bridge SecTrustRef) [aStream propertyForKey:(__bridge NSString *) kCFStreamPropertySSLPeerTrust];
    SecTrustResultType res = kSecTrustResultInvalid;
    NSMutableArray *policies = [NSMutableArray array];
    NSString *domain = [[APIController shared] domainPathForKey:self.mutableRequest.URL.host];
    if (domain) {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateSSL(true, (__bridge CFStringRef) domain)];
    } else {
        [policies addObject:(__bridge_transfer id) SecPolicyCreateBasicX509()];
    }
   
    // 证书校验
    SecTrustSetPolicies(trust, (__bridge CFArrayRef) policies);
    if (SecTrustEvaluate(trust, &res) != errSecSuccess) {
        return NO;
    }
    if (res != kSecTrustResultProceed && res != kSecTrustResultUnspecified) {
        return NO;
    }
    return YES;
}

- (void)readStreamData:(NSInputStream *)aInputStream {
    UInt8 buffer[16 * 1024];
    UInt8 *buf = NULL;
    NSUInteger length = 0;
    
    // 从stream读数据
    if (![aInputStream getBuffer:&buf length:&length]) {
        NSInteger amount = [self.inputStream read:buffer maxLength:sizeof(buffer)];
        buf = buffer;
        length = amount;
    }
    NSData *data = [[NSData alloc] initWithBytes:buf length:length];

    // 数据上报
    [self.client URLProtocol:self didLoadData:data];
}

- (BOOL)isRedirectCode:(NSInteger)statusCode {
    if (statusCode >= 300 && statusCode < 400) {
        return YES;
    }
    return NO;
}

- (void)handleRedirect:(CFHTTPMessageRef )messageRef {
    // 响应头
    CFDictionaryRef headerFieldsRef = CFHTTPMessageCopyAllHeaderFields(messageRef);
    NSDictionary *headDict = (__bridge_transfer NSDictionary *)headerFieldsRef;
    
    // 响应头的loction
    NSString *location = headDict[@"Location"];
    if (!location)
        location = headDict[@"location"];
    NSURL *redirectUrl = [[NSURL alloc] initWithString:location];
    
    // 读取http version
    CFStringRef httpVersionRef = CFHTTPMessageCopyVersion(messageRef);
    NSString *httpVersion = (__bridge_transfer NSString *)httpVersionRef;
    
    // 读取状态码
    CFIndex statusCode = CFHTTPMessageGetResponseStatusCode(messageRef);
    
    // 生成response
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.mutableRequest.URL statusCode:statusCode HTTPVersion: httpVersion headerFields:headDict];
    
    // 上层实现了redirect协议，则回调到上层
    // 否则，内部进行redirect
    if ([self.client respondsToSelector:@selector(URLProtocol:wasRedirectedToRequest:redirectResponse:)]) {
        [self.client URLProtocol:self
          wasRedirectedToRequest:[NSURLRequest requestWithURL:redirectUrl]
                redirectResponse:response];
    } else {
        [self doRedirect:headDict];
    }
}

@end
