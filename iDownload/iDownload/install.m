//
//  install.m
//  iDownload
//
//  Created by Linus Henze on 09.02.20.
//  Copyright © 2020 Linus Henze. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CFNetwork/CFNetwork.h>
#import <dispatch/dispatch.h>
#import <notify.h>

#import "install.h"

bool deviceLocked = true;
bool installStarted = false;

void (^deviceUnlockHandler)(void) = NULL;

@interface FBSSystemService
+ (instancetype) sharedService;
- (void)openApplication: (NSString *) id options: (NSDictionary*) suspended withResult: (id) res;
@end

void update_springboard_plist() {
    NSDictionary *springBoardPlist = [NSMutableDictionary dictionaryWithContentsOfFile: @"/var/mobile/Library/Preferences/com.apple.springboard.plist"];
    [springBoardPlist setValue: @YES forKey: @"SBShowNonDefaultSystemApps"];
    [springBoardPlist writeToFile: @"/var/mobile/Library/Preferences/com.apple.springboard.plist" atomically: YES];
    
    NSDictionary* attr = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithShort:0755], NSFilePosixPermissions, @"mobile", NSFileOwnerAccountName, NULL];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] setAttributes: attr ofItemAtPath: @"/var/mobile/Library/Preferences/com.apple.springboard.plist" error: &error];
}

CFOptionFlags showMessage(CFDictionaryRef dict) {
    while (true) {
        while (deviceLocked) {
            sleep(1);
        }
        
        SInt32 err = 0;
        CFUserNotificationRef notif = CFUserNotificationCreate(NULL, 0, kCFUserNotificationPlainAlertLevel, &err, dict);
        if (notif == NULL || err != 0) {
            sleep(1);
            continue;
        }
        
        CFOptionFlags response = 0;
        CFUserNotificationReceiveResponse(notif, 0, &response);
        
        sleep(1);
        
        if ((response & 0x3) != kCFUserNotificationCancelResponse) {
            return response & 0x3;
        }
    }
}

void showSimpleMessage(NSString *title, NSString *message) {
    CFDictionaryRef dict = (__bridge CFDictionaryRef) @{
        (__bridge NSString*) kCFUserNotificationAlertTopMostKey: @1,
        (__bridge NSString*) kCFUserNotificationAlertHeaderKey: title,
        (__bridge NSString*) kCFUserNotificationAlertMessageKey: message
    };
    
    showMessage(dict);
}

__strong NSData *downloadData(NSString *url, NSError **error) {
    NSLog(@"Downloading file at %@", url);
    
    NSURL *nsurl = [NSURL URLWithString: url];
    if (!nsurl) {
        *error = [NSError errorWithDomain: @"URLError" code: 1 userInfo: nil];
        return nil;
    }
    
    __block __strong NSData *download = nil;
    while (!download) {
        *error = nil;
        
        dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
        
        NSURLSession *session = [NSURLSession sharedSession];
        NSInteger __block status = 0;
        
        [[session dataTaskWithURL: nsurl completionHandler: ^(NSData *data, NSURLResponse *response, NSError *e) {
            if ([response isKindOfClass: [NSHTTPURLResponse class]] && [(NSHTTPURLResponse*) response statusCode] == 200 && !e) {
                download = [[NSData alloc] initWithBytes: [data bytes] length: [data length]];
            } else {
                download = NULL;
                *error = e;
            }
          
            status = [response isKindOfClass: [NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*) response statusCode] : 0;
            
            dispatch_semaphore_signal(semaphore);
        }] resume];

        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        
        if (!download && !*error) {
            // Connected to the internet but no file
            // Fatal
            *error = [NSError errorWithDomain: @"HTTP Error" code: status userInfo: nil];
            return nil;
        }
    }
    
    return [[NSData alloc] initWithBytes: [download bytes] length: [download length]];
}

NSString *download(NSString *url, NSString *dir, NSError **error) {
    *error = nil;
    
    NSURL *nsurl = [NSURL URLWithString: url];
    if (!nsurl) {
        *error = [NSError errorWithDomain: @"URLError" code: 1 userInfo: nil];
        return nil;
    }
    
    if ([dir characterAtIndex: ([dir length] - 1)] != '/') {
        dir = [dir stringByAppendingString: @"/"];
    }
    
    NSString *filename = [dir stringByAppendingString: [nsurl lastPathComponent]];
    
    NSData *download = downloadData(url, error);
    if (*error) {
        return nil;
    }
    
    NSLog(@"Will write to file %@", filename);
    
    FILE *f = fopen([filename UTF8String], "w+");
    if (!f) {
        NSLog(@"Failed to open %@", filename);
        *error = [NSError errorWithDomain: @"FileWriteError" code: 1 userInfo: nil];
        return nil;
    }
    
    size_t written = fwrite([download bytes], 1, [download length], f);
    fclose(f);
    
    if (written != [download length]) {
        NSLog(@"Failed to write to %@", filename);
        unlink([filename UTF8String]);
        *error = [NSError errorWithDomain: @"FileWriteError" code: 1 userInfo: nil];
        return nil;
    }
    
    NSLog(@"Wrote to %@", filename);
    
    return filename;
}

int runCmd(NSString *file, NSArray *args) {
    const char **cargs = malloc(([args count] + 2) * sizeof(char*));
    
    cargs[0] = [file UTF8String];
    cargs[[args count] + 1] = NULL;
    
    for (NSUInteger i = 0; i < [args count]; i++) {
        cargs[i+1] = [(NSString*)[args objectAtIndex: i] UTF8String];
    }
    
    NSLog(@"About to run %@", file);
    for (NSUInteger i = 0; i < ([args count] + 2); i++) {
        NSLog(@"Arg[%lu]: %s", i, cargs[i]);
    }
    
    pid_t pid = fork();
    if (!pid) {
        // Child
        int fd_r = open("/dev/null", O_RDONLY);
        dup2(fd_r, STDIN_FILENO);
        
        int fd_w = open("/fugu_install.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
        dup2(fd_w, STDOUT_FILENO);
        dup2(fd_w, STDERR_FILENO);
        
        execv(cargs[0], (char * const *) cargs);
        exit(-1);
    }
    
    free(cargs);
    
    // Parent
    int status;
    waitpid(pid, &status, 0);
    
    status = WEXITSTATUS(status);
    
    NSLog(@"Exit status: %d", status);
    
    return status;
}

void startInstall(NSDictionary *installData) {
    // installData looks like bootstrap.plist
    // but it doesn't have a version and it has local
    // paths instead of URLs
    
    // Step 1: Decompress bootstrap.tar.gz
    NSString *bootstrap = [installData valueForKey: @"bootstrap"];
    NSString *decomp = [bootstrap stringByReplacingOccurrencesOfString: @".tar.gz" withString: @".tar"];
    NSString *gzip = [installData valueForKey: @"gzip"];
    
    unlink([decomp UTF8String]); // In case it exists from a previous attempt
    
    int status = runCmd(gzip, @[@"-d", bootstrap]);
    if (status != 0) {
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the bootstrap.tar.gz couldn't be decompressed (Error code %d). To retry, reboot and launch Fugu again.", status]);
        return;
    }
    
    sync();
    
    // Step 2: Extract bootstrap.tar
    NSString *tar = [installData valueForKey: @"tar"];
    chdir("/");
    status = runCmd(tar, @[@"--preserve-permissions", @"--no-overwrite-dir", @"-xf", decomp]);
    if (status != 0) {
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the bootstrap.tar couldn't be extracted (Error code %d). To retry, reboot and launch Fugu again.", status]);
        return;
    }
    
    // Step 3: Enable SBShowNonDefaultSystemApps
    update_springboard_plist();
    
    // Step 4: Launch install script
    NSString *installScript = [installData valueForKey: @"installScript"];
    status = runCmd(@"/bin/bash", @[installScript, @"noRespring"]);
    if (status != 0) {
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the install script exited with error code %d. To retry, reboot and launch Fugu again.", status]);
        return;
    }
    
    // Step 5: Tell the user that we're about to respring
    bool respringNow = false;
    while (!respringNow) {
        CFDictionaryRef respringNotif = (__bridge CFDictionaryRef) @{
            (__bridge NSString*) kCFUserNotificationAlertTopMostKey: @1,
            (__bridge NSString*) kCFUserNotificationAlertHeaderKey: @"Fugu\nRespring required!",
            (__bridge NSString*) kCFUserNotificationAlertMessageKey: @"To finish the installation, a respring is required. Continue?",
            (__bridge NSString*) kCFUserNotificationDefaultButtonTitleKey: @"Respring now!",
            (__bridge NSString*) kCFUserNotificationAlternateButtonTitleKey: @"Remind me in a minute"
        };
        
        CFOptionFlags flags = showMessage(respringNotif);
        if (flags == kCFUserNotificationDefaultResponse) {
            respringNow = true;
        } else {
            sleep(60);
        }
    }
    
    // Step 6: Tell the install script to finish and respring
    status = runCmd(@"/bin/bash", @[installScript, @"respringNow"]);
    if (status != 0) {
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the install script exited with error code %d. To retry, reboot and launch Fugu again.", status]);
        return;
    }
    
    deviceLocked = true; // We are respringing
    
    // Step 7: Tell user we succeeded
    CFDictionaryRef respringNotif = (__bridge CFDictionaryRef) @{
        (__bridge NSString*) kCFUserNotificationAlertTopMostKey: @1,
        (__bridge NSString*) kCFUserNotificationAlertHeaderKey: @"Fugu\nInstallation succeded!",
        (__bridge NSString*) kCFUserNotificationAlertMessageKey: @"The installation has been completed successfully! Enjoy your jailbroken device ;)",
        (__bridge NSString*) kCFUserNotificationDefaultButtonTitleKey: @"OK",
        (__bridge NSString*) kCFUserNotificationAlternateButtonTitleKey: @"Open Sileo"
    };
    
    // Step 8: Launch Sileo if requested
    CFOptionFlags flags = showMessage(respringNotif);
    if (flags == kCFUserNotificationAlternateResponse) {
        Class FBSSystemService = NSClassFromString(@"FBSSystemService");
        [[FBSSystemService sharedService] openApplication: @"org.coolstar.SileoStore" options: @{@"__ActivateSuspended": @0} withResult: nil];
    }
    
    // We're done!
}

#define PLIST_GET_VALUE(valueName, value, className, classDesc) className *value = [plist valueForKey: valueName]; if (!value || ![value isKindOfClass: [className class]]) { \
    showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the bootstrap.plist is invalid (%@ %@). To retry, reboot and launch Fugu again.", valueName, value ? [@"is not " stringByAppendingString: classDesc] : @"is missing"]); \
    return; \
}

#define CHECK_DOWNLOADED(var, url) if (!var) { \
    if ([[error domain] isEqualToString: @"URLError"]) { \
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the bootstrap.plist is invalid (URL %@ is invalid). To retry, reboot and launch Fugu again.", url]); \
        return; \
    } else if ([[error domain] isEqualToString: @"FileWriteError"]) { \
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because a required file couldn't be written (URL: %@). To retry, reboot and launch Fugu again.", url]); \
        return; \
    } else { \
        NSString *loc = [error localizedDescription]; \
        showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because of the following error: %@. To retry, reboot and launch Fugu again.", loc ? loc : [error description]]); \
        return; \
    } \
}

#define SET_FILE_PERM(file, perm) \
[[NSFileManager defaultManager] setAttributes: @{ NSFilePosixPermissions: @perm } ofItemAtPath: file error:&error];\
if (error) { \
    NSString *loc = [error localizedDescription]; \
showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the file permissions couldn't be set (File: %@ -- Error: %@). To retry, reboot and launch Fugu again.", file, loc ? loc : [error description]]); \
    return; \
}

void startDownload() {
    // Download bootstrap.plist
    NSError *error;
    NSData *bstrapData = downloadData(@"https://repo.fugujb.dev/bootstrap/bootstrap.plist", &error);
    if (error) {
        // Cannot be an URL error
        // Connected to the internet but no file
        // Fatal
        showSimpleMessage(@"Fugu\nInstallation failed!", @"The installation failed because the bootstrap.plist couldn't be downloaded. To retry, reboot and launch Fugu again.");
        return;
    }
    
    NSPropertyListFormat format;
    NSDictionary* plist = [NSPropertyListSerialization propertyListWithData: bstrapData options: NSPropertyListImmutable format: &format error: &error];
    if (!plist) {
        // Invalid format?
        showSimpleMessage(@"Fugu\nInstallation failed!", @"The installation failed because the bootstrap.plist is invalid. To retry, reboot and launch Fugu again.");
        return;
    }
    
    // Now check format
    PLIST_GET_VALUE(@"version", version, NSNumber, @"a number")
    
    if ([version unsignedIntValue] != PLIST_VERSION) {
        showSimpleMessage(@"Fugu\nUpdate required!", @"The installation failed because your version of Fugu is too old. Please update Fugu and try again.");
        return;
    }
    
    // Get tar, gzip, bootstrap, installScript, debs
    PLIST_GET_VALUE(@"tar", tar, NSString, @"a string")
    PLIST_GET_VALUE(@"gzip", gzip, NSString, @"a string")
    PLIST_GET_VALUE(@"bootstrap", bootstrap, NSString, @"a string")
    PLIST_GET_VALUE(@"installScript", installScript, NSString, @"a string")
    PLIST_GET_VALUE(@"debs", debs, NSArray, @"an array")
    
    for (NSUInteger i = 0; i < [debs count]; i++) {
        NSString *value = [debs objectAtIndex: i];
        if (![value isKindOfClass: [NSString class]]) {
            showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the bootstrap.plist is invalid (debs[%lu] is not a string). To retry, reboot and launch Fugu again.", i]);
            return;
        }
    }
    
    // Download files
    NSMutableDictionary *installDict = [[NSMutableDictionary alloc] init];
    
    NSString *tarFile = download(tar, @"/bin", &error);
    CHECK_DOWNLOADED(tarFile, tar)
    SET_FILE_PERM(tarFile, 0755)
    [installDict setValue: tarFile forKey: @"tar"];
    
    NSString *gzipFile = download(gzip, @"/usr/bin", &error);
    CHECK_DOWNLOADED(gzipFile, gzip)
    SET_FILE_PERM(gzipFile, 0755)
    [installDict setValue: gzipFile forKey: @"gzip"];
    
    NSString *bootstrapFile = download(bootstrap, @"/", &error);
    CHECK_DOWNLOADED(bootstrapFile, bootstrap)
    [installDict setValue: bootstrapFile forKey: @"bootstrap"];
    
    NSString *installScriptFile = download(installScript, @"/", &error);
    CHECK_DOWNLOADED(installScriptFile, installScript)
    SET_FILE_PERM(installScriptFile, 0755)
    [installDict setValue: installScriptFile forKey: @"installScript"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath: @"/debs" isDirectory: nil]) {
        BOOL debsCreated = [[NSFileManager defaultManager] createDirectoryAtPath: @"/debs" withIntermediateDirectories: NO attributes: @{} error: &error];
        if (!debsCreated) {
            NSString *loc = [error localizedDescription];
            showSimpleMessage(@"Fugu\nInstallation failed!", [NSString stringWithFormat: @"The installation failed because the /debs directory couldn't be created (error: %@). To retry, reboot and launch Fugu again.", loc ? loc : [error description]]);
            return;
        }
    }
    
    NSMutableArray *debFiles = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < [debs count]; i++) {
        // Guaranteed to be a string
        NSString *url = [debs objectAtIndex: i];
        NSString *dwnldLoc = download(url, @"/debs", &error);
        CHECK_DOWNLOADED(dwnldLoc, url)
        
        [debFiles addObject: dwnldLoc];
    }
    
    [installDict setValue: debFiles forKey: @"debs"];
    
    // Downloaded everything, install now!
    CFDictionaryRef installNotif = (__bridge CFDictionaryRef) @{
        (__bridge NSString*) kCFUserNotificationAlertTopMostKey: @1,
        (__bridge NSString*) kCFUserNotificationAlertHeaderKey: @"Fugu\nDownload completed!",
        (__bridge NSString*) kCFUserNotificationAlertMessageKey: @"All required files have been downloaded and are ready to be installed.",
        (__bridge NSString*) kCFUserNotificationDefaultButtonTitleKey: @"Install now!"
    };
    
    showMessage(installNotif);
    
    startInstall(installDict);
}

void handleLockNotification(int stateToken, int token) {
    // Is this an unlock notification?
    uint64_t state;
    notify_get_state(stateToken, &state);
    if (state == 0) {
        deviceLocked = false;
        
        if (!installStarted) {
            // Start install now!
            dispatch_async(dispatch_queue_create("Download", NULL), ^{
                installStarted = true;
                
                showSimpleMessage(@"Welcome to Fugu!", @"We will now download and install Sileo, Substitute and other components. Depending on your internet connection, this may take a few minutes. You will get another message once the download has been completed.");
                
                startDownload();
            });
        } else {
            if (deviceUnlockHandler) {
                deviceUnlockHandler();
                deviceUnlockHandler = NULL;
            }
        }
    } else {
        deviceLocked = true;
    }
}

void requestInstall() {
    int notify_token;
    notify_register_dispatch("com.apple.springboard.lockstate", &notify_token, dispatch_queue_create("LockstateNotify", NULL), ^(int stateToken) {
        handleLockNotification(stateToken, notify_token);
    });
}
