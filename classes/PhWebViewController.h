//
//  PhWebViewController.h
//  PhFacebook
//
//  Created by Philippe on 10-08-27.
//  Copyright 2010 Philippe Casgrain. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>


@class PhFacebook;

@interface PhWebViewController : NSViewController <NSWindowDelegate>
{
    IBOutlet NSWindow *window;
    IBOutlet NSButton *cancelButton;

    PhFacebook *parent;
    NSString *permissions;
}

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSButton *cancelButton;
@property (assign) PhFacebook *parent;
@property (nonatomic, retain) NSString *permissions;

- (IBAction) cancel: (id) sender;

@end
