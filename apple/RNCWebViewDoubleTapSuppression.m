#import <WebKit/WebKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// Disables WKContentView's double-tap gesture recognizers for any
// RNCWKWebView. iOS routes double-tap-to-select-word and double-tap-to-zoom
// through UITapGestureRecognizers with numberOfTapsRequired >= 2 attached to
// WKContentView. Long-press selection lives on a separate
// UILongPressGestureRecognizer and is unaffected.
//
// We intercept at the point of attachment by swizzling
// -[WKContentView addGestureRecognizer:]. Every recognizer WebKit installs —
// at init, after document load, or lazily on first interaction — passes
// through here, so there is no timing window where a double-tap recognizer
// could slip through.

static IMP gOriginalAddGestureRecognizer = NULL;

static BOOL RNCIsInsideRNCWebView(UIView *view) {
    Class target = NSClassFromString(@"RNCWKWebView");
    if (!target) return NO;
    UIView *v = view;
    while (v) {
        if ([v isKindOfClass:target]) return YES;
        v = v.superview;
    }
    return NO;
}

static BOOL RNCIsDoubleTapRecognizer(UIGestureRecognizer *gr) {
    if (![gr isKindOfClass:[UITapGestureRecognizer class]]) return NO;
    return ((UITapGestureRecognizer *)gr).numberOfTapsRequired >= 2;
}

static void rnc_swizzled_addGestureRecognizer(id self, SEL _cmd, UIGestureRecognizer *gr) {
    ((void(*)(id, SEL, UIGestureRecognizer *))gOriginalAddGestureRecognizer)(self, _cmd, gr);
    if (RNCIsDoubleTapRecognizer(gr) && RNCIsInsideRNCWebView((UIView *)self)) {
        gr.enabled = NO;
    }
}

@interface RNCWebViewDoubleTapSuppression : NSObject
@end

@implementation RNCWebViewDoubleTapSuppression

+ (void)load {
    Class cv = NSClassFromString(@"WKContentView");
    if (!cv) return;

    SEL sel = @selector(addGestureRecognizer:);
    Method orig = class_getInstanceMethod(cv, sel);
    if (!orig) return;

    // class_getInstanceMethod walks the inheritance chain. Install a local
    // copy on WKContentView first so method_setImplementation only affects
    // WKContentView itself, not every UIView in the app.
    IMP fwd = class_getMethodImplementation(cv, sel);
    class_addMethod(cv, sel, fwd, method_getTypeEncoding(orig));
    orig = class_getInstanceMethod(cv, sel);
    gOriginalAddGestureRecognizer = method_setImplementation(orig, (IMP)rnc_swizzled_addGestureRecognizer);
}

@end
