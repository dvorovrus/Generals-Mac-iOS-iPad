#include "IOSModManager.h"

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <CommonCrypto/CommonDigest.h>

#include <array>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace
{
NSString * const GXHubErrorDomain = @"GeneralsXHub";

NSError *GXHubError(NSInteger code, NSString *message)
{
    return [NSError errorWithDomain:GXHubErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown Generals Hub error"}];
}

BOOL GXHubSafeId(NSString *value)
{
    if (value.length == 0 || value.length > 63)
        return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"];
    return [value rangeOfCharacterFromSet:[allowed invertedSet]].location == NSNotFound;
}

BOOL GXHubSafeRelativePath(NSString *relative)
{
    if (relative.length == 0 || [relative hasPrefix:@"/"] || [relative hasPrefix:@"\\"])
        return NO;
    NSArray<NSString *> *parts = [relative pathComponents];
    for (NSString *part in parts)
    {
        if ([part isEqualToString:@".."] || [part isEqualToString:@"."])
            return NO;
    }
    return YES;
}

NSData *GXHubReadExact(NSFileHandle *handle, NSUInteger count, NSError **error)
{
    NSMutableData *data = [NSMutableData dataWithCapacity:count];
    while (data.length < count)
    {
        @try
        {
            NSData *chunk = [handle readDataOfLength:count - data.length];
            if (chunk.length == 0)
                break;
            [data appendData:chunk];
        }
        @catch (NSException *exception)
        {
            if (error != nullptr)
                *error = GXHubError(20, [NSString stringWithFormat:@"Package read failed: %@", exception.reason]);
            return nil;
        }
    }
    if (data.length != count)
    {
        if (error != nullptr)
            *error = GXHubError(21, @"Unexpected end of .gxmod package.");
        return nil;
    }
    return data;
}

unsigned long long GXHubParseOctal(const unsigned char *bytes, size_t length)
{
    char buffer[32] = {};
    size_t out = 0;
    for (size_t i = 0; i < length && out + 1 < sizeof(buffer); ++i)
    {
        unsigned char c = bytes[i];
        if (c == '\0' || c == ' ')
        {
            if (out == 0)
                continue;
            break;
        }
        if (c < '0' || c > '7')
            break;
        buffer[out++] = (char)c;
    }
    return out == 0 ? 0 : strtoull(buffer, nullptr, 8);
}

NSString *GXHubTarString(const unsigned char *bytes, size_t length)
{
    size_t actual = 0;
    while (actual < length && bytes[actual] != '\0')
        ++actual;
    if (actual == 0)
        return @"";
    return [[NSString alloc] initWithBytes:bytes length:actual encoding:NSUTF8StringEncoding] ?: @"";
}

BOOL GXHubHeaderIsZero(const unsigned char *bytes)
{
    for (size_t i = 0; i < 512; ++i)
    {
        if (bytes[i] != 0)
            return NO;
    }
    return YES;
}

NSString *GXHubSHA256ForFile(NSURL *url, NSError **error)
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (handle == nil)
        return nil;

    CC_SHA256_CTX ctx;
    CC_SHA256_Init(&ctx);
    @try
    {
        while (true)
        {
            @autoreleasepool
            {
                NSData *data = [handle readDataOfLength:1024 * 1024];
                if (data.length == 0)
                    break;
                CC_SHA256_Update(&ctx, data.bytes, (CC_LONG)data.length);
            }
        }
    }
    @catch (NSException *exception)
    {
        [handle closeFile];
        if (error != nullptr)
            *error = GXHubError(22, [NSString stringWithFormat:@"SHA-256 read failed: %@", exception.reason]);
        return nil;
    }
    [handle closeFile];

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &ctx);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i)
        [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

NSDictionary<NSString *, id> *GXHubParseManifest(NSData *data, NSError **error)
{
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:[NSDictionary class]])
    {
        if (error != nullptr && *error == nil)
            *error = GXHubError(30, @"manifest.json is not an object.");
        return nil;
    }

    NSDictionary *manifest = (NSDictionary *)json;
    NSNumber *schema = manifest[@"schemaVersion"];
    NSString *profileId = manifest[@"profileId"];
    NSString *name = manifest[@"name"];
    NSString *version = manifest[@"version"];
    if (schema.integerValue != 1 || !GXHubSafeId(profileId) || name.length == 0 || version.length == 0)
    {
        if (error != nullptr)
            *error = GXHubError(31, @"Invalid .gxmod manifest (schemaVersion/profileId/name/version).");
        return nil;
    }
    return manifest;
}

BOOL GXHubCopyTarFile(
    NSFileHandle *input,
    unsigned long long size,
    NSString *destination,
    NSError **error)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *parent = [destination stringByDeletingLastPathComponent];
    if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:error])
        return NO;
    if (![fm createFileAtPath:destination contents:nil attributes:nil])
    {
        if (error != nullptr)
            *error = GXHubError(40, [NSString stringWithFormat:@"Cannot create %@", destination.lastPathComponent]);
        return NO;
    }

    NSFileHandle *output = [NSFileHandle fileHandleForWritingAtPath:destination];
    if (output == nil)
    {
        if (error != nullptr)
            *error = GXHubError(41, @"Cannot open extracted file for writing.");
        return NO;
    }

    unsigned long long remaining = size;
    @try
    {
        while (remaining > 0)
        {
            @autoreleasepool
            {
                NSUInteger request = (NSUInteger)MIN(remaining, (unsigned long long)(1024 * 1024));
                NSData *chunk = [input readDataOfLength:request];
                if (chunk.length != request)
                {
                    [output closeFile];
                    if (error != nullptr)
                        *error = GXHubError(42, @"Unexpected end while extracting .gxmod.");
                    return NO;
                }
                [output writeData:chunk];
                remaining -= chunk.length;
            }
        }
    }
    @catch (NSException *exception)
    {
        [output closeFile];
        if (error != nullptr)
            *error = GXHubError(43, [NSString stringWithFormat:@"Extraction failed: %@", exception.reason]);
        return NO;
    }

    [output closeFile];
    return YES;
}

BOOL GXHubSkipBytes(NSFileHandle *handle, unsigned long long count, NSError **error)
{
    @try
    {
        unsigned long long offset = handle.offsetInFile;
        [handle seekToFileOffset:offset + count];
        return YES;
    }
    @catch (NSException *exception)
    {
        if (error != nullptr)
            *error = GXHubError(44, [NSString stringWithFormat:@"Package seek failed: %@", exception.reason]);
        return NO;
    }
}

BOOL GXHubInstallTar(NSURL *packageURL, NSDictionary **installedManifest, NSError **error)
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:packageURL error:error];
    if (handle == nil)
        return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *modsRoot = GXHubModsRootPath();
    if (![fm createDirectoryAtPath:modsRoot withIntermediateDirectories:YES attributes:nil error:error])
    {
        [handle closeFile];
        return NO;
    }

    NSString *stage = [modsRoot stringByAppendingPathComponent:
        [@".staging-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    if (![fm createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:error])
    {
        [handle closeFile];
        return NO;
    }

    NSDictionary *manifest = nil;
    NSUInteger extractedFiles = 0;
    BOOL ok = YES;

    while (ok)
    {
        NSError *readError = nil;
        NSData *header = GXHubReadExact(handle, 512, &readError);
        if (header == nil)
        {
            if (error != nullptr)
                *error = readError;
            ok = NO;
            break;
        }

        const unsigned char *bytes = (const unsigned char *)header.bytes;
        if (GXHubHeaderIsZero(bytes))
            break;

        NSString *name = GXHubTarString(bytes, 100);
        NSString *prefix = GXHubTarString(bytes + 345, 155);
        if (prefix.length > 0)
            name = [prefix stringByAppendingFormat:@"/%@", name];

        unsigned long long size = GXHubParseOctal(bytes + 124, 12);
        unsigned char type = bytes[156];
        BOOL regular = type == '\0' || type == '0';
        BOOL directory = type == '5';

        if (!GXHubSafeRelativePath(name))
        {
            if (error != nullptr)
                *error = GXHubError(45, [NSString stringWithFormat:@"Unsafe package path: %@", name]);
            ok = NO;
            break;
        }

        if ([name isEqualToString:@"manifest.json"])
        {
            if (!regular || size == 0 || size > 1024 * 1024)
            {
                if (error != nullptr)
                    *error = GXHubError(46, @"Invalid manifest.json entry.");
                ok = NO;
                break;
            }
            NSData *manifestData = GXHubReadExact(handle, (NSUInteger)size, error);
            if (manifestData == nil)
            {
                ok = NO;
                break;
            }
            manifest = GXHubParseManifest(manifestData, error);
            if (manifest == nil)
            {
                ok = NO;
                break;
            }
        }
        else if ([name hasPrefix:@"profile/"])
        {
            if (manifest == nil)
            {
                if (error != nullptr)
                    *error = GXHubError(47, @"manifest.json must be the first .gxmod entry.");
                ok = NO;
                break;
            }

            NSString *relative = [name substringFromIndex:[@"profile/" length]];
            if (!GXHubSafeRelativePath(relative))
            {
                if (error != nullptr)
                    *error = GXHubError(48, @"Unsafe profile path in package.");
                ok = NO;
                break;
            }

            NSString *destination = [[stage stringByAppendingPathComponent:@"profile"]
                stringByAppendingPathComponent:relative];
            if (directory)
            {
                if (![fm createDirectoryAtPath:destination
                    withIntermediateDirectories:YES attributes:nil error:error])
                {
                    ok = NO;
                    break;
                }
            }
            else if (regular)
            {
                if (!GXHubCopyTarFile(handle, size, destination, error))
                {
                    ok = NO;
                    break;
                }
                ++extractedFiles;
            }
            else
            {
                if (error != nullptr)
                    *error = GXHubError(49, @"Unsupported entry type in .gxmod package.");
                ok = NO;
                break;
            }
        }
        else if (regular)
        {
            if (!GXHubSkipBytes(handle, size, error))
            {
                ok = NO;
                break;
            }
        }
        else if (!directory)
        {
            if (error != nullptr)
                *error = GXHubError(50, @"Unsupported top-level .gxmod entry.");
            ok = NO;
            break;
        }

        unsigned long long padding = (512 - (size % 512)) % 512;
        if (padding > 0 && !GXHubSkipBytes(handle, padding, error))
        {
            ok = NO;
            break;
        }
    }

    [handle closeFile];

    if (ok && manifest == nil)
    {
        if (error != nullptr)
            *error = GXHubError(51, @".gxmod package has no manifest.json.");
        ok = NO;
    }
    if (ok && extractedFiles == 0)
    {
        if (error != nullptr)
            *error = GXHubError(52, @".gxmod package contains no profile files.");
        ok = NO;
    }

    NSNumber *expectedFiles = manifest[@"profileFiles"];
    if (ok && expectedFiles != nil && expectedFiles.unsignedIntegerValue != extractedFiles)
    {
        if (error != nullptr)
            *error = GXHubError(
                53,
                [NSString stringWithFormat:@"Profile file count mismatch: expected %@, extracted %lu.",
                    expectedFiles, (unsigned long)extractedFiles]);
        ok = NO;
    }

    if (!ok)
    {
        [fm removeItemAtPath:stage error:nil];
        return NO;
    }

    NSString *profileId = manifest[@"profileId"];
    NSData *installedData = [NSJSONSerialization dataWithJSONObject:manifest
                                                            options:NSJSONWritingPrettyPrinted
                                                             error:error];
    if (installedData == nil)
    {
        [fm removeItemAtPath:stage error:nil];
        return NO;
    }
    if (![installedData writeToFile:[stage stringByAppendingPathComponent:@"installed.json"]
                            options:NSDataWritingAtomic
                              error:error])
    {
        [fm removeItemAtPath:stage error:nil];
        return NO;
    }

    NSString *finalPath = [modsRoot stringByAppendingPathComponent:profileId];
    NSString *backupPath = [modsRoot stringByAppendingPathComponent:
        [@".backup-" stringByAppendingString:[NSUUID UUID].UUIDString]];

    if ([fm fileExistsAtPath:finalPath])
    {
        if (![fm moveItemAtPath:finalPath toPath:backupPath error:error])
        {
            [fm removeItemAtPath:stage error:nil];
            return NO;
        }
    }

    if (![fm moveItemAtPath:stage toPath:finalPath error:error])
    {
        if ([fm fileExistsAtPath:backupPath])
            [fm moveItemAtPath:backupPath toPath:finalPath error:nil];
        [fm removeItemAtPath:stage error:nil];
        return NO;
    }

    [fm removeItemAtPath:backupPath error:nil];

    fprintf(stderr,
            "[HUB] installed profile='%s' version='%s' files=%lu path='%s'\n",
            [profileId UTF8String],
            [manifest[@"version"] UTF8String],
            (unsigned long)extractedFiles,
            [finalPath fileSystemRepresentation]);

    if (installedManifest != nullptr)
        *installedManifest = manifest;
    return YES;
}
} // namespace

NSString *GXHubModsRootPath(void)
{
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Mods"];
}

NSString *GXHubInstalledProfilePath(NSString *profileId)
{
    if (!GXHubSafeId(profileId))
        return @"";
    return [[[GXHubModsRootPath() stringByAppendingPathComponent:profileId]
        stringByAppendingPathComponent:@"profile"] stringByStandardizingPath];
}

BOOL GXHubProfileInstalled(NSString *profileId)
{
    NSString *path = GXHubInstalledProfilePath(profileId);
    if (path.length == 0)
        return NO;
    BOOL isDirectory = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory;
}

NSDictionary<NSString *, id> *GXHubInstalledManifest(NSString *profileId)
{
    if (!GXHubSafeId(profileId))
        return nil;
    NSString *path = [[GXHubModsRootPath() stringByAppendingPathComponent:profileId]
        stringByAppendingPathComponent:@"installed.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil)
        return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

NSArray<NSDictionary<NSString *, id> *> *GXHubCatalogEntries(void)
{
    NSString *documentsCatalog = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Documents/HubCatalog.json"];
    NSString *bundleCatalog = [[[NSBundle mainBundle] resourcePath]
        stringByAppendingPathComponent:@"HubCatalog.json"];
    NSString *path = [[NSFileManager defaultManager] fileExistsAtPath:documentsCatalog]
        ? documentsCatalog
        : bundleCatalog;

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil)
        return @[];

    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *entries = nil;
    if ([json isKindOfClass:[NSArray class]])
        entries = json;
    else if ([json isKindOfClass:[NSDictionary class]])
        entries = ((NSDictionary *)json)[@"mods"];

    if (![entries isKindOfClass:[NSArray class]])
        return @[];

    NSMutableArray *valid = [NSMutableArray array];
    for (id raw in entries)
    {
        if (![raw isKindOfClass:[NSDictionary class]])
            continue;
        NSDictionary *entry = raw;
        if (GXHubSafeId(entry[@"profileId"]) &&
            [entry[@"name"] isKindOfClass:[NSString class]] &&
            [entry[@"version"] isKindOfClass:[NSString class]])
        {
            [valid addObject:entry];
        }
    }
    return valid;
}

NSArray<NSDictionary<NSString *, id> *> *GXHubInstalledModEntries(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:GXHubModsRootPath() error:nil] ?: @[];
    NSMutableArray *entries = [NSMutableArray array];
    for (NSString *child in children)
    {
        if ([child hasPrefix:@"."] || !GXHubSafeId(child))
            continue;
        NSDictionary *manifest = GXHubInstalledManifest(child);
        if (manifest != nil && GXHubProfileInstalled(child))
            [entries addObject:manifest];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    return entries;
}

BOOL GXHubRemoveMod(NSString *profileId, NSError **error)
{
    if (!GXHubSafeId(profileId))
    {
        if (error != nullptr)
            *error = GXHubError(60, @"Invalid mod profile ID.");
        return NO;
    }
    NSString *path = [GXHubModsRootPath() stringByAppendingPathComponent:profileId];
    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        return YES;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:path error:error];
    if (ok)
        fprintf(stderr, "[HUB] removed profile='%s'\n", [profileId UTF8String]);
    return ok;
}

BOOL GXHubInstallPackageAtURL(
    NSURL *packageURL,
    NSString *expectedSHA256,
    NSDictionary<NSString *, id> **installedManifest,
    NSError **error)
{
    if (packageURL == nil || !packageURL.isFileURL)
    {
        if (error != nullptr)
            *error = GXHubError(70, @"Installer requires a local .gxmod file URL.");
        return NO;
    }

    if (![[packageURL.pathExtension lowercaseString] isEqualToString:@"gxmod"])
    {
        if (error != nullptr)
            *error = GXHubError(72, @"Selected file is not a .gxmod package.");
        return NO;
    }

    NSDictionary<NSFileAttributeKey, id> *packageAttributes =
        [[NSFileManager defaultManager] attributesOfItemAtPath:packageURL.path error:error];
    if (packageAttributes == nil)
        return NO;

    unsigned long long packageBytes = [packageAttributes fileSize];
    NSDictionary<NSFileAttributeKey, id> *fsAttributes =
        [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:error];
    if (fsAttributes == nil)
        return NO;

    unsigned long long freeBytes = [fsAttributes[NSFileSystemFreeSize] unsignedLongLongValue];
    const unsigned long long reserveBytes = 256ULL * 1024ULL * 1024ULL;
    if (freeBytes < packageBytes + reserveBytes)
    {
        if (error != nullptr)
        {
            *error = GXHubError(
                73,
                [NSString stringWithFormat:
                    @"Not enough free space. Need about %.1f GB free to install this mod; available %.1f GB.",
                    (double)(packageBytes + reserveBytes) / 1024.0 / 1024.0 / 1024.0,
                    (double)freeBytes / 1024.0 / 1024.0 / 1024.0]);
        }
        return NO;
    }

    if (expectedSHA256.length > 0)
    {
        NSString *actual = GXHubSHA256ForFile(packageURL, error);
        if (actual == nil)
            return NO;
        if ([actual caseInsensitiveCompare:expectedSHA256] != NSOrderedSame)
        {
            if (error != nullptr)
                *error = GXHubError(
                    71,
                    [NSString stringWithFormat:@"Package SHA-256 mismatch. Expected %@, got %@.",
                        expectedSHA256, actual]);
            return NO;
        }
    }

    return GXHubInstallTar(packageURL, installedManifest, error);
}

void GXHubDownloadAndInstall(
    NSDictionary<NSString *, id> *catalogEntry,
    GXHubInstallCompletion completion)
{
    NSString *urlText = catalogEntry[@"packageURL"];
    NSString *expected = catalogEntry[@"sha256"];
    NSURL *url = urlText.length > 0 ? [NSURL URLWithString:urlText] : nil;
    if (url == nil || ![[url scheme] isEqualToString:@"https"])
    {
        NSError *error = GXHubError(80, @"This catalog entry has no valid HTTPS package URL.");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, error);
        });
        return;
    }
    if (expected.length != 64)
    {
        NSError *error = GXHubError(81, @"Remote packages require a SHA-256 value in the catalog.");
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, error);
        });
        return;
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 120.0;
    configuration.timeoutIntervalForResource = 60.0 * 60.0 * 6.0;
    configuration.allowsCellularAccess = YES;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];

    fprintf(stderr, "[HUB] download-start profile='%s' url='%s'\n",
            [catalogEntry[@"profileId"] UTF8String], [urlText UTF8String]);

    NSURLSessionDownloadTask *task =
        [session downloadTaskWithURL:url
                  completionHandler:^(NSURL *location, NSURLResponse *response, NSError *downloadError) {
        if (downloadError != nil)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, downloadError);
            });
            [session finishTasksAndInvalidate];
            return;
        }

        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]]
            ? (NSHTTPURLResponse *)response
            : nil;
        if (http != nil && (http.statusCode < 200 || http.statusCode >= 300))
        {
            NSError *error = GXHubError(
                82,
                [NSString stringWithFormat:@"Download failed with HTTP %ld.", (long)http.statusCode]);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
            [session finishTasksAndInvalidate];
            return;
        }

        NSError *installError = nil;
        NSDictionary *manifest = nil;
        BOOL installed = GXHubInstallPackageAtURL(location, expected, &manifest, &installError);
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(installed ? manifest : nil, installError);
        });
        [session finishTasksAndInvalidate];
    }];
    [task resume];
}

#endif
