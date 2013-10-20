//
//  AFNetworkDomainZoneLoader.m
//  DNS Server
//
//  Created by Keith Duncan on 22/09/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZoneLoader.h"

#import "AFNetworkDomainZone.h"

#import "DNS Server-Constants.h"

@implementation AFNetworkDomainZoneLoader

+ (NSSet *)loadZones:(NSError **)errorRef
{
	NSString *zoneFileConfigurationKey = @"DNS_ZONE_FILE";
	NSString *zoneFilePath = [[NSProcessInfo processInfo] environment][zoneFileConfigurationKey];
	if (zoneFilePath == nil) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedStringFromTableInBundle(@"Couldn\u2019t load initial zone file configuration", nil, [NSBundle bundleWithIdentifier:AFNetworkDomainServerBundleIdentifier], @"AFNetworkDomainZoneLoader, no zone file environment variable, error description"),
				NSLocalizedRecoverySuggestionErrorKey : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Set the %@ environment variable to configure the initial zone set", nil, [NSBundle bundleWithIdentifier:AFNetworkDomainServerBundleIdentifier], @"AFNetworkDomainZoneLoader, no zone file environment variable, error recovery suggestion"), zoneFileConfigurationKey],
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainServerBundleIdentifier code:0 userInfo:errorInfo];
		}
		return nil;
	}
	
	NSMutableArray *zoneFileLocations = [NSMutableArray array];
	
	NSURL *zoneFileLocation = [[NSURL fileURLWithPath:[zoneFilePath stringByExpandingTildeInPath]] URLByResolvingSymlinksInPath];
	
	NSString *zoneFileLocationType = nil; NSError *zoneFileLocationTypeError = nil;
	BOOL getZoneFileLocationType = [zoneFileLocation getResourceValue:&zoneFileLocationType forKey:NSURLFileResourceTypeKey error:&zoneFileLocationTypeError];
	if (!getZoneFileLocationType) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Couldn\u2019t determine the file system type of the %@ configuration", nil, [NSBundle bundleWithIdentifier:AFNetworkDomainServerBundleIdentifier], @"AFNetworkDomainZoneLoader, zone file path type, error description"), zoneFileConfigurationKey],
				NSUnderlyingErrorKey : zoneFileLocationTypeError,
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainServerBundleIdentifier code:0 userInfo:errorInfo];
		}
		return nil;
	}
	
	if ([zoneFileLocationType isEqualToString:NSURLFileResourceTypeRegular]) {
		[zoneFileLocations addObject:zoneFileLocation];
	}
	else if ([zoneFileLocationType isEqualToString:NSURLFileResourceTypeDirectory]) {
		NSArray *locations = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:zoneFileLocation includingPropertiesForKeys:@[] options:(NSDirectoryEnumerationOptions)0 error:errorRef];
		if (locations == nil) {
			return nil;
		}
		
		locations = [locations objectsAtIndexes:[locations indexesOfObjectsPassingTest:^ BOOL (NSURL *location, NSUInteger idx, BOOL *stop) {
			return [[location lastPathComponent] hasPrefix:@"db."];
		}]];
		
		[zoneFileLocations addObjectsFromArray:locations];
	}
	else {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Cannot load zone file configuration from file of type %@", nil, [NSBundle bundleWithIdentifier:AFNetworkDomainServerBundleIdentifier], @"AFNetworkDomainZoneLoader, zone file path type, error description"), zoneFileLocationType],
				NSLocalizedRecoverySuggestionErrorKey : [NSString stringWithFormat:NSLocalizedStringFromTableInBundle(@"Supported types are regular files or directories of files, check the %@ path", nil, [NSBundle bundleWithIdentifier:AFNetworkDomainServerBundleIdentifier], @"AFNetworkDomainZoneLoader, zone file path type, error recovery suggestion"), zoneFileConfigurationKey],
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainServerBundleIdentifier code:0 userInfo:errorInfo];
		}
		return nil;
	}
	
	NSMutableSet *zones = [NSMutableSet setWithCapacity:[zoneFileLocations count]];
	for (NSURL *currentZoneLocation in zoneFileLocations) {
		AFNetworkDomainZone *zone = [[AFNetworkDomainZone alloc] init];
		
		BOOL readZone = [zone readFromURL:currentZoneLocation options:nil error:errorRef];
		if (!readZone) {
			return nil;
		}
		
		[zones addObject:zone];
	}
	
	return zones;
}

@end
