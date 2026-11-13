// Headless acceptance probe using the real Sparkle updater, never installs or launches MultiShift.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>

@interface DeltaProbe : NSObject <SPUUserDriver, SPUUpdaterDelegate>
@property(nonatomic, strong) SPUUpdater *updater;
@property(nonatomic, copy) NSString *feed;
@property(nonatomic, copy) NSString *expectedName;
@property(nonatomic, copy) NSString *report;
@property(nonatomic) uint64_t received;
@property(nonatomic) uint64_t expected;
@property(nonatomic) BOOL selectedDelta;
@property(nonatomic) BOOL downloadedDelta;
@end

@implementation DeltaProbe
- (void)fail:(NSString *)message {
    fprintf(stderr, "Delta probe failed: %s\n", message.UTF8String);
    exit(1);
}
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)updater { return NO; }
- (NSString *)feedURLStringForUpdater:(SPUUpdater *)updater { return self.feed; }
- (BOOL)updater:(SPUUpdater *)updater shouldDownloadReleaseNotesForUpdate:(SUAppcastItem *)item { return NO; }
- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item {
    if (!item.deltaUpdate || ![item.fileURL.lastPathComponent isEqual:self.expectedName])
        [self fail:@"Real Sparkle selector did not choose the expected delta"];
    fprintf(stderr, "Sparkle selected %s (%llu bytes)\n", item.fileURL.absoluteString.UTF8String, item.contentLength);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:item.fileURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || [(NSHTTPURLResponse *)response statusCode] != 200 || data.length != item.contentLength)
            [self fail:@"Selected delta download failed or returned the wrong size"];
        NSString *patch = [self.report stringByAppendingString:@".delta"];
        if (![data writeToFile:patch atomically:YES]) [self fail:@"Could not save downloaded patch"];
        NSDictionary *result = @{@"selected_delta": @YES, @"downloaded_bytes": @(data.length),
            @"expected_bytes": @(item.contentLength), @"archive": self.expectedName,
            @"download_transport": @"NSURLSession after Sparkle checkForUpdateInformation selection",
            @"installed": @NO};
        NSData *reportData = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
        if (![reportData writeToFile:self.report atomically:YES]) [self fail:@"Could not save report"];
        puts("Real Sparkle delta selection and selected-URL download PASS; installer never started");
        exit(0);
    }];
    [task resume];
}
- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request {
    self.selectedDelta = item.deltaUpdate && [request.URL.lastPathComponent isEqual:self.expectedName];
    if (!self.selectedDelta) [self fail:@"Sparkle selected the full archive or wrong delta"];
    fprintf(stderr, "Sparkle selected %s\n", request.URL.absoluteString.UTF8String);
}
- (void)updater:(SPUUpdater *)updater didDownloadUpdate:(SUAppcastItem *)item {
    self.downloadedDelta = item.deltaUpdate;
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    [self fail:@"Unexpected permission request"];
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation { fprintf(stderr, "Checking signed delta feed...\n"); }
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    fprintf(stderr, "Update found: %s\n", item.versionString.UTF8String);
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    [self fail:error.localizedDescription];
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    [self fail:error.description];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation { fprintf(stderr, "Download initiated\n"); }
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength { self.expected = expectedContentLength; }
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length { self.received += length; }
- (void)showDownloadDidStartExtractingUpdate { fprintf(stderr, "Extracting verified patch\n"); }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply {
    [self fail:@"Installer must not be started in read-only selection mode"];
}
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {
    [self fail:@"Installation must never be invoked by this probe"];
}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement {
    [self fail:@"Probe unexpectedly installed an update"];
}
- (void)dismissUpdateInstallation {}
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 5) { fprintf(stderr, "Usage: probe old.app feed-url delta-name report.json\n"); return 2; }
        NSBundle *host = [NSBundle bundleWithPath:@(argv[1])];
        if (!host) return 2;
        DeltaProbe *probe = [DeltaProbe new];
        probe.feed = @(argv[2]); probe.expectedName = @(argv[3]); probe.report = @(argv[4]);
        probe.updater = [[SPUUpdater alloc] initWithHostBundle:host applicationBundle:host userDriver:probe delegate:probe];
        NSError *error = nil;
        if (![probe.updater startUpdater:&error]) { fprintf(stderr, "%s\n", error.description.UTF8String); return 1; }
        [probe.updater checkForUpdateInformation];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 90 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [probe fail:@"Timed out"]; });
        [[NSRunLoop mainRunLoop] run];
    }
    return 1;
}
