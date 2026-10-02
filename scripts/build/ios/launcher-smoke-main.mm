#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "IOSProfileLauncher.h"

@interface GXSmokeViewController : UIViewController
@property(nonatomic, strong) UILabel *label;
@end

@implementation GXSmokeViewController
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    self.label = [[UILabel alloc] init];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    self.label.textColor = UIColor.whiteColor;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.numberOfLines = 0;
    self.label.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    self.label.text = @"Opening launcher…";

    [self.view addSubview:self.label];
    [NSLayoutConstraint activateConstraints:@[
        [self.label.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.label.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [self.label.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [self.label.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
    ]];

    dispatch_async(dispatch_get_main_queue(), ^{
        const char *profile = GeneralsXRunIOSProfileLauncher();
        NSString *value = profile != nullptr ? [NSString stringWithUTF8String:profile] : @"unknown";
        self.label.text = [NSString stringWithFormat:
            @"Launcher test passed\n\nSelected profile: %@\n\nClose the app and reopen it to test another profile.",
            value];
    });
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end

@interface GXSmokeAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation GXSmokeAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.blackColor;
    self.window.rootViewController = [[GXSmokeViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([GXSmokeAppDelegate class]));
    }
}
