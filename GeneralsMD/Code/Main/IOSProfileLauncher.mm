#include "IOSProfileLauncher.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

#include <atomic>
#include <cstring>
#include <unistd.h>

namespace
{
std::atomic<bool> gLauncherFinished(false);
char gSelectedProfile[32] = "vanilla";

bool IsSupportedProfile(const char *profile)
{
    return profile != nullptr &&
        (strcmp(profile, "vanilla") == 0 ||
         strcmp(profile, "enhanced") == 0 ||
         strcmp(profile, "contra-x") == 0);
}

void SetSelectedProfile(NSString *profile)
{
    if (profile == nil)
        return;

    const char *utf8 = [profile UTF8String];
    if (!IsSupportedProfile(utf8))
        return;

    strlcpy(gSelectedProfile, utf8, sizeof(gSelectedProfile));
    gLauncherFinished.store(true, std::memory_order_release);
}

UIWindowScene *FindActiveWindowScene()
{
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes)
    {
        if (![scene isKindOfClass:[UIWindowScene class]])
            continue;

        if (scene.activationState == UISceneActivationStateForegroundActive ||
            scene.activationState == UISceneActivationStateForegroundInactive)
        {
            return (UIWindowScene *)scene;
        }
    }

    return nil;
}
}

@interface GXProfileLauncherViewController : UIViewController <WKScriptMessageHandler>
@property(nonatomic, strong) WKWebView *webView;
@end

@implementation GXProfileLauncherViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor blackColor];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *contentController = [[WKUserContentController alloc] init];
    [contentController addScriptMessageHandler:self name:@"launchProfile"];
    configuration.userContentController = contentController;

    self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.opaque = NO;
    self.webView.backgroundColor = [UIColor blackColor];
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;

    [self.view addSubview:self.webView];

    NSURL *indexURL = [[NSBundle mainBundle] URLForResource:@"index"
                                             withExtension:@"html"
                                              subdirectory:@"Launcher"];
    if (indexURL == nil)
    {
        NSLog(@"GeneralsX launcher: Launcher/index.html is missing, falling back to vanilla.");
        SetSelectedProfile(@"vanilla");
        return;
    }

    NSURL *readAccessURL = [indexURL URLByDeletingLastPathComponent];
    [self.webView loadFileURL:indexURL allowingReadAccessToURL:readAccessURL];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (![message.name isEqualToString:@"launchProfile"])
        return;

    if (![message.body isKindOfClass:[NSDictionary class]])
        return;

    NSDictionary *body = (NSDictionary *)message.body;
    id value = body[@"profile"];
    if (![value isKindOfClass:[NSString class]])
        return;

    SetSelectedProfile((NSString *)value);
}

- (void)dealloc
{
    [self.webView.configuration.userContentController removeScriptMessageHandlerForName:@"launchProfile"];
}

@end

const char *GeneralsXRunIOSProfileLauncher()
{
    // GeneralsX @feature dvorovrus 25/09/2026 Allow automation/debug builds to skip the UI.
    const char *forcedProfile = getenv("GX_LAUNCH_PROFILE");
    if (IsSupportedProfile(forcedProfile))
    {
        strlcpy(gSelectedProfile, forcedProfile, sizeof(gSelectedProfile));
        return gSelectedProfile;
    }

    gLauncherFinished.store(false, std::memory_order_release);
    strlcpy(gSelectedProfile, "vanilla", sizeof(gSelectedProfile));

    __block UIWindow *launcherWindow = nil;

    void (^presentLauncher)(void) = ^{
        UIWindowScene *scene = FindActiveWindowScene();
        if (scene != nil)
        {
            launcherWindow = [[UIWindow alloc] initWithWindowScene:scene];
            launcherWindow.frame = scene.coordinateSpace.bounds;
        }
        else
        {
            launcherWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }

        launcherWindow.windowLevel = UIWindowLevelNormal + 1.0;
        launcherWindow.rootViewController = [[GXProfileLauncherViewController alloc] init];
        [launcherWindow makeKeyAndVisible];
    };

    if ([NSThread isMainThread])
    {
        presentLauncher();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), presentLauncher);
    }

    // SDL's iOS bootstrap has already entered UIApplicationMain before calling SDL_main.
    // When SDL_main is on the main thread, keep the native run loop pumping so WKWebView
    // remains fully interactive until the user chooses a profile.
    if ([NSThread isMainThread])
    {
        while (!gLauncherFinished.load(std::memory_order_acquire))
        {
            @autoreleasepool
            {
                [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode
                                      beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
        }
    }
    else
    {
        while (!gLauncherFinished.load(std::memory_order_acquire))
        {
            usleep(10000);
        }
    }

    void (^dismissLauncher)(void) = ^{
        launcherWindow.hidden = YES;
        launcherWindow.rootViewController = nil;
        launcherWindow = nil;
    };

    if ([NSThread isMainThread])
    {
        dismissLauncher();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), dismissLauncher);
    }

    return gSelectedProfile;
}

#endif
