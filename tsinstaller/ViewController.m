//
//  ViewController.m
//  tsinstaller
//
//  Created by Zheng on 12/20/15.
//  Copyright © 2015 Zheng. All rights reserved.
//

#import <spawn.h>
#import <stdio.h>
#import <sys/stat.h>
#import "ViewController.h"

#define currentVersion @"2.2.5"

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

@interface ViewController ()
@property (strong, nonatomic) NSMutableData *fileData;
@property (strong, nonatomic) NSFileHandle *writeHandle;
@property (nonatomic, assign) long long currentLength;
@property (nonatomic, assign) long long sumLength;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *grayActivityIndicator_1;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *grayActivityIndicator_2;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *grayActivityIndicator_3;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *grayActivityIndicator_4;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *grayActivityIndicator_5;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *grayActivityIndicator_6;
@property (weak, nonatomic) IBOutlet UILabel *activityLabel_1; // 检查安装环境
@property (weak, nonatomic) IBOutlet UILabel *activityLabel_2; // 检查所需依赖
@property (weak, nonatomic) IBOutlet UILabel *activityLabel_3; // 检查网络环境
@property (weak, nonatomic) IBOutlet UILabel *activityLabel_4; // 获取资源文件
@property (weak, nonatomic) IBOutlet UILabel *activityLabel_5; // 执行安装进程
@property (weak, nonatomic) IBOutlet UILabel *activityLabel_6; // 执行清理
@property (weak, nonatomic) IBOutlet UIButton *installButton;
@property (weak, nonatomic) IBOutlet UITextView *introLabel;
@property (weak, nonatomic) IBOutlet UILabel *tipsLabel;
@property (strong, nonatomic) NSString *verifyStr;
@property (strong, nonatomic) NSString *downloadUrl;
@property BOOL appInstalled;
@property BOOL shouldUseCydia;
@property BOOL downloading;
@property BOOL downloadResult;
@property BOOL installSucceed;

@end

@implementation ViewController

const char* sshpass = "/tmp/sshpass";
const char* password = "alpine";
const char* envp[] = {"PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME=/var/mobile", "USER=mobile", "LOGNAME=mobile", NULL};

- (instancetype)init {
    if (self = [super init]) {
        _appInstalled = NO;
        _shouldUseCydia = NO;
        _verifyStr = nil;
        _downloadUrl = nil;
        _downloadResult = NO;
        _downloading = NO;
        _installSucceed = NO;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    BOOL result = [self checkPrivileges];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:@"/Applications/TouchSprite.app/NewTouchSprite"]) {
        _appInstalled = YES;
        _installButton.enabled = YES;
        [_installButton setTitle:@"立即启动" forState:UIControlStateNormal];
        _tipsLabel.text = @"已检测到该设备上安装的触动精灵，轻按立即启动。";
    } else {
        if (!result) {
            _shouldUseCydia = YES;
        }
        _installButton.enabled = YES;
        [_installButton setTitle:@"一键安装" forState:UIControlStateNormal];
        _tipsLabel.text = [@"触动精灵安装器 v" stringByAppendingString:currentVersion];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)installButtonTapped:(id)sender {
    if (_installSucceed) {
        _installButton.enabled = NO;
        [_installButton setTitle:@"正在重启……" forState:UIControlStateDisabled];
        pid_t pid; int status = 0;
        const char* args[] = {"killall", "-9", "SpringBoard", "backboardd", NULL};
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char* const*)args, (char* const*)envp);
        waitpid(pid, &status, 0);
        return;
    } else if (_appInstalled) {
        if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"touchsprite://"]]) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"touchsprite://"]];
        }
        [self doCleaning];
    } else {
        _installButton.enabled = NO;
        [_installButton setTitle:@"安装中……" forState:UIControlStateNormal];
        [self stepAnimate:1];
        if (![self checkEnvironment]) {
            [self fatalError:1];
            return;
        }
        if (_shouldUseCydia) {
            [self stepAnimate:8];
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"cydia://url/file://%@/%@", [[NSBundle mainBundle] resourcePath], @"install.html"]]];
            return;
        }
        [self stepAnimate:2];
        if (![self checkDependencies]) {
            if (![self installDependencies]) {
                [self fatalError:2];
                return;
            }
        }
        [self stepAnimate:3];
        if (![self checkNetwork]) {
            _activityLabel_3.text = @"无法连接到服务器";
            _activityLabel_3.textColor = [UIColor grayColor];
        }
        [self stepAnimate:4];
        if (![self downloadResources]) {
            if (!_downloadUrl) {
                _activityLabel_4.text = @"无需获取更新资源";
            } else {
                _activityLabel_4.text = @"更新资源获取失败";
            }
            _activityLabel_4.textColor = [UIColor grayColor];
        }
        [self stepAnimate:5];
        if (![self doInstalling]) {
            [self fatalError:5];
            return;
        }
        [self stepAnimate:6];
        if (![self doCleaning]) {
            _activityLabel_6.text = @"清理执行失败";
            _activityLabel_6.textColor = [UIColor grayColor];
        }
        [self stepAnimate:7];
    }
}

- (void)stepAnimate:(int)step {
    [UIView setAnimationCurve:UIViewAnimationCurveEaseIn];
    if (step == 1) {
        [UIView animateWithDuration:1.0 animations:^{
            _introLabel.alpha = 0;
            _grayActivityIndicator_1.alpha =
            _activityLabel_1.alpha =
            _activityLabel_2.alpha =
            _activityLabel_3.alpha =
            _activityLabel_4.alpha =
            _activityLabel_5.alpha =
            _activityLabel_6.alpha =
            1;
            _installButton.enabled = NO;
        }];
    } else if (step == 2) {
        [UIView animateWithDuration:1.0 animations:^{
            _grayActivityIndicator_1.alpha = 0;
            _grayActivityIndicator_2.alpha = 1;
        }];
    } else if (step == 3) {
        [UIView animateWithDuration:1.0 animations:^{
            _grayActivityIndicator_2.alpha = 0;
            _grayActivityIndicator_3.alpha = 1;
        }];
    } else if (step == 4) {
        [UIView animateWithDuration:1.0 animations:^{
            _grayActivityIndicator_3.alpha = 0;
            _grayActivityIndicator_4.alpha = 1;
        }];
    } else if (step == 5) {
        [UIView animateWithDuration:1.0 animations:^{
            _grayActivityIndicator_4.alpha = 0;
            _grayActivityIndicator_5.alpha = 1;
        }];
    } else if (step == 6) {
        [UIView animateWithDuration:1.0 animations:^{
            _grayActivityIndicator_5.alpha = 0;
            _grayActivityIndicator_6.alpha = 1;
        }];
    } else if (step == 7) {
        [UIView animateWithDuration:3.0 animations:^{
            _grayActivityIndicator_6.alpha = 0;
        } completion:^(BOOL finished) {
            _appInstalled = YES;
            _installButton.enabled = YES;
            _installSucceed = YES;
            [_installButton setTitle:@"立即重启" forState:UIControlStateNormal];
            _tipsLabel.text = @"安装完成，需要重启设备，轻按立即重启。";
        }];
    } else if (step == 8) {
        [UIView animateWithDuration:1.0 animations:^{
            _grayActivityIndicator_1.alpha = 0;
        } completion:^(BOOL finished) {
            _installButton.enabled = YES;
            [_installButton setTitle:@"打开 Cydia" forState:UIControlStateNormal];
            _tipsLabel.text = @"请在 Cydia 中继续安装。";
        }];
    }
}

- (void)fatalError:(int)step {
    if (step == 1) {
        _activityLabel_1.textColor = [UIColor redColor];
    } else if (step == 2) {
        _activityLabel_2.textColor = [UIColor redColor];
    } else if (step == 3) {
        _activityLabel_3.textColor = [UIColor redColor];
    } else if (step == 4) {
        _activityLabel_4.textColor = [UIColor redColor];
    } else if (step == 5) {
        _activityLabel_5.textColor = [UIColor redColor];
    } else if (step == 6) {
        _activityLabel_6.textColor = [UIColor redColor];
    }
    [UIView animateWithDuration:1.0 animations:^{
        _grayActivityIndicator_1.alpha = 0;
        _grayActivityIndicator_2.alpha = 0;
        _grayActivityIndicator_3.alpha = 0;
        _grayActivityIndicator_4.alpha = 0;
        _grayActivityIndicator_5.alpha = 0;
        _grayActivityIndicator_6.alpha = 0;
    } completion:^(BOOL finished) {
        if (step != 1) {
            _shouldUseCydia = YES;
            _installButton.enabled = YES;
            [_installButton setTitle:@"打开 Cydia" forState:UIControlStateNormal];
            _tipsLabel.text = @"一键安装失败，请尝试在 Cydia 中继续安装。";
        } else {
            [_installButton setTitle:@"安装失败" forState:UIControlStateDisabled];
            _tipsLabel.text = @"安装失败，请检查安装环境。";
        }
    }];
}

- (BOOL)checkPrivileges {
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (!fileManager) {
        return NO;
    }
    if (![fileManager fileExistsAtPath:@"/tmp/sshpass"]) {
        [fileManager copyItemAtPath:[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"bin/sshpass"] toPath:@"/tmp/sshpass" error:&error];
        if (!error) {
            return NO;
        }
    }
    if (chmod("/tmp/sshpass", 0755)) {
        return NO;
    }
    pid_t pid; int status = 0;
    const char* args[] = {"sshpass", "-p", password, "/bin/su", "-c", "echo", NULL};
    posix_spawn(&pid, sshpass, NULL, NULL, (char* const*)args, (char* const*)envp);
    waitpid(pid, &status, 0);
    if (status == 0) {
        return YES;
    }
    return NO;
}

- (BOOL)checkEnvironment {
    if (SYSTEM_VERSION_LESS_THAN(@"7.0") || SYSTEM_VERSION_GREATER_THAN(@"9.0.2")) {
        _activityLabel_1.text = @"不支持的 iOS 版本";
        return NO;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/Applications/Cydia.app"]) {
        _activityLabel_1.text = @"请先越狱并安装 Cydia";
        return NO;
    }
    return YES;
}

- (BOOL)checkDependencies {
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/Library/MobileSubstrate/MobileSubstrate.dylib"]) {
        _activityLabel_2.text = @"未安装 Cydia Substrate";
        return NO;
    }
    return YES;
}

- (BOOL)installDependencies {
    __block BOOL running = YES;
    __block int status = 0;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        pid_t pid;
        NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Packages/Dependencies/*.deb"];
        const char* args[] = {"sshpass", "-p", password, "/bin/su", "-c", [[NSString stringWithFormat:@"dpkg -i %@", path] UTF8String], NULL};
        posix_spawn(&pid, sshpass, NULL, NULL, (char* const*)args, (char* const*)envp);
        waitpid(pid, &status, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            running = NO;
            if (status == 0) {
                _activityLabel_2.text = @"Cydia Substrate 安装成功";
            } else {
                _activityLabel_2.text = @"Cydia Substrate 安装失败";
            }
        });
    });
    while (running) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    if (status == 0) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)checkNetwork {
    __block BOOL running = YES;
    __block BOOL result = NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.touchsprite.net/ajax/web?type=home"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10.0f];
        [request setHTTPMethod:@"GET"];
        NSHTTPURLResponse *response = nil;
        NSError	*error = nil;
        NSData *data	 = [NSURLConnection sendSynchronousRequest:request
                                              returningResponse:&response
                                                          error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            running = NO;
            if ( !error && data ) {
                NSError	*error = nil;
                NSDictionary *retDict = [NSJSONSerialization JSONObjectWithData:data
                                                                        options:NSJSONReadingMutableContainers
                                                                          error:&error];
                if ( !error && retDict ) {
                    id errorCode = [retDict objectForKey:@"success"];
                    if (errorCode) {
                        if ([errorCode boolValue] == YES) {
                            id softVersions = [retDict objectForKey:@"softVersions"];
                            if (softVersions && [softVersions respondsToSelector:@selector(count)]) {
                                for (int i = 0; i < [softVersions count]; i++) {
                                    id softVersion = [softVersions objectAtIndex:i];
                                    if (softVersion && [[softVersion objectForKey:@"os"] isEqualToString:@"ios"]) {
                                        id version = [softVersion objectForKey:@"version"];
                                        if (version && [version isEqualToString:currentVersion]) {
                                            _downloadUrl = nil;
                                            _activityLabel_3.text = @"内置资源已经是最新版本";
                                        } else {
                                            _downloadUrl = [softVersion objectForKey:@"url"];
                                            _activityLabel_3.text = [NSString stringWithFormat:@"发现新版本：%@", version];
                                        }
                                        result = YES;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        });
    });
    while (running) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    return result;
}

- (BOOL)downloadResources {
    if (_downloadUrl != nil) {
        _downloading = YES;
        NSURL *url = [NSURL URLWithString:_downloadUrl];
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        [NSURLConnection connectionWithRequest:request delegate:self];
        while (_downloading) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    }
    return _downloadResult;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSError *error = nil;
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    NSString *cachePath = [caches stringByAppendingPathComponent:@"cache.deb"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:cachePath]) {
        [fileManager removeItemAtPath:cachePath error:&error];
    }
    [fileManager createFileAtPath:cachePath contents:nil attributes:nil];
    _writeHandle = [NSFileHandle fileHandleForWritingAtPath:cachePath];
    _sumLength = response.expectedContentLength;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    _currentLength += data.length;
    double progress = (double)_currentLength / _sumLength;
    _activityLabel_4.text = [NSString stringWithFormat:@"获取资源文件……%.2f%%", progress * 100];
    [_writeHandle seekToEndOfFile];
    [_writeHandle writeData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [_writeHandle closeFile];
    _writeHandle = nil;
    _currentLength = 0;
    _sumLength = 0;
    _downloadResult = YES;
    _downloading = NO;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    _downloadResult = NO;
    _downloading = NO;
}

- (BOOL)doInstalling {
    __block int status = 0;
    __block BOOL running = YES;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        _activityLabel_5.text = @"正在安装触动精灵";
        NSString *cachePath = nil;
        if (_downloadUrl != nil && _downloadResult) {
            cachePath = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"cache.deb"];
        } else {
            cachePath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Packages/*.deb"];
        }
        NSString *command = [NSString stringWithFormat:@"dpkg -i %@", cachePath];
        pid_t pid;
        const char* args[] = {"sshpass", "-p", password, "/bin/su", "-c", [command UTF8String], NULL};
        posix_spawn(&pid, sshpass, NULL, NULL, (char* const*)args, (char* const*)envp);
        waitpid(pid, &status, 0);
        dispatch_async(dispatch_get_main_queue(), ^{
            running = NO;
            if (status == 0) {
                _activityLabel_5.text = @"触动精灵安装成功";
            } else {
                _activityLabel_5.text = @"触动精灵安装失败";
            }
        });
    });
    while (running) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
    }
    if (status == 0) {
        return YES;
    } else {
        return NO;
    }
}

- (BOOL)doCleaning {
    pid_t pid; int status = 0;
    const char* args[] = {"uicache", NULL};
    posix_spawn(&pid, "/usr/bin/uicache", NULL, NULL, (char* const*)args, (char* const*)envp);
    waitpid(pid, &status, 0);
//    const char* args[] = {"sshpass", "-p", password, "/bin/su", "-c", "rm /tmp/sshpass", NULL};
//    posix_spawn(&pid, sshpass, NULL, NULL, (char* const*)args, (char* const*)envp);
//    waitpid(pid, &status, 0);
    _activityLabel_6.text = @"图标缓存重建成功";
    return YES;
}

@end
