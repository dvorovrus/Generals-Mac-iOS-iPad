#include "IOSProfileLauncher.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <atomic>
#include <cstring>
#include <cstdio>
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
    fprintf(stderr, "INFO: iOS native launcher selected profile: %s\n", gSelectedProfile);
    gLauncherFinished.store(true, std::memory_order_release);
}

NSString *IPadOverridesPath()
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/iPadOverrides.ini"];
}

NSString *DefaultIPadOverrides()
{
    // GeneralsX @feature dvorovrus 26/09/2026 Default shared iPad tuning.
    return @"GameData\n"
            "  MaxCameraHeight = 550.0\n"
            "  MinCameraHeight = 70.0\n"
            "  CameraPitch = 37.0\n"
            "  EnforceMaxCameraHeight = No\n"
            "  KeyboardScrollSpeedFactor = 1.0\n"
            "  TerrainDrawDistanceScale = 1.20\n"
            "  UseFPSLimit = Yes\n"
            "  FramesPerSecondLimit = 60\n"
            "End\n";
}

void EnsureDefaultIPadOverrides()
{
    NSString *path = IPadOverridesPath();
    if ([[NSFileManager defaultManager] fileExistsAtPath:path])
        return;

    NSError *error = nil;
    BOOL ok = [DefaultIPadOverrides() writeToFile:path
                                      atomically:YES
                                        encoding:NSUTF8StringEncoding
                                           error:&error];
    if (ok)
    {
        fprintf(stderr, "INFO: iOS launcher seeded %s\n", path.fileSystemRepresentation);
    }
    else
    {
        fprintf(stderr, "ERROR: iOS launcher failed to seed iPadOverrides.ini: %s\n",
                [[error description] UTF8String]);
    }
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

UILabel *MakeLabel(NSString *text, CGFloat size, UIFontWeight weight)
{
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.numberOfLines = 0;
    return label;
}

UIButton *MakeButton(NSString *title, id target, SEL action)
{
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:19.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    button.layer.cornerRadius = 10.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:0.28 alpha:1.0].CGColor;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:460.0],
        [button.heightAnchor constraintEqualToConstant:58.0],
    ]];
    return button;
}
}

@interface GXProfileLauncherViewController : UIViewController
@property(nonatomic, strong) UIStackView *menuStack;
@property(nonatomic, strong) UIView *settingsView;
@property(nonatomic, strong) UITextView *settingsEditor;
@property(nonatomic, strong) UILabel *settingsStatus;
@end

@implementation GXProfileLauncherViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.blackColor;
    EnsureDefaultIPadOverrides();

    [self buildMenu];
    [self buildSettings];
}

- (void)buildMenu
{
    UILabel *title = MakeLabel(@"ZERO HOUR", 34.0, UIFontWeightBold);
    UILabel *subtitle = MakeLabel(@"iPad launcher", 14.0, UIFontWeightRegular);
    subtitle.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];

    UIButton *vanilla = MakeButton(@"Zero Hour 1.04", self, @selector(launchVanilla));
    UIButton *enhanced = MakeButton(@"Zero Hour Enhanced", self, @selector(launchEnhanced));
    UIButton *contra = MakeButton(@"Contra X Beta 2 + Patch 1", self, @selector(launchContra));
    UIButton *settings = MakeButton(@"Settings", self, @selector(showSettings));
    settings.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];

    self.menuStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, subtitle, vanilla, enhanced, contra, settings
    ]];
    self.menuStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.menuStack.axis = UILayoutConstraintAxisVertical;
    self.menuStack.alignment = UIStackViewAlignmentCenter;
    self.menuStack.spacing = 12.0;
    [self.menuStack setCustomSpacing:26.0 afterView:subtitle];

    [self.view addSubview:self.menuStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.menuStack.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.menuStack.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
    ]];
}

- (void)buildSettings
{
    self.settingsView = [[UIView alloc] init];
    self.settingsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsView.backgroundColor = UIColor.blackColor;
    self.settingsView.hidden = YES;
    [self.view addSubview:self.settingsView];

    [NSLayoutConstraint activateConstraints:@[
        [self.settingsView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:28.0],
        [self.settingsView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-28.0],
        [self.settingsView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20.0],
        [self.settingsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-20.0],
    ]];

    UILabel *title = MakeLabel(@"iPadOverrides.ini", 26.0, UIFontWeightBold);
    title.textAlignment = NSTextAlignmentLeft;

    UILabel *note = MakeLabel(@"Shared settings — applied to Zero Hour, Enhanced and Contra X on the next launch.", 13.0, UIFontWeightRegular);
    note.textAlignment = NSTextAlignmentLeft;
    note.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];

    self.settingsEditor = [[UITextView alloc] init];
    self.settingsEditor.translatesAutoresizingMaskIntoConstraints = NO;
    self.settingsEditor.backgroundColor = [UIColor colorWithWhite:0.055 alpha:1.0];
    self.settingsEditor.textColor = UIColor.whiteColor;
    self.settingsEditor.tintColor = UIColor.whiteColor;
    self.settingsEditor.font = [UIFont monospacedSystemFontOfSize:17.0 weight:UIFontWeightRegular];
    self.settingsEditor.layer.cornerRadius = 8.0;
    self.settingsEditor.layer.borderWidth = 1.0;
    self.settingsEditor.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1.0].CGColor;
    self.settingsEditor.textContainerInset = UIEdgeInsetsMake(14.0, 14.0, 14.0, 14.0);
    self.settingsEditor.autocorrectionType = UITextAutocorrectionTypeNo;
    self.settingsEditor.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.settingsEditor.smartQuotesType = UITextSmartQuotesTypeNo;
    self.settingsEditor.smartDashesType = UITextSmartDashesTypeNo;
    self.settingsEditor.spellCheckingType = UITextSpellCheckingTypeNo;

    UIButton *save = MakeButton(@"Save", self, @selector(saveSettings));
    UIButton *reset = MakeButton(@"Reset defaults", self, @selector(resetSettings));
    UIButton *back = MakeButton(@"Back", self, @selector(hideSettings));

    [save.widthAnchor constraintEqualToConstant:180.0].active = YES;
    [reset.widthAnchor constraintEqualToConstant:180.0].active = YES;
    [back.widthAnchor constraintEqualToConstant:180.0].active = YES;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[save, reset, back]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.alignment = UIStackViewAlignmentCenter;
    buttons.distribution = UIStackViewDistributionEqualSpacing;
    buttons.spacing = 12.0;

    self.settingsStatus = MakeLabel(@"", 13.0, UIFontWeightRegular);
    self.settingsStatus.textAlignment = NSTextAlignmentLeft;
    self.settingsStatus.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];

    [self.settingsView addSubview:title];
    [self.settingsView addSubview:note];
    [self.settingsView addSubview:self.settingsEditor];
    [self.settingsView addSubview:buttons];
    [self.settingsView addSubview:self.settingsStatus];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:self.settingsView.topAnchor],

        [note.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [note.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],

        [self.settingsEditor.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [self.settingsEditor.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [self.settingsEditor.topAnchor constraintEqualToAnchor:note.bottomAnchor constant:14.0],
        [self.settingsEditor.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-14.0],

        [buttons.centerXAnchor constraintEqualToAnchor:self.settingsView.centerXAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:self.settingsStatus.topAnchor constant:-8.0],

        [self.settingsStatus.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [self.settingsStatus.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [self.settingsStatus.bottomAnchor constraintEqualToAnchor:self.settingsView.bottomAnchor],
    ]];
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

- (void)launchVanilla
{
    SetSelectedProfile(@"vanilla");
}

- (void)launchEnhanced
{
    SetSelectedProfile(@"enhanced");
}

- (void)launchContra
{
    SetSelectedProfile(@"contra-x");
}

- (void)showSettings
{
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:IPadOverridesPath()
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (contents == nil)
    {
        contents = DefaultIPadOverrides();
        self.settingsStatus.text = @"Using defaults; Save will create iPadOverrides.ini.";
        if (error != nil)
        {
            fprintf(stderr, "WARNING: iOS launcher could not read iPadOverrides.ini: %s\n",
                    [[error description] UTF8String]);
        }
    }
    else
    {
        self.settingsStatus.text = @"";
    }

    self.settingsEditor.text = contents;
    self.menuStack.hidden = YES;
    self.settingsView.hidden = NO;
}

- (void)hideSettings
{
    [self.settingsEditor resignFirstResponder];
    self.settingsView.hidden = YES;
    self.menuStack.hidden = NO;
}

- (void)saveSettings
{
    NSString *contents = self.settingsEditor.text ?: @"";
    NSString *trimmed = [contents stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (trimmed.length == 0 ||
        [contents rangeOfString:@"GameData"].location == NSNotFound ||
        [contents rangeOfString:@"End"].location == NSNotFound)
    {
        self.settingsStatus.text = @"Not saved: the file must contain GameData ... End.";
        self.settingsStatus.textColor = [UIColor systemRedColor];
        return;
    }

    NSError *error = nil;
    BOOL ok = [contents writeToFile:IPadOverridesPath()
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];
    if (ok)
    {
        self.settingsStatus.text = @"Saved. These values will apply to every profile on launch.";
        self.settingsStatus.textColor = [UIColor systemGreenColor];
        fprintf(stderr, "INFO: iOS launcher saved %s\n",
                IPadOverridesPath().fileSystemRepresentation);
    }
    else
    {
        self.settingsStatus.text = @"Save failed. See generals-stderr.log.";
        self.settingsStatus.textColor = [UIColor systemRedColor];
        fprintf(stderr, "ERROR: iOS launcher failed to save iPadOverrides.ini: %s\n",
                [[error description] UTF8String]);
    }
}

- (void)resetSettings
{
    self.settingsEditor.text = DefaultIPadOverrides();
    self.settingsStatus.text = @"Default values loaded. Tap Save to apply.";
    self.settingsStatus.textColor = [UIColor colorWithWhite:0.65 alpha:1.0];
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

        fprintf(stderr, "INFO: iOS native launcher presented\n");
    };

    if ([NSThread isMainThread])
    {
        presentLauncher();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), presentLauncher);
    }

    // SDL's iOS bootstrap is already inside UIApplicationMain. Keep the native
    // main run loop alive until a profile is selected.
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
