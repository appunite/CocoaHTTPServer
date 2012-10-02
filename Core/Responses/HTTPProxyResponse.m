#import "HTTPProxyResponse.h"
#import "HTTPConnection.h"
#import "DDRange.h"
#import "HTTPLogging.h"
#import "AirbenderAppSettings.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

// Log levels : off, error, warn, info, verbose
// Other flags: trace
static const int httpLogLevel = HTTP_LOG_LEVEL_OFF; // | HTTP_LOG_FLAG_TRACE;


@implementation HTTPProxyResponse

- (id)initWithDelegate:(id)delegate socket:(GCDAsyncSocket *)socket{
    self = [self init];
    if (self) {
        [self setDelegate:delegate];
        offset = 0;
        _socket = socket;
        _data = [[NSData alloc] init];
    }
    return self;
}

- (void)dealloc
{
	HTTPLogTrace();
	
}

- (NSDictionary *)httpHeaders {
    return _responseDictionary;
}

- (NSInteger)status {
    return CFHTTPMessageGetResponseStatusCode(_response);;
}

- (UInt64)contentLength
{
    UInt64 result = [[[self httpHeaders] objectForKey:@"Content-Length"] intValue];
    
    HTTPLogTrace2(@"%@[%p]: contentLength - %llu", THIS_FILE, self, result);
    
    return (UInt64) result;
}

- (UInt64)offset
{
	HTTPLogTrace();
	
	return offset;
}

- (void)setOffset:(UInt64)offsetParam
{
	HTTPLogTrace2(@"%@[%p]: setOffset:%lu", THIS_FILE, self, (unsigned long)offset);
	
	offset = (NSUInteger)offsetParam;
}

- (NSData *)readDataOfLength:(NSUInteger)lengthParameter
{
	HTTPLogTrace2(@"%@[%p]: readDataOfLength:%lu", THIS_FILE, self, (unsigned long)lengthParameter);
	
	NSUInteger remaining = [self contentLength]  - [_data length] - offset;
	NSUInteger length = lengthParameter < remaining ? lengthParameter : remaining;
	
//	void *bytes = (void *)([data bytes] + offset);
	
    if (!_data) {
        NSLog(@"Error");
    }
    
	offset += [_data length];
	
	return _data;
}

- (BOOL)isDone
{
	BOOL result = (offset == [self contentLength]);
	
	HTTPLogTrace2(@"%@[%p]: isDone - %@", THIS_FILE, self, (result ? @"YES" : @"NO"));
	
	return result;
}

- (void)cancel {
    [_inputStream removeFromRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
    [_inputStream close];
    _inputStream = nil;
    _readStream = nil;

}

#pragma  mark - proxy 

- (void)sendRequest:(CFHTTPMessageRef)request {
    
    [self cancel];
    
    CFURLRef originUrl = CFHTTPMessageCopyRequestURL(request);
    NSURL *originNSUrl = (__bridge NSURL *)(originUrl);

    NSString * server = [[[RKClient sharedClient] baseURL] host];
    
#ifdef STATIC_PLAYER_MODE 
    server = kStaticPlayerServer;
#endif
    
    NSURL *customURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@:80%@",[originNSUrl scheme], server, [originNSUrl path]]];
    NSString *customHost = [NSString stringWithFormat:@"%@:80",server];
    
    CFURLRef url = (__bridge CFURLRef) customURL;
    
    CFHTTPMessageRef newRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, CFSTR("GET"), url, (__bridge CFStringRef) HTTPVersion1_1);
    
    CFStringRef range = CFHTTPMessageCopyHeaderFieldValue(request, CFSTR("Range"));
    
    DDRange ddRange = DDRangeFromString((__bridge NSString *)(range));
    
    _encoder = [[ABMovieEncoder alloc] initWithStartPoint:ddRange.location endPoint:ddRange.location+ddRange.length];
    
    CFHTTPMessageSetHeaderFieldValue(newRequest, CFSTR("Accept"), CFSTR("*/*"));
    CFHTTPMessageSetHeaderFieldValue(newRequest, CFSTR("Accept-Encoding"), CFSTR("identity"));
    CFHTTPMessageSetHeaderFieldValue(newRequest, CFSTR("Connection"), CFSTR("keep-alive"));
    CFHTTPMessageSetHeaderFieldValue(newRequest, CFSTR("Range"), range);
    CFHTTPMessageSetHeaderFieldValue(newRequest, CFSTR("Host"), (__bridge CFStringRef)(customHost));
    CFHTTPMessageSetHeaderFieldValue(newRequest, CFSTR("User-Agent"), CFSTR("AppleCoreMedia/1.0.0.9B176 (iPad; U; CPU OS 5_1 like Mac OS X; en_us)"));
    
    _readStream = CFReadStreamCreateForStreamedHTTPRequest(CFAllocatorGetDefault(), newRequest, _readStream);
    _inputStream = (__bridge NSInputStream*) _readStream;
    [_inputStream setDelegate:self];
    [_inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                            forMode:NSRunLoopCommonModes];
    [_inputStream open];
    [[NSRunLoop currentRunLoop] run];
}

- (void)stream:(NSInputStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch(eventCode) {
        case NSStreamEventHasBytesAvailable: {
        
            uint8_t buffer[BUFSIZE];
            NSInteger length = [aStream read:buffer maxLength:BUFSIZE];
            _data = [_encoder decodeDataWithBytes:[NSData dataWithBytes:(const void*)buffer length:length] length:length];
            _response = (CFHTTPMessageRef) CFReadStreamCopyProperty((__bridge CFReadStreamRef)(aStream),kCFStreamPropertyHTTPResponseHeader);
            _responseDictionary = (__bridge NSDictionary*) CFHTTPMessageCopyAllHeaderFields(_response);
            [self didFinishLoading];
            
        }
            break;
        case NSStreamEventErrorOccurred: {
            [aStream removeFromRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
            [self didFailLoadingWithError:[aStream streamError]];
        }
            break;
        case NSStreamEventEndEncountered: {
            [aStream removeFromRunLoop: [NSRunLoop currentRunLoop] forMode: NSDefaultRunLoopMode];
        }
            break;
    }
}

#pragma mark - HTTPProxyResponse Delegate

- (void)didFailLoadingWithError:(NSError *)error {
    NSLog(@"ABProxyConnection didFailLoadingWithError %@",[error description]);
    
    if ([_delegate respondsToSelector:@selector(HTTPProxyResponse:didFailWithError:)]) {
        [_delegate performSelector:@selector(HTTPProxyResponse:didFailWithError:) withObject:self withObject:error];
    }
}

- (void)didFinishLoading {
    
    HTTPLogTrace();
    
    if ([_delegate respondsToSelector:@selector(HTTPProxyResponse:didFinishWithData:)]) {
        [_delegate performSelector:@selector(HTTPProxyResponse:didFinishWithData:) withObject:self withObject:_data];
    }
    
    [self shouldForwardData];
}

- (void)shouldForwardData {
    
    HTTPLogTrace();
    
    if ([_delegate respondsToSelector:@selector(HTTPProxyResponse:shouldForwardData:)]) {
        [_delegate performSelector:@selector(HTTPProxyResponse:shouldForwardData:) withObject:self withObject:_data];
    }
}

@end
