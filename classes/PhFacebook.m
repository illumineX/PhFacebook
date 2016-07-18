//
//  PhFacebook.m
//  PhFacebook
//
//  Created by Philippe on 10-08-25.
//  Copyright 2010 Philippe Casgrain. All rights reserved.
//

#import "PhFacebook.h"
#import "PhWebViewController.h"
#import "PhAuthenticationToken.h"
#import "PhFacebook_URLs.h"
#import "Debug.h"
#import "WebView+PhFacebook.h"
#import "JSONKit.h"

#define kFBStoreAccessToken @"FBAStoreccessToken"
#define kFBStoreTokenExpiry @"FBStoreTokenExpiry"
#define kFBStoreAccessPermissions @"FBStoreAccessPermissions"

@implementation PhFacebook

@synthesize tokenRequestCompletionHandler=_tokenRequestCompletionHandler, loginError=_loginError;

#pragma mark NSCoding Protocol

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super init];
    if (self) {
        _appID = [[coder decodeObjectForKey:@"appID"] retain];
        _authToken = [[coder decodeObjectForKey:@"authToken"] retain];
    }
    return self;
}

- (void) encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_appID forKey:@"appID"];
    [coder encodeObject:_authToken forKey:@"authToken"];
}

#pragma mark Initialization

// Designated initializer for completion block based authorization
//
- (instancetype) initWithApplicationID:(NSString *)appID
{
	return [self initWithApplicationID:appID delegate:nil];
}

- (instancetype) initWithApplicationID: (NSString*) appID delegate: (id) delegate
{
    if ((self = [super init]))
    {
        if (appID)
            _appID = [[NSString stringWithString: appID] retain];
        _delegate = delegate; // Don't retain delegate to avoid retain cycles
        _webViewController = nil;
        _authToken = nil;
        _permissions = nil;
        DebugLog(@"Initialized with AppID '%@'", _appID);
    }

    return self;
}

- (void) dealloc
{
    [_appID release];
    [_webViewController release];
    [_authToken release];
    [_tokenRequestCompletionHandler release];
    [_loginError release];
    [super dealloc];
}

- (void) saveTokenToUserDefaults:(PhAuthenticationToken *)token
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject: token.authenticationToken forKey: kFBStoreAccessToken];
    if (token.expiry)
        [defaults setObject: token.expiry forKey: kFBStoreTokenExpiry];
    else
        [defaults removeObjectForKey: kFBStoreTokenExpiry];
    [defaults setObject: token.permissions forKey: kFBStoreAccessPermissions];
}

- (NSDictionary *)authenticationResultFromToken:(PhAuthenticationToken *)token error:(NSError *)error
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (token)
    {
        result[@"valid"] = @YES;
    }
    else
    {
        result[@"valid"] = @NO;
        
        // If the user hit cancel there will be no error
        if (error) {
            result[@"error"] = error;
        }
    }
    return result;
}

#pragma mark Access

- (id) delegate
{
    return [[_delegate retain] autorelease];
}

- (void) setDelegate:(id)delegate
{
    _delegate = delegate;    // Weak reference
}

- (void) clearToken
{
    [_authToken release];
    _authToken = nil;
}

-(void) invalidateCachedToken
{
    [self clearToken];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kFBStoreAccessToken];
    [defaults removeObjectForKey: kFBStoreTokenExpiry];
    [defaults removeObjectForKey: kFBStoreAccessPermissions];

    // Allow logout by clearing the left-over cookies (issue #35)
    NSURL *facebookUrl = [NSURL URLWithString:kFBURL];
    NSURL *facebookSecureUrl = [NSURL URLWithString:kFBSecureURL];

    NSHTTPCookieStorage *cookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray *cookies = [[cookieStorage cookiesForURL: facebookUrl] arrayByAddingObjectsFromArray:[cookieStorage cookiesForURL: facebookSecureUrl]];

    for (NSHTTPCookie *cookie in cookies)
        [cookieStorage deleteCookie: cookie];
}

- (void) setAccessToken: (NSString*) accessToken expires: (NSTimeInterval) tokenExpires permissions: (NSString*) perms
{
    [self clearToken];

    if (accessToken)
    {
        _authToken = [[PhAuthenticationToken alloc] initWithToken: accessToken
                                                  secondsToExpiry: tokenExpires
                                                      permissions: perms];
        [self saveTokenToUserDefaults:_authToken];
    }
}

- (void) getAccessTokenForPermissions:(NSArray *)permissions
                               cached:(BOOL)canCache
                       relativeToRect:(NSRect)rect
                               ofView:(NSView *)view
                           completion:(PhTokenRequestCompletionHandler)completion
{
    // Must save completion handler because web view is delegate callback based and thus does not offer
    // another way to call completion handler when authentication success URL has been loaded
    self.tokenRequestCompletionHandler = completion;
    BOOL validToken = NO;
    NSString *scope = [permissions componentsJoinedByString: @","];

    if (canCache && _authToken == nil)
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *accessToken = [defaults stringForKey: kFBStoreAccessToken];
        NSDate *date = [defaults objectForKey: kFBStoreTokenExpiry];
        NSString *perms = [defaults stringForKey: kFBStoreAccessPermissions];
        if (accessToken && perms)
        {
            // Do not notify delegate yet...
            [self setAccessToken: accessToken expires: date.timeIntervalSinceNow permissions: perms];
        }
    }

    if ([_authToken.permissions isCaseInsensitiveLike: scope])
    {
        // We already have a token for these permissions; check if it has expired or not
        if (_authToken.expiry == nil || [[_authToken.expiry laterDate: [NSDate date]] isEqual: _authToken.expiry])
            validToken = YES;
    }

    if (validToken)
    {
        if (completion) {
            completion([self authenticationResultFromToken:_authToken error:nil]);
        }
    }
    else
    {
        [self clearToken];

        // Use _webViewController to request a new token
        NSString *authURL;
        if (scope)
            authURL = [NSString stringWithFormat: kFBAuthorizeWithScopeURL, _appID, kFBLoginSuccessURL, scope];
        else
            authURL = [NSString stringWithFormat: kFBAuthorizeURL, _appID, kFBLoginSuccessURL];
      
        if ([_delegate respondsToSelector: @selector(needsAuthentication:forPermissions:)]) 
        {
            if ([_delegate needsAuthentication: authURL forPermissions: scope]) 
            {
                // If needsAuthentication returns YES, let the delegate handle the authentication UI
                return;
            }
        }
      
        // Retrieve token from web page
        if (_webViewController == nil)
        {
            _webViewController = [[PhWebViewController alloc] init];
            [_webViewController loadView];
        }

        // Prepare window but keep it ordered out. The _webViewController will make it visible
        // if it needs to.
        _webViewController.parent = self;
        _webViewController.permissions = scope;
        WebView *webView = _webViewController.webView;
        
        // Need to fake Safari-like user agent because otherwise auth token will be missing on request
        // when cookies are deleted
        [webView poseAsSafari];
        
        // When using NSPopover for login need positioning parameters
        [_webViewController setRelativeToRect:rect ofView:view];
        
        webView.mainFrameURL = authURL;
    }
}

// To be called when web view is done (either with or without having successfully logged in).
// Will call completion handler that was provided earlier
//
- (void) completeTokenRequestWithError:(NSError *)error
{
    [_webViewController release];
    _webViewController = nil;
    
    if (self.tokenRequestCompletionHandler)
    {
        self.tokenRequestCompletionHandler([self authenticationResultFromToken:_authToken error:error]);
        
        // Do not reuse completion handler nor error
        self.tokenRequestCompletionHandler = nil;
        self.loginError = nil;
    }
}

- (NSString*) accessToken
{
    return [[_authToken.authenticationToken copy] autorelease];
}

- (NSDictionary*) resultFromRequest:(NSString *)request data:(NSData *)data
{
    NSDictionary *result = nil;
    NSString *responseStr = @"";
    NSDictionary *responseDict = @{};
    id facebookError = nil;
    if (data) {
        responseStr = [[NSString alloc] initWithBytesNoCopy: (void*)data.bytes
                                                     length: data.length
                                                   encoding:NSASCIIStringEncoding
                                               freeWhenDone: NO];
        
        // Structured data returned from Facebook
        
        if (NSAppKitVersionNumber >= NSAppKitVersionNumber10_7) {
            responseDict = (NSDictionary *) [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        } else {
            responseDict = (NSDictionary *) [[JSONDecoder decoder] objectWithData:data error:nil];
        }
        
        // May contain a Facebook error
        facebookError = [responseDict valueForKey:@"error"];
    }
    // Any nil in parameter list of NSDictionary creation will terminate parameter list
    if (facebookError && [facebookError isKindOfClass:[NSDictionary class]]) {
        result = @{@"request": request,
                  @"sender": self,
                  @"error": facebookError,
//                  data, @"raw",
                  @"result": responseStr,
                  @"resultDict": responseDict};
    } else {
        result = @{@"request": request,
                  @"sender": self,
//                  data, @"raw",
                  @"result": responseStr,
                  @"resultDict": responseDict};
    }
    [responseStr release];
    return result;
}

- (NSDictionary *)_doRequest:(NSDictionary *)allParams
{
    NSDictionary *result = nil;
    
    if (_authToken)
    {
        //        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        
        NSString *request = allParams[@"request"];
        NSString *str;
        
        // Determine request method
        
        NSString *requestMethod = allParams[@"requestMethod"];
        BOOL postRequest = NO;
        if (requestMethod) {
            if ([requestMethod isEqualToString:@"POST"]) {
                postRequest = YES;
            }
        } else {
            postRequest = [allParams[@"postRequest"] boolValue];
            requestMethod = postRequest ? @"POST" : @"GET";
        }
        
        if (postRequest)
        {
            str = [NSString stringWithFormat: kFBGraphApiPostURL, request];
        }
        else
        {
            // Check if request already has optional parameters
            NSString *formatStr = kFBGraphApiGetURL;
            NSRange rng = [request rangeOfString:@"?"];
            if (rng.length > 0)
                formatStr = kFBGraphApiGetURLWithParams;
            str = [NSString stringWithFormat: formatStr, request, _authToken.authenticationToken];
        }
        
        
        NSDictionary *params = allParams[@"params"];
        NSMutableString *strPostParams = nil;
        if (params != nil)
        {
            if (postRequest)
            {
                strPostParams = [NSMutableString stringWithFormat: @"access_token=%@", _authToken.authenticationToken];
                for (NSString *p in params.allKeys)
                    [strPostParams appendFormat: @"&%@=%@", p, params[p]];
            }
            else
            {
                NSMutableString *strWithParams = [NSMutableString stringWithString: str];
                for (NSString *p in params.allKeys)
                    [strWithParams appendFormat: @"&%@=%@", p, params[p]];
                str = strWithParams;
            }
        }
        
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: str]];
        req.HTTPMethod = requestMethod;
        
        if (postRequest)
        {
            NSData *requestData = [NSData dataWithBytes: strPostParams.UTF8String length: strPostParams.length];
            req.HTTPBody = requestData;
            [req setValue: @"application/x-www-form-urlencoded" forHTTPHeaderField: @"content-type"];
        }
        
        NSURLResponse *response = nil;
        NSError *error = nil;
        
        DebugLog(@"Sending %@ request: %@", requestMethod, req.URL);
        
        NSData *data = [NSURLConnection sendSynchronousRequest: req returningResponse: &response error: &error];
        
        // Error out parameter from sending request is not yet taken into consideration
        
        result = [self resultFromRequest:request data:data];
    }
    return result;
}

- (void) sendFacebookRequest:(NSDictionary *)allParams
{
    if ([_delegate respondsToSelector:@selector(requestResult:)])
    {
        NSDictionary *result = [self _doRequest:allParams];
        [_delegate performSelectorOnMainThread:@selector(requestResult:) withObject: result waitUntilDone:YES];
    }
}

- (void) sendRequest:(NSString*) request
{
    NSDictionary *allParams = [self allParams:nil request:request HTTPMethod:@"GET"];
    [NSThread detachNewThreadSelector:@selector(sendFacebookRequest:) toTarget:self withObject:allParams];
}

- (NSDictionary *)sendSynchronousFacebookRequest:(NSDictionary *)allParams
{
    NSDictionary* result = [self _doRequest:allParams];
    return result;
}

- (NSDictionary *)allParams:(NSDictionary*)params request:(NSString *)request HTTPMethod:(NSString *)method
{
    return @{@"request": request,
            @"requestMethod": method,
            @"params": params};        // params may be nil
}

- (NSDictionary *)sendSynchronousRequest:(NSString *)request
                              HTTPMethod:(NSString *)method
                                  params:(NSDictionary *)params
{
    NSDictionary *allParams = [self allParams:params request:request HTTPMethod:method];
    return [self sendSynchronousFacebookRequest:allParams];
}

- (NSDictionary *)sendSynchronousRequest:(NSString *)request params:(NSDictionary *)params
{
    return [self sendSynchronousRequest:request HTTPMethod:@"GET" params:params];
}

- (NSDictionary *)sendSynchronousRequest:(NSString *)request
{
    return [self sendSynchronousRequest:request params:nil];
}

/**
 Sends an FQL query synchronously
 
 @returns Dictionary containing the following keys: request (string), sender, result (as string), resultDict, raw (raw result data), Error
 */
- (NSDictionary *)sendSynchronousFQLRequest:(NSString *)query
{
    NSDictionary *result = nil;
    
    if (_authToken)
    {
        NSString *escQuery = [query stringByAddingPercentEncodingWithAllowedCharacters: [NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *str = [NSString stringWithFormat: kFBGraphApiFqlURL, escQuery, _authToken.authenticationToken];
        
        NSLog(@"FQL query request: %@", str);
        
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: str]];
        
        NSURLResponse *response = nil;
        NSError *error = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest: req returningResponse: &response error: &error];
        
        // Error out parameter from sending request is not yet taken into consideration
        
        result = [self resultFromRequest:query data:data];
    }
    return result;
}

- (void) sendFacebookFQLRequest: (NSString*) query
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    if (_authToken)
    {
        NSString *escQuery = [query stringByAddingPercentEncodingWithAllowedCharacters: [NSCharacterSet URLQueryAllowedCharacterSet]];
        NSString *str = [NSString stringWithFormat: kFBGraphApiFqlURL, escQuery, _authToken.authenticationToken];

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: str]];

        NSURLResponse *response = nil;
        NSError *error = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest: req returningResponse: &response error: &error];

        if ([_delegate respondsToSelector: @selector(requestResult:)])
        {
            NSString *str = [[NSString alloc] initWithBytesNoCopy: (void*)data.bytes length: data.length encoding:NSASCIIStringEncoding freeWhenDone: NO];

            NSDictionary *result = @{@"result": str,
                                    @"request": query,
                                    @"raw": data,
                                    @"sender": self};
            [_delegate performSelectorOnMainThread:@selector(requestResult:) withObject: result waitUntilDone:YES];
            [str release];
        }
    }
    [pool drain];
}

- (void) sendFQLRequest: (NSString*) query
{
    [NSThread detachNewThreadSelector: @selector(sendFacebookFQLRequest:) toTarget: self withObject: query];
}


#pragma mark Notifications

- (void) webViewWillShowUI
{
    if ([_delegate respondsToSelector: @selector(willShowUINotification:)])
        [_delegate performSelectorOnMainThread: @selector(willShowUINotification:) withObject: self waitUntilDone: YES];
}

- (void) didDismissUI
{
    [self completeTokenRequestWithError:self.loginError];
    
    if ([_delegate respondsToSelector: @selector(didDismissUI:)])
        [_delegate performSelectorOnMainThread: @selector(didDismissUI:) withObject: self waitUntilDone: YES];
}

@end
