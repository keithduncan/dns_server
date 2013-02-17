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
				NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Couldn\u2019t read the contents of the zone file as %@ data", encodingName],
			};
			*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
	BOOL read = [self _readFromString:zoneString error:errorRef];
	if (!read) {
		return NO;
	}
	
	return YES;
}

- (NSSet *)recordsForFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType
{
	return [self _recordsMatchingName:fullyQualifiedDomainName recordClass:recordClass recordType:recordType];
}

@end
