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
#import <objc/runtime.h>

// Global static variable to hold the active mask, mimicking Capacitor's state management
static UIInterfaceOrientationMask currentSupportedInterfaceOrientations = UIInterfaceOrientationMaskAll;

@implementation CDVViewController (CDVOrientationLock)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        SEL originalSelector = @selector(supportedInterfaceOrientations);
        SEL swizzledSelector = @selector(cdvol_supportedInterfaceOrientations);

        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);

        BOOL didAddMethod = class_addMethod(class,
                                            originalSelector,
                                            method_getImplementation(swizzledMethod),
                                            method_getTypeEncoding(swizzledMethod));

        if (didAddMethod) {
            class_replaceMethod(class,
                                swizzledSelector,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (UIInterfaceOrientationMask)cdvol_supportedInterfaceOrientations {
    return currentSupportedInterfaceOrientations;
}

@end

@implementation CDVOrientation

- (UIInterfaceOrientationMask)convertMaskToInterfaceOrientationMask:(NSInteger)orientationMask {
    switch (orientationMask) {
        case 1:  return UIInterfaceOrientationMaskPortrait;
        case 2:  return UIInterfaceOrientationMaskPortraitUpsideDown;
        case 3:  return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
        case 4:  return UIInterfaceOrientationMaskLandscapeRight;
        case 8:  return UIInterfaceOrientationMaskLandscapeLeft;
        case 12: return UIInterfaceOrientationMaskLandscapeLeft | UIInterfaceOrientationMaskLandscapeRight;
        case 15: return UIInterfaceOrientationMaskAll;
        default: return UIInterfaceOrientationMaskAll;
    }
}

- (void)requestGeometryUpdateWithMask:(UIInterfaceOrientationMask)orientationMask fallbackValue:(NSNumber *)fallbackValue {
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *geometryPreferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:orientationMask];
        
        UIWindowScene *activeWindowScene = self.viewController.view.window.windowScene;
        if (activeWindowScene == nil) {
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                    activeWindowScene = (UIWindowScene *)scene;
                    break;
                }
            }
        }

        if (activeWindowScene != nil) {
            [activeWindowScene requestGeometryUpdateWithPreferences:geometryPreferences errorHandler:^(NSError * _Nonnull error) {
                NSLog(@"Geometry update failed: %@", error.localizedDescription);
            }];
        }
    } else {
        if (fallbackValue != nil) {
            [[UIDevice currentDevice] setValue:fallbackValue forKey:@"orientation"];
        }
    }
}

- (void)screenOrientation:(CDVInvokedUrlCommand *)command {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger orientationMask = [[command argumentAtIndex:0] integerValue];
        UIInterfaceOrientationMask mappedMask = [self convertMaskToInterfaceOrientationMask:orientationMask];
        
        currentSupportedInterfaceOrientations = mappedMask;
        [self.viewController setNeedsUpdateOfSupportedInterfaceOrientations];
        
        NSNumber *fallbackValue = nil;
        
        if (orientationMask != 15) {
            if (!self->_isLocked) {
                self->_lastOrientation = [UIApplication sharedApplication].statusBarOrientation;
            }
            self->_isLocked = YES;
            
            if (orientationMask == 8) {
                fallbackValue = @(UIInterfaceOrientationLandscapeLeft);
            } else if (orientationMask == 4) {
                fallbackValue = @(UIInterfaceOrientationLandscapeRight);
            } else if (orientationMask == 1) {
                fallbackValue = @(UIInterfaceOrientationPortrait);
            } else if (orientationMask == 2) {
                fallbackValue = @(UIInterfaceOrientationPortraitUpsideDown);
            }
        } else {
            self->_isLocked = NO;
            if (self->_lastOrientation != UIInterfaceOrientationUnknown) {
                fallbackValue = @(self->_lastOrientation);
            }
        }
        
        [self requestGeometryUpdateWithMask:mappedMask fallbackValue:fallbackValue];
        [UINavigationController attemptRotationToDeviceOrientation];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    });
}

@end
