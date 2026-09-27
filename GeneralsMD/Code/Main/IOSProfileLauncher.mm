#include "IOSProfileLauncher.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <atomic>
#include <cstring>
#include <cstdio>
#include <cmath>
#include <unistd.h>

#ifndef GX_LAUNCHER_COMMIT
#define GX_LAUNCHER_COMMIT "unknown"
#endif
#ifndef GX_ENGINE_COMMIT
#define GX_ENGINE_COMMIT "unknown"
#endif
#ifndef GX_BASE_SHELL_RUN
#define GX_BASE_SHELL_RUN "unknown"
#endif
#ifndef GX_PROJECT_VERSION
#define GX_PROJECT_VERSION "0.0.0"
#endif
#ifndef GX_ENGINE_VERSION
#define GX_ENGINE_VERSION "0.0.0"
#endif
#ifndef GX_LAUNCHER_VERSION
#define GX_LAUNCHER_VERSION "0.0.0"
#endif
#ifndef GX_LAUNCHER_RUN
#define GX_LAUNCHER_RUN "unknown"
#endif

namespace
{
std::atomic<bool> gLauncherFinished(false);
char gSelectedProfile[32] = "vanilla";

NSString *ShortBuildIdentifier(const char *raw)
{
    if (raw == nullptr || raw[0] == '\0')
        return @"unknown";

    NSString *value = [NSString stringWithUTF8String:raw];
    if (value == nil || value.length == 0)
        return @"unknown";

    if ([value isEqualToString:@"unknown"] || value.length <= 10)
        return value;

    return [value substringToIndex:10];
}

NSString *DocumentsFilePath(NSString *name)
{
    return [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
            stringByAppendingPathComponent:name];
}

unsigned long long FileSizeAtPath(NSString *path)
{
    NSDictionary<NSFileAttributeKey, id> *attributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    return attributes != nil ? [attributes fileSize] : 0;
}

NSString *HumanReadableBytes(unsigned long long bytes)
{
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

unsigned long long DirectorySizeAtPath(NSString *path)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDirectoryEnumerator<NSString *> *enumerator = [fileManager enumeratorAtPath:path];
    if (enumerator == nil)
        return 0;

    unsigned long long total = 0;
    for (NSString *relativePath in enumerator)
    {
        NSString *fullPath = [path stringByAppendingPathComponent:relativePath];
        NSDictionary<NSFileAttributeKey, id> *attributes =
            [fileManager attributesOfItemAtPath:fullPath error:nil];
        if ([[attributes fileType] isEqualToString:NSFileTypeRegular])
            total += [attributes fileSize];
    }
    return total;
}

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

NSString *BundledAutoLaunchProfile()
{
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *markerPath = [resourcePath stringByAppendingPathComponent:@"AutoLaunchProfile.txt"];

    NSError *error = nil;
    NSString *value = [NSString stringWithContentsOfFile:markerPath
                                                encoding:NSUTF8StringEncoding
                                                   error:&error];
    if (value == nil)
        return nil;

    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    const char *utf8 = [value UTF8String];
    if (!IsSupportedProfile(utf8))
    {
        fprintf(stderr, "WARNING: iOS launcher ignored unsupported AutoLaunchProfile '%s'\n",
                utf8 != nullptr ? utf8 : "<null>");
        return nil;
    }

    return value;
}

NSString *IPadOverridesPath()
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/iPadOverrides.ini"];
}

bool ProfileDirectoryExists(NSString *profileDirectory)
{
    NSString *resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString *path = [[resourcePath stringByAppendingPathComponent:@"Profiles"]
                      stringByAppendingPathComponent:profileDirectory];

    BOOL isDirectory = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path
                                               isDirectory:&isDirectory] && isDirectory;
}

NSString *DefaultIPadOverrides()
{
    // GeneralsX @feature dvorovrus 26/09/2026 Default shared iPad tuning.
    return @"GameData\n"
            @"  MaxCameraHeight = 550.0\n"
            @"  MinCameraHeight = 70.0\n"
            @"  CameraPitch = 37.0\n"
            @"  EnforceMaxCameraHeight = No\n"
            @"  KeyboardScrollSpeedFactor = 1.0\n"
            @"  TerrainDrawDistanceScale = 1.20\n"
            @"  UseFPSLimit = Yes\n"
            @"  FramesPerSecondLimit = 60\n"
            @"End\n";
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
    [button.heightAnchor constraintEqualToConstant:58.0].active = YES;
    return button;
}
}

@interface GXProfileLauncherViewController : UIViewController
@property(nonatomic, strong) UIStackView *menuStack;
@property(nonatomic, strong) UIView *settingsView;
@property(nonatomic, strong) UILabel *settingsStatus;
@property(nonatomic, strong) UISlider *maxCameraSlider;
@property(nonatomic, strong) UISlider *minCameraSlider;
@property(nonatomic, strong) UISlider *cameraPitchSlider;
@property(nonatomic, strong) UISlider *scrollSpeedSlider;
@property(nonatomic, strong) UISlider *drawDistanceSlider;
@property(nonatomic, strong) UISlider *fpsSlider;
@property(nonatomic, strong) UILabel *maxCameraValue;
@property(nonatomic, strong) UILabel *minCameraValue;
@property(nonatomic, strong) UILabel *cameraPitchValue;
@property(nonatomic, strong) UILabel *scrollSpeedValue;
@property(nonatomic, strong) UILabel *drawDistanceValue;
@property(nonatomic, strong) UILabel *fpsValue;
@property(nonatomic, strong) UISwitch *enforceMaxSwitch;
@property(nonatomic, strong) UISwitch *fpsLimitSwitch;
@property(nonatomic, strong) UIView *diagnosticsView;
@property(nonatomic, strong) UILabel *diagnosticsText;
@property(nonatomic, strong) UIButton *shareDiagnosticsButton;
@property(nonatomic, assign) BOOL diagnosticsScanRunning;
@end

@implementation GXProfileLauncherViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = UIColor.blackColor;
    EnsureDefaultIPadOverrides();

    [self buildMenu];
    [self buildSettings];
    [self buildDiagnostics];
}

- (void)buildMenu
{
    UILabel *title = MakeLabel(@"ZERO HOUR", 34.0, UIFontWeightBold);
    UILabel *subtitle = MakeLabel(@"iPad launcher", 14.0, UIFontWeightRegular);
    subtitle.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];

    UIButton *vanilla = MakeButton(@"Zero Hour 1.04", self, @selector(launchVanilla));
    UIButton *settings = MakeButton(@"Settings", self, @selector(showSettings));
    UIButton *diagnostics = MakeButton(@"Diagnostics", self, @selector(showDiagnostics));
    settings.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];
    diagnostics.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1.0];

    NSMutableArray<UIView *> *views = [NSMutableArray arrayWithObjects:title, subtitle, vanilla, nil];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray arrayWithObject:vanilla];

    if (ProfileDirectoryExists(@"enhanced"))
    {
        UIButton *enhanced = MakeButton(@"Zero Hour Enhanced", self, @selector(launchEnhanced));
        [views addObject:enhanced];
        [buttons addObject:enhanced];
        fprintf(stderr, "INFO: iOS launcher found Enhanced profile\n");
    }

    if (ProfileDirectoryExists(@"contra-x"))
    {
        UIButton *contra = MakeButton(@"Contra X Beta 2 + Patch 1", self, @selector(launchContra));
        [views addObject:contra];
        [buttons addObject:contra];
        fprintf(stderr, "INFO: iOS launcher found Contra X profile\n");
    }

    [views addObject:settings];
    [buttons addObject:settings];
    [views addObject:diagnostics];
    [buttons addObject:diagnostics];

    for (UIButton *button in buttons)
        [button.widthAnchor constraintEqualToConstant:460.0].active = YES;

    self.menuStack = [[UIStackView alloc] initWithArrangedSubviews:views];
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

- (UISlider *)makeSliderWithMin:(float)minimum max:(float)maximum
{
    UISlider *slider = [[UISlider alloc] init];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = minimum;
    slider.maximumValue = maximum;
    slider.minimumTrackTintColor = UIColor.whiteColor;
    slider.maximumTrackTintColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    [slider addTarget:self action:@selector(settingsSliderChanged:) forControlEvents:UIControlEventValueChanged];
    return slider;
}

- (UILabel *)makeValueLabel
{
    UILabel *label = MakeLabel(@"", 15.0, UIFontWeightSemibold);
    label.textAlignment = NSTextAlignmentRight;
    label.font = [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [label.widthAnchor constraintEqualToConstant:72.0].active = YES;
    return label;
}

- (UIStackView *)sliderRow:(NSString *)title slider:(UISlider *)slider value:(UILabel *)value
{
    UILabel *name = MakeLabel(title, 15.0, UIFontWeightMedium);
    name.textAlignment = NSTextAlignmentLeft;

    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[slider, value]];
    line.axis = UILayoutConstraintAxisHorizontal;
    line.alignment = UIStackViewAlignmentCenter;
    line.spacing = 14.0;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[name, line]];
    row.axis = UILayoutConstraintAxisVertical;
    row.alignment = UIStackViewAlignmentFill;
    row.spacing = 7.0;
    row.layoutMargins = UIEdgeInsetsMake(10.0, 14.0, 10.0, 14.0);
    row.layoutMarginsRelativeArrangement = YES;
    row.backgroundColor = [UIColor colorWithWhite:0.055 alpha:1.0];
    row.layer.cornerRadius = 9.0;
    return row;
}

- (UIStackView *)switchRow:(NSString *)title control:(UISwitch *)control
{
    UILabel *name = MakeLabel(title, 15.0, UIFontWeightMedium);
    name.textAlignment = NSTextAlignmentLeft;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[name, control]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.distribution = UIStackViewDistributionFill;
    row.spacing = 18.0;
    row.layoutMargins = UIEdgeInsetsMake(10.0, 14.0, 10.0, 14.0);
    row.layoutMarginsRelativeArrangement = YES;
    row.backgroundColor = [UIColor colorWithWhite:0.055 alpha:1.0];
    row.layer.cornerRadius = 9.0;
    return row;
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
        [self.settingsView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:18.0],
        [self.settingsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18.0],
    ]];

    UILabel *title = MakeLabel(@"Game settings", 26.0, UIFontWeightBold);
    title.textAlignment = NSTextAlignmentLeft;

    UILabel *note = MakeLabel(@"Shared settings for every installed profile. Changes apply on the next game launch.", 13.0, UIFontWeightRegular);
    note.textAlignment = NSTextAlignmentLeft;
    note.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];

    self.maxCameraSlider = [self makeSliderWithMin:300.0f max:800.0f];
    self.minCameraSlider = [self makeSliderWithMin:40.0f max:150.0f];
    self.cameraPitchSlider = [self makeSliderWithMin:20.0f max:60.0f];
    self.scrollSpeedSlider = [self makeSliderWithMin:0.5f max:2.0f];
    self.drawDistanceSlider = [self makeSliderWithMin:0.5f max:2.0f];
    self.fpsSlider = [self makeSliderWithMin:30.0f max:120.0f];

    self.maxCameraValue = [self makeValueLabel];
    self.minCameraValue = [self makeValueLabel];
    self.cameraPitchValue = [self makeValueLabel];
    self.scrollSpeedValue = [self makeValueLabel];
    self.drawDistanceValue = [self makeValueLabel];
    self.fpsValue = [self makeValueLabel];

    self.enforceMaxSwitch = [[UISwitch alloc] init];
    self.fpsLimitSwitch = [[UISwitch alloc] init];
    [self.fpsLimitSwitch addTarget:self action:@selector(fpsLimitChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *controls = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self sliderRow:@"Maximum camera height" slider:self.maxCameraSlider value:self.maxCameraValue],
        [self sliderRow:@"Minimum camera height" slider:self.minCameraSlider value:self.minCameraValue],
        [self sliderRow:@"Camera pitch" slider:self.cameraPitchSlider value:self.cameraPitchValue],
        [self switchRow:@"Enforce maximum camera height" control:self.enforceMaxSwitch],
        [self sliderRow:@"Keyboard / edge scroll speed" slider:self.scrollSpeedSlider value:self.scrollSpeedValue],
        [self sliderRow:@"Terrain draw distance" slider:self.drawDistanceSlider value:self.drawDistanceValue],
        [self switchRow:@"FPS limit" control:self.fpsLimitSwitch],
        [self sliderRow:@"Frames per second" slider:self.fpsSlider value:self.fpsValue],
    ]];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    controls.axis = UILayoutConstraintAxisVertical;
    controls.alignment = UIStackViewAlignmentFill;
    controls.spacing = 9.0;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;
    [scroll addSubview:controls];

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
    [self.settingsView addSubview:scroll];
    [self.settingsView addSubview:buttons];
    [self.settingsView addSubview:self.settingsStatus];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:self.settingsView.topAnchor],

        [note.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [note.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],

        [scroll.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:note.bottomAnchor constant:12.0],
        [scroll.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-12.0],

        [controls.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [controls.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [controls.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [controls.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [controls.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],

        [buttons.centerXAnchor constraintEqualToAnchor:self.settingsView.centerXAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:self.settingsStatus.topAnchor constant:-7.0],

        [self.settingsStatus.leadingAnchor constraintEqualToAnchor:self.settingsView.leadingAnchor],
        [self.settingsStatus.trailingAnchor constraintEqualToAnchor:self.settingsView.trailingAnchor],
        [self.settingsStatus.bottomAnchor constraintEqualToAnchor:self.settingsView.bottomAnchor],
    ]];

    [self resetSettingsControls];
}


- (NSString *)diagnosticsTextWithGameDataSize:(NSString *)gameDataSize
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *shortVersion = [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *buildVersion = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
    NSString *resourcePath = bundle.resourcePath ?: @"";
    NSString *gameDataPath = [resourcePath stringByAppendingPathComponent:@"GameData"];

    BOOL gameDataExists = [[NSFileManager defaultManager] fileExistsAtPath:gameDataPath];
    BOOL enhancedInstalled = ProfileDirectoryExists(@"enhanced");
    BOOL contraInstalled = ProfileDirectoryExists(@"contra-x");

    NSString *currentLog = DocumentsFilePath(@"generals-stderr.log");
    NSString *previousLog = DocumentsFilePath(@"generals-stderr-prev.log");
    NSString *settingsPath = IPadOverridesPath();

    BOOL currentLogExists = [[NSFileManager defaultManager] fileExistsAtPath:currentLog];
    BOOL previousLogExists = [[NSFileManager defaultManager] fileExistsAtPath:previousLog];
    BOOL settingsExists = [[NSFileManager defaultManager] fileExistsAtPath:settingsPath];

    NSString *currentLogText = currentLogExists
        ? [NSString stringWithFormat:@"Yes (%@)", HumanReadableBytes(FileSizeAtPath(currentLog))]
        : @"No";
    NSString *previousLogText = previousLogExists
        ? [NSString stringWithFormat:@"Yes (%@)", HumanReadableBytes(FileSizeAtPath(previousLog))]
        : @"No";

    return [NSString stringWithFormat:
        @"APP\n"
         "Project: %s\n"
         "Bundle: %@ (%@)\n"
         "iOS: %@\n"
         "Device: %@\n\n"
         "BUILD\n"
         "Launcher: v%s · %@\n"
         "Launcher run: %@\n"
         "Engine: v%s · %@\n"
         "Base shell run: %@\n\n"
         "CONTENT\n"
         "GameData: %@\n"
         "GameData size: %@\n"
         "Enhanced: %@\n"
         "Contra X: %@\n\n"
         "FILES\n"
         "Settings: %@\n"
         "Current log: %@\n"
         "Previous log: %@\n",
        GX_PROJECT_VERSION,
        shortVersion,
        buildVersion,
        UIDevice.currentDevice.systemVersion,
        UIDevice.currentDevice.model,
        GX_LAUNCHER_VERSION,
        ShortBuildIdentifier(GX_LAUNCHER_COMMIT),
        ShortBuildIdentifier(GX_LAUNCHER_RUN),
        GX_ENGINE_VERSION,
        ShortBuildIdentifier(GX_ENGINE_COMMIT),
        ShortBuildIdentifier(GX_BASE_SHELL_RUN),
        gameDataExists ? @"Installed" : @"Missing",
        gameDataSize,
        enhancedInstalled ? @"Installed" : @"Not installed",
        contraInstalled ? @"Installed" : @"Not installed",
        settingsExists ? @"Present" : @"Missing",
        currentLogText,
        previousLogText];
}

- (void)buildDiagnostics
{
    self.diagnosticsView = [[UIView alloc] init];
    self.diagnosticsView.translatesAutoresizingMaskIntoConstraints = NO;
    self.diagnosticsView.backgroundColor = UIColor.blackColor;
    self.diagnosticsView.hidden = YES;
    [self.view addSubview:self.diagnosticsView];

    [NSLayoutConstraint activateConstraints:@[
        [self.diagnosticsView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:28.0],
        [self.diagnosticsView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-28.0],
        [self.diagnosticsView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:18.0],
        [self.diagnosticsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-18.0],
    ]];

    UILabel *title = MakeLabel(@"Diagnostics", 26.0, UIFontWeightBold);
    title.textAlignment = NSTextAlignmentLeft;

    UILabel *note = MakeLabel(@"Build, installed content and crash logs. GameData size is calculated in the background.", 13.0, UIFontWeightRegular);
    note.textAlignment = NSTextAlignmentLeft;
    note.textColor = [UIColor colorWithWhite:0.62 alpha:1.0];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = YES;

    self.diagnosticsText = MakeLabel(@"", 15.0, UIFontWeightRegular);
    self.diagnosticsText.textAlignment = NSTextAlignmentLeft;
    self.diagnosticsText.font = [UIFont monospacedSystemFontOfSize:15.0 weight:UIFontWeightRegular];
    [scroll addSubview:self.diagnosticsText];

    UIButton *refresh = MakeButton(@"Refresh", self, @selector(refreshDiagnostics));
    self.shareDiagnosticsButton = MakeButton(@"Share report + logs", self, @selector(shareDiagnostics));
    UIButton *back = MakeButton(@"Back", self, @selector(hideDiagnostics));

    [refresh.widthAnchor constraintEqualToConstant:180.0].active = YES;
    [self.shareDiagnosticsButton.widthAnchor constraintEqualToConstant:220.0].active = YES;
    [back.widthAnchor constraintEqualToConstant:180.0].active = YES;

    UIStackView *buttons = [[UIStackView alloc] initWithArrangedSubviews:@[
        refresh, self.shareDiagnosticsButton, back
    ]];
    buttons.translatesAutoresizingMaskIntoConstraints = NO;
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.alignment = UIStackViewAlignmentCenter;
    buttons.spacing = 12.0;

    [self.diagnosticsView addSubview:title];
    [self.diagnosticsView addSubview:note];
    [self.diagnosticsView addSubview:scroll];
    [self.diagnosticsView addSubview:buttons];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:self.diagnosticsView.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:self.diagnosticsView.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:self.diagnosticsView.topAnchor],

        [note.leadingAnchor constraintEqualToAnchor:self.diagnosticsView.leadingAnchor],
        [note.trailingAnchor constraintEqualToAnchor:self.diagnosticsView.trailingAnchor],
        [note.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],

        [scroll.leadingAnchor constraintEqualToAnchor:self.diagnosticsView.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.diagnosticsView.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:note.bottomAnchor constant:14.0],
        [scroll.bottomAnchor constraintEqualToAnchor:buttons.topAnchor constant:-14.0],

        [self.diagnosticsText.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [self.diagnosticsText.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [self.diagnosticsText.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [self.diagnosticsText.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [self.diagnosticsText.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],

        [buttons.centerXAnchor constraintEqualToAnchor:self.diagnosticsView.centerXAnchor],
        [buttons.bottomAnchor constraintEqualToAnchor:self.diagnosticsView.bottomAnchor],
    ]];
}

- (void)showDiagnostics
{
    self.menuStack.hidden = YES;
    self.settingsView.hidden = YES;
    self.diagnosticsView.hidden = NO;
    [self refreshDiagnostics];
}

- (void)hideDiagnostics
{
    self.diagnosticsView.hidden = YES;
    self.menuStack.hidden = NO;
}

- (void)refreshDiagnostics
{
    if (self.diagnosticsScanRunning)
        return;

    self.diagnosticsScanRunning = YES;
    self.diagnosticsText.text = [self diagnosticsTextWithGameDataSize:@"Calculating…"];

    NSString *resourcePath = [NSBundle mainBundle].resourcePath ?: @"";
    NSString *gameDataPath = [resourcePath stringByAppendingPathComponent:@"GameData"];
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:gameDataPath];

    __weak GXProfileLauncherViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        unsigned long long bytes = exists ? DirectorySizeAtPath(gameDataPath) : 0;
        NSString *sizeText = exists ? HumanReadableBytes(bytes) : @"n/a";

        dispatch_async(dispatch_get_main_queue(), ^{
            GXProfileLauncherViewController *strongSelf = weakSelf;
            if (strongSelf == nil)
                return;

            strongSelf.diagnosticsScanRunning = NO;
            strongSelf.diagnosticsText.text =
                [strongSelf diagnosticsTextWithGameDataSize:sizeText];
        });
    });
}

- (void)shareDiagnostics
{
    NSMutableArray *items = [NSMutableArray array];

    NSString *reportPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"GeneralsZH-Diagnostics.txt"];
    NSError *writeError = nil;
    BOOL wroteReport = [self.diagnosticsText.text writeToFile:reportPath
                                                  atomically:YES
                                                    encoding:NSUTF8StringEncoding
                                                       error:&writeError];
    if (wroteReport)
        [items addObject:[NSURL fileURLWithPath:reportPath]];
    else
        [items addObject:self.diagnosticsText.text ?: @"Generals ZH diagnostics unavailable"];

    for (NSString *name in @[@"generals-stderr.log", @"generals-stderr-prev.log"])
    {
        NSString *path = DocumentsFilePath(name);
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            [items addObject:[NSURL fileURLWithPath:path]];
    }

    UIActivityViewController *activity =
        [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];

    UIPopoverPresentationController *popover = activity.popoverPresentationController;
    if (popover != nil)
    {
        popover.sourceView = self.shareDiagnosticsButton;
        popover.sourceRect = self.shareDiagnosticsButton.bounds;
    }

    [self presentViewController:activity animated:YES completion:nil];

    if (!wroteReport && writeError != nil)
    {
        fprintf(stderr, "WARNING: failed to write diagnostics report: %s\n",
                [[writeError description] UTF8String]);
    }
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

- (NSString *)valueForKey:(NSString *)key inContents:(NSString *)contents
{
    NSString *prefix = [key stringByAppendingString:@"="];
    for (NSString *line in [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
    {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *compact = [trimmed stringByReplacingOccurrencesOfString:@" " withString:@""];
        if ([compact hasPrefix:prefix])
        {
            NSRange equals = [trimmed rangeOfString:@"="];
            if (equals.location != NSNotFound)
            {
                return [[trimmed substringFromIndex:equals.location + 1]
                        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
        }
    }
    return nil;
}

- (float)floatSetting:(NSString *)key contents:(NSString *)contents fallback:(float)fallback
{
    NSString *value = [self valueForKey:key inContents:contents];
    return value.length > 0 ? value.floatValue : fallback;
}

- (BOOL)boolSetting:(NSString *)key contents:(NSString *)contents fallback:(BOOL)fallback
{
    NSString *value = [[self valueForKey:key inContents:contents] lowercaseString];
    if ([value isEqualToString:@"yes"] || [value isEqualToString:@"true"] || [value isEqualToString:@"1"])
        return YES;
    if ([value isEqualToString:@"no"] || [value isEqualToString:@"false"] || [value isEqualToString:@"0"])
        return NO;
    return fallback;
}

- (void)resetSettingsControls
{
    self.maxCameraSlider.value = 550.0f;
    self.minCameraSlider.value = 70.0f;
    self.cameraPitchSlider.value = 37.0f;
    self.enforceMaxSwitch.on = NO;
    self.scrollSpeedSlider.value = 1.0f;
    self.drawDistanceSlider.value = 1.20f;
    self.fpsLimitSwitch.on = YES;
    self.fpsSlider.value = 60.0f;
    [self settingsSliderChanged:nil];
    [self fpsLimitChanged:self.fpsLimitSwitch];
}

- (void)loadSettingsControls
{
    NSError *error = nil;
    NSString *contents = [NSString stringWithContentsOfFile:IPadOverridesPath()
                                                   encoding:NSUTF8StringEncoding
                                                      error:&error];
    if (contents == nil)
    {
        [self resetSettingsControls];
        self.settingsStatus.text = @"Using defaults.";
        if (error != nil)
        {
            fprintf(stderr, "WARNING: iOS launcher could not read iPadOverrides.ini: %s\n",
                    [[error description] UTF8String]);
        }
        return;
    }

    self.maxCameraSlider.value = [self floatSetting:@"MaxCameraHeight" contents:contents fallback:550.0f];
    self.minCameraSlider.value = [self floatSetting:@"MinCameraHeight" contents:contents fallback:70.0f];
    self.cameraPitchSlider.value = [self floatSetting:@"CameraPitch" contents:contents fallback:37.0f];
    self.enforceMaxSwitch.on = [self boolSetting:@"EnforceMaxCameraHeight" contents:contents fallback:NO];
    self.scrollSpeedSlider.value = [self floatSetting:@"KeyboardScrollSpeedFactor" contents:contents fallback:1.0f];
    self.drawDistanceSlider.value = [self floatSetting:@"TerrainDrawDistanceScale" contents:contents fallback:1.20f];
    self.fpsLimitSwitch.on = [self boolSetting:@"UseFPSLimit" contents:contents fallback:YES];
    self.fpsSlider.value = [self floatSetting:@"FramesPerSecondLimit" contents:contents fallback:60.0f];
    [self settingsSliderChanged:nil];
    [self fpsLimitChanged:self.fpsLimitSwitch];
    self.settingsStatus.text = @"";
}

- (void)showSettings
{
    [self loadSettingsControls];
    self.menuStack.hidden = YES;
    self.settingsView.hidden = NO;
}

- (void)hideSettings
{
    self.settingsView.hidden = YES;
    self.menuStack.hidden = NO;
}

- (void)settingsSliderChanged:(UISlider *)sender
{
    auto snap = [](float value, float step) -> float {
        return roundf(value / step) * step;
    };

    self.maxCameraSlider.value = snap(self.maxCameraSlider.value, 10.0f);
    self.minCameraSlider.value = snap(self.minCameraSlider.value, 5.0f);
    self.cameraPitchSlider.value = snap(self.cameraPitchSlider.value, 1.0f);
    self.scrollSpeedSlider.value = snap(self.scrollSpeedSlider.value, 0.1f);
    self.drawDistanceSlider.value = snap(self.drawDistanceSlider.value, 0.05f);
    self.fpsSlider.value = snap(self.fpsSlider.value, 5.0f);

    self.maxCameraValue.text = [NSString stringWithFormat:@"%.0f", self.maxCameraSlider.value];
    self.minCameraValue.text = [NSString stringWithFormat:@"%.0f", self.minCameraSlider.value];
    self.cameraPitchValue.text = [NSString stringWithFormat:@"%.0f°", self.cameraPitchSlider.value];
    self.scrollSpeedValue.text = [NSString stringWithFormat:@"%.1fx", self.scrollSpeedSlider.value];
    self.drawDistanceValue.text = [NSString stringWithFormat:@"%.2fx", self.drawDistanceSlider.value];
    self.fpsValue.text = [NSString stringWithFormat:@"%.0f", self.fpsSlider.value];
}

- (void)fpsLimitChanged:(UISwitch *)sender
{
    BOOL enabled = self.fpsLimitSwitch.on;
    self.fpsSlider.enabled = enabled;
    self.fpsSlider.alpha = enabled ? 1.0 : 0.35;
    self.fpsValue.alpha = enabled ? 1.0 : 0.35;
}

- (void)saveSettings
{
    NSString *contents = [NSString stringWithFormat:
        @"GameData\n"
         "  MaxCameraHeight = %.1f\n"
         "  MinCameraHeight = %.1f\n"
         "  CameraPitch = %.1f\n"
         "  EnforceMaxCameraHeight = %@\n"
         "  KeyboardScrollSpeedFactor = %.1f\n"
         "  TerrainDrawDistanceScale = %.2f\n"
         "  UseFPSLimit = %@\n"
         "  FramesPerSecondLimit = %.0f\n"
         "End\n",
        self.maxCameraSlider.value,
        self.minCameraSlider.value,
        self.cameraPitchSlider.value,
        self.enforceMaxSwitch.on ? @"Yes" : @"No",
        self.scrollSpeedSlider.value,
        self.drawDistanceSlider.value,
        self.fpsLimitSwitch.on ? @"Yes" : @"No",
        self.fpsSlider.value];

    NSError *error = nil;
    BOOL ok = [contents writeToFile:IPadOverridesPath()
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:&error];
    if (ok)
    {
        self.settingsStatus.text = @"Saved. Changes apply on the next game launch.";
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
    [self resetSettingsControls];
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
        fprintf(stderr, "INFO: iOS launcher forced profile: %s\n", gSelectedProfile);
        return gSelectedProfile;
    }

    // Dedicated variants can opt into a standalone boot without changing the
    // shared launcher binary. The Contra-only packager drops this marker in the
    // app bundle; All-in-one and other variants do not.
    NSString *autoProfile = BundledAutoLaunchProfile();
    if (autoProfile != nil)
    {
        const char *utf8 = [autoProfile UTF8String];
        strlcpy(gSelectedProfile, utf8, sizeof(gSelectedProfile));
        fprintf(stderr, "INFO: iOS launcher auto-selected bundled profile: %s\n",
                gSelectedProfile);
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
