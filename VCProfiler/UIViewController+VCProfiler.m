//
//  UIViewController+VCProfiler.m
//  VCProfiler
//
//  Created by 潘名扬 on 2018/5/31.
//  Copyright © 2018 Punmy. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "UIViewController+VCProfiler.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define VCP_LOG_ENABLE 1

#ifdef VCP_LOG_ENABLE
#define VCLog(...) NSLog(__VA_ARGS__)
#else
#define VCLog(...)
#endif


static char const kAssociatedRemoverKey;

static NSString *const kUniqueFakeKeyPath = @"pmy_useless_key_path";


#pragma mark - IMP of Key Method

static void pmy_loadView(UIViewController *kvo_self, SEL _sel) {
    Class kvo_cls = object_getClass(kvo_self);
    Class origin_cls = class_getSuperclass(kvo_cls);
    IMP origin_imp = method_getImplementation(class_getInstanceMethod(origin_cls, _sel));
    assert(origin_imp != NULL);

    void (*func)(UIViewController *, SEL) = (void (*)(UIViewController *, SEL))origin_imp;

    VCLog(@"VC: %p -loadView \t\tbegin  at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
    func(kvo_self, _sel);
    VCLog(@"VC: %p -loadView \t\tfinish at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
}

static void pmy_viewDidLoad(UIViewController *kvo_self, SEL _sel) {
    Class kvo_cls = object_getClass(kvo_self);
    Class origin_cls = class_getSuperclass(kvo_cls);
    IMP origin_imp = method_getImplementation(class_getInstanceMethod(origin_cls, _sel));
    assert(origin_imp != NULL);

    void (*func)(UIViewController *, SEL) = (void (*)(UIViewController *, SEL))origin_imp;

    VCLog(@"VC: %p -viewDidLoad \t\tbegin  at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
    func(kvo_self, _sel);
    VCLog(@"VC: %p -viewDidLoad \t\tfinish at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
}

static void pmy_viewWillAppear(UIViewController *kvo_self, SEL _sel, BOOL animated) {
    Class kvo_cls = object_getClass(kvo_self);
    Class origin_cls = class_getSuperclass(kvo_cls);

    IMP origin_imp = method_getImplementation(class_getInstanceMethod(origin_cls, _sel));
    assert(origin_imp != NULL);

    void (*func)(UIViewController *, SEL, BOOL) = (void (*)(UIViewController *, SEL, BOOL))origin_imp;

    VCLog(@"VC: %p -viewWillAppear \tbegin  at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
    func(kvo_self, _sel, animated);
    VCLog(@"VC: %p -viewWillAppear \tfinish at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
}

static void pmy_viewDidAppear(UIViewController *kvo_self, SEL _sel, BOOL animated) {
    Class kvo_cls = object_getClass(kvo_self);
    Class origin_cls = class_getSuperclass(kvo_cls);
    IMP origin_imp = method_getImplementation(class_getInstanceMethod(origin_cls, _sel));
    assert(origin_imp != NULL);

    void (*func)(UIViewController *, SEL, BOOL) = (void (*)(UIViewController *, SEL, BOOL))origin_imp;

    VCLog(@"VC: %p -viewDidAppear \tbegin  at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
    func(kvo_self, _sel, animated);
    VCLog(@"VC: %p -viewDidAppear \tfinish at CF time:\t%lf", kvo_self, CFAbsoluteTimeGetCurrent());
}


#pragma mark -

@implementation MTHFakeKVOObserver

+ (instancetype)shared {
    static id sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

@end


#pragma mark -

@implementation MTHFakeKVORemover

- (void)dealloc {
    VCLog(@"dealloc: %@", _target);
    [_target removeObserver:[MTHFakeKVOObserver shared] forKeyPath:_keyPath];
    _target = nil;
}

@end


#pragma mark -

@implementation UIViewController (VCDetector)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [UIViewController class];
        [self swizzleMethodInClass:class originalMethod:@selector(initWithNibName:bundle:) swizzledSelector:@selector(pmy_initWithNibName:bundle:)];
        [self swizzleMethodInClass:class originalMethod:@selector(initWithCoder:) swizzledSelector:@selector(pmy_initWithCoder:)];
    });
}

- (instancetype)pmy_initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    [self createAndHookKVOClass];
    [self pmy_initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    return self;
}

- (nullable instancetype)pmy_initWithCoder:(NSCoder *)aDecoder {
    [self createAndHookKVOClass];
    [self pmy_initWithCoder:aDecoder];
    return self;
}

- (void)createAndHookKVOClass {
    // Setup KVO, which trigger runtime to create the KVO subclass of VC.
    [self addObserver:[MTHFakeKVOObserver shared] forKeyPath:kUniqueFakeKeyPath options:NSKeyValueObservingOptionNew context:nil];

    // Setup remover of KVO, automatically remove KVO when VC dealloc.
    MTHFakeKVORemover *remover = [[MTHFakeKVORemover alloc] init];
    remover.target = self;
    remover.keyPath = kUniqueFakeKeyPath;
    objc_setAssociatedObject(self, &kAssociatedRemoverKey, remover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // NSKVONotifying_ViewController
    Class kvoCls = object_getClass(self);

    // Compare current Imp with our Imp. Make sure we didn't hooked before.
    IMP currentViewDidLoadImp = class_getMethodImplementation(kvoCls, @selector(viewDidLoad));
    if (currentViewDidLoadImp == (IMP)pmy_viewDidLoad) {
        return;
    }

    // ViewController
    Class originCls = class_getSuperclass(kvoCls);

    VCLog(@"Hook %@", kvoCls);

    // 获取原来实现的encoding
    const char *originLoadViewEncoding = method_getTypeEncoding(class_getInstanceMethod(originCls, @selector(loadView)));
    const char *originViewDidLoadEncoding = method_getTypeEncoding(class_getInstanceMethod(originCls, @selector(viewDidLoad)));
    const char *originViewDidAppearEncoding = method_getTypeEncoding(class_getInstanceMethod(originCls, @selector(viewDidAppear:)));
    const char *originViewWillAppearEncoding = method_getTypeEncoding(class_getInstanceMethod(originCls, @selector(viewWillAppear:)));

    // 重点，添加方法。
    class_addMethod(kvoCls, @selector(loadView), (IMP)pmy_loadView, originLoadViewEncoding);
    class_addMethod(kvoCls, @selector(viewDidLoad), (IMP)pmy_viewDidLoad, originViewDidLoadEncoding);
    class_addMethod(kvoCls, @selector(viewDidAppear:), (IMP)pmy_viewDidAppear, originViewDidAppearEncoding);
    class_addMethod(kvoCls, @selector(viewWillAppear:), (IMP)pmy_viewWillAppear, originViewWillAppearEncoding);
}

+ (void)swizzleMethodInClass:(Class) class originalMethod:(SEL)originalSelector swizzledSelector:(SEL)swizzledSelector
{
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
}

@end
