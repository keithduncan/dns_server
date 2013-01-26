//
//  AFNetworkDomainZone.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"

#import "CoreNetworking/CoreNetworking.h"

@interface AFNetworkDomainZone ()
@property (copy, nonatomic) NSString *origin;
@property (assign, nonatomic) NSTimeInterval ttl;
@property (copy, nonatomic) NSString *class;
@property (retain, nonatomic) NSSet *records;
@end

static NSString *const AFDomainServerErrorDomain = @"com.thirty-three.corenetworking.domain-server";

@implementation AFNetworkDomainZone

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
	
	NSSet *newRecords = [self _parseRecordsFromZoneString:zoneString error:errorRef];
	if (newRecords == nil) {
		return NO;
	}
	self.records = newRecords;
	
	return YES;
}

- (NSSet *)_parseRecordsFromZoneString:(NSString *)zoneString error:(NSError **)errorRef
{
#if 1
	return nil;
#else
	NSScanner *zoneScanner = [NSScanner scannerWithString:zoneString];
	[zoneScanner setCharactersToBeSkipped:nil];
	
	NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet], *whitespaceAndNewlineCharacterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	
	void (^scanWhitespace)(void) = ^ {
		[zoneScanner scanCharactersFromSet:whitespaceCharacterSet intoString:NULL];
	};
	
	NSUInteger recordCapacityHint = [[zoneString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count];
	NSMutableSet *records = [NSMutableSet setWithCapacity:recordCapacityHint];
	
	while (![zoneScanner isAtEnd]) {
		/*
			Line Parser
		 */
		
		NSMutableCharacterSet *recordStartCharacterSet = [[NSMutableCharacterSet alloc] init];
		[recordStartCharacterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
		[recordStartCharacterSet addCharactersInString:@"@"];
		
		// Directive
		if ([zoneScanner scanString:@"$" intoString:NULL]) {
			NSString *directive = nil;
			BOOL scanDirective = [zoneScanner scanUpToCharactersFromSet:whitespaceAndNewlineCharacterSet intoString:&directive];
			if (!scanDirective) {
				break;
			}
			
			NSDictionary *valueRequiredErrorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Cannot process directive \u201c%@\u201d without a parameter", directive],
			};
			NSError *valueRequiredError = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:valueRequiredErrorInfo];
			
			if ([directive isEqualToString:@"ORIGIN"]) {
				scanWhitespace();
				
				NSString *originValue = nil;
				BOOL scanOriginValue = [zoneScanner scanUpToCharactersFromSet:whitespaceAndNewlineCharacterSet intoString:&originValue];
				if (!scanOriginValue) {
					break;
				}
				
				originValue = [originValue stringByTrimmingCharactersInSet:whitespaceCharacterSet];
				
				if ([originValue length] == 0) {
					if (errorRef != NULL) {
						*errorRef = valueRequiredError;
					}
					return NO;
				}
				
				if (![originValue hasSuffix:@"."]) {
					if (errorRef != NULL) {
						NSDictionary *errorInfo = @{
							NSLocalizedDescriptionKey : @"Zone origin must be a fully qualified domain name",
						};
						*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
					}
					return NO;
				}
				
				self.origin = originValue;
			}
			else if ([directive isEqualToString:@"TTL"]) {
				scanWhitespace();
				
#error  this doesn't accommodate for comments trailing the `$TTL val`
				
				NSString *ttlValue = nil;
				BOOL scanTtlValue = [zoneScanner scanUpToCharactersFromSet:whitespaceAndNewlineCharacterSet intoString:&ttlValue];
				if (!scanTtlValue) {
					break;
				}
				
				if ([[ttlValue stringByTrimmingCharactersInSet:whitespaceCharacterSet] length] == 0) {
					if (errorRef != NULL) {
						*errorRef = valueRequiredError;
					}
					return NO;
				}
				
				NSTimeInterval ttl = [self _parseTimeValue:ttlValue];
				if (ttl == -1) {
					if (errorRef != NULL) {
						NSDictionary *errorInfo = @{
							NSLocalizedDescriptionKey : @"Cannot parse TTL time value",
						};
						*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
					}
					return NO;
				}
				
				self.ttl = ttl;
			}
			else {
				if (errorRef != NULL) {
					NSDictionary *errorInfo = @{
						NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Cannot process directive \u201c%@\u201d", directive],
					};
					*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
				}
				return NO;
			}
			
			[zoneScanner scanUpToString:<#(NSString *)#> intoString:<#(NSString **)#>
		}
		// Record
		else if ([zoneScanner scanCharactersFromSet:recordStartCharacterSet intoString:NULL) {
			
		}
		
#warning first record should be SOA unless the last (prior to .) label in origin is "local"
		
#warning when adding a record check the class of the record, that fixes the class of all other records, if they differ in class return an error, zones files can only include resource records in a single class
	}
	
	if (![zoneScanner isAtEnd]) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : @"Couldn\u2019t parse all the zone file entries, some data may be missing",
			};
			*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
#endif
}

static NSString * (^scanStringFromArray)(NSScanner *, NSArray *) = ^ NSString * (NSScanner *scanner, NSArray *strings) {
	for (NSString *currentString in strings) {
		if (![scanner scanString:currentString intoString:NULL]) {
			continue;
		}
		
		return currentString;
	}
	
	return nil;
};

- (NSTimeInterval)_parseTimeValue:(NSString *)timeValue
{
	NSScanner *timeScanner = [NSScanner scannerWithString:timeValue];
	[timeScanner setCharactersToBeSkipped:nil];
	
	NSCharacterSet *digitCharacterSet = [NSCharacterSet decimalDigitCharacterSet];
	
	NSString *ttl = nil;
	BOOL scanTtl = [timeScanner scanCharactersFromSet:digitCharacterSet intoString:&ttl];
	if (!scanTtl) {
		return -1;
	}
	
	// No unit
	if ([timeScanner isAtEnd]) {
		return [ttl doubleValue];
	}
	
	NSDictionary *unitToMultiple = @{ @"w" : @(604800.), @"d" : @(86400.) , @"h" : @(3600.), @"m" : @(60.), @"s" : @(1.) };
	NSArray *units = [unitToMultiple allKeys];
	
	NSTimeInterval (^valueOfUnit)(NSString *, NSString *) = ^ NSTimeInterval (NSString *duration, NSString *unit) {
		NSNumber *multiple = unitToMultiple[[unit lowercaseString]];
		NSParameterAssert(multiple != nil);
		return [ttl doubleValue] * [multiple doubleValue];
	};
	
	// Rogue unit
	NSString *unit = scanStringFromArray(timeScanner, units);
	if (unit == nil) {
		return -1;
	}
	
	NSTimeInterval cumulativeTime = 0;
	cumulativeTime += valueOfUnit(ttl, unit);
	
	while (![timeScanner isAtEnd]) {
		BOOL scanDuration = [timeScanner scanCharactersFromSet:digitCharacterSet intoString:&ttl];
		if (!scanDuration) {
			return -1;
		}
		
		unit = scanStringFromArray(timeScanner, units);
		if (unit == nil) {
			return -1;
		}
		
		cumulativeTime += valueOfUnit(ttl, unit);
	}
	
	return cumulativeTime;
}

- (AFNetworkDomainRecord *)recordForFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType
{
	return nil;
}

@end
