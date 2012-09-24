#import <Foundation/Foundation.h>
#import "HTTPResponse.h"
#import "HTTPMessage.h"
#import "GCDAsyncSocket.h"
#import "ABMovieEncoder.h"

#define BUFSIZE 512

@class HTTPConnection;
@class HTTPProxyResponse;

@protocol HTTPProxyResponseDelegate <NSObject>

- (void)HTTPProxyResponse:(HTTPProxyResponse*)proxyResponse didFailWithError:(NSError*)error;
- (void)HTTPProxyResponse:(HTTPProxyResponse*)proxyResponse didFinishWithData:(NSData*)data;
- (void)HTTPProxyResponse:(HTTPProxyResponse*)proxyResponse shouldForwardData:(NSData*)data;

@end

@interface HTTPProxyResponse : NSObject <HTTPResponse,HTTPProxyResponseDelegate,NSStreamDelegate>
{
    HTTPConnection *_connection;

    GCDAsyncSocket * _socket;
    
    ABMovieEncoder * _encoder;
    
    dispatch_queue_t sendQueue;
    
    NSString * _path;
    
	NSUInteger offset;
	NSData *_data;
    
    CFHTTPMessageRef _originRequest;
    CFHTTPMessageRef _request;
    CFHTTPMessageRef _response;
    NSDictionary* _responseDictionary;
    
    CFReadStreamRef _readStream;
    NSInputStream *_inputStream;
}

@property (nonatomic, weak) id<HTTPProxyResponseDelegate> delegate;
@property (nonatomic, strong) GCDAsyncSocket* socket;

- (id)initWithDelegate:(id)delegate socket:(GCDAsyncSocket*)socket;
- (void)sendRequest:(CFHTTPMessageRef)request;
- (void)cancel;

- (void)didFailLoadingWithError:(NSError *)error;
- (void)didFinishLoading;
- (void)shouldForwardData;

@end
