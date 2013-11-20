//
//  NNMultiDispatchManager.m
//  NNKit
//
//  Created by Scott Perry on 11/19/13.
//  Copyright © 2013 Scott Perry.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//

#import "NNMultiDispatchManager.h"

#import "NNMutableWeakSet.h"
#import "despatch.h"
#import "nn_autofree.h"
#import "runtime.h"


@interface NNMultiDispatchManager ()

@property (nonatomic, readonly, assign) Protocol *protocol;
@property (nonatomic, readonly, strong) NSMutableDictionary *signatureCache;
@property (nonatomic, readonly, strong) NNMutableWeakSet *observers;

@end


@implementation NNMultiDispatchManager

- (instancetype)initWithProtocol:(Protocol *)protocol;
{
    if (!(self = [super init])) { return nil; }
    
    self->_enabled = YES;
    self->_protocol = protocol;
    self->_signatureCache = [NSMutableDictionary new];
    [self _cacheMethodSignaturesForProcotol:protocol];
    self->_observers = [NNMutableWeakSet new];

    return self;
}

- (void)addObserver:(id)observer;
{
    NSParameterAssert([observer conformsToProtocol:self.protocol]);
    
    [self.observers addObject:observer];
}

- (void)removeObserver:(id)observer;
{
    [self.observers removeObject:observer];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector;
{
    return [self.signatureCache objectForKey:NSStringFromSelector(aSelector)];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation;
{
    if (self.enabled) {
        NSAssert(strstr(anInvocation.methodSignature.methodReturnType, "v"), @"Method return type must be void.");
        dispatch_block_t dispatch = ^{
            for (id obj in self.observers) {
                if ([obj respondsToSelector:anInvocation.selector]) {
                    [anInvocation invokeWithTarget:obj];
                }
            }
        };
        if (anInvocation.methodSignature.isOneway) {
            [anInvocation retainArguments];
            dispatch_async(dispatch_get_main_queue(), dispatch);
        } else {
            despatch_sync_main_reentrant(dispatch);
        }
    }
    
    anInvocation.target = nil;
    [anInvocation invoke];
}

#pragma mark Private

- (void)_cacheMethodSignaturesForProcotol:(Protocol *)protocol;
{
    unsigned int totalCount;
    for (uint8_t i = 0; i < 1 << 1; ++i) {
        struct objc_method_description *methodDescriptions = nn_autofree(protocol_copyMethodDescriptionList(protocol, i & 1, YES, &totalCount));
        
        for (unsigned j = 0; j < totalCount; j++) {
            struct objc_method_description *methodDescription = methodDescriptions + j;
            [self.signatureCache setObject:[NSMethodSignature signatureWithObjCTypes:methodDescription->types] forKey:NSStringFromSelector(methodDescription->name)];
        }
    }
    
    // Recurse to include other protocols to which this protocol adopts
    Protocol * __unsafe_unretained *adoptions = (Protocol * __unsafe_unretained*)nn_autofree(protocol_copyProtocolList(protocol, &totalCount));
    for (unsigned j = 0; j < totalCount; j++) {
        [self _cacheMethodSignaturesForProcotol:adoptions[j]];
    }
}

@end