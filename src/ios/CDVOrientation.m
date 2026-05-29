/*
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 *
 */
#import "CDVOrientation.h"
#import <Cordova/CDVViewController.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Associated object key for the locked orientation mask
static const void *kCDVLockedOrientationMaskKey = &kCDVLockedOrientationMaskKey;

// ---------------------------------------------------------------------------
// Category defined in this .m file — keeps everything in one place.
// Provides the swizzled replacement for supportedInterfaceOrientations.
// ---------------------------------------------------------------------------
@interface CDVViewController (CDVOrientationLock)
- (UIInterfaceOrientationMask)cdvol_supportedInterfaceOrientations;
@end

@implementation CDVViewController (CDVOrientationLock)
- (UIInterfaceOrientationMask)cdvol_supportedInterfaceOrientations {
    NSNumber *mask = objc_getAssociatedObject(self, kCDVLockedOrientationMaskKey);
    if (mask != nil) {
        return (UIInterfaceOrientationMask)[mask unsignedIntegerValue];
    }
    // After swizzling, calling self.cdvol_... actually calls the original implementation
    return [self cdvol_supportedInterfaceOrientations];
}
@end

// ---------------------------------------------------------------------------

@interface CDVOrientation () {}
@end

@implementation CDVOrientation

- (void)pluginInitialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class vcClass = [CDVViewController class];
        SEL originalSel  = @selector(supportedInterfaceOrientations);
        SEL replacementSel = @selector(cdvol_supportedInterfaceOrientations);

        Method originalMethod    = class_getInstanceMethod(vcClass, originalSel);
        Method replacementMethod = class_getInstanceMethod(vcClass, replacementSel);

        // If CDVViewController doesn't have its own implementation (inherits from
        // UIViewController), add it first so the exchange stays on this class.
        BOOL added = class_addMethod(vcClass,
                                     originalSel,
                                     method_getImplementation(replacementMethod),
                                     method_getTypeEncoding(replacementMethod));
        if (added) {
            // Point the replacement selector at the original (inherited) IMP
            class_replaceMethod(vcClass,
                                replacementSel,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            // CDVViewController already had its own implementation — just swap
            method_exchangeImplementations(originalMethod, replacementMethod);
        }
    });
}

// ---------------------------------------------------------------------------
// Helper: write (or clear) the associated mask and notify UIKit
// ---------------------------------------------------------------------------
- (void)setLockedMask:(UIInterfaceOrientationMask)mask {
    objc_setAssociatedObject(self.viewController,
                             kCDVLockedOrientationMaskKey,
                             @(mask),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)clearLockedMask {
    objc_setAssociatedObject(self.viewController,
                             kCDVLockedOrientationMaskKey,
                             nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---------------------------------------------------------------------------

-(void)handleBelowEqualIos15WithOrientationMask:(NSInteger)orientationMask
                                 viewController:(CDVViewController*)vc
                                         result:(NSMutableArray*)result
                                       selector:(SEL)selector
{
    NSValue *value;
    if (orientationMask != 15) {
        if (!_isLocked) {
            _lastOrientation = [UIApplication sharedApplication].statusBarOrientation;
        }
        UIInterfaceOrientation deviceOrientation = [UIApplication sharedApplication].statusBarOrientation;
        if (orientationMask == 8 || (orientationMask == 12 && !UIInterfaceOrientationIsLandscape(deviceOrientation))) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft];
        } else if (orientationMask == 4) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight];
        } else if (orientationMask == 1 || (orientationMask == 3 && !UIInterfaceOrientationIsPortrait(deviceOrientation))) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationPortrait];
        } else if (orientationMask == 2) {
            value = [NSNumber numberWithInt:UIInterfaceOrientationPortraitUpsideDown];
        }
    } else {
        if (_lastOrientation != UIInterfaceOrientationUnknown) {
            [[UIDevice currentDevice] setValue:[NSNumber numberWithInt:_lastOrientation] forKey:@"orientation"];
            if ([vc respondsToSelector:selector]) {
                ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(vc, selector, result);
            }
            [UINavigationController attemptRotationToDeviceOrientation];
        }
    }
    if (value != nil) {
        _isLocked = true;
        [[UIDevice currentDevice] setValue:value forKey:@"orientation"];
    } else {
        _isLocked = false;
    }
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 160000
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

-(void)handleAboveEqualIos16WithOrientationMask:(NSInteger)orientationMask
                                 viewController:(CDVViewController*)vc
                                         result:(NSMutableArray*)result
                                       selector:(SEL)selector
{
    NSObject *value;

    if (orientationMask != 15) {
        if (!_isLocked) {
            _lastOrientation = [UIApplication sharedApplication].statusBarOrientation;
        }
        UIInterfaceOrientation deviceOrientation = [UIApplication sharedApplication].statusBarOrientation;

        if (orientationMask == 8 || (orientationMask == 12 && !UIInterfaceOrientationIsLandscape(deviceOrientation))) {
            [self setLockedMask:UIInterfaceOrientationMaskLandscapeLeft];
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeLeft];
        } else if (orientationMask == 4) {
            [self setLockedMask:UIInterfaceOrientationMaskLandscapeRight];
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight];
        } else if (orientationMask == 1 || (orientationMask == 3 && !UIInterfaceOrientationIsPortrait(deviceOrientation))) {
            [self setLockedMask:UIInterfaceOrientationMaskPortrait];
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        } else if (orientationMask == 2) {
            [self setLockedMask:UIInterfaceOrientationMaskPortraitUpsideDown];
            value = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortraitUpsideDown];
        }
    } else {
        [self clearLockedMask];
        if ([vc respondsToSelector:selector]) {
            ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(vc, selector, result);
        }
    }

    if (value != nil) {
        _isLocked = true;
        // Tell UIKit to re-query supportedInterfaceOrientations BEFORE requesting
        // the geometry change, so both gates agree at the same moment.
        [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
        UIWindowScene *scene = (UIWindowScene*)[[UIApplication.sharedApplication connectedScenes] anyObject];
        [scene requestGeometryUpdateWithPreferences:(UIWindowSceneGeometryPreferencesIOS*)value
                                      errorHandler:^(NSError * _Nonnull error) {
            NSLog(@"Failed to change orientation %@ %@", error, [error userInfo]);
        }];
    } else {
        _isLocked = false;
        [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
    }
}
#pragma clang diagnostic pop

-(void)handleWithOrientationMask:(NSInteger)orientationMask
                  viewController:(CDVViewController*)vc
                          result:(NSMutableArray*)result
                        selector:(SEL)selector
{
    if (@available(iOS 16.0, *)) {
        [self handleAboveEqualIos16WithOrientationMask:orientationMask viewController:vc result:result selector:selector];
        [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
    } else {
        [self handleBelowEqualIos15WithOrientationMask:orientationMask viewController:vc result:result selector:selector];
    }
}
#else
-(void)handleWithOrientationMask:(NSInteger)orientationMask
                  viewController:(CDVViewController*)vc
                          result:(NSMutableArray*)result
                        selector:(SEL)selector
{
    [self handleBelowEqualIos15WithOrientationMask:orientationMask viewController:vc result:result selector:selector];
}
#endif

-(void)screenOrientation:(CDVInvokedUrlCommand *)command
{
    CDVPluginResult *pluginResult;
    NSInteger orientationMask = [[command argumentAtIndex:0] integerValue];
    CDVViewController *vc = (CDVViewController*)self.viewController;
    NSMutableArray *result = [[NSMutableArray alloc] init];

    if (orientationMask & 1) [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortrait]];
    if (orientationMask & 2) [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationPortraitUpsideDown]];
    if (orientationMask & 4) [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeRight]];
    if (orientationMask & 8) [result addObject:[NSNumber numberWithInt:UIInterfaceOrientationLandscapeLeft]];

    SEL selector = NSSelectorFromString(@"setSupportedOrientations:");

    if ([vc respondsToSelector:selector]) {
        if (orientationMask != 15 || [UIDevice currentDevice] == nil) {
            ((void (*)(CDVViewController*, SEL, NSMutableArray*))objc_msgSend)(vc, selector, result);
        }
    }

    if ([UIDevice currentDevice] != nil) {
        [self handleWithOrientationMask:orientationMask viewController:vc result:result selector:selector];
    }

    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

@end
