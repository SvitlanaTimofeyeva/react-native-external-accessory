/**
 * Copyright 2017 David Bolcsfoldi <david@bolcsfoldi.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 */

#import "EAMExternalAccessory.h"

#import <Foundation/Foundation.h>
#import <ExternalAccessory/ExternalAccessory.h>

#import <React/RCTBridge.h>
#import <React/RCTConvert.h>
#import <React/RCTUIManager.h>

@interface EAMExternalAccessoryBrowser () <EAWiFiUnconfiguredAccessoryBrowserDelegate>
@end

@implementation EAMExternalAccessoryBrowser
{
    EAWiFiUnconfiguredAccessoryBrowser *_accessoryBrowser;
    BOOL _hasListeners;
}

RCT_EXPORT_MODULE()

#pragma mark - Lifecycle

- (void) dealloc
{
    [_accessoryBrowser stopSearchingForUnconfiguredAccessories];
    _accessoryBrowser.delegate = nil;
}

- (NSArray<NSString *> *) supportedEvents
{
    return @[
             @"didFindUnconfiguredAccessories",
             @"didRemoveUnconfiguredAccessories",
             @"didFinishConfiguringAccessory",
             @"didUpdateState" ];
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

- (void) startObserving {
    _hasListeners = YES;
}

- (void) stopObserving {
    _hasListeners = NO;
}

#pragma mark - Public API

RCT_EXPORT_METHOD(startSearch)
{
    if (!_accessoryBrowser) {
        _accessoryBrowser = [[EAWiFiUnconfiguredAccessoryBrowser alloc] initWithDelegate: self
                                                                                   queue: nil];
    }
    
    [_accessoryBrowser startSearchingForUnconfiguredAccessoriesMatchingPredicate: nil];
}

RCT_EXPORT_METHOD(stopSearch)
{
    if (_accessoryBrowser) {
        [_accessoryBrowser stopSearchingForUnconfiguredAccessories];
    }
}

RCT_EXPORT_METHOD(unconfiguredAccessories: (RCTPromiseResolveBlock) resolver reject: (RCTPromiseRejectBlock) rejecter)
{
    if (!_accessoryBrowser) {
        _accessoryBrowser = [[EAWiFiUnconfiguredAccessoryBrowser alloc] initWithDelegate: self
                                                                                   queue: dispatch_get_main_queue()];
    }
    
    NSSet <EAWiFiUnconfiguredAccessory *> *accessories = [_accessoryBrowser unconfiguredAccessories];
    NSMutableArray *accessoryList = [NSMutableArray arrayWithCapacity: [accessories count]];
    
    [accessories enumerateObjectsUsingBlock:^(EAWiFiUnconfiguredAccessory * _Nonnull obj, BOOL * _Nonnull stop) {
        [accessoryList addObject: [self accessoryToJson: obj]];
    }];
    
    resolver(accessoryList);
}

RCT_EXPORT_METHOD(configureAccessory: (NSDictionary *) accessory
                  resolve: (RCTPromiseResolveBlock) resolver
                  reject: (RCTPromiseRejectBlock) rejecter)
{
    BOOL __block notFound = YES;
    [[_accessoryBrowser unconfiguredAccessories] enumerateObjectsUsingBlock: ^(EAWiFiUnconfiguredAccessory * _Nonnull obj, BOOL * _Nonnull stop) {
        if ([obj.name isEqual: accessory[@"name"]] &&
            [obj.manufacturer isEqual: accessory[@"manufacturer"]] &&
            [obj.model isEqual: accessory[@"model"]] &&
            [obj.ssid isEqual: accessory[@"ssid"]] &&
            [obj.macAddress isEqual: accessory[@"macAddress"]]) {
            *stop = YES;
            
            UIView *responder = [RCTUIManager JSResponder];
            UIViewController *controller = [[responder window] rootViewController];
            [_accessoryBrowser configureAccessory: obj withConfigurationUIOnViewController: controller];
            
            resolver(@(YES));
            notFound = NO;
        }
    }];
    
    if (notFound) {
        rejecter(@"no_accessory", @"No such accessory", nil);
    }
}

#pragma mark - Private methods

- (NSArray<id> *) makeAccessoryList: (NSSet<EAWiFiUnconfiguredAccessory *> *) accessories
{
    NSMutableArray<id> *accessoryList = [NSMutableArray arrayWithCapacity: [accessories count]];
    
    [accessories enumerateObjectsUsingBlock:^(EAWiFiUnconfiguredAccessory * _Nonnull obj, BOOL * _Nonnull stop) {
        [accessoryList addObject: [self accessoryToJson: obj]];
    }];
    
    return accessoryList;
}

- (NSDictionary <NSString *, id> *) accessoryToJson: (EAWiFiUnconfiguredAccessory *) accessory
{
    return @{
      @"name": accessory.name,
      @"manufacturer": accessory.manufacturer,
      @"model": accessory.model,
      @"ssid": accessory.ssid,
      @"macAddress": accessory.macAddress,
      @"supportsAirPlay": @(accessory.properties & EAWiFiUnconfiguredAccessoryPropertySupportsAirPlay),
      @"supportsAirPrint": @(accessory.properties & EAWiFiUnconfiguredAccessoryPropertySupportsAirPrint),
      @"supportsHomeKit": @(accessory.properties & EAWiFiUnconfiguredAccessoryPropertySupportsHomeKit)
      };
}

#pragma mark - EAWiFiUnconfiguredAccessoryBrowserDelegate

static const NSString *kStates[] = { @"WiFiUnavailable", @"Stopped", @"Searching", @"Configuring" };

- (void) accessoryBrowser: (EAWiFiUnconfiguredAccessoryBrowser *) browser
           didUpdateState: (EAWiFiUnconfiguredAccessoryBrowserState) state
{
    const NSString *s = @"Unknown";
   
    if (state >= EAWiFiUnconfiguredAccessoryBrowserStateWiFiUnavailable &&
        state < EAWiFiUnconfiguredAccessoryBrowserStateConfiguring) {
        s = kStates[state];
    }
    
    if (_hasListeners) {
        [self sendEventWithName: @"didUpdateState" body: @{ @"state": s}];
    }
}

- (void) accessoryBrowser: (EAWiFiUnconfiguredAccessoryBrowser *) browser didFindUnconfiguredAccessories: (NSSet<EAWiFiUnconfiguredAccessory *> *) accessories
{
    NSArray<id> *accessoryList = [self makeAccessoryList: accessories];
    if (_hasListeners) {
        [self sendEventWithName: @"didFindUnconfiguredAccessories" body: @{ @"accessories":  accessoryList}];
    }
}

- (void) accessoryBrowser: (EAWiFiUnconfiguredAccessoryBrowser *) browser didRemoveUnconfiguredAccessories: (NSSet<EAWiFiUnconfiguredAccessory *> *) accessories
{
    NSArray<id> *accessoryList = [self makeAccessoryList: accessories];
    if (_hasListeners) {
        [self sendEventWithName: @"didRemoveUnconfiguredAccessories" body: @{ @"accessories":  accessoryList}];
    }
}

static const NSString *kStatus[] = { @"Success", @"UserCancelledConfiguration", @"Failed" };

- (void) accessoryBrowser: (EAWiFiUnconfiguredAccessoryBrowser *) browser didFinishConfiguringAccessory: (EAWiFiUnconfiguredAccessory *) accessory withStatus:(EAWiFiUnconfiguredAccessoryConfigurationStatus) status
{
    if (_hasListeners) {
        [self sendEventWithName: @"didFinishConfiguringAccessory"
                       body: @{
                               @"accessory": [self accessoryToJson: accessory],
                               @"status": kStatus[status]
                               }];
    }
}
@end
