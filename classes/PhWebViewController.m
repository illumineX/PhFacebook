//
//  PhWebViewController.m
//  PhFacebook
//
//  Created by Philippe on 10-08-27.
//  Copyright 2010 Philippe Casgrain. All rights reserved.
//

#import "PhWebViewController.h"
#import "PhFacebook_URLs.h"
#import "PhFacebook.h"
#import "Debug.h"

//#define ALWAYS_SHOW_UI

@implementation PhWebViewController

@synthesize window;
@synthesize cancelButton;
@synthesize parent;
@synthesize permissions;

// Designated initializer
//
- (id) init
{
	if (self = [super initWithNibName:[self className] bundle:[NSBundle bundleForClass:[self class]]])
	{
        ;
	}
	return self;
}

- (id) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	// Disregard parameters - nib name is an implementation detail
	return [self init];
}

- (void) dealloc
{
    [super dealloc];
}

- (void) awakeFromNib
{
    NSBundle *bundle = [NSBundle bundleForClass: [PhFacebook class]];
    self.window.title = [bundle localizedStringForKey: @"FBAuthWindowTitle" value: @"" table: nil];
//    self.cancelButton.title = [bundle localizedStringForKey: @"FBAuthWindowCancel" value: @"" table: nil];
    self.window.delegate = self;
    self.window.level = NSFloatingWindowLevel;
}

- (void) windowWillClose: (NSNotification*) notification
{
    [parent performSelector: @selector(didDismissUI)];
}

#pragma mark Delegate

- (void) showUI
{
    // Facebook needs user input, show the window
    [self.window makeKeyAndOrderFront: self];
    // Notify parent that we're about to show UI
    [self.parent webViewWillShowUI];
}


- (void) webView: (WebView*) sender didCommitLoadForFrame: (WebFrame*) frame;
{
    NSString *url = [sender mainFrameURL];
    DebugLog(@"didCommitLoadForFrame: {%@}", [url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);

    NSString *urlWithoutSchema = [url substringFromIndex: [@"http://" length]];
    if ([url hasPrefix: @"https://"])
        urlWithoutSchema = [url substringFromIndex: [@"https://" length]];
    
    NSString *uiServerURLWithoutSchema = [kFBUIServerURL substringFromIndex: [@"http://" length]];
    NSComparisonResult res = [urlWithoutSchema compare: uiServerURLWithoutSchema options: NSCaseInsensitiveSearch range: NSMakeRange(0, [uiServerURLWithoutSchema length])];
    if (res == NSOrderedSame)
        [self showUI];

#ifdef ALWAYS_SHOW_UI
    [self showUI];
#endif
}

- (NSString*) extractParameter: (NSString*) param fromURL: (NSString*) url
{
    NSString *res = nil;

    NSRange paramNameRange = [url rangeOfString: param options: NSCaseInsensitiveSearch];
    if (paramNameRange.location != NSNotFound)
    {
        // Search for '&' or end-of-string
        NSRange searchRange = NSMakeRange(paramNameRange.location + paramNameRange.length, [url length] - (paramNameRange.location + paramNameRange.length));
        NSRange ampRange = [url rangeOfString: @"&" options: NSCaseInsensitiveSearch range: searchRange];
        if (ampRange.location == NSNotFound)
            ampRange.location = [url length];
        res = [url substringWithRange: NSMakeRange(searchRange.location, ampRange.location - searchRange.location)];
    }

    return res;
}

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    parent.loginError = error;
}

-(void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    parent.loginError = error;
}

- (void) webView: (WebView*) sender didFinishLoadForFrame: (WebFrame*) frame
{
    NSString *url = [sender mainFrameURL];
    DebugLog(@"didFinishLoadForFrame: {%@}", [url stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding]);

    NSString *urlWithoutSchema = [url substringFromIndex: [@"http://" length]];
    if ([url hasPrefix: @"https://"])
        urlWithoutSchema = [url substringFromIndex: [@"https://" length]];
    
    NSString *loginSuccessURLWithoutSchema = [kFBLoginSuccessURL substringFromIndex: 7];
    NSComparisonResult res = [urlWithoutSchema compare: loginSuccessURLWithoutSchema options: NSCaseInsensitiveSearch range: NSMakeRange(0, [loginSuccessURLWithoutSchema length])];
    if (res == NSOrderedSame)
    {
        NSString *accessToken = [self extractParameter: kFBAccessToken fromURL: url];
        NSString *tokenExpires = [self extractParameter: kFBExpiresIn fromURL: url];
        NSString *errorReason = [self extractParameter: kFBErrorReason fromURL: url];
        
        if (errorReason) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                      errorReason, NSLocalizedDescriptionKey,
                                      nil];
            // For lack of better code picked arbitrary
            parent.loginError = [NSError errorWithDomain:@"PhFacebookError" code:-1 userInfo:userInfo];
        }
        [parent setAccessToken:accessToken expires:[tokenExpires floatValue] permissions:self.permissions];
        [self.window close];
    }
    else
    {
        // If access token is not retrieved, UI is shown to allow user to login/authorize
        [self showUI];
    }

#ifdef ALWAYS_SHOW_UI
    [self showUI];
#endif
}

- (IBAction) cancel: (id) sender
{
    [self.window close];
}

@end
