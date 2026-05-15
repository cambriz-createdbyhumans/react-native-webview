#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Runtime swizzle of WKContentView's edit-menu hooks. WKContentView is the
// private subview that owns selection-menu presentation in WKWebView, so
// overrides on the outer RNCWKWebView never reach Speak/Spell injected by
// iOS Accessibility. When the enclosing WKWebView is an RNCWKWebView with
// disableTextHighlightMenu=YES, suppress the menu; otherwise call through
// to the original implementation unchanged.

static IMP gOriginalBuildMenu = NULL;
static IMP gOriginalCanPerform = NULL;

static UIView * RNCFindEnclosingRNCWebView(UIView *view) {
    Class target = NSClassFromString(@"RNCWKWebView");
    if (!target) return nil;
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:target]) return v;
        v = v.superview;
    }
    return nil;
}

static BOOL RNCShouldSuppressMenuFor(UIView *contentView) {
    UIView *web = RNCFindEnclosingRNCWebView(contentView);
    if (!web) return NO;
    NSNumber *flag = [web valueForKey:@"disableTextHighlightMenu"];
    return [flag boolValue];
}

static void rnc_swizzled_buildMenu(id self, SEL _cmd, id<UIMenuBuilder> builder) {
    if (RNCShouldSuppressMenuFor(self)) {
        if (@available(iOS 16.0, *)) {
            NSArray<UIMenuIdentifier> *ids = @[
                UIMenuStandardEdit,
                UIMenuReplace,
                UIMenuLookup,
                UIMenuShare,
                UIMenuFormat,
                UIMenuSubstitutions,
                UIMenuTransformations,
                UIMenuSpeech,
                UIMenuLearn,
                UIMenuOpen,
            ];
            for (UIMenuIdentifier mid in ids) {
                [builder removeMenuForIdentifier:mid];
            }
        }
        return;
    }
    ((void(*)(id, SEL, id))gOriginalBuildMenu)(self, _cmd, builder);
}

static BOOL rnc_swizzled_canPerform(id self, SEL _cmd, SEL action, id sender) {
    if (RNCShouldSuppressMenuFor(self)) return NO;
    return ((BOOL(*)(id, SEL, SEL, id))gOriginalCanPerform)(self, _cmd, action, sender);
}

@interface RNCWebViewMenuSuppression : NSObject
@end

@implementation RNCWebViewMenuSuppression

+ (void)load {
    Class cv = NSClassFromString(@"WKContentView");
    if (!cv) return;

    SEL bSel = @selector(buildMenuWithBuilder:);
    Method bOrig = class_getInstanceMethod(cv, bSel);
    if (bOrig) {
        // class_getInstanceMethod walks up the inheritance chain. If the IMP
        // is inherited from UIResponder, install a local copy on WKContentView
        // first so method_setImplementation only affects WKContentView itself.
        IMP fwd = class_getMethodImplementation(cv, bSel);
        class_addMethod(cv, bSel, fwd, method_getTypeEncoding(bOrig));
        bOrig = class_getInstanceMethod(cv, bSel);
        gOriginalBuildMenu = method_setImplementation(bOrig, (IMP)rnc_swizzled_buildMenu);
    }

    SEL cSel = @selector(canPerformAction:withSender:);
    Method cOrig = class_getInstanceMethod(cv, cSel);
    if (cOrig) {
        IMP fwd = class_getMethodImplementation(cv, cSel);
        class_addMethod(cv, cSel, fwd, method_getTypeEncoding(cOrig));
        cOrig = class_getInstanceMethod(cv, cSel);
        gOriginalCanPerform = method_setImplementation(cOrig, (IMP)rnc_swizzled_canPerform);
    }
}

@end
