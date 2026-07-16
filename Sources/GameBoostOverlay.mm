#import "GameBoostShared.h"
#import "GameBoostGlass.h"

static UIColor *GBThemeColor(void) {
    return [UIColor colorWithHue:(CGFloat)gMenuHue.load(std::memory_order_relaxed)
                      saturation:0.58
                      brightness:0.98
                           alpha:1.0];
}

@interface OAGameBoostPassthroughWindow : UIWindow
@end

@implementation OAGameBoostPassthroughWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self || hitView == self.rootViewController.view) {
        return nil;
    }
    return hitView;
}

- (BOOL)canBecomeKeyWindow {
    return NO;
}

@end


@interface OAGameBoostOverlayViewController : UIViewController <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIButton *menuButton;
@property(nonatomic, strong) GBGlassSurfaceView *menuButtonGlass;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) GBGlassSurfaceView *glassView;
@property(nonatomic, strong) UIView *sidebar;
@property(nonatomic, strong) UIView *gameTabRow;
@property(nonatomic, strong) UIView *graphicsTabRow;
@property(nonatomic, strong) UIView *ipadTabRow;
@property(nonatomic, strong) UIView *settingsTabRow;
@property(nonatomic, strong) UIButton *gameTabButton;
@property(nonatomic, strong) UIButton *graphicsTabButton;
@property(nonatomic, strong) UIButton *ipadTabButton;
@property(nonatomic, strong) UIButton *settingsTabButton;
@property(nonatomic, strong) UISwitch *gameMasterSwitch;
@property(nonatomic, strong) UISwitch *graphicsMasterSwitch;
@property(nonatomic, strong) UISwitch *ipadMasterSwitch;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIScrollView *gameScroll;
@property(nonatomic, strong) UIScrollView *graphicsScroll;
@property(nonatomic, strong) UIScrollView *ipadScroll;
@property(nonatomic, strong) UIScrollView *settingsScroll;
@property(nonatomic, strong) UILabel *gameStatusLabel;
@property(nonatomic, strong) UILabel *graphicsStatusLabel;
@property(nonatomic, strong) UILabel *ipadStatusLabel;
@property(nonatomic, strong) UISegmentedControl *ipadProfileControl;
@property(nonatomic, strong) UILabel *ipadProfileHintLabel;
@property(nonatomic, strong) UISwitch *performanceSwitch;
@property(nonatomic, strong) UISwitch *lowLatencySwitch;
@property(nonatomic, strong) UISwitch *keepAwakeSwitch;
@property(nonatomic, strong) UISwitch *landscapeSwitch;
@property(nonatomic, strong) UILabel *landscapeHintLabel;
@property(nonatomic, strong) UISegmentedControl *fpsControl;
@property(nonatomic, strong) UISlider *scaleSlider;
@property(nonatomic, strong) UILabel *scaleValueLabel;
@property(nonatomic, strong) UILabel *scaleHintLabel;
@property(nonatomic, strong) UISlider *graphicsScaleSlider;
@property(nonatomic, strong) UILabel *graphicsScaleValueLabel;
@property(nonatomic, strong) UILabel *graphicsScaleHintLabel;
@property(nonatomic, strong) UISwitch *linearFilteringSwitch;
@property(nonatomic, strong) UISwitch *trilinearFilteringSwitch;
@property(nonatomic, strong) UISlider *anisotropySlider;
@property(nonatomic, strong) UILabel *anisotropyValueLabel;
@property(nonatomic, strong) UISwitch *wideColorSwitch;
@property(nonatomic, strong) UISwitch *highQualityScalingSwitch;
@property(nonatomic, strong) UISlider *menuScaleSlider;
@property(nonatomic, strong) UILabel *menuScaleValueLabel;
@property(nonatomic, strong) UISwitch *menuDragSwitch;
@property(nonatomic, strong) UISlider *hueSlider;
@property(nonatomic, strong) UISlider *opacitySlider;
@property(nonatomic, strong) UILabel *opacityValueLabel;
@property(nonatomic, strong) UISwitch *liquidGlassSwitch;
@property(nonatomic, strong) UIPanGestureRecognizer *panelPanGesture;
@property(nonatomic, assign) NSInteger selectedTab;
@property(nonatomic, assign) BOOL hasInitialButtonPosition;
@property(nonatomic, assign) BOOL hasPanelPosition;
@end

@implementation OAGameBoostOverlayViewController

- (UILabel *)labelWithText:(NSString *)text
                       frame:(CGRect)frame
                        font:(UIFont *)font
                       color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.text = text;
    label.textColor = color;
    label.font = font;
    label.numberOfLines = 0;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    return label;
}

- (UISwitch *)addSwitchRowTo:(UIScrollView *)scroll
                       title:(NSString *)title
                        hint:(NSString *)hint
                           y:(CGFloat)y
                    selector:(SEL)selector {
    const CGFloat width = CGRectGetWidth(scroll.bounds);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(10.0,
                                                            y - 7.0,
                                                            width - 20.0,
                                                            66.0)];
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.040];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 0.6;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.075].CGColor;
    card.userInteractionEnabled = NO;
    [scroll addSubview:card];

    UILabel *titleLabel = [self labelWithText:title
                                         frame:CGRectMake(16.0, y, width - 92.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [scroll addSubview:titleLabel];

    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(width - 67.0,
                                                                  y - 3.0,
                                                                  51.0,
                                                                  31.0)];
    toggle.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [toggle addTarget:self action:selector forControlEvents:UIControlEventValueChanged];
    [scroll addSubview:toggle];

    UILabel *hintLabel = [self labelWithText:hint
                                        frame:CGRectMake(16.0, y + 27.0, width - 32.0, 34.0)
                                         font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular]
                                        color:[UIColor colorWithWhite:0.72 alpha:1.0]];
    [scroll addSubview:hintLabel];
    return toggle;
}

- (UILabel *)addPageTitle:(NSString *)title to:(UIScrollView *)scroll {
    UILabel *label = [self labelWithText:title
                                    frame:CGRectMake(16.0, 12.0,
                                                     CGRectGetWidth(scroll.bounds) - 74.0,
                                                     30.0)
                                     font:[UIFont systemFontOfSize:21.0 weight:UIFontWeightSemibold]
                                    color:UIColor.whiteColor];
    [scroll addSubview:label];
    return label;
}

- (UILabel *)addStatusLabelTo:(UIScrollView *)scroll y:(CGFloat)y {
    UILabel *label = [self labelWithText:@""
                                    frame:CGRectMake(16.0, y,
                                                     CGRectGetWidth(scroll.bounds) - 32.0,
                                                     24.0)
                                     font:[UIFont systemFontOfSize:10.0 weight:UIFontWeightSemibold]
                                    color:UIColor.whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 12.0;
    label.layer.borderWidth = 0.6;
    label.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    label.layer.masksToBounds = YES;
    [scroll addSubview:label];
    return label;
}

- (UIButton *)sidebarButtonWithTitle:(NSString *)title selector:(SEL)selector {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.titleLabel.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    button.titleLabel.numberOfLines = 1;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        NSDictionary<NSString *, NSString *> *symbols = @{
            @"Game": @"gamecontroller.fill",
            @"Display": @"sparkles.rectangle.stack.fill",
            @"iPad View": @"ipad.landscape",
            @"Menu": @"slider.horizontal.3"
        };
        UIImage *image = [UIImage systemImageNamed:symbols[title]];
        button.tintColor = UIColor.whiteColor;
        if (@available(iOS 15.0, *)) {
            UIButtonConfiguration *configuration =
                [UIButtonConfiguration plainButtonConfiguration];
            configuration.title = title;
            configuration.image = image;
            configuration.imagePadding = 10.0;
            configuration.contentInsets = NSDirectionalEdgeInsetsMake(0.0,
                                                                        10.0,
                                                                        0.0,
                                                                        8.0);
            configuration.baseForegroundColor = UIColor.whiteColor;
            button.configuration = configuration;
        } else {
            [button setImage:image forState:UIControlStateNormal];
            if (image != nil) {
                [button setTitle:[@"  " stringByAppendingString:title]
                         forState:UIControlStateNormal];
            }
        }
    }
    [button addTarget:self action:selector forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.selectedTab = GBIsEnhanceGraphicsActive()
        ? 1
        : (gConfiguredIpadModeEnabled.load(std::memory_order_relaxed) ? 2 : 0);

    self.menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.menuButton.frame = CGRectMake(16.0, 96.0, 48.0, 48.0);
    self.menuButton.backgroundColor = UIColor.clearColor;
    self.menuButton.layer.cornerRadius = 24.0;
    self.menuButton.layer.borderWidth = 0.75;
    self.menuButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.menuButton.layer.shadowOpacity = 0.34;
    self.menuButton.layer.shadowRadius = 16.0;
    self.menuButton.layer.shadowOffset = CGSizeMake(0.0, 7.0);
    self.menuButton.titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
    self.menuButton.accessibilityLabel = @"Open GameBoost menu";
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
            configurationWithPointSize:18.0
                                weight:UIImageSymbolWeightSemibold];
        UIImage *image = [[UIImage systemImageNamed:@"speedometer"]
            imageByApplyingSymbolConfiguration:configuration];
        [self.menuButton setImage:image forState:UIControlStateNormal];
    } else {
        [self.menuButton setTitle:@"G" forState:UIControlStateNormal];
    }
    [self.menuButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.menuButtonGlass = [[GBGlassSurfaceView alloc]
        initWithFrame:self.menuButton.bounds
          interactive:YES];
    self.menuButtonGlass.frame = self.menuButton.bounds;
    self.menuButtonGlass.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self.menuButtonGlass setCornerRadius:24.0];
    [self.menuButton insertSubview:self.menuButtonGlass atIndex:0];
    [self.menuButton addTarget:self action:@selector(togglePanel)
              forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *buttonPan =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMenuButton:)];
    buttonPan.delegate = self;
    [self.menuButton addGestureRecognizer:buttonPan];
    [self.view addSubview:self.menuButton];

    self.panel = [[UIView alloc] initWithFrame:CGRectMake(76.0, 80.0, 510.0, 370.0)];
    self.panel.layer.cornerRadius = 28.0;
    self.panel.layer.borderWidth = 0.75;
    self.panel.layer.masksToBounds = NO;
    self.panel.layer.shadowColor = UIColor.blackColor.CGColor;
    self.panel.layer.shadowOpacity = 0.42;
    self.panel.layer.shadowRadius = 28.0;
    self.panel.layer.shadowOffset = CGSizeMake(0.0, 14.0);
    self.panel.hidden = YES;
    [self.view addSubview:self.panel];

    self.glassView = [[GBGlassSurfaceView alloc]
        initWithFrame:self.panel.bounds
          interactive:NO];
    self.glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
        UIViewAutoresizingFlexibleHeight;
    [self.glassView setCornerRadius:28.0];
    [self.panel addSubview:self.glassView];

    self.sidebar = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 148.0, 370.0)];
    self.sidebar.layer.cornerRadius = 28.0;
    self.sidebar.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMinXMaxYCorner;
    self.sidebar.layer.masksToBounds = YES;
    self.sidebar.layer.borderWidth = 0.5;
    self.sidebar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    [self.panel addSubview:self.sidebar];

    UILabel *brandLabel = [self labelWithText:@"GameBoost\nControl Center"
                                         frame:CGRectMake(16.0, 12.0, 112.0, 38.0)
                                          font:[UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    brandLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.sidebar addSubview:brandLabel];

    self.gameTabRow = [UIView new];
    self.gameTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.gameTabRow];
    self.gameTabButton = [self sidebarButtonWithTitle:@"Game"
                                             selector:@selector(selectGameTab)];
    [self.gameTabRow addSubview:self.gameTabButton];

    self.graphicsTabRow = [UIView new];
    self.graphicsTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.graphicsTabRow];
    self.graphicsTabButton = [self sidebarButtonWithTitle:@"Display"
                                                 selector:@selector(selectGraphicsTab)];
    [self.graphicsTabRow addSubview:self.graphicsTabButton];

    self.ipadTabRow = [UIView new];
    self.ipadTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.ipadTabRow];
    self.ipadTabButton = [self sidebarButtonWithTitle:@"iPad View"
                                             selector:@selector(selectIpadTab)];
    [self.ipadTabRow addSubview:self.ipadTabButton];

    self.settingsTabRow = [UIView new];
    self.settingsTabRow.layer.cornerRadius = 14.0;
    [self.sidebar addSubview:self.settingsTabRow];
    self.settingsTabButton = [self sidebarButtonWithTitle:@"Menu"
                                                 selector:@selector(selectSettingsTab)];
    [self.settingsTabRow addSubview:self.settingsTabButton];

    CGRect pageFrame = CGRectMake(148.0, 0.0, 362.0, 370.0);
    self.gameScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    self.graphicsScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    self.ipadScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    self.settingsScroll = [[UIScrollView alloc] initWithFrame:pageFrame];
    for (UIScrollView *scroll in @[self.gameScroll,
                                   self.graphicsScroll,
                                   self.ipadScroll,
                                   self.settingsScroll]) {
        scroll.alwaysBounceVertical = YES;
        scroll.showsVerticalScrollIndicator = YES;
        scroll.backgroundColor = UIColor.clearColor;
        [self.panel addSubview:scroll];
    }

    [self buildGamePage];
    [self buildGraphicsPage];
    [self buildIpadPage];
    [self buildSettingsPage];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(432.0, 4.0, 44.0, 44.0);
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightRegular];
    self.closeButton.accessibilityLabel = @"Close GameBoost menu";
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration
            configurationWithPointSize:13.0
                                weight:UIImageSymbolWeightSemibold];
        UIImage *image = [[UIImage systemImageNamed:@"xmark"]
            imageByApplyingSymbolConfiguration:configuration];
        [self.closeButton setImage:image forState:UIControlStateNormal];
    } else {
        [self.closeButton setTitle:@"×" forState:UIControlStateNormal];
    }
    [self.closeButton setTitleColor:[UIColor colorWithWhite:0.88 alpha:1.0]
                           forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(hidePanel)
               forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.closeButton];

    self.panelPanGesture =
        [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    self.panelPanGesture.delegate = self;
    [self.panel addGestureRecognizer:self.panelPanGesture];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(settingsDidChange)
                                               name:GBSettingsDidChangeNotification
                                             object:nil];
    [self settingsDidChange];
}

- (void)buildGamePage {
    const CGFloat width = CGRectGetWidth(self.gameScroll.bounds);
    [self addPageTitle:@"Game" to:self.gameScroll];
    self.gameMasterSwitch = [[UISwitch alloc]
        initWithFrame:CGRectMake(width - 118.0, 6.0, 51.0, 31.0)];
    self.gameMasterSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.gameMasterSwitch addTarget:self
                              action:@selector(gameMasterChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.gameScroll addSubview:self.gameMasterSwitch];
    self.gameStatusLabel = [self addStatusLabelTo:self.gameScroll y:48.0];

    self.performanceSwitch = [self addSwitchRowTo:self.gameScroll
                                            title:@"Performance QoS"
                                             hint:@"Ưu tiên thread render; không còn tự tắt theo nhiệt."
                                                y:84.0
                                         selector:@selector(performanceSwitchChanged:)];
    self.lowLatencySwitch = [self addSwitchRowTo:self.gameScroll
                                           title:@"Low latency 2-buffer"
                                            hint:@"Giảm hàng đợi Metal; thử tắt nếu game bị khựng."
                                               y:154.0
                                        selector:@selector(lowLatencySwitchChanged:)];
    self.keepAwakeSwitch = [self addSwitchRowTo:self.gameScroll
                                          title:@"Giữ màn hình sáng"
                                           hint:@"Không cho máy tự khóa khi đang chơi."
                                              y:224.0
                                       selector:@selector(keepAwakeSwitchChanged:)];
    self.landscapeSwitch = [self addSwitchRowTo:self.gameScroll
                                          title:@"Khóa ngang game"
                                           hint:@""
                                              y:294.0
                                       selector:@selector(landscapeSwitchChanged:)];
    self.landscapeHintLabel = (UILabel *)self.gameScroll.subviews.lastObject;

    UILabel *fpsLabel = [self labelWithText:@"Giới hạn / ưu tiên FPS"
                                       frame:CGRectMake(16.0, 368.0, width - 32.0, 22.0)
                                        font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                       color:UIColor.whiteColor];
    [self.gameScroll addSubview:fpsLabel];
    self.fpsControl = [[UISegmentedControl alloc] initWithItems:@[@"Auto", @"30", @"60", @"120"]];
    self.fpsControl.frame = CGRectMake(16.0, 397.0, width - 32.0, 32.0);
    self.fpsControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.fpsControl addTarget:self action:@selector(fpsChanged:)
              forControlEvents:UIControlEventValueChanged];
    [self.gameScroll addSubview:self.fpsControl];
    UILabel *fpsHint = [self labelWithText:@"120 chỉ áp dụng khi màn hình và game hỗ trợ."
                                      frame:CGRectMake(16.0, 434.0, width - 32.0, 20.0)
                                       font:[UIFont systemFontOfSize:11.0]
                                      color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.gameScroll addSubview:fpsHint];

    UILabel *scaleLabel = [self labelWithText:@"Độ phân giải app"
                                         frame:CGRectMake(16.0, 466.0, width - 100.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [self.gameScroll addSubview:scaleLabel];
    self.scaleValueLabel = [self labelWithText:@"100%"
                                         frame:CGRectMake(width - 82.0, 466.0, 66.0, 24.0)
                                          font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    self.scaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.scaleValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.gameScroll addSubview:self.scaleValueLabel];
    self.scaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 495.0, width - 32.0, 30.0)];
    self.scaleSlider.minimumValue = 0.1f;
    self.scaleSlider.maximumValue = 1.0f;
    self.scaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.scaleSlider addTarget:self action:@selector(scaleSliderChanged:)
               forControlEvents:UIControlEventValueChanged];
    [self.gameScroll addSubview:self.scaleSlider];
    self.scaleHintLabel = [self labelWithText:@""
                                        frame:CGRectMake(16.0, 528.0, width - 32.0, 34.0)
                                         font:[UIFont systemFontOfSize:11.0]
                                        color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.gameScroll addSubview:self.scaleHintLabel];
    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.frame = CGRectMake(16.0, 570.0, width - 32.0, 34.0);
    resetButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.09];
    resetButton.layer.cornerRadius = 9.0;
    [resetButton setTitle:@"Đặt lại độ phân giải 100%" forState:UIControlStateNormal];
    [resetButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetGameScale)
          forControlEvents:UIControlEventTouchUpInside];
    [self.gameScroll addSubview:resetButton];
    self.gameScroll.contentSize = CGSizeMake(width, 622.0);
}

- (void)buildGraphicsPage {
    const CGFloat width = CGRectGetWidth(self.graphicsScroll.bounds);
    [self addPageTitle:@"Display" to:self.graphicsScroll];
    self.graphicsMasterSwitch = [[UISwitch alloc]
        initWithFrame:CGRectMake(width - 118.0, 6.0, 51.0, 31.0)];
    self.graphicsMasterSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.graphicsMasterSwitch addTarget:self
                                  action:@selector(graphicsMasterChanged:)
                        forControlEvents:UIControlEventValueChanged];
    [self.graphicsScroll addSubview:self.graphicsMasterSwitch];
    self.graphicsStatusLabel = [self addStatusLabelTo:self.graphicsScroll y:48.0];

    UILabel *scaleLabel = [self labelWithText:@"Super Resolution"
                                         frame:CGRectMake(16.0, 86.0, width - 100.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [self.graphicsScroll addSubview:scaleLabel];
    self.graphicsScaleValueLabel = [self labelWithText:@"100%"
                                                 frame:CGRectMake(width - 82.0, 86.0, 66.0, 24.0)
                                                  font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                                 color:UIColor.whiteColor];
    self.graphicsScaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.graphicsScaleValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.graphicsScroll addSubview:self.graphicsScaleValueLabel];
    self.graphicsScaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 115.0, width - 32.0, 30.0)];
    self.graphicsScaleSlider.minimumValue = 1.0f;
    self.graphicsScaleSlider.maximumValue = 1.5f;
    self.graphicsScaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.graphicsScaleSlider addTarget:self action:@selector(graphicsScaleChanged:)
                       forControlEvents:UIControlEventValueChanged];
    [self.graphicsScroll addSubview:self.graphicsScaleSlider];
    self.graphicsScaleHintLabel = [self labelWithText:@""
                                                frame:CGRectMake(16.0, 148.0, width - 32.0, 38.0)
                                                 font:[UIFont systemFontOfSize:11.0]
                                                color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.graphicsScroll addSubview:self.graphicsScaleHintLabel];

    self.linearFilteringSwitch = [self addSwitchRowTo:self.graphicsScroll
                                                title:@"Linear texture filter"
                                                 hint:@"Làm mượt phóng/thu texture trên Metal."
                                                    y:196.0
                                             selector:@selector(linearFilteringChanged:)];
    self.trilinearFilteringSwitch = [self addSwitchRowTo:self.graphicsScroll
                                                   title:@"Trilinear mip filter"
                                                    hint:@"Chuyển mipmap mượt hơn ở vật thể xa."
                                                       y:266.0
                                                selector:@selector(trilinearFilteringChanged:)];

    UILabel *anisoLabel = [self labelWithText:@"Anisotropic filtering"
                                         frame:CGRectMake(16.0, 340.0, width - 100.0, 24.0)
                                          font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                         color:UIColor.whiteColor];
    [self.graphicsScroll addSubview:anisoLabel];
    self.anisotropyValueLabel = [self labelWithText:@"4×"
                                              frame:CGRectMake(width - 82.0, 340.0, 66.0, 24.0)
                                               font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                              color:UIColor.whiteColor];
    self.anisotropyValueLabel.textAlignment = NSTextAlignmentRight;
    self.anisotropyValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.graphicsScroll addSubview:self.anisotropyValueLabel];
    self.anisotropySlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 369.0, width - 32.0, 30.0)];
    self.anisotropySlider.minimumValue = 0.0f;
    self.anisotropySlider.maximumValue = 4.0f;
    self.anisotropySlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.anisotropySlider addTarget:self action:@selector(anisotropyChanged:)
                     forControlEvents:UIControlEventValueChanged];
    [self.graphicsScroll addSubview:self.anisotropySlider];
    UILabel *anisoHint = [self labelWithText:@"1× / 2× / 4× / 8× / 16× • pipeline tạo mới"
                                        frame:CGRectMake(16.0, 401.0, width - 32.0, 24.0)
                                         font:[UIFont systemFontOfSize:11.0]
                                        color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.graphicsScroll addSubview:anisoHint];

    self.wideColorSwitch = [self addSwitchRowTo:self.graphicsScroll
                                          title:@"Display-P3 output"
                                           hint:@"Dải màu rộng cho CAMetalLayer khi màn hình hỗ trợ."
                                              y:438.0
                                       selector:@selector(wideColorChanged:)];
    self.highQualityScalingSwitch = [self addSwitchRowTo:self.graphicsScroll
                                                   title:@"High-quality layer scaling"
                                                    hint:@"Dùng lọc trilinear khi Metal layer được scale."
                                                       y:508.0
                                                selector:@selector(highQualityScalingChanged:)];
    UILabel *compatibility = [self labelWithText:@"Lưu ý: hiệu quả tùy engine. Tweak không ép shader, texture pack hay MSAA vì có thể làm game crash."
                                             frame:CGRectMake(16.0, 580.0, width - 32.0, 52.0)
                                              font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
                                             color:[UIColor colorWithRed:1.0 green:0.76 blue:0.36 alpha:1.0]];
    [self.graphicsScroll addSubview:compatibility];
    self.graphicsScroll.contentSize = CGSizeMake(width, 644.0);
}

- (void)buildIpadPage {
    const CGFloat width = CGRectGetWidth(self.ipadScroll.bounds);
    [self addPageTitle:@"iPad View" to:self.ipadScroll];
    self.ipadMasterSwitch = [[UISwitch alloc]
        initWithFrame:CGRectMake(width - 118.0, 6.0, 51.0, 31.0)];
    self.ipadMasterSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.ipadMasterSwitch addTarget:self
                              action:@selector(ipadMasterChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.ipadScroll addSubview:self.ipadMasterSwitch];
    self.ipadStatusLabel = [self addStatusLabelTo:self.ipadScroll y:48.0];

    UILabel *intro = [self labelWithText:@"Mỗi preset dùng metrics riêng; đổi xong phải đóng hẳn rồi mở lại game."
                                    frame:CGRectMake(16.0, 82.0, width - 32.0, 42.0)
                                     font:[UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium]
                                    color:[UIColor colorWithWhite:0.82 alpha:1.0]];
    [self.ipadScroll addSubview:intro];

    UIView *profileCard = [[UIView alloc] initWithFrame:CGRectMake(10.0,
                                                                   130.0,
                                                                   width - 20.0,
                                                                   196.0)];
    profileCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    profileCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.040];
    profileCard.layer.cornerRadius = 18.0;
    profileCard.layer.borderWidth = 0.6;
    profileCard.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.075].CGColor;
    profileCard.userInteractionEnabled = NO;
    [self.ipadScroll addSubview:profileCard];

    UILabel *profileLabel = [self labelWithText:@"Game adapter"
                                           frame:CGRectMake(18.0, 144.0, width - 36.0, 24.0)
                                            font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                           color:UIColor.whiteColor];
    [self.ipadScroll addSubview:profileLabel];

    self.ipadProfileControl = [[UISegmentedControl alloc]
        initWithItems:@[@"Roblox Tablet", @"PUBG 4:3 Fit"]];
    self.ipadProfileControl.frame = CGRectMake(18.0, 176.0, width - 36.0, 34.0);
    self.ipadProfileControl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.ipadProfileControl addTarget:self
                                action:@selector(ipadProfileChanged:)
                      forControlEvents:UIControlEventValueChanged];
    [self.ipadScroll addSubview:self.ipadProfileControl];

    self.ipadProfileHintLabel = [self labelWithText:@""
                                                frame:CGRectMake(18.0,
                                                                 220.0,
                                                                 width - 36.0,
                                                                 94.0)
                                                 font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular]
                                                color:[UIColor colorWithWhite:0.72 alpha:1.0]];
    [self.ipadScroll addSubview:self.ipadProfileHintLabel];

    UILabel *relaunch = [self labelWithText:@"↻ Bắt buộc force-close game. Bật/tắt giữa phiên chỉ lưu cấu hình cho lần mở kế tiếp."
                                         frame:CGRectMake(16.0, 340.0, width - 32.0, 48.0)
                                          font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
                                         color:[UIColor colorWithRed:1.0 green:0.78 blue:0.42 alpha:1.0]];
    [self.ipadScroll addSubview:relaunch];

    UIButton *resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    resetButton.frame = CGRectMake(16.0, 398.0, width - 32.0, 36.0);
    resetButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    resetButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.070];
    resetButton.layer.cornerRadius = 14.0;
    resetButton.layer.borderWidth = 0.6;
    resetButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    [resetButton setTitle:@"Khôi phục thiết bị thật" forState:UIControlStateNormal];
    [resetButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [resetButton addTarget:self action:@selector(resetIpadMode)
          forControlEvents:UIControlEventTouchUpInside];
    [self.ipadScroll addSubview:resetButton];
    self.ipadScroll.contentSize = CGSizeMake(width, 454.0);
}

- (void)buildSettingsPage {
    const CGFloat width = CGRectGetWidth(self.settingsScroll.bounds);
    [self addPageTitle:@"Menu" to:self.settingsScroll];

    UILabel *sizeLabel = [self labelWithText:@"Kích thước menu"
                                        frame:CGRectMake(16.0, 62.0, width - 100.0, 24.0)
                                         font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                        color:UIColor.whiteColor];
    [self.settingsScroll addSubview:sizeLabel];
    self.menuScaleValueLabel = [self labelWithText:@"100%"
                                             frame:CGRectMake(width - 82.0, 62.0, 66.0, 24.0)
                                              font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                             color:UIColor.whiteColor];
    self.menuScaleValueLabel.textAlignment = NSTextAlignmentRight;
    self.menuScaleValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.settingsScroll addSubview:self.menuScaleValueLabel];
    self.menuScaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 91.0, width - 32.0, 30.0)];
    self.menuScaleSlider.minimumValue = 0.75f;
    self.menuScaleSlider.maximumValue = 1.25f;
    self.menuScaleSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.menuScaleSlider addTarget:self action:@selector(menuScaleChanged:)
                    forControlEvents:UIControlEventValueChanged];
    [self.settingsScroll addSubview:self.menuScaleSlider];

    self.menuDragSwitch = [self addSwitchRowTo:self.settingsScroll
                                         title:@"Cho phép kéo menu"
                                          hint:@"Tắt để panel luôn cố định giữa màn hình."
                                             y:142.0
                                      selector:@selector(menuDragChanged:)];

    UILabel *hueLabel = [self labelWithText:@"Màu chủ đề"
                                       frame:CGRectMake(16.0, 218.0, width - 32.0, 24.0)
                                        font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                       color:UIColor.whiteColor];
    [self.settingsScroll addSubview:hueLabel];
    self.hueSlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 247.0, width - 32.0, 30.0)];
    self.hueSlider.minimumValue = 0.0f;
    self.hueSlider.maximumValue = 1.0f;
    self.hueSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.hueSlider addTarget:self action:@selector(hueChanged:)
              forControlEvents:UIControlEventValueChanged];
    [self.settingsScroll addSubview:self.hueSlider];

    UILabel *opacityLabel = [self labelWithText:@"Độ đậm của kính"
                                           frame:CGRectMake(16.0, 298.0, width - 100.0, 24.0)
                                            font:[UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold]
                                           color:UIColor.whiteColor];
    [self.settingsScroll addSubview:opacityLabel];
    self.opacityValueLabel = [self labelWithText:@"96%"
                                           frame:CGRectMake(width - 82.0, 298.0, 66.0, 24.0)
                                            font:[UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold]
                                           color:UIColor.whiteColor];
    self.opacityValueLabel.textAlignment = NSTextAlignmentRight;
    self.opacityValueLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.settingsScroll addSubview:self.opacityValueLabel];
    self.opacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(16.0, 327.0, width - 32.0, 30.0)];
    self.opacitySlider.minimumValue = 0.45f;
    self.opacitySlider.maximumValue = 1.0f;
    self.opacitySlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.opacitySlider addTarget:self action:@selector(opacityChanged:)
                  forControlEvents:UIControlEventValueChanged];
    [self.settingsScroll addSubview:self.opacitySlider];

    self.liquidGlassSwitch = [self addSwitchRowTo:self.settingsScroll
                                            title:@"Liquid Glass"
                                             hint:@"Vật liệu hệ thống trên iOS 26 • blur tương thích trên iOS 12–18."
                                                y:380.0
                                         selector:@selector(liquidGlassChanged:)];
    UILabel *settingsHint = [self labelWithText:@"Settings luôn hoạt động, kể cả khi hai module đang tắt."
                                            frame:CGRectMake(16.0, 456.0, width - 32.0, 36.0)
                                             font:[UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium]
                                            color:[UIColor colorWithWhite:0.69 alpha:1.0]];
    [self.settingsScroll addSubview:settingsHint];
    self.settingsScroll.contentSize = CGSizeMake(width, 510.0);
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return GBShouldKeepLandscape() ? GBLandscapeMask() : GBHostOrientationMask();
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (GBShouldKeepLandscape()) {
        return GBPreferredLandscapeOrientation();
    }
    UIWindow *hostWindow = GBHostApplicationWindow();
    UIViewController *hostController = GBTopViewController(hostWindow.rootViewController);
    UIInterfaceOrientation preferred =
        hostController.preferredInterfaceOrientationForPresentation;
    const UIInterfaceOrientationMask mask = GBHostOrientationMask();
    if (GBMaskContainsOrientation(mask, preferred)) {
        return preferred;
    }
    if ((mask & UIInterfaceOrientationMaskPortrait) != 0) {
        return UIInterfaceOrientationPortrait;
    }
    return GBPreferredLandscapeOrientation();
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.hasInitialButtonPosition) {
        self.menuButton.center = CGPointMake(41.0,
            MAX(108.0, self.view.safeAreaInsets.top + 38.0));
        self.hasInitialButtonPosition = YES;
    }
    [self clampMenuButton];
    [self layoutPanel];
}

- (void)layoutPanel {
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat margin = 8.0;
    const CGFloat scale = (CGFloat)gMenuScale.load(std::memory_order_relaxed);
    const CGFloat maxWidth = MAX(1.0, CGRectGetWidth(safeBounds) - margin * 2.0);
    const CGFloat maxHeight = MAX(1.0, CGRectGetHeight(safeBounds) - margin * 2.0);
    const CGFloat width = MIN(maxWidth, MAX(MIN(350.0, maxWidth), 510.0 * scale));
    const CGFloat height = MIN(maxHeight, MAX(MIN(270.0, maxHeight), 370.0 * scale));

    CGPoint center = self.panel.center;
    if (!self.hasPanelPosition || !gMenuDragEnabled.load(std::memory_order_relaxed)) {
        center = CGPointMake(CGRectGetMidX(safeBounds), CGRectGetMidY(safeBounds));
        self.hasPanelPosition = YES;
    }
    self.panel.bounds = CGRectMake(0.0, 0.0, width, height);
    self.panel.center = center;
    [self clampPanel];

    self.glassView.frame = self.panel.bounds;
    const CGFloat sidebarWidth = MIN(154.0, MAX(136.0, width * 0.30));
    self.sidebar.frame = CGRectMake(0.0, 0.0, sidebarWidth, height);

    self.gameTabRow.frame = CGRectMake(8.0, 54.0, sidebarWidth - 16.0, 48.0);
    self.graphicsTabRow.frame = CGRectMake(8.0, 108.0, sidebarWidth - 16.0, 48.0);
    self.ipadTabRow.frame = CGRectMake(8.0, 162.0, sidebarWidth - 16.0, 48.0);
    self.settingsTabRow.frame = CGRectMake(8.0,
                                           MIN(216.0, height - 54.0),
                                           sidebarWidth - 16.0,
                                           46.0);
    self.gameTabButton.frame = self.gameTabRow.bounds;
    self.graphicsTabButton.frame = self.graphicsTabRow.bounds;
    self.ipadTabButton.frame = self.ipadTabRow.bounds;
    self.settingsTabButton.frame = self.settingsTabRow.bounds;

    CGRect pageFrame = CGRectMake(sidebarWidth, 0.0, width - sidebarWidth, height);
    for (UIScrollView *scroll in @[self.gameScroll,
                                   self.graphicsScroll,
                                   self.ipadScroll,
                                   self.settingsScroll]) {
        scroll.frame = pageFrame;
        scroll.contentSize = CGSizeMake(CGRectGetWidth(pageFrame), scroll.contentSize.height);
        scroll.scrollIndicatorInsets = UIEdgeInsetsMake(45.0, 0.0, 8.0, 2.0);
    }
    self.closeButton.frame = CGRectMake(width - 46.0, 2.0, 44.0, 44.0);
}

- (void)clampPanel {
    CGRect safeBounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat margin = 8.0;
    CGFloat halfWidth = CGRectGetWidth(self.panel.bounds) / 2.0;
    CGFloat halfHeight = CGRectGetHeight(self.panel.bounds) / 2.0;
    CGFloat minX = CGRectGetMinX(safeBounds) + halfWidth + margin;
    CGFloat maxX = CGRectGetMaxX(safeBounds) - halfWidth - margin;
    CGFloat minY = CGRectGetMinY(safeBounds) + halfHeight + margin;
    CGFloat maxY = CGRectGetMaxY(safeBounds) - halfHeight - margin;
    self.panel.center = CGPointMake(minX > maxX ? CGRectGetMidX(safeBounds)
                                                : MIN(MAX(self.panel.center.x, minX), maxX),
                                    minY > maxY ? CGRectGetMidY(safeBounds)
                                                : MIN(MAX(self.panel.center.y, minY), maxY));
}

- (void)clampMenuButton {
    CGRect bounds = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    const CGFloat halfWidth = CGRectGetWidth(self.menuButton.bounds) / 2.0;
    const CGFloat halfHeight = CGRectGetHeight(self.menuButton.bounds) / 2.0;
    CGFloat minX = CGRectGetMinX(bounds) + halfWidth + 8.0;
    CGFloat maxX = CGRectGetMaxX(bounds) - halfWidth - 8.0;
    CGFloat minY = CGRectGetMinY(bounds) + halfHeight + 8.0;
    CGFloat maxY = CGRectGetMaxY(bounds) - halfHeight - 8.0;
    self.menuButton.center = CGPointMake(MIN(MAX(self.menuButton.center.x, minX), maxX),
                                         MIN(MAX(self.menuButton.center.y, minY), maxY));
}

- (void)applyTintToView:(UIView *)view color:(UIColor *)color {
    if ([view isKindOfClass:UISwitch.class]) {
        ((UISwitch *)view).onTintColor = color;
    } else if ([view isKindOfClass:UISlider.class]) {
        ((UISlider *)view).minimumTrackTintColor = color;
    } else if ([view isKindOfClass:UISegmentedControl.class]) {
        UISegmentedControl *control = (UISegmentedControl *)view;
        if (@available(iOS 13.0, *)) {
            control.selectedSegmentTintColor = color;
        } else {
            control.tintColor = color;
        }
    }
    for (UIView *subview in view.subviews) {
        [self applyTintToView:subview color:color];
    }
}

- (void)applyVisualSettings {
    UIColor *theme = GBThemeColor();
    const CGFloat density = (CGFloat)fmin(1.0, fmax(0.45,
        gMenuOpacity.load(std::memory_order_relaxed)));
    const CGFloat strength = (density - 0.45) / 0.55;
    const BOOL glass = gLiquidGlassEnabled.load(std::memory_order_relaxed);

    // Never fade the whole hierarchy: doing that leaves the blur fully opaque
    // while dimming every control above it. The slider now changes the glass
    // layers themselves, so tint and density update immediately and separately.
    self.panel.alpha = 1.0;
    self.menuButton.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:glass ? 0.22 : 0.14].CGColor;
    self.panel.layer.borderColor =
        [UIColor colorWithWhite:1.0 alpha:glass ? 0.15 : 0.10].CGColor;
    self.panel.layer.shadowOpacity = glass ? 0.26 : 0.40;
    self.sidebar.backgroundColor = glass
        ? [UIColor colorWithWhite:0.0 alpha:0.055 + 0.055 * strength]
        : [UIColor colorWithWhite:0.0 alpha:0.16];
    [self applyTintToView:self.panel color:theme];

    self.gameTabRow.backgroundColor = self.selectedTab == 0
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    self.graphicsTabRow.backgroundColor = self.selectedTab == 1
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    self.ipadTabRow.backgroundColor = self.selectedTab == 2
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    self.settingsTabRow.backgroundColor = self.selectedTab == 3
        ? [theme colorWithAlphaComponent:0.13]
        : UIColor.clearColor;
    for (UIView *tabRow in @[self.gameTabRow,
                             self.graphicsTabRow,
                             self.ipadTabRow,
                             self.settingsTabRow]) {
        const BOOL selected = (tabRow == self.gameTabRow && self.selectedTab == 0) ||
            (tabRow == self.graphicsTabRow && self.selectedTab == 1) ||
            (tabRow == self.ipadTabRow && self.selectedTab == 2) ||
            (tabRow == self.settingsTabRow && self.selectedTab == 3);
        tabRow.layer.borderWidth = 0.6;
        tabRow.layer.borderColor = selected
            ? [UIColor colorWithWhite:1.0 alpha:0.17].CGColor
            : UIColor.clearColor.CGColor;
    }
    self.gameStatusLabel.backgroundColor = GBIsGameBoostActive()
        ? [theme colorWithAlphaComponent:0.18]
        : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.graphicsStatusLabel.backgroundColor = GBIsEnhanceGraphicsActive()
        ? [theme colorWithAlphaComponent:0.18]
        : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.ipadStatusLabel.backgroundColor =
        gConfiguredIpadModeEnabled.load(std::memory_order_relaxed)
            ? [theme colorWithAlphaComponent:0.18]
            : [UIColor colorWithWhite:1.0 alpha:0.055];
    self.scaleValueLabel.textColor = theme;
    self.graphicsScaleValueLabel.textColor = theme;
    self.anisotropyValueLabel.textColor = theme;
    self.menuScaleValueLabel.textColor = theme;
    self.opacityValueLabel.textColor = theme;

    const BOOL animateMaterial = self.view.window != nil;
    [self.glassView updateWithTintColor:theme
                                density:strength
                                enabled:glass
                               animated:animateMaterial];
    [self.menuButtonGlass updateWithTintColor:theme
                                      density:MIN(1.0, strength + 0.08)
                                      enabled:glass
                                     animated:animateMaterial];
    const BOOL nativeGlass = glass && self.glassView.isUsingNativeGlass;
    self.panel.layer.borderWidth = nativeGlass ? 0.0 : 0.65;
    self.menuButton.layer.borderWidth = nativeGlass ? 0.0 : 0.65;
    if (nativeGlass) {
        self.panel.layer.shadowOpacity = 0.20;
        self.sidebar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.025];
    }
    self.menuButton.backgroundColor = UIColor.clearColor;
    self.panel.backgroundColor = UIColor.clearColor;
}

- (void)settingsDidChange {
    const GBModuleMode mode = GBCurrentModuleMode();
    self.gameMasterSwitch.on = mode == GBModuleModeGameBoost;
    self.graphicsMasterSwitch.on = mode == GBModuleModeEnhanceGraphics;
    const BOOL configuredIpadMode =
        gConfiguredIpadModeEnabled.load(std::memory_order_relaxed);
    const GBIpadProfile configuredIpadProfile = GBSanitizeIpadProfile(
        gConfiguredIpadProfile.load(std::memory_order_relaxed));
    self.ipadMasterSwitch.on = configuredIpadMode;
    const BOOL gameEnabled = mode == GBModuleModeGameBoost;
    const BOOL graphicsEnabled = mode == GBModuleModeEnhanceGraphics;
    self.gameScroll.userInteractionEnabled = YES;
    self.graphicsScroll.userInteractionEnabled = YES;
    self.ipadScroll.userInteractionEnabled = YES;
    for (UIControl *control in @[self.performanceSwitch,
                                 self.lowLatencySwitch,
                                 self.keepAwakeSwitch,
                                 self.landscapeSwitch,
                                 self.fpsControl,
                                 self.scaleSlider]) {
        control.enabled = gameEnabled;
    }
    for (UIControl *control in @[self.graphicsScaleSlider,
                                 self.linearFilteringSwitch,
                                 self.trilinearFilteringSwitch,
                                 self.anisotropySlider,
                                 self.wideColorSwitch,
                                 self.highQualityScalingSwitch]) {
        control.enabled = graphicsEnabled;
    }
    self.ipadProfileControl.enabled = configuredIpadMode;
    self.gameStatusLabel.text = mode == GBModuleModeGameBoost
        ? @"Đang hoạt động"
        : @"Đang tắt • bật công tắc phía trên";
    self.graphicsStatusLabel.text = mode == GBModuleModeEnhanceGraphics
        ? @"Đang hoạt động"
        : @"Đang tắt • bật công tắc phía trên";
    const BOOL ipadNeedsRelaunch =
        configuredIpadMode != gLaunchedIpadModeEnabled ||
        (configuredIpadMode && configuredIpadProfile != gLaunchedIpadProfile);
    if (configuredIpadMode) {
        self.ipadStatusLabel.text = ipadNeedsRelaunch
            ? @"Đã lưu • cần mở lại ứng dụng ↻"
            : @"iPad View đang hoạt động";
    } else {
        self.ipadStatusLabel.text = ipadNeedsRelaunch
            ? @"Đã tắt • cần mở lại ứng dụng ↻"
            : @"Đang tắt • bật công tắc phía trên";
    }
    self.ipadProfileControl.selectedSegmentIndex =
        configuredIpadProfile == GBIpadProfilePUBGView ? 1 : 0;
    self.ipadProfileHintLabel.text = configuredIpadProfile == GBIpadProfilePUBGView
        ? @"PUBG: giả iPad Pro + regular traits, render surface 4:3 và Aspect Fit khi compose. Có viền hai bên để giữ đúng tỉ lệ, không kéo giãn/zoom như bản cũ."
        : @"Roblox: giả iPad + regular traits và tăng logical viewport cùng tỉ lệ lên trên 1024×500. Mục tiêu là full hotbar và player list, không đổi aspect màn hình.";
    self.performanceSwitch.on = gPerformanceEnabled.load(std::memory_order_relaxed);
    self.lowLatencySwitch.on = gLowLatencyEnabled.load(std::memory_order_relaxed);
    self.keepAwakeSwitch.on = gKeepAwakeEnabled.load(std::memory_order_relaxed);
    self.landscapeSwitch.on = gLandscapeLockEnabled.load(std::memory_order_relaxed);
    self.landscapeHintLabel.text = GBAppIsLandscapeOnly()
        ? @"Game chỉ hỗ trợ ngang • tự giữ đúng hướng."
        : @"Vẫn nằm ngang khi khóa xoay hệ thống đang bật.";
    NSInteger frameRate = gFrameRate.load(std::memory_order_relaxed);
    self.fpsControl.selectedSegmentIndex = frameRate == 30 ? 1
        : frameRate == 60 ? 2
        : frameRate == 120 ? 3
        : 0;

    const double gameScale = gConfiguredResolutionScale.load(std::memory_order_relaxed);
    self.scaleSlider.value = (float)gameScale;
    const BOOL gameNeedsRelaunch = mode == GBModuleModeGameBoost &&
        (gLaunchedModuleMode != GBModuleModeGameBoost ||
         fabs(gResolutionScale.load(std::memory_order_relaxed) - gameScale) >= 0.001);
    self.scaleValueLabel.text = [NSString stringWithFormat:@"%.0f%%%@",
        gameScale * 100.0, gameNeedsRelaunch ? @"↻" : @""];
    if (gameNeedsRelaunch) {
        self.scaleHintLabel.text = @"Đã lưu • đóng/mở lại app để áp dụng an toàn.";
    } else if (gameScale <= 0.25) {
        self.scaleHintLabel.text = @"10–25% rất mờ • menu vẫn giữ độ nét gốc.";
    } else {
        self.scaleHintLabel.text = @"Giảm pixel thật, giữ nguyên khung hình • không zoom.";
    }

    const double graphicsScale = gConfiguredGraphicsScale.load(std::memory_order_relaxed);
    self.graphicsScaleSlider.value = (float)graphicsScale;
    const BOOL graphicsNeedsRelaunch = mode == GBModuleModeEnhanceGraphics &&
        (gLaunchedModuleMode != GBModuleModeEnhanceGraphics ||
         fabs(gResolutionScale.load(std::memory_order_relaxed) - graphicsScale) >= 0.001);
    self.graphicsScaleValueLabel.text = [NSString stringWithFormat:@"%.0f%%%@",
        graphicsScale * 100.0, graphicsNeedsRelaunch ? @"↻" : @""];
    self.graphicsScaleHintLabel.text = graphicsNeedsRelaunch
        ? @"Đã lưu • đóng/mở lại app để đổi framebuffer."
        : @"Render 100–150% rồi downsample; tốn GPU và RAM hơn.";
    self.linearFilteringSwitch.on = gLinearFilteringEnabled.load(std::memory_order_relaxed);
    self.trilinearFilteringSwitch.on = gTrilinearFilteringEnabled.load(std::memory_order_relaxed);
    const int anisotropy = gAnisotropyLevel.load(std::memory_order_relaxed);
    self.anisotropySlider.value = anisotropy == 16 ? 4.0f
        : anisotropy == 8 ? 3.0f
        : anisotropy == 4 ? 2.0f
        : anisotropy == 2 ? 1.0f
        : 0.0f;
    self.anisotropyValueLabel.text = [NSString stringWithFormat:@"%d×", anisotropy];
    self.wideColorSwitch.on = gWideColorEnabled.load(std::memory_order_relaxed);
    self.highQualityScalingSwitch.on =
        gHighQualityScalingEnabled.load(std::memory_order_relaxed);

    self.menuScaleSlider.value = (float)gMenuScale.load(std::memory_order_relaxed);
    self.menuScaleValueLabel.text = [NSString stringWithFormat:@"%.0f%%",
        gMenuScale.load(std::memory_order_relaxed) * 100.0];
    self.menuDragSwitch.on = gMenuDragEnabled.load(std::memory_order_relaxed);
    self.panelPanGesture.enabled = self.menuDragSwitch.isOn;
    self.hueSlider.value = (float)gMenuHue.load(std::memory_order_relaxed);
    self.opacitySlider.value = (float)gMenuOpacity.load(std::memory_order_relaxed);
    self.opacityValueLabel.text = [NSString stringWithFormat:@"%.0f%%",
        gMenuOpacity.load(std::memory_order_relaxed) * 100.0];
    self.liquidGlassSwitch.on = gLiquidGlassEnabled.load(std::memory_order_relaxed);

    self.gameScroll.hidden = self.selectedTab != 0;
    self.graphicsScroll.hidden = self.selectedTab != 1;
    self.ipadScroll.hidden = self.selectedTab != 2;
    self.settingsScroll.hidden = self.selectedTab != 3;
    [self.panel bringSubviewToFront:self.closeButton];
    [self applyVisualSettings];
    [self.view setNeedsLayout];
}

- (void)selectGameTab {
    self.selectedTab = 0;
    [self settingsDidChange];
}

- (void)selectGraphicsTab {
    self.selectedTab = 1;
    [self settingsDidChange];
}

- (void)selectSettingsTab {
    self.selectedTab = 3;
    [self settingsDidChange];
}

- (void)selectIpadTab {
    self.selectedTab = 2;
    [self settingsDidChange];
}

- (void)gameMasterChanged:(UISwitch *)sender {
    GBSetModuleMode(sender.isOn ? GBModuleModeGameBoost : GBModuleModeNone, YES);
}

- (void)graphicsMasterChanged:(UISwitch *)sender {
    GBSetModuleMode(sender.isOn ? GBModuleModeEnhanceGraphics : GBModuleModeNone, YES);
}

- (void)ipadMasterChanged:(UISwitch *)sender {
    GBSetIpadModeEnabled(sender.isOn, YES);
}

- (void)ipadProfileChanged:(UISegmentedControl *)sender {
    GBSetIpadProfile(sender.selectedSegmentIndex == 1
        ? GBIpadProfilePUBGView
        : GBIpadProfileRobloxTablet, YES);
}

- (void)resetIpadMode {
    GBSetIpadProfile(GBIpadProfileRobloxTablet, YES);
    GBSetIpadModeEnabled(NO, YES);
}

- (void)performanceSwitchChanged:(UISwitch *)sender {
    GBSetPerformanceEnabled(sender.isOn, YES);
}

- (void)lowLatencySwitchChanged:(UISwitch *)sender {
    GBSetLowLatencyEnabled(sender.isOn, YES);
}

- (void)keepAwakeSwitchChanged:(UISwitch *)sender {
    GBSetKeepAwakeEnabled(sender.isOn, YES);
}

- (void)landscapeSwitchChanged:(UISwitch *)sender {
    GBSetLandscapeLockEnabled(sender.isOn, YES);
}

- (void)fpsChanged:(UISegmentedControl *)sender {
    NSInteger values[] = {0, 30, 60, 120};
    NSInteger index = MIN(MAX(sender.selectedSegmentIndex, 0), 3);
    GBSetFrameRate(values[index], YES);
}

- (void)scaleSliderChanged:(UISlider *)sender {
    GBSetGameResolutionScale(round((double)sender.value * 20.0) / 20.0, YES);
}

- (void)resetGameScale {
    GBSetGameResolutionScale(1.0, YES);
}

- (void)graphicsScaleChanged:(UISlider *)sender {
    GBSetGraphicsResolutionScale(round((double)sender.value * 20.0) / 20.0, YES);
}

- (void)linearFilteringChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gLinearFilteringEnabled, GBLinearFilteringKey, sender.isOn, NO);
}

- (void)trilinearFilteringChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gTrilinearFilteringEnabled, GBTrilinearFilteringKey, sender.isOn, NO);
}

- (void)anisotropyChanged:(UISlider *)sender {
    const NSInteger index = (NSInteger)round(sender.value);
    const NSInteger values[] = {1, 2, 4, 8, 16};
    GBSetAnisotropy(values[MIN(MAX(index, 0), 4)]);
}

- (void)wideColorChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gWideColorEnabled, GBWideColorKey, sender.isOn, YES);
}

- (void)highQualityScalingChanged:(UISwitch *)sender {
    GBSetGraphicsBoolean(gHighQualityScalingEnabled,
                         GBHighQualityScalingKey,
                         sender.isOn,
                         YES);
}

- (void)menuScaleChanged:(UISlider *)sender {
    const double value = GBClampMenuScale(round((double)sender.value * 20.0) / 20.0);
    gMenuScale.store(value, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:GBMenuScaleKey];
    GBPostSettingsChanged();
}

- (void)menuDragChanged:(UISwitch *)sender {
    gMenuDragEnabled.store(sender.isOn, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:GBMenuDragKey];
    if (!sender.isOn) {
        self.hasPanelPosition = NO;
    }
    GBPostSettingsChanged();
}

- (void)hueChanged:(UISlider *)sender {
    const double value = GBClampUnit(sender.value, 0.55);
    gMenuHue.store(value, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:GBMenuHueKey];
    GBPostSettingsChanged();
}

- (void)opacityChanged:(UISlider *)sender {
    const double value = fmin(1.0, fmax(0.45, (double)sender.value));
    gMenuOpacity.store(value, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setDouble:value forKey:GBMenuOpacityKey];
    GBPostSettingsChanged();
}

- (void)liquidGlassChanged:(UISwitch *)sender {
    gLiquidGlassEnabled.store(sender.isOn, std::memory_order_relaxed);
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:GBLiquidGlassKey];
    GBPostSettingsChanged();
}

- (void)togglePanel {
    if (!self.panel.hidden) {
        [self hidePanel];
        return;
    }

    [self.panel.layer removeAllAnimations];
    self.panel.hidden = NO;
    self.panel.alpha = 0.0;
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.panel.alpha = 1.0;
    } completion:nil];
}

- (void)hidePanel {
    if (self.panel.hidden) {
        return;
    }
    [UIView animateWithDuration:0.16
                          delay:0.0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction |
                                UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.panel.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        self.panel.hidden = YES;
        self.panel.alpha = 1.0;
    }];
}

- (void)dragMenuButton:(UIPanGestureRecognizer *)gesture {
    if (!gMenuDragEnabled.load(std::memory_order_relaxed)) {
        return;
    }
    CGPoint translation = [gesture translationInView:self.view];
    self.menuButton.center = CGPointMake(self.menuButton.center.x + translation.x,
                                         self.menuButton.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view];
    [self clampMenuButton];
}

- (void)dragPanel:(UIPanGestureRecognizer *)gesture {
    if (!gMenuDragEnabled.load(std::memory_order_relaxed)) {
        return;
    }
    CGPoint translation = [gesture translationInView:self.view];
    self.panel.center = CGPointMake(self.panel.center.x + translation.x,
                                    self.panel.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:self.view];
    self.hasPanelPosition = YES;
    [self clampPanel];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (!gMenuDragEnabled.load(std::memory_order_relaxed)) {
        return NO;
    }
    if (gestureRecognizer == self.panelPanGesture) {
        UIView *view = touch.view;
        while (view != nil && view != self.panel) {
            if ([view isKindOfClass:UIControl.class] ||
                [view isKindOfClass:UIScrollView.class]) {
                return NO;
            }
            view = view.superview;
        }
    }
    return YES;
}

@end

@interface OAGameBoostOverlayManager : NSObject
@property(nonatomic, strong) OAGameBoostPassthroughWindow *overlayWindow;
+ (instancetype)sharedManager;
- (UIWindowScene *)activeWindowScene API_AVAILABLE(ios(13.0));
- (void)installIfPossible;
@end


@implementation OAGameBoostOverlayManager

+ (instancetype)sharedManager {
    static OAGameBoostOverlayManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [OAGameBoostOverlayManager new];
    });
    return manager;
}

- (UIWindowScene *)activeWindowScene {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:UIWindowScene.class] &&
                scene.activationState == UISceneActivationStateForegroundActive) {
                return (UIWindowScene *)scene;
            }
        }
    }
    return nil;
}

- (void)installIfPossible {
    if (self.overlayWindow != nil) {
        return;
    }

    if (@available(iOS 13.0, *)) {
        UIWindowScene *windowScene = [self activeWindowScene];
        if (windowScene == nil) {
            return;
        }
        self.overlayWindow = [[OAGameBoostPassthroughWindow alloc] initWithWindowScene:windowScene];
        self.overlayWindow.frame = windowScene.coordinateSpace.bounds;
    } else {
        self.overlayWindow = [[OAGameBoostPassthroughWindow alloc]
            initWithFrame:gOriginalMainScreenBounds];
    }
    self.overlayWindow.backgroundColor = UIColor.clearColor;
    // Keep the tweak above the game but below system alert windows.
    self.overlayWindow.windowLevel = UIWindowLevelAlert - 1.0;
    objc_setAssociatedObject(self.overlayWindow,
                             GBOverlayWindowKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    self.overlayWindow.rootViewController = [OAGameBoostOverlayViewController new];
    self.overlayWindow.hidden = NO;

    // The control panel stays at the device's native backing scale. It is not
    // part of the app/game framebuffer being downscaled.
    GBApplyResolutionToViewTree(self.overlayWindow, gOriginalMainScreenScale);
    GBApplyResolutionToLayerTree(self.overlayWindow.layer, gOriginalMainScreenScale);
}

@end

void GBInstallOverlayIfPossible(void) {
    [[OAGameBoostOverlayManager sharedManager] installIfPossible];
}
