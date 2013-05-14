//
//  WebView+PhFacebook.m
//  PhFacebook
//
//  Created by Jörg Jacobsen on 07.05.13.
//
//

#import "WebView+PhFacebook.h"

@implementation WebView (PhFacebook)

// Tweaks the original user agent so it pretends to being Safari web browser
// (By appending "Safari" and the webview version)
//
- (void) poseAsSafari
{
    NSString *webViewUserAgent = [self userAgentForURL:[NSURL URLWithString:@"http://www.apple.com"]];
    NSString *pattern = @"(/[0-9]+\\.[0-9]+\\.[0-9]+)";         // E.g. "/536.28.10"
    __block NSString *match = nil;
    NSRegularExpressionOptions options = 0;
    NSError *error = NULL;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:&error];
    if (!regex) {
        NSString *errMsg = [NSString stringWithFormat:@"Unable to compile regular expression from pattern '%@' due to: %@", pattern, [error localizedFailureReason]];
        NSLog(@"%@", errMsg);
        [[NSException exceptionWithName:@"PhProgrammerError" reason:errMsg userInfo:nil] raise];
    }
    void (^captureMatch)(NSTextCheckingResult* result, NSMatchingFlags flags, BOOL *stop) = ^(NSTextCheckingResult* result, NSMatchingFlags flags, BOOL *stop) {
        match = [webViewUserAgent substringWithRange:result.range];
    };
    NSRange range = NSMakeRange(0, [webViewUserAgent length]);
    [regex enumerateMatchesInString:webViewUserAgent options:options range:range usingBlock:captureMatch];   // Should only match once
    
    [self setCustomUserAgent:[NSString stringWithFormat:@"%@ Safari%@", webViewUserAgent, match]];
}


@end
