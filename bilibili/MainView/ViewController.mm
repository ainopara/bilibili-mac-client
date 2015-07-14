//
//  ViewController.m
//  bilibili
//
//  Created by TYPCN on 2015/3/30.
//  Copyleft 2015 TYPCN. All rights reserved.
//

#import "ViewController.h"
#import <Sparkle/Sparkle.h>
#import "downloadWrapper.h"
#import "Analytics.h"

NSString *vUrl;
NSString *vCID;
NSString *vTitle;
NSString *userAgent;
NSWindow *currWindow;
NSMutableArray *downloaderObjects;
Downloader* DL;
NSLock *dList = [[NSLock alloc] init];
BOOL parsing = false;
BOOL isTesting;

@implementation ViewController

- (BOOL)canBecomeMainWindow { return YES; }
- (BOOL)canBecomeKeyWindow { return YES; }

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
- (IBAction)playClick:(id)sender {
    vUrl = [self.urlField stringValue];
    NSLog(@"USER INPUT: %@",vUrl);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view.window setBackgroundColor:NSColor.whiteColor];
    self.view.layer.backgroundColor = CGColorCreateGenericRGB(255, 255, 255, 1.0f);
    currWindow = self.view.window;
    [self.view.window makeKeyWindow];
    NSRect rect = [[NSScreen mainScreen] visibleFrame];
    [self.view setFrame:rect];

    NSArray *TaskList = [[NSUserDefaults standardUserDefaults] arrayForKey:@"DownloadTaskList"];
    downloaderObjects = [TaskList mutableCopy];

}

@end

@implementation WebController{
    bool ariainit;
    long acceptAnalytics;
}

+(NSString*)webScriptNameForSelector:(SEL)sel
{
    if(sel == @selector(checkForUpdates))
        return @"checkForUpdates";
    if(sel == @selector(showPlayGUI))
        return @"showPlayGUI";
    if(sel == @selector(playVideoByCID:))
        return @"playVideoByCID";
    if(sel == @selector(downloadVideoByCID:))
        return @"downloadVideoByCID";
    return nil;
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)sel
{
    if(sel == @selector(checkForUpdates))
        return NO;
    if(sel == @selector(showPlayGUI))
        return NO;
    if(sel == @selector(playVideoByCID:))
        return NO;
    if(sel == @selector(downloadVideoByCID:))
        return NO;
    return YES;
}

- (void)checkForUpdates
{
    [[SUUpdater sharedUpdater] checkForUpdates:nil];
    if(acceptAnalytics == 1 || acceptAnalytics == 2){
        action("App","CheckForUpdate","CheckForUpdate");
    }else{
        NSLog(@"Analytics disabled ! won't upload.");
    }
}

- (void)showPlayGUI
{
    [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"$('#bofqi').html('%@');$('head').append('<style>%@</style>');",WebUI,WebCSS]];
}

- (void)playVideoByCID:(NSString *)cid
{
    if(parsing){
        return;
    }
    NSArray *fn = [webView.mainFrameTitle componentsSeparatedByString:@"_"];
    NSString *mediaTitle = [fn objectAtIndex:0];
    parsing = true;
    vCID = cid;
    vUrl = webView.mainFrameURL;
    if([mediaTitle length] > 0){
        vTitle = [fn objectAtIndex:0];
    }else{
        vTitle = @"未命名";
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:vUrl forKey:@"LastPlay"];
    NSLog(@"Video detected ! CID: %@",vCID);
    if(acceptAnalytics == 1){
        action("video", "play", [vCID cStringUsingEncoding:NSUTF8StringEncoding]);
        screenView("PlayerView");
    }else if(acceptAnalytics == 2){
        screenView("PlayerView");
    }else{
        NSLog(@"Analytics disabled ! won't upload.");
    }
    [self.switchButton performClick:nil];
}
- (void)downloadVideoByCID:(NSString *)cid
{
    if(!downloaderObjects){
        downloaderObjects = [[NSMutableArray alloc] init];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"注意：下载功能仅供测试，可能有各种 BUG，支持分段视频，默认保存在 Movies 文件夹。\n点击 文件->下载管理 来查看任务"];
        [alert runModal];
    }
    if(!DL){
        DL = new Downloader();
    }
    
    if(acceptAnalytics == 1){
        action("video", "download", [cid cStringUsingEncoding:NSUTF8StringEncoding]);
        screenView("PlayerView");
    }else if(acceptAnalytics == 2){
        screenView("PlayerView");
    }else{
        NSLog(@"Analytics disabled ! won't upload.");
    }
    
    NSArray *fn = [webView.mainFrameTitle componentsSeparatedByString:@"_"];
    NSString *filename = [fn objectAtIndex:0];

    dispatch_async( dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSDictionary *taskData = @{
                                   @"name":filename,
                                   @"status":@"正在等待",
                                   @"cid":cid,
                                   };
        [dList lock];
        int index = (int)[downloaderObjects count];
        [downloaderObjects insertObject:taskData atIndex:index];
        [dList unlock];
        DL->init();
        DL->newTask([cid intValue], filename);
        
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        notification.title = filename;
        notification.informativeText = @"下载已开始，通过 文件->下载管理 来查看进度";
        notification.soundName = NSUserNotificationDefaultSoundName;
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
        DL->runDownload(index, filename);
    });
}


- (void)awakeFromNib //当 WebContoller 加载完成后执行的动作
{
    NSError *err;

    [webView setFrameLoadDelegate:self];
    [webView setUIDelegate:self];
    [webView setResourceLoadDelegate:self];

    NSUserDefaults *s = [NSUserDefaults standardUserDefaults];
    acceptAnalytics = [s integerForKey:@"acceptAnalytics"];
    
    if(!acceptAnalytics || acceptAnalytics == 1 || acceptAnalytics == 2){
        screenView("StartApplication");
    }
    NSLog(@"Start");
    webView.mainFrameURL = @"http://www.bilibili.com";
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(AVNumberUpdated:) name:@"AVNumberUpdate" object:nil];
    
    NSString *path = [[NSBundle mainBundle] pathForResource:@"webpage/inject" ofType:@"js"];
    WebScript = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if(err){
        [self showError];
    }
    
    path = [[NSBundle mainBundle] pathForResource:@"webpage/webui" ofType:@"html"];
    WebUI = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if(err){
        [self showError];
    }
    
    path = [[NSBundle mainBundle] pathForResource:@"webpage/webui" ofType:@"css"];
    WebCSS = [[NSString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if(err){
        [self showError];
    }
}

- (void)showError
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"文件读取失败，您可能无法正常使用本软件，请向开发者反馈。"];
    [alert runModal];
}

- (WebView *)webView:(WebView *)sender createWebViewWithRequest:(NSURLRequest *)request
{
    return webView;
}

- (NSURLRequest *)webView:(WebView *)sender
                 resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource{
    NSString *URL = [request.URL absoluteString];
    NSMutableURLRequest *re = [[NSMutableURLRequest alloc] init];
    re = (NSMutableURLRequest *) request.mutableCopy;
    if([URL containsString:@"google"]){
        // Google ad is blocked in some (china) area, maybe take 30 seconds to wait for timeout
        [re setURL:[NSURL URLWithString:@"http://static.hdslb.com/images/transparent.gif"]];
    }else if([URL containsString:@"qq.com"]){
        // QQ analytics may block more than 10 seconds in some area
        [re setURL:[NSURL URLWithString:@"http://static.hdslb.com/images/transparent.gif"]];
    }else if([URL containsString:@"cnzz.com"]){
        // CNZZ is very slow in other country
        [re setURL:[NSURL URLWithString:@"http://static.hdslb.com/images/transparent.gif"]];
    }else if([URL containsString:@".swf"]){
        // Block Flash
        NSLog(@"Block flash url:%@",URL);
        [re setURL:[NSURL URLWithString:@"http://static.hdslb.com/images/transparent.gif"]];
    }else if([URL containsString:@".eqoe.cn"]){
        [re setValue:@"http://client.typcn.com" forHTTPHeaderField:@"Referer"];
    }else{
        NSUserDefaults *settingsController = [NSUserDefaults standardUserDefaults];
        NSString *xff = [settingsController objectForKey:@"xff"];
        if([xff length] > 4){
            [re setValue:xff forHTTPHeaderField:@"X-Forwarded-For"];
            [re setValue:xff forHTTPHeaderField:@"Client-IP"];
        }
    }
    return re;
}

- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowScriptObject forFrame:(WebFrame *)frame
{
    [windowScriptObject setValue:self forKeyPath:@"window.external"];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if(isTesting){
        if([webView.mainFrameURL isEqualToString:@"http://www.bilibili.com/ranking"]){
            [webView stringByEvaluatingJavaScriptFromString:@"window.location=$('#rank_list li:first-child .content > a').attr('href')"];
        }else if(![webView.mainFrameURL hasPrefix:@"http://www.bilibili.com/video/av"]){
            webView.mainFrameURL = @"http://www.bilibili.com/ranking";
        }else{
            [webView stringByEvaluatingJavaScriptFromString:@"setTimeout(function(){window.external.playVideoByCID(TYPCN_PLAYER_CID)},2000);"];
        }
    }
    [webView stringByEvaluatingJavaScriptFromString:WebScript];
    userAgent =  [webView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
}

- (void)webView:(WebView *)sender
didReceiveTitle:(NSString *)title
       forFrame:(WebFrame *)frame{
    [webView stringByEvaluatingJavaScriptFromString:WebScript];
    userAgent =  [webView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
    if(acceptAnalytics == 1 || acceptAnalytics == 2){
        screenView("WebView");
    }else{
        NSLog(@"Analytics disabled ! won't upload.");
    }
    NSString *lastPlay = [[NSUserDefaults standardUserDefaults] objectForKey:@"LastPlay"];
    if([lastPlay length] > 1){
        webView.mainFrameURL = lastPlay;
        NSLog(@"Opening last play url %@",lastPlay);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LastPlay"];
    }
}

- (void)webView:(WebView *)sender
didStartProvisionalLoadForFrame:(WebFrame *)frame{
    [webView stringByEvaluatingJavaScriptFromString:WebScript];
    userAgent =  [webView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
}

- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
   
}

- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems{
    NSMenuItem *copy = [[NSMenuItem alloc] initWithTitle:@"复制页面地址" action:@selector(CopyLink) keyEquivalent:@""];
    [copy setTarget:self];
    [copy setEnabled:YES];
    NSMenuItem *play = [[NSMenuItem alloc] initWithTitle:@"强制显示播放界面" action:@selector(ShowPlayer) keyEquivalent:@""];
    [play setTarget:self];
    [play setEnabled:YES];
    NSMenuItem *contact = [[NSMenuItem alloc] initWithTitle:@"呼叫程序猿" action:@selector(Contact) keyEquivalent:@""];
    [contact setTarget:self];
    [contact setEnabled:YES];
    NSMutableArray *mutableArray = [[NSMutableArray alloc] init];
    [mutableArray addObjectsFromArray:defaultMenuItems];
    [mutableArray addObject:copy];
    [mutableArray addObject:play];
    [mutableArray addObject:contact];
    return mutableArray;
}

- (void)CopyLink{
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:webView.mainFrameURL  forType:NSStringPboardType];
}

- (void)ShowPlayer{
    [webView stringByEvaluatingJavaScriptFromString:WebScript];
    userAgent =  [webView stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
}

- (void)Contact{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"mailto:typcncom@gmail.com"]];
}

- (IBAction)openAv:(id)sender {
    NSString *avNumber = [sender stringValue];
    if([[sender stringValue] length] > 2 ){
        if ([[avNumber substringToIndex:2] isEqual: @"av"]) {
            avNumber = [avNumber substringFromIndex:2];
        }


        webView.mainFrameURL = [NSString stringWithFormat:@"http://www.bilibili.com/video/av%@",avNumber];
        [sender setStringValue:@""];
    }
}

- (void)AVNumberUpdated:(NSNotification *)notification {
    NSString *url = [notification object];
    if ([[url substringToIndex:6] isEqual: @"http//"]) { //somehow, 传入url的Colon会被移除 暂时没有找到相关的说明，这里统一去掉，在最后添加http://
        url = [url substringFromIndex:6];
    }
    webView.mainFrameURL = [NSString stringWithFormat:@"http://%@", url];
}

@end

@interface PlayerWindowController : NSWindowController

@end

@implementation PlayerWindowController{
    
}


@end