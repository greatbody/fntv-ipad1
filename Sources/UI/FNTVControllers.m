#import "FNTVControllers.h"
#import "FNTVClient.h"
#import "FNTVDiagnostics.h"
#import "FNTVForegroundSmoke.h"
#import "FNTVAudio.h"
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

static UIColor *Background(void) { return [UIColor colorWithRed:0.082 green:0.090 blue:0.102 alpha:1]; }
static UIColor *Panel(void) { return [UIColor colorWithRed:0.137 green:0.141 blue:0.169 alpha:1]; }
static UIColor *Accent(void) { return [UIColor colorWithRed:0.20 green:0.455 blue:0.859 alpha:1]; }
static NSString *Text(id value) { return [value isKindOfClass:[NSString class]] ? value : @""; }
static NSTimeInterval Seconds(id value) {
    double n = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    return isfinite(n) && n > 0 ? n : 0;
}
static NSString *TimeText(NSTimeInterval seconds) {
    NSUInteger minutes = (NSUInteger)MIN(Seconds([NSNumber numberWithDouble:seconds]) / 60, (double)NSUIntegerMax);
    return minutes >= 60 ? [NSString stringWithFormat:@"%lu小时%lu分", (unsigned long)(minutes / 60), (unsigned long)(minutes % 60)] :
        [NSString stringWithFormat:@"%lu分", (unsigned long)minutes];
}
static BOOL IsContainer(NSDictionary *item) {
    NSString *type = [Text([item objectForKey:@"type"]) lowercaseString];
    return [type isEqualToString:@"tv"] || [type isEqualToString:@"season"] || [type isEqualToString:@"directory"];
}
static void Cancel(NSOperation **operation) {
    NSOperation *pending = *operation; *operation = nil;
    [pending cancel]; [pending release];
}
static UILabel *Label(CGFloat fontSize, BOOL bold) {
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
    label.backgroundColor = [UIColor clearColor]; label.textColor = [UIColor whiteColor];
    label.font = bold ? [UIFont boldSystemFontOfSize:fontSize] : [UIFont systemFontOfSize:fontSize];
    return label;
}
static UIButton *ActionButton(NSString *title, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = Accent(); button.titleLabel.font = [UIFont boldSystemFontOfSize:19];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
static void ShowError(NSString *title, NSError *error) {
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:[error localizedDescription]
        delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil];
    [alert show]; [alert release];
}
static void RunRequestedSelfCheck(void) {
#if FNTV_DIAGNOSTICS
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![FNTVClient sharedClient].isAuthenticated || ![defaults boolForKey:@"FNTVRunReadOnlySelfCheck"]) return;
    [defaults setBool:NO forKey:@"FNTVRunReadOnlySelfCheck"]; [defaults synchronize];
    [[FNTVClient sharedClient] readOnlySelfCheck:^(id result, NSError *error) {
        NSDictionary *report = [result isKindOfClass:[NSDictionary class]] ? result :
            [NSDictionary dictionaryWithObjectsAndKeys:@1, @"schemaVersion", [NSNumber numberWithInteger:error ? [error code] : -1], @"errorCode", nil];
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
        NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        NSString *path = [directory stringByAppendingPathComponent:@"FNTV-selfcheck.json"];
        BOOL saved = [data writeToFile:path options:NSDataWritingAtomic error:NULL];
        if (saved) [[NSFileManager defaultManager] setAttributes:[NSDictionary dictionaryWithObject:@0600 forKey:NSFilePosixPermissions] ofItemAtPath:path error:NULL];
        NSLog(@"FNTV_READ_ONLY_SELF_CHECK_%@", saved ? @"SAVED" : @"WRITE_FAILED");
    }];
#endif
}

@interface FNTVPortraitNavigationController : UINavigationController
@end
@implementation FNTVPortraitNavigationController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return [self.topViewController shouldAutorotateToInterfaceOrientation:orientation];
}
@end

@interface FNTVLoginController : UIViewController <UITextFieldDelegate> {
    UIScrollView *_scroll;
    UIImageView *_background;
    UIImageView *_brand;
    UIView *_form;
    UILabel *_heading, *_status;
    UITextField *_server, *_username, *_password;
    UIButton *_login;
    UIActivityIndicatorView *_spinner;
    NSOperation *_request;
}
@end
@interface FNTVLibraryController : UIViewController <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
    UITableView *_table;
    UISearchBar *_search;
    UILabel *_status;
    UIButton *_more;
    UIView *_footer;
    NSArray *_libraries;
    NSMutableArray *_items;
    NSString *_libraryGUID, *_query;
    NSOperation *_request, *_libraryRequest;
    NSUInteger _page, _columns;
    BOOL _hasMore, _loading;
#if FNTV_DIAGNOSTICS
    BOOL _smokeModalActive;
#endif
}
#if FNTV_DIAGNOSTICS
- (void)tryForegroundSmoke;
#endif
@end
@interface FNTVDetailController : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    NSDictionary *_item;
    NSArray *_children;
    UITableView *_table;
    UIView *_header;
    UIImageView *_poster;
    UILabel *_name, *_metadata, *_overview, *_status;
    UIButton *_play, *_restart, *_moreDirectory;
    NSOperation *_request, *_childrenRequest, *_imageRequest, *_playRequest;
    BOOL _loading, _preparing;
    NSUInteger _directoryPage;
    BOOL _directoryHasMore;
#if FNTV_DIAGNOSTICS
    BOOL _smokeVisible;
#endif
}
- (id)initWithItem:(NSDictionary *)item;
#if FNTV_DIAGNOSTICS
- (void)tryForegroundSmoke;
#endif
@end
@interface FNTVPlayerController : MPMoviePlayerViewController {
    NSDictionary *_playback;
    NSTimer *_timer;
    NSTimeInterval _lastSeconds;
    BOOL _closing, _releasingAudio, _audioIOStopped;
    NSUInteger _audioLease;
}
- (id)initWithPlayback:(NSDictionary *)playback audioLease:(NSUInteger)lease;
@end

@implementation FNTVLoginController
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = Background();
    _background = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"login-pad-dark.png"]];
    _background.contentMode = UIViewContentModeScaleAspectFill; _background.alpha = 0.35;
    _background.clipsToBounds = YES; [self.view addSubview:_background];
    _scroll = [[UIScrollView alloc] initWithFrame:CGRectZero]; _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];
    _form = [[UIView alloc] initWithFrame:CGRectZero]; _form.backgroundColor = Panel(); [_scroll addSubview:_form];
    _brand = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"brand-wordmark-dark.png"]];
    _brand.contentMode = UIViewContentModeScaleAspectFit; [_form addSubview:_brand];
    _heading = [Label(18, NO) retain]; _heading.text = @"连接你的飞牛 NAS"; _heading.textAlignment = (NSInteger)UITextAlignmentCenter; [_form addSubview:_heading];
    UITextField **fields[] = { &_server, &_username, &_password };
    NSArray *placeholders = [NSArray arrayWithObjects:@"NAS 地址，例如 http://NAS地址:5666", @"用户名", @"密码", nil];
    for (NSUInteger i = 0; i < 3; i++) {
        UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];
        *fields[i] = field; field.borderStyle = UITextBorderStyleRoundedRect; field.font = [UIFont systemFontOfSize:18];
        field.placeholder = [placeholders objectAtIndex:i]; field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo; field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter; field.delegate = self;
        field.returnKeyType = i == 2 ? UIReturnKeyGo : UIReturnKeyNext; [_form addSubview:field];
    }
    _server.keyboardType = UIKeyboardTypeURL; _password.secureTextEntry = YES;
    _server.text = [FNTVClient sharedClient].serverURL; _username.text = [FNTVClient sharedClient].username;
    _login = [ActionButton(@"连接并登录", self, @selector(login:)) retain]; [_form addSubview:_login];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _spinner.hidesWhenStopped = YES; [_form addSubview:_spinner];
    _status = [Label(15, NO) retain]; _status.numberOfLines = 4; _status.textAlignment = (NSInteger)UITextAlignmentCenter;
    _status.textColor = [UIColor lightGrayColor]; _status.text = @"请使用 NAS 的影视服务地址。账号仅用于连接你的 NAS。"; [_form addSubview:_status];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setNavigationBarHidden:YES animated:animated]; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
#if FNTV_DIAGNOSTICS
    if (_request) return;
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSError *error = nil;
    NSDictionary *credentials = FNTVConsumeDiagnosticLogin([directory stringByAppendingPathComponent:@".fntv-test-login.json"], &error);
    if (!credentials) { if (error) _status.text = [error localizedDescription]; return; }
    _server.text = [credentials objectForKey:@"server"]; _username.text = [credentials objectForKey:@"username"];
    _password.text = [credentials objectForKey:@"password"]; [self login:nil]; _password.text = @"";
#endif
}
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; Cancel(&_request); [self.view endEditing:YES]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; _background.frame = self.view.bounds; _scroll.frame = self.view.bounds;
    CGFloat width = MIN(500, self.view.bounds.size.width - 64), height = 490;
    CGFloat top = MAX(30, (self.view.bounds.size.height - height) / 2);
    _form.frame = CGRectMake((self.view.bounds.size.width - width) / 2, top, width, height);
    _brand.frame = CGRectMake((width - 210) / 2, 30, 210, 48); _heading.frame = CGRectMake(20, 91, width - 40, 26);
    _server.frame = CGRectMake(28, 140, width - 56, 48); _username.frame = CGRectMake(28, 204, width - 56, 48);
    _password.frame = CGRectMake(28, 268, width - 56, 48); _login.frame = CGRectMake(28, 337, width - 56, 52);
    _spinner.center = CGPointMake(width - 50, 363); _status.frame = CGRectMake(28, 403, width - 56, 70);
    _scroll.contentSize = CGSizeMake(self.view.bounds.size.width, top + height + 30);
}
- (void)keyboardChanged:(NSNotification *)notification {
    CGRect keyboard = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    keyboard = [self.view convertRect:keyboard fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboard));
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0); _scroll.scrollIndicatorInsets = _scroll.contentInset;
    UITextField *field = _server.isFirstResponder ? _server : (_username.isFirstResponder ? _username : _password);
    [_scroll scrollRectToVisible:[_form convertRect:CGRectInset(field.frame, 0, -16) toView:_scroll] animated:YES];
}
- (void)keyboardHidden:(NSNotification *)notification { (void)notification; _scroll.contentInset = UIEdgeInsetsZero; _scroll.scrollIndicatorInsets = UIEdgeInsetsZero; }
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    if (field == _server) [_username becomeFirstResponder]; else if (field == _username) [_password becomeFirstResponder]; else [self login:nil];
    return YES;
}
- (void)login:(id)sender {
    (void)sender; if (_request) return; [self.view endEditing:YES];
    NSError *error = nil;
    if (![[FNTVClient sharedClient] configureServer:_server.text error:&error]) { _status.text = [error localizedDescription]; return; }
    if (![_username.text length] || ![_password.text length]) { _status.text = @"请输入用户名和密码。"; return; }
    _login.enabled = NO; _login.alpha = 0.6; _status.text = @"正在连接 NAS…"; [_spinner startAnimating];
    _request = [[[FNTVClient sharedClient] loginUsername:_username.text password:_password.text completion:^(id result, NSError *failure) {
        (void)result; [_request release]; _request = nil; [_spinner stopAnimating]; _login.enabled = YES; _login.alpha = 1;
        if (failure) { _status.text = [failure localizedDescription]; return; }
        _password.text = @"";
        RunRequestedSelfCheck();
        FNTVLibraryController *library = [[[FNTVLibraryController alloc] init] autorelease];
        [self.navigationController setViewControllers:[NSArray arrayWithObject:library] animated:YES];
    }] retain];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self]; Cancel(&_request);
    [_scroll release]; [_background release]; [_brand release]; [_form release]; [_heading release]; [_status release];
    [_server release]; [_username release]; [_password release]; [_login release]; [_spinner release]; [super dealloc];
}
@end

@interface FNTVPosterControl : UIControl {
    NSDictionary *_item;
    UIImageView *_poster;
    UILabel *_title, *_subtitle;
    NSOperation *_request;
}
@property(nonatomic, readonly) NSDictionary *item;
- (void)displayItem:(NSDictionary *)item;
- (void)cancelImage;
@end
@implementation FNTVPosterControl
@synthesize item = _item;
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _poster = [[UIImageView alloc] initWithFrame:CGRectZero]; _poster.backgroundColor = Panel();
        _poster.contentMode = UIViewContentModeScaleAspectFit; _poster.clipsToBounds = YES; [self addSubview:_poster];
        _title = [Label(16, YES) retain]; _title.numberOfLines = 2; [self addSubview:_title];
        _subtitle = [Label(13, NO) retain]; _subtitle.textColor = [UIColor lightGrayColor]; [self addSubview:_subtitle];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitButton;
    }
    return self;
}
- (void)displayItem:(NSDictionary *)item {
    Cancel(&_request); [_item release]; _item = [item copy];
    _title.text = Text([item objectForKey:@"title"]); self.accessibilityLabel = _title.text;
    NSTimeInterval resume = Seconds([item objectForKey:@"resumeSeconds"]);
    NSString *year = Text([item objectForKey:@"year"]);
    if (![year length] && [[item objectForKey:@"year"] respondsToSelector:@selector(stringValue)]) year = [[item objectForKey:@"year"] stringValue];
    _subtitle.text = resume > 0 ? [NSString stringWithFormat:@"看到 %@", TimeText(resume)] : year;
    _poster.image = [UIImage imageNamed:@"poster-placeholder.png"];
    _poster.contentMode = UIViewContentModeScaleAspectFit;
    NSString *path = Text([item objectForKey:@"poster"]);
    if ([path length]) _request = [[[FNTVClient sharedClient] imageForPath:path completion:^(id image, NSError *error) {
        [_request release]; _request = nil;
        if (!error && [image isKindOfClass:[UIImage class]]) { _poster.image = image; _poster.contentMode = UIViewContentModeScaleAspectFill; }
    }] retain];
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat h = self.bounds.size.height - 65;
    _poster.frame = CGRectMake(0, 0, self.bounds.size.width, h);
    _title.frame = CGRectMake(0, h + 7, self.bounds.size.width, 39); _subtitle.frame = CGRectMake(0, h + 48, self.bounds.size.width, 17);
}
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.alpha = highlighted ? 0.55 : 1; }
- (void)cancelImage { Cancel(&_request); }
- (void)dealloc { Cancel(&_request); [_item release]; [_poster release]; [_title release]; [_subtitle release]; [super dealloc]; }
@end

@implementation FNTVLibraryController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"飞牛影视"; self.view.backgroundColor = Background();
    _items = [[NSMutableArray alloc] init]; _libraryGUID = [@"" copy]; _query = [@"" copy]; _columns = 4;
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"全部媒体库 ▾" style:UIBarButtonItemStyleBordered target:self action:@selector(chooseLibrary:)] autorelease];
    UIBarButtonItem *logout = [[[UIBarButtonItem alloc] initWithTitle:@"退出登录" style:UIBarButtonItemStyleBordered target:self action:@selector(confirmLogout:)] autorelease];
    UIBarButtonItem *refresh = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh:)] autorelease];
    self.navigationItem.rightBarButtonItems = [NSArray arrayWithObjects:logout, refresh, nil];
    _search = [[UISearchBar alloc] initWithFrame:CGRectZero]; _search.barStyle = UIBarStyleBlack; _search.delegate = self;
    _search.placeholder = @"搜索全部媒体"; _search.showsCancelButton = YES; [self.view addSubview:_search];
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain]; _table.backgroundColor = Background();
    _table.separatorStyle = UITableViewCellSeparatorStyleNone; _table.dataSource = self; _table.delegate = self; [self.view addSubview:_table];
    _footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 768, 110)];
    _status = [Label(16, NO) retain]; _status.numberOfLines = 3; _status.textColor = [UIColor lightGrayColor];
    _status.textAlignment = (NSInteger)UITextAlignmentCenter; [_footer addSubview:_status];
    _more = [ActionButton(@"加载更多", self, @selector(loadMore:)) retain]; [_footer addSubview:_more]; _more.hidden = YES;
    _table.tableFooterView = _footer; [self loadLibraries];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.navigationController setNavigationBarHidden:NO animated:animated]; }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews]; CGFloat width = self.view.bounds.size.width;
    _search.frame = CGRectMake(0, 0, width, 44); _table.frame = CGRectMake(0, 44, width, self.view.bounds.size.height - 44);
    NSUInteger columns = MAX(3, (NSUInteger)(width / 175));
    if (columns != _columns) { _columns = columns; [_table reloadData]; }
    _footer.frame = CGRectMake(0, 0, width, 110); _status.frame = CGRectMake(24, 4, width - 48, 48);
    _more.frame = CGRectMake((width - 220) / 2, 60, 220, 44);
}
- (void)setStatus:(NSString *)status { _status.text = status; _more.hidden = !_hasMore || _loading; }
- (void)loadLibraries {
    Cancel(&_libraryRequest); _loading = YES; [self setStatus:@"正在读取媒体库…"];
    _libraryRequest = [[[FNTVClient sharedClient] libraries:^(id result, NSError *error) {
        [_libraryRequest release]; _libraryRequest = nil; _loading = NO;
        if (error) { [self setStatus:[NSString stringWithFormat:@"%@\n点击右上角刷新重试。", [error localizedDescription]]]; return; }
        [_libraries release]; _libraries = [result copy]; [self loadPage:1];
    }] retain];
}
- (void)loadPage:(NSUInteger)page {
    Cancel(&_request);
    if (page == 1) { [_items removeAllObjects]; _page = 0; _hasMore = NO; [_table reloadData]; }
    _loading = YES; [self setStatus:@"正在加载影片…"];
    _request = [[[FNTVClient sharedClient] itemsInLibrary:_libraryGUID page:page search:_query completion:^(id result, NSError *error) {
        [_request release]; _request = nil; _loading = NO;
        if (error) { [self setStatus:[NSString stringWithFormat:@"%@\n点击右上角刷新重试。", [error localizedDescription]]]; return; }
        if (page == 1) [_items removeAllObjects];
        NSArray *items = [result objectForKey:@"items"]; if ([items isKindOfClass:[NSArray class]]) [_items addObjectsFromArray:items];
        _page = page; _hasMore = [[result objectForKey:@"hasMore"] boolValue]; [_table reloadData];
        if (page == 1) [_table setContentOffset:CGPointZero animated:NO];
        NSString *status = [_items count] ? [NSString stringWithFormat:@"%@ %lu 部%@", [_query length] ? @"全库搜索：" : @"已显示", (unsigned long)[_items count], _hasMore ? @"" : @" · 已全部加载"] : @"没有找到影片。可以切换媒体库或更改搜索词。";
        [self setStatus:status];
    }] retain];
}
- (void)refresh:(id)sender { (void)sender; if (!_libraries) [self loadLibraries]; else [self loadPage:1]; }
- (void)loadMore:(id)sender { (void)sender; if (!_loading && _hasMore) [self loadPage:_page + 1]; }
- (void)chooseLibrary:(id)sender {
    (void)sender; [_search resignFirstResponder];
#if FNTV_DIAGNOSTICS
    _smokeModalActive = YES;
#endif
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"选择媒体库" delegate:self cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
    [sheet addButtonWithTitle:@"全部媒体库"];
    for (NSDictionary *library in _libraries) [sheet addButtonWithTitle:Text([library objectForKey:@"title"])];
    sheet.cancelButtonIndex = [sheet addButtonWithTitle:@"取消"];
    [sheet showFromBarButtonItem:self.navigationItem.leftBarButtonItem animated:YES]; [sheet release];
}
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex < 0 || buttonIndex == actionSheet.cancelButtonIndex) return;
    NSDictionary *library = buttonIndex > 0 && (NSUInteger)buttonIndex <= [_libraries count] ? [_libraries objectAtIndex:buttonIndex - 1] : nil;
    [_libraryGUID release]; _libraryGUID = [Text([library objectForKey:@"guid"]) copy];
    self.navigationItem.leftBarButtonItem.title = [NSString stringWithFormat:@"%@ ▾", library ? Text([library objectForKey:@"title"]) : @"全部媒体库"];
    [_query release]; _query = [@"" copy]; _search.text = @""; [self loadPage:1];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder]; [_query release]; _query = [[searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy]; [self loadPage:1];
}
- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder]; searchBar.text = @""; [_query release]; _query = [@"" copy]; [self loadPage:1];
}
- (void)confirmLogout:(id)sender {
#if FNTV_DIAGNOSTICS
    _smokeModalActive = YES;
#endif
    (void)sender; UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"退出登录？" message:@"下次使用时需要重新输入密码。"
        delegate:self cancelButtonTitle:@"取消" otherButtonTitles:@"退出登录", nil]; [alert show]; [alert release];
}
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    (void)alertView; if (buttonIndex != 1) return;
    Cancel(&_request); Cancel(&_libraryRequest); [[FNTVClient sharedClient] logout];
    FNTVLoginController *login = [[[FNTVLoginController alloc] init] autorelease];
    [self.navigationController setViewControllers:[NSArray arrayWithObject:login] animated:YES];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return ([_items count] + _columns - 1) / _columns; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)indexPath; CGFloat cardWidth = (tableView.bounds.size.width - 24 * 2 - 18 * (_columns - 1)) / _columns;
    return cardWidth * 1.5 + 85;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Posters"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Posters"] autorelease];
    cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.backgroundColor = Background();
    for (UIView *view in [[cell.contentView.subviews copy] autorelease]) {
        if ([view isKindOfClass:[FNTVPosterControl class]]) [(FNTVPosterControl *)view cancelImage];
        [view removeFromSuperview];
    }
    CGFloat width = (tableView.bounds.size.width - 48 - 18 * (_columns - 1)) / _columns;
    for (NSUInteger column = 0; column < _columns; column++) {
        NSUInteger index = indexPath.row * _columns + column; if (index >= [_items count]) break;
        FNTVPosterControl *poster = [[[FNTVPosterControl alloc] initWithFrame:CGRectMake(24 + column * (width + 18), 12, width, width * 1.5 + 65)] autorelease];
        [poster displayItem:[_items objectAtIndex:index]]; [poster addTarget:self action:@selector(openItem:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:poster];
    }
    return cell;
}
- (void)openItem:(FNTVPosterControl *)sender {
    [_search resignFirstResponder]; FNTVDetailController *detail = [[[FNTVDetailController alloc] initWithItem:sender.item] autorelease];
#if FNTV_DIAGNOSTICS
    FNTVSmokeBindDetail(Text([sender.item objectForKey:@"guid"]), detail);
#endif
    [self.navigationController pushViewController:detail animated:YES];
}
#if FNTV_DIAGNOSTICS
- (void)actionSheet:(UIActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)index { (void)sheet; (void)index; _smokeModalActive = NO; }
- (void)alertView:(UIAlertView *)alert didDismissWithButtonIndex:(NSInteger)index { (void)alert; (void)index; _smokeModalActive = NO; }
- (void)tryForegroundSmoke {
    if (_loading || _smokeModalActive || !_table.window || [UIApplication sharedApplication].keyWindow != self.view.window ||
        _search.isFirstResponder || self.navigationController.topViewController != self ||
        self.navigationController.presentedViewController || self.presentedViewController) return;
    for (NSIndexPath *path in [[_table indexPathsForVisibleRows] sortedArrayUsingSelector:@selector(compare:)]) {
        UITableViewCell *cell = [_table cellForRowAtIndexPath:path];
        for (UIView *view in cell.contentView.subviews) if ([view isKindOfClass:[FNTVPosterControl class]]) {
            FNTVPosterControl *poster = (FNTVPosterControl *)view;
            if ([[Text([poster.item objectForKey:@"type"]) lowercaseString] isEqualToString:@"movie"] &&
                FNTVSmokeSelectMovie(Text([poster.item objectForKey:@"guid"]))) {
                [poster sendActionsForControlEvents:UIControlEventTouchUpInside]; return;
            }
        }
    }
}
#endif
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (void)dealloc {
    Cancel(&_request); Cancel(&_libraryRequest); [_table release]; [_search release]; [_status release]; [_more release]; [_footer release];
    [_libraries release]; [_items release]; [_libraryGUID release]; [_query release]; [super dealloc];
}
@end

@implementation FNTVDetailController
- (id)initWithItem:(NSDictionary *)item { if ((self = [super init])) _item = [item copy]; return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = Background(); self.title = Text([_item objectForKey:@"title"]);
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh:)] autorelease];
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight; _table.backgroundColor = Background();
    _table.separatorColor = Panel(); _table.dataSource = self; _table.delegate = self; [self.view addSubview:_table];
    _header = [[UIView alloc] initWithFrame:CGRectZero];
    _poster = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"poster-placeholder.png"]];
    _poster.contentMode = UIViewContentModeScaleAspectFit; _poster.clipsToBounds = YES; [_header addSubview:_poster];
    _name = [Label(28, YES) retain]; _name.numberOfLines = 3; [_header addSubview:_name];
    _metadata = [Label(16, NO) retain]; _metadata.numberOfLines = 2; _metadata.textColor = [UIColor lightGrayColor]; [_header addSubview:_metadata];
    _overview = [Label(17, NO) retain]; _overview.numberOfLines = 0; [_header addSubview:_overview];
    _play = [ActionButton(@"播放", self, @selector(play:)) retain]; [_header addSubview:_play];
    _restart = [[UIButton buttonWithType:UIButtonTypeCustom] retain]; [_restart setTitle:@"从头播放" forState:UIControlStateNormal];
    [_restart setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal]; [_restart addTarget:self action:@selector(restart:) forControlEvents:UIControlEventTouchUpInside]; [_header addSubview:_restart];
    _status = [Label(16, NO) retain]; _status.numberOfLines = 3; _status.textColor = [UIColor lightGrayColor]; [_header addSubview:_status];
    _moreDirectory = [ActionButton(@"加载更多", self, @selector(moreDirectory:)) retain];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackStopped:) name:@"FNTVPlaybackStopped" object:nil];
    [self renderItem]; [self loadDetail];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
#if FNTV_DIAGNOSTICS
    _smokeVisible = NO;
#endif
    if (self.isMovingFromParentViewController || !self.navigationController || [self.navigationController.viewControllers indexOfObjectIdenticalTo:self] == NSNotFound) {
#if FNTV_DIAGNOSTICS
        FNTVSmokeDetailPopped(self);
#endif
        Cancel(&_request); Cancel(&_childrenRequest); Cancel(&_imageRequest);
        if (_preparing) { Cancel(&_playRequest); [[FNTVClient sharedClient] stopPlayback]; _preparing = NO; }
    }
}
#if FNTV_DIAGNOSTICS
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; _smokeVisible = YES; }
- (void)tryForegroundSmoke {
    if (!_smokeVisible || _loading || _preparing || !_play.enabled || _play.hidden || !self.view.window ||
        [UIApplication sharedApplication].keyWindow != self.view.window ||
        self.navigationController.topViewController != self || self.presentedViewController || self.navigationController.presentedViewController) return;
    if ([[Text([_item objectForKey:@"type"]) lowercaseString] isEqualToString:@"movie"] &&
        FNTVSmokeStartPlayback(Text([_item objectForKey:@"guid"]), self)) [_play sendActionsForControlEvents:UIControlEventTouchUpInside];
}
#endif
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self layoutHeader]; }
- (void)layoutHeader {
    CGFloat width = self.view.bounds.size.width, textX = 255, textWidth = width - textX - 30;
    BOOL directory = [[Text([_item objectForKey:@"type"]) lowercaseString] isEqualToString:@"directory"];
    _poster.hidden = directory; _overview.hidden = directory; _metadata.hidden = directory;
    _moreDirectory.frame = CGRectMake(0, 0, width, 52);
    if (directory) {
        _name.frame = CGRectMake(28, 20, width - 56, 65); _status.frame = CGRectMake(28, 91, width - 56, 60);
        if (_header.frame.size.width != width || _header.frame.size.height != 165) {
            _header.frame = CGRectMake(0, 0, width, 165); _table.tableHeaderView = _header;
        }
        return;
    }
    _poster.frame = CGRectMake(28, 28, 195, 292);
    _name.frame = CGRectMake(textX, 28, textWidth, 100); _metadata.frame = CGRectMake(textX, 138, textWidth, 48);
    _play.frame = CGRectMake(textX, 210, MIN(250, textWidth), 52); _restart.frame = CGRectMake(textX, 274, MIN(250, textWidth), 44);
    CGSize descriptionSize = [_overview.text sizeWithFont:_overview.font constrainedToSize:CGSizeMake(width - 56, 3000) lineBreakMode:(NSInteger)UILineBreakModeWordWrap];
    CGFloat overviewHeight = MAX(24, descriptionSize.height);
    _overview.frame = CGRectMake(28, 345, width - 56, overviewHeight); _status.frame = CGRectMake(28, 363 + overviewHeight, width - 56, 65);
    CGFloat height = 440 + overviewHeight;
    if (_header.frame.size.width != width || _header.frame.size.height != height) {
        _header.frame = CGRectMake(0, 0, width, height); _table.tableHeaderView = _header;
    }
}
- (void)renderItem {
    _name.text = Text([_item objectForKey:@"title"]); self.title = _name.text;
    NSMutableArray *metadata = [NSMutableArray array];
    NSString *date = Text([_item objectForKey:@"release_date"]);
    if ([date length] >= 4) [metadata addObject:[date substringToIndex:4]];
    NSTimeInterval duration = Seconds([_item objectForKey:@"duration"]); if (duration > 0) [metadata addObject:TimeText(duration)];
    id rating = [_item objectForKey:@"vote_average"]; if ([rating respondsToSelector:@selector(doubleValue)] && [rating doubleValue] > 0) [metadata addObject:[NSString stringWithFormat:@"评分 %.1f", [rating doubleValue]]];
    _metadata.text = [metadata componentsJoinedByString:@"  ·  "];
    _overview.text = [Text([_item objectForKey:@"overview"]) length] ? Text([_item objectForKey:@"overview"]) : @"暂无简介。";
    BOOL container = IsContainer(_item); _play.hidden = container; _restart.hidden = container || Seconds([_item objectForKey:@"resumeSeconds"]) <= 0;
    [_play setTitle:Seconds([_item objectForKey:@"resumeSeconds"]) > 0 ? [NSString stringWithFormat:@"继续播放 · %@", TimeText(Seconds([_item objectForKey:@"resumeSeconds"]))] : @"播放" forState:UIControlStateNormal];
    Cancel(&_imageRequest); NSString *poster = Text([_item objectForKey:@"poster"]);
    if ([poster length]) _imageRequest = [[[FNTVClient sharedClient] imageForPath:poster completion:^(id image, NSError *error) {
        [_imageRequest release]; _imageRequest = nil;
        if (!error && [image isKindOfClass:[UIImage class]]) { _poster.image = image; _poster.contentMode = UIViewContentModeScaleAspectFill; }
    }] retain];
    [self layoutHeader];
}
- (void)refresh:(id)sender { (void)sender; if (!_preparing) [self loadDetail]; }
- (void)playbackStopped:(NSNotification *)notification {
    if (![Text([notification.object objectForKey:@"item_guid"]) isEqualToString:Text([_item objectForKey:@"guid"])]) return;
    NSMutableDictionary *updated = [[_item mutableCopy] autorelease];
    [updated setObject:[[notification userInfo] objectForKey:@"seconds"] forKey:@"resumeSeconds"];
    [_item release]; _item = [updated copy]; [self renderItem];
}
- (void)loadDetail {
    Cancel(&_request); Cancel(&_childrenRequest); _loading = YES; _status.text = @"正在读取详情…";
    _request = [[[FNTVClient sharedClient] detailForItem:Text([_item objectForKey:@"guid"]) completion:^(id result, NSError *error) {
        [_request release]; _request = nil; _loading = NO;
        if (error) {
#if FNTV_DIAGNOSTICS
            FNTVSmokeFailed(Text([_item objectForKey:@"guid"]), 1, error, nil);
#endif
            _status.text = [NSString stringWithFormat:@"%@\n点击刷新重试。", [error localizedDescription]]; return;
        }
        [_item release]; _item = [result copy]; [self renderItem];
        NSString *type = [Text([_item objectForKey:@"type"]) lowercaseString];
        if ([type isEqualToString:@"tv"] || [type isEqualToString:@"season"]) {
            _status.text = [type isEqualToString:@"tv"] ? @"正在读取季…" : @"正在读取剧集…";
            FNTVCompletion completion = ^(id children, NSError *failure) {
                [_childrenRequest release]; _childrenRequest = nil;
                if (failure) { _status.text = [failure localizedDescription]; return; }
                [_children release]; _children = [children copy]; [_table reloadData];
                _status.text = [_children count] ? [NSString stringWithFormat:@"选择%@ · %lu 项", [type isEqualToString:@"tv"] ? @"季" : @"剧集", (unsigned long)[_children count]] : @"暂无可播放的剧集。";
            };
            _childrenRequest = [([type isEqualToString:@"tv"] ? [[FNTVClient sharedClient] seasonsForTV:Text([_item objectForKey:@"guid"]) completion:completion] :
                [[FNTVClient sharedClient] episodesForSeason:Text([_item objectForKey:@"guid"]) completion:completion]) retain];
        } else if ([type isEqualToString:@"directory"]) {
            [self loadDirectoryPage:1];
        } else _status.text = @"播放时可暂停、拖动进度；观看进度会同步至 NAS。";
    }] retain];
}
- (void)loadDirectoryPage:(NSUInteger)page {
    Cancel(&_childrenRequest); _moreDirectory.enabled = NO; _status.text = @"正在读取文件夹…";
    _childrenRequest = [[[FNTVClient sharedClient] itemsInDirectory:Text([_item objectForKey:@"guid"]) page:page completion:^(id result, NSError *error) {
        [_childrenRequest release]; _childrenRequest = nil; _moreDirectory.enabled = YES;
        if (error) { _status.text = [error localizedDescription]; return; }
        NSArray *items = [result objectForKey:@"items"];
        NSArray *combined = page == 1 ? items : [_children arrayByAddingObjectsFromArray:items];
        [combined retain]; [_children release]; _children = combined;
        _directoryPage = page; _directoryHasMore = [[result objectForKey:@"hasMore"] boolValue];
        _table.tableFooterView = _directoryHasMore ? _moreDirectory : nil; [_table reloadData];
        _status.text = [_children count] ? [NSString stringWithFormat:@"%lu 项%@", (unsigned long)[_children count], _directoryHasMore ? @" · 可继续加载" : @""] : @"这个文件夹中没有媒体。";
    }] retain];
}
- (void)moreDirectory:(id)sender { (void)sender; if (!_childrenRequest && _directoryHasMore) [self loadDirectoryPage:_directoryPage + 1]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return [_children count]; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { (void)tableView; (void)indexPath; return 80; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Episode"];
    if (!cell) cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Episode"] autorelease];
    NSDictionary *item = [_children objectAtIndex:indexPath.row];
    cell.backgroundColor = Panel(); cell.textLabel.backgroundColor = [UIColor clearColor]; cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont boldSystemFontOfSize:20]; cell.textLabel.text = Text([item objectForKey:@"title"]);
    cell.detailTextLabel.backgroundColor = [UIColor clearColor]; cell.detailTextLabel.textColor = [UIColor lightGrayColor]; cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
    NSTimeInterval resume = Seconds([item objectForKey:@"resumeSeconds"]), duration = Seconds([item objectForKey:@"duration"]);
    BOOL directory = [[Text([item objectForKey:@"type"]) lowercaseString] isEqualToString:@"directory"];
    cell.detailTextLabel.text = resume > 0 ? [NSString stringWithFormat:@"继续观看 · %@", TimeText(resume)] : (duration > 0 ? TimeText(duration) : (directory ? @"打开文件夹" : (IsContainer(item) ? @"查看剧集" : @"查看详情与播放")));
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    FNTVDetailController *detail = [[[FNTVDetailController alloc] initWithItem:[_children objectAtIndex:indexPath.row]] autorelease];
    [self.navigationController pushViewController:detail animated:YES];
}
- (void)play:(id)sender { (void)sender; [self preparePlayback:Seconds([_item objectForKey:@"resumeSeconds"])]; }
- (void)restart:(id)sender { (void)sender; [self preparePlayback:0]; }
- (void)preparePlayback:(NSTimeInterval)seconds {
    if (_preparing) return; _preparing = YES; _play.enabled = NO; _restart.enabled = NO; _play.alpha = 0.5;
    _status.text = @"正在为 iPad 准备播放…";
#if FNTV_DIAGNOSTICS
    BOOL smokeRequest = FNTVSmokeOwnsPreparation(Text([_item objectForKey:@"guid"]), self);
#endif
    __block NSOperation *preparedRequest = nil;
    preparedRequest = [[FNTVClient sharedClient] preparePlaybackForItem:Text([_item objectForKey:@"guid"]) startTime:seconds completion:^(id result, NSError *error) {
#if FNTV_DIAGNOSTICS
        // A later manual request must not be mistaken for this callback's operation.
        NSOperation *completedRequest = [[preparedRequest retain] autorelease];
        if (smokeRequest && _playRequest != completedRequest) {
            if (error) FNTVSmokeFailed(Text([_item objectForKey:@"guid"]), 2, error, completedRequest);
            else FNTVSmokeCompletePreparation(Text([_item objectForKey:@"guid"]), self, completedRequest, YES, NO, ^{}, ^{
                [[FNTVClient sharedClient] discardPreparedPlayback:result];
            });
            return;
        }
#endif
        [_playRequest release]; _playRequest = nil; _preparing = NO; _play.enabled = YES; _restart.enabled = YES; _play.alpha = 1;
        if (error) {
#if FNTV_DIAGNOSTICS
            FNTVSmokeFailed(Text([_item objectForKey:@"guid"]), 2, error, completedRequest);
#endif
            _status.text = [error localizedDescription]; ShowError(@"无法播放", error); return;
        }
        void (^presentPlayer)(void) = ^{
            NSError *audioError = nil; NSUInteger audioLease = FNTVBeginPlaybackAudio(&audioError);
            if (!audioLease) {
#if FNTV_DIAGNOSTICS
                FNTVSmokeFailed(Text([_item objectForKey:@"guid"]), 4, audioError, completedRequest);
#endif
                [[FNTVClient sharedClient] discardPreparedPlayback:result];
                _status.text = [audioError localizedDescription]; ShowError(@"无法启用播放声音", audioError); return;
            }
            void (^showPlayer)(void) = ^{
                _status.text = @"播放已就绪。";
                FNTVPlayerController *player = [[[FNTVPlayerController alloc] initWithPlayback:result audioLease:audioLease] autorelease];
                if (!player) {
                    FNTVSchedulePlaybackAudioRelease(audioLease); [[FNTVClient sharedClient] discardPreparedPlayback:result];
                    _status.text = @"无法创建播放器，请重试。"; return;
                }
#if FNTV_DIAGNOSTICS
                FNTVSmokeAttachPlayer(Text([_item objectForKey:@"guid"]), completedRequest, player, audioLease);
#endif
                [self presentMoviePlayerViewControllerAnimated:player];
            };
#if FNTV_DIAGNOSTICS
            // Audio activation can block; recheck the same presentation gate afterwards.
            BOOL stillCurrent = _smokeVisible && self.view.window && [UIApplication sharedApplication].keyWindow == self.view.window &&
                self.navigationController.topViewController == self && !self.presentedViewController && !self.navigationController.presentedViewController;
            FNTVSmokeCompletePreparation(Text([_item objectForKey:@"guid"]), self, completedRequest, smokeRequest, stillCurrent, showPlayer, ^{
                FNTVSchedulePlaybackAudioRelease(audioLease); [[FNTVClient sharedClient] discardPreparedPlayback:result];
                _status.text = @"播放准备已取消。";
            });
#else
            showPlayer();
#endif
        };
#if FNTV_DIAGNOSTICS
        BOOL currentDetail = _smokeVisible && self.view.window && [UIApplication sharedApplication].keyWindow == self.view.window &&
            self.navigationController.topViewController == self && !self.presentedViewController && !self.navigationController.presentedViewController;
        FNTVSmokeCompletePreparation(Text([_item objectForKey:@"guid"]), self, completedRequest, smokeRequest, currentDetail, presentPlayer, ^{
            [[FNTVClient sharedClient] discardPreparedPlayback:result];
            _status.text = @"播放准备已取消。";
        });
#else
        presentPlayer();
#endif
    }];
    _playRequest = [preparedRequest retain];
#if FNTV_DIAGNOSTICS
    NSOperation *ownedRequest = _playRequest;
    FNTVSmokeTrackPreparation(Text([_item objectForKey:@"guid"]), ownedRequest, ^{
        if (_playRequest != ownedRequest) return;
        Cancel(&_playRequest); _preparing = NO; _play.enabled = YES; _restart.enabled = YES; _play.alpha = 1;
        _status.text = @"播放准备已取消。";
    });
#endif
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    Cancel(&_request); Cancel(&_childrenRequest); Cancel(&_imageRequest); Cancel(&_playRequest);
    [_item release]; [_children release]; [_table release]; [_header release]; [_poster release]; [_name release]; [_metadata release]; [_overview release];
    [_status release]; [_play release]; [_restart release]; [_moreDirectory release]; [super dealloc];
}
@end

@implementation FNTVPlayerController
- (id)initWithPlayback:(NSDictionary *)playback audioLease:(NSUInteger)lease {
    if ((self = [super initWithContentURL:[playback objectForKey:@"URL"]])) {
        _audioLease = lease;
        _playback = [playback copy]; _lastSeconds = Seconds([playback objectForKey:@"startTime"]);
        self.moviePlayer.initialPlaybackTime = _lastSeconds; self.moviePlayer.controlStyle = MPMovieControlStyleFullscreen;
        self.moviePlayer.shouldAutoplay = YES; self.moviePlayer.scalingMode = MPMovieScalingModeAspectFit;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(finished:) name:MPMoviePlayerPlaybackDidFinishNotification object:self.moviePlayer];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(resignActive:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!_timer && !_closing) _timer = [[NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(progress:) userInfo:nil repeats:YES] retain];
}
- (void)progress:(NSTimer *)timer {
    (void)timer; if (_closing) return;
    NSTimeInterval time = self.moviePlayer.currentPlaybackTime;
    if (isfinite(time) && time >= 0) _lastSeconds = time;
    if (_lastSeconds > 0) [[FNTVClient sharedClient] recordPlayback:_playback seconds:_lastSeconds completion:nil];
}
- (void)resignActive:(NSNotification *)notification { (void)notification; [self.moviePlayer pause]; [self progress:nil]; }
- (void)finishProgress {
    if (_closing) return;
    NSTimeInterval time = self.moviePlayer.currentPlaybackTime;
    if (isfinite(time) && time >= 0) _lastSeconds = time;
    _closing = YES; [_timer invalidate]; [_timer release]; _timer = nil;
    [self.moviePlayer pause];
    // Close this proxy before a new player can start; progress only needs the saved session dictionary.
    [[FNTVClient sharedClient] stopPlayback];
    if (![FNTVClient sharedClient].isAuthenticated) return;
    if (_lastSeconds > 0) [[NSNotificationCenter defaultCenter] postNotificationName:@"FNTVPlaybackStopped" object:_playback
        userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:_lastSeconds] forKey:@"seconds"]];
    if (_lastSeconds > 0) [[FNTVClient sharedClient] recordPlayback:_playback seconds:_lastSeconds completion:^(id result, NSError *error) {
        (void)result; if (error) ShowError(@"观看进度未能同步", error);
    }];
}
- (void)finished:(NSNotification *)notification {
    if (_releasingAudio) return;
    NSInteger reason = [[[notification userInfo] objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey] integerValue];
    [self finishProgress];
    UIViewController *presenter = self.presentingViewController;
    [presenter dismissMoviePlayerViewControllerAnimated];
    if (reason == MPMovieFinishReasonPlaybackError) {
        NSError *error = [[notification userInfo] objectForKey:@"error"];
        if (![error isKindOfClass:[NSError class]]) error = [NSError errorWithDomain:@"FNTVPlayer" code:1 userInfo:[NSDictionary dictionaryWithObject:@"iPad 无法播放此视频。请检查 NAS 转码服务和网络连接后重试。" forKey:NSLocalizedDescriptionKey]];
        ShowError(@"播放中断", error);
    }
}
- (void)viewWillDisappear:(BOOL)animated { [self finishProgress]; [super viewWillDisappear:animated]; }
- (void)releasePlaybackAudio {
    FNTVStopPlaybackAudioIOOnce(_audioLease, &_audioIOStopped, ^{
        _releasingAudio = YES; [self.moviePlayer stop]; _releasingAudio = NO;
    });
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated]; [self releasePlaybackAudio]; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self]; [self releasePlaybackAudio];
    NSUInteger lease = _audioLease;
    [_timer invalidate]; [_timer release]; [_playback release]; [super dealloc];
    // Only a copied scalar is used after super has released the old movie and its I/O.
    FNTVSchedulePlaybackAudioRelease(lease);
}
@end

UIViewController *FNTVRootController(void) {
    RunRequestedSelfCheck();
    UIViewController *root = [FNTVClient sharedClient].isAuthenticated ? [[[FNTVLibraryController alloc] init] autorelease] : [[[FNTVLoginController alloc] init] autorelease];
    UINavigationController *navigation = [[[FNTVPortraitNavigationController alloc] initWithRootViewController:root] autorelease];
    navigation.navigationBar.barStyle = UIBarStyleBlack; navigation.navigationBar.tintColor = Panel();
#if FNTV_DIAGNOSTICS
    FNTVBeginForegroundSmoke(^{
        UIViewController *top = navigation.topViewController;
        if ([top isKindOfClass:[FNTVLibraryController class]]) [(FNTVLibraryController *)top tryForegroundSmoke];
        else if ([top isKindOfClass:[FNTVDetailController class]]) [(FNTVDetailController *)top tryForegroundSmoke];
    });
#endif
    return navigation;
}
void FNTVRunUISelfTests(void) {
#ifdef FNTV_SELF_TEST
    NSCAssert(Seconds([NSNull null]) == 0 && Seconds(@"-4") == 0 && Seconds(@"90") == 90, @"Invalid progress must not enter player");
    NSCAssert([TimeText(3900) isEqualToString:@"1小时5分"] && [TimeText(0) isEqualToString:@"0分"], @"Duration display must match minutes");
    NSCAssert(IsContainer([NSDictionary dictionaryWithObject:@"TV" forKey:@"type"]), @"TV opens seasons");
    NSCAssert(IsContainer([NSDictionary dictionaryWithObject:@"Season" forKey:@"type"]), @"Season opens episodes");
    NSCAssert(!IsContainer([NSDictionary dictionaryWithObject:@"Episode" forKey:@"type"]), @"Episode can play");
    NSLog(@"FNTV_UI_SELF_TEST_PASS: progress validation, duration, TV/season/episode routing");
#endif
}
