#import <AppKit/AppKit.h>
#import <ScreenSaver/ScreenSaver.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) { NSLog(@"%@", error); return 1; }
        Class cls = bundle.principalClass;
        if (![cls isSubclassOfClass:ScreenSaverView.class]) return 3;
        ScreenSaverView *view = [[cls alloc] initWithFrame:NSMakeRect(0, 0, 960, 600) isPreview:YES];
        if (!view) return 4;
        [view startAnimation];
        for (int i = 0; i < 10; i++) [view animateOneFrame];
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
        [view stopAnimation];
        printf("PASS saver bundle load, principal class, animation lifecycle, and preview render\n");
    }
    return 0;
}
