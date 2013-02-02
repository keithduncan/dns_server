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
	NSUInteger recordCapacityHint = [[zoneString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count];
	NSMutableSet *records = [NSMutableSet setWithCapacity:recordCapacityHint];
	
	NSScanner *zoneScanner = [NSScanner scannerWithString:zoneString];
	[zoneScanner setCharactersToBeSkipped:nil];
	
	// Reused character sets / scanners
	
	NSString * (^scanCharacterFromSet)(NSScanner *, NSCharacterSet *) = ^ NSString * (NSScanner *scanner, NSCharacterSet *characterSet) {
		NSString *originalString = [scanner string];
		NSRange characterRange = [originalString rangeOfCharacterFromSet:characterSet options:NSAnchoredSearch range:NSMakeRange([scanner scanLocation], [originalString length] - [scanner scanLocation])];
		if (characterRange.location == NSNotFound) {
			return nil;
		}
		
		[scanner setScanLocation:NSMaxRange(characterRange)];
		
		return [originalString substringWithRange:characterRange];
	};
	
	NSString * (^scanCharacterSetMinMax)(NSScanner *, NSCharacterSet *, NSUInteger, NSUInteger) = ^ NSString * (NSScanner *scanner, NSCharacterSet *characterSet, NSUInteger min, NSUInteger max) {
		NSUInteger startLocation = [scanner scanLocation];
		
		NSMutableString *cumulative = [NSMutableString string];
		
		NSUInteger matchCount = 0;
		while (matchCount < max) {
			NSString *match = scanCharacterFromSet(scanner, characterSet);
			if (match == nil) {
				break;
			}
			
			[cumulative appendString:match];
			matchCount++;
		}
		
		if (matchCount < min) {
			[scanner setScanLocation:startLocation];
			return nil;
		}
		
		return cumulative;
	};
	
	NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
	
	BOOL (^scanWs)(NSScanner *, NSUInteger, NSUInteger) = ^ BOOL (NSScanner *scanner, NSUInteger min, NSUInteger max) {
		return (scanCharacterSetMinMax(scanner, whitespaceCharacterSet, min, max) != nil);
	};
	
	void (^scanLws)(NSScanner *) = ^ void (NSScanner *scanner) {
		scanWs(scanner, 0, NSUIntegerMax);
	};
	
	BOOL (^scanNewline)(NSScanner *) = ^ BOOL (NSScanner *scanner) {
		if ([scanner scanString:@"\n" intoString:NULL]) {
			return YES;
		}
		
		return [scanner scanString:@"\r\n" intoString:NULL];
	};
	
	NSString *alphaCharacters = @"abcdefghijklmnopqrstuvwxyz";
	NSMutableCharacterSet *alphaCharacterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[alphaCharacterSet addCharactersInString:[alphaCharacters lowercaseString]];
	[alphaCharacterSet addCharactersInString:[alphaCharacters uppercaseString]];
	
	NSString *digitCharacters = @"0123456789";
	NSCharacterSet *digitCharacterSet = [NSCharacterSet characterSetWithCharactersInString:digitCharacters];
	
	NSMutableCharacterSet *labelCharacterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[labelCharacterSet formUnionWithCharacterSet:alphaCharacterSet];
	[labelCharacterSet formUnionWithCharacterSet:digitCharacterSet];
	[labelCharacterSet addCharactersInString:@"-"];
	
	NSString * (^scanLabel)(NSScanner *) = ^ NSString * (NSScanner *scanner) {
		return scanCharacterSetMinMax(scanner, labelCharacterSet, 1, NSUIntegerMax);
	};
	
	NSString * (^scanFqdn)(NSScanner *) = ^ NSString * (NSScanner *scanner) {
		NSUInteger startLocation = [scanner scanLocation];
		NSUInteger lastPairLocation = startLocation;
		
		NSMutableString *cumulative = [NSMutableString string];
		
		while (1) {
			NSString *label = scanLabel(scanner);
			if (label == nil) {
				break;
			}
			
			NSString *separator = nil;
			if (![scanner scanString:@"." intoString:&separator]) {
				break;
			}
			
			[cumulative appendString:label];
			[cumulative appendString:separator];
			
			lastPairLocation = [scanner scanLocation];
		}
		
		if (lastPairLocation == startLocation) {
			return nil;
		}
		
		return cumulative;
	};
	
	/*
		Zone Parser
	 */
	
	BOOL scanNewlineFirst = NO;
	while (![zoneScanner isAtEnd]) {
		/*
			Newline Prefix
		 */
		if (scanNewlineFirst) {
			if (!scanNewline(zoneScanner)) {
				break;
			}
		}
		else {
			scanNewlineFirst = YES;
		}
		
		/*
			Line Parser
		 */
		
		// Directive
		if ([zoneScanner scanString:@"$" intoString:NULL]) {
			if ([zoneScanner scanString:@"ORIGIN" intoString:NULL]) {
				if (!scanWs(zoneScanner, 1, NSUIntegerMax)) {
					break;
				}
				
				NSString *fqdn = scanFqdn(zoneScanner);
				if (fqdn == nil) {
					if (errorRef != NULL) {
						NSDictionary *errorInfo = @{
							NSLocalizedDescriptionKey : @"ORIGIN directive must be followed by a fully qualified domain name",
						};
						*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
					}
					return NO;
				}
				
				self.origin = fqdn;
			}
			else if ([zoneScanner scanString:@"TTL" intoString:NULL]) {
				if (!scanWs(zoneScanner, 1, NSUIntegerMax)) {
					break;
				}
				
				NSTimeInterval ttl = [self _scanTimeValue:zoneScanner];
				if (ttl == -1) {
					if (errorRef != NULL) {
						NSDictionary *errorInfo = @{
							NSLocalizedDescriptionKey : @"TTL directive must be followed by a time value",
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
						NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Cannot process directive"],
					};
					*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
				}
				return NO;
			}
		}
#if 0
		// Record
		else if ([zoneScanner scanCharactersFromSet:recordStartCharacterSet intoString:NULL]) {
			
		}
		// Blank
		else if (0) {
			
		}
#endif
		
		// LWS
		
		{
			
		}
		
		// Comment
		
		{
			
		}
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

	return records;
}

static NSString * (^scanStringFromArray)(NSScanner *, NSArray *) = ^ NSString * (NSScanner *scanner, NSArray *strings)
{
	for (NSString *currentString in strings) {
		if (![scanner scanString:currentString intoString:NULL]) {
			continue;
		}
		
		return currentString;
	}
	
	return nil;
};

- (NSTimeInterval)_scanTimeValue:(NSScanner *)timeScanner
{
	NSCharacterSet *digitCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"];
	
	NSString *ttl = nil;
	BOOL scanTtl = [timeScanner scanCharactersFromSet:digitCharacterSet intoString:&ttl];
	if (!scanTtl) {
		return -1;
	}
	
	NSDictionary *unitToMultiple = @{ @"w" : @(604800.), @"d" : @(86400.) , @"h" : @(3600.), @"m" : @(60.), @"s" : @(1.) };
	NSArray *units = [unitToMultiple allKeys];
	
	NSTimeInterval (^valueOfUnit)(NSString *, NSString *) = ^ NSTimeInterval (NSString *duration, NSString *unit) {
		NSNumber *multiple = unitToMultiple[[unit lowercaseString]];
		NSParameterAssert(multiple != nil);
		return [duration doubleValue] * [multiple doubleValue];
	};
	
	NSString *unit = scanStringFromArray(timeScanner, units);
	if (unit == nil) {
		// No unit
		return [ttl doubleValue];
	}
	
	NSTimeInterval cumulativeDuration = 0;
	cumulativeDuration += valueOfUnit(ttl, unit);
	
	NSUInteger lastPairScanLocation = [timeScanner scanLocation];
	
	BOOL abort = NO;
	while (1) {
		NSString *currentDuration = nil;
		BOOL scanCurrentDuration = [timeScanner scanCharactersFromSet:digitCharacterSet intoString:&currentDuration];
		if (!scanCurrentDuration) {
			abort = YES;
			break;
		}
		
		NSString *currentUnit = scanStringFromArray(timeScanner, units);
		if (currentUnit == nil) {
			abort = YES;
			break;
		}
		
		NSTimeInterval evaluatedDuration = valueOfUnit(currentDuration, currentUnit);
		cumulativeDuration += evaluatedDuration;
		
		lastPairScanLocation = [timeScanner scanLocation];
	}
	
	if (abort) {
		[timeScanner setScanLocation:lastPairScanLocation];
		return cumulativeDuration;
	}
	
	return cumulativeDuration;
}

- (AFNetworkDomainRecord *)recordForFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType
{
	return nil;
}

@end
