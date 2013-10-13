//
//  AFNetworkDomainZone.h
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"
#import "AFNetworkDomainZone+AFNetworkPrivate.h"

#import "AFNetworkDomainZone+RecordParsing.h"
#import "AFNetworkDomainZone+RecordMatching.h"

#import "CoreNetworking/CoreNetworking.h"

NSString *const AFNetworkDomainZoneErrorDomain = @"com.thirty-three.corenetworking.domain-zone";

@implementation AFNetworkDomainZone

@synthesize origin=_origin;
@synthesize records=_records;

- (void)dealloc
{
	[_origin release];
	
	[_records release];
	
	[super dealloc];
}

- (BOOL)readFromURL:(NSURL *)URL options:(NSDictionary *)options error:(NSError **)errorRef
{
	NSError *readError = nil;
	BOOL read = [self _readFromURL:URL options:options error:&readError];
	if (!read) {
		if (errorRef != NULL) {
			if ([readError userInfo][NSURLErrorKey] == nil) {
				NSMutableDictionary *newErrorInfo = [NSMutableDictionary dictionaryWithDictionary:[readError userInfo]];
				newErrorInfo[NSURLErrorKey] = URL;
				readError = [NSError errorWithDomain:[readError domain] code:[readError code] userInfo:newErrorInfo];
			}
			
			*errorRef = readError;
		}
		return NO;
	}
	
	return YES;
}

- (BOOL)_readFromURL:(NSURL *)URL options:(NSDictionary *)options error:(NSError **)errorRef
{
	NSString *lastPathComponent = [URL lastPathComponent];
	if ([lastPathComponent hasPrefix:@"db."]) {
		NSString *defaultOrigin = [lastPathComponent substringFromIndex:3];
		if (![defaultOrigin hasPrefix:@"."]) {
			defaultOrigin = [defaultOrigin stringByAppendingString:@"."];
		}
		self.origin = defaultOrigin;
	}
	
	self.ttl = -1;
	
	NSData *zoneData = [NSData dataWithContentsOfURL:URL options:(NSDataReadingOptions)0 error:errorRef];
	if (zoneData == nil) {
		return NO;
	}
	
	NSStringEncoding stringEncoding = NSUTF8StringEncoding;
	NSString *zoneString = [[[NSString alloc] initWithData:zoneData encoding:stringEncoding] autorelease];
	if (zoneString == nil) {
		if (errorRef != NULL) {
			NSString *encodingName = (NSString *)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(stringEncoding));
			
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Couldn\u2019t read the contents of the zone file as %@ data", @"AFNetworkDomainZone file not string error description"), encodingName],
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
	return [self _readFromString:zoneString error:errorRef];
}

- (NSSet *)recordsForFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType
{
	return [self _recordsMatchingName:fullyQualifiedDomainName recordClass:recordClass recordType:recordType];
}

@end
