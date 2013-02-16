//
//  AFNetworkDomainZone.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkDomainRecord.h"

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

- (BOOL)_readFromString:(NSString *)zoneString error:(NSError **)errorRef
{
	NSSet *newRecords = [self _parseRecordsFromZoneString:zoneString error:errorRef];
	if (newRecords == nil) {
		return NO;
	}
	self.records = newRecords;
	
	return YES;
}

#pragma mark -

static NSString *scanStringFromArray(NSScanner *scanner, NSArray *strings)
{
	NSString *longestMatch = nil;
	
	for (NSString *currentString in strings) {
		NSScanner *currentScanner = [[scanner copy] autorelease];
		
		NSString *match = nil;
		if (![currentScanner scanString:currentString intoString:&match]) {
			continue;
		}
		
		if ([match length] <= [longestMatch length]) {
			continue;
		}
		
		longestMatch = match;
	}
	
	[scanner setScanLocation:([scanner scanLocation] + [longestMatch length])];
	return longestMatch;
}

NSString *scanCharacterFromSet(NSScanner *scanner, NSCharacterSet *characterSet)
{
	NSString *originalString = [scanner string];
	NSRange characterRange = [originalString rangeOfCharacterFromSet:characterSet options:NSAnchoredSearch range:NSMakeRange([scanner scanLocation], [originalString length] - [scanner scanLocation])];
	if (characterRange.location == NSNotFound) {
		return nil;
	}
	
	[scanner setScanLocation:NSMaxRange(characterRange)];
	
	return [originalString substringWithRange:characterRange];
}

NSString *scanCharacterSetMinMax(NSScanner *scanner, NSCharacterSet *characterSet, NSUInteger min, NSUInteger max)
{
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
}

static BOOL scanNewline(NSScanner *scanner)
{
	if ([scanner scanString:@"\n" intoString:NULL]) {
		return YES;
	}
	
	return [scanner scanString:@"\r\n" intoString:NULL];
}

static BOOL scanWs(NSScanner *scanner, NSUInteger min, NSUInteger max)
{
	NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
	return (scanCharacterSetMinMax(scanner, whitespaceCharacterSet, min, max) != nil);
}

void scanLws(NSScanner *scanner)
{
	scanWs(scanner, 0, NSUIntegerMax);
}

static NSString *scanLabel(NSScanner *scanner)
{
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
	[labelCharacterSet addCharactersInString:@"_"];
	
	return scanCharacterSetMinMax(scanner, labelCharacterSet, 1, NSUIntegerMax);
}

static NSString *scanFqdn(NSScanner *scanner)
{
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
		[scanner setScanLocation:startLocation];
		return nil;
	}
	
	return cumulative;
}

static NSString *scanDn(NSScanner *scanner)
{
	NSString *firstLabel = scanLabel(scanner);
	if (firstLabel == nil) {
		return nil;
	}
	
	NSUInteger lastLabelLocation = [scanner scanLocation];
	
	NSMutableString *cumulative = [NSMutableString stringWithString:firstLabel];
	while (1) {
		NSString *prefix = nil;
		if (![scanner scanString:@"." intoString:&prefix]) {
			break;
		}
		
		NSString *label = scanLabel(scanner);
		if (label == nil) {
			break;
		}
		
		[cumulative appendString:prefix];
		[cumulative appendString:label];
		
		lastLabelLocation = [scanner scanLocation];
	}
	
	[scanner setScanLocation:lastLabelLocation];
	
	return cumulative;
}

static NSCharacterSet *textCharacterSet(void)
{
	NSMutableCharacterSet *textCharacterSet = [[NSMutableCharacterSet alloc] init];
	
	[textCharacterSet addCharactersInRange:NSMakeRange(0, 255)];
	// CTLs
	[textCharacterSet removeCharactersInRange:NSMakeRange(0, 32)];
	[textCharacterSet removeCharactersInRange:NSMakeRange(127, 1)];
	// WS
	[textCharacterSet addCharactersInRange:NSMakeRange(9, 1)];
	
	return textCharacterSet;
}

static NSString *scanText(NSScanner *scanner)
{
	return scanCharacterSetMinMax(scanner, textCharacterSet(), 0, NSUIntegerMax);
}

static NSString *scanComment(NSScanner *scanner)
{
	NSUInteger startLocation = [scanner scanLocation];
	
	if (![scanner scanString:@";" intoString:NULL]) {
		return nil;
	}
	
	NSString *comment = scanText(scanner);
	if (comment == nil) {
		[scanner setScanLocation:startLocation];
		return nil;
	}
	
	return comment;
}

#pragma mark -

- (NSSet *)_parseRecordsFromZoneString:(NSString *)zoneString error:(NSError **)errorRef
{
	NSUInteger recordCapacityHint = [[zoneString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count];
	
	// Order the records are read in is important for back references to class and type
	NSMutableArray *records = [NSMutableArray arrayWithCapacity:recordCapacityHint];
	
	/*
		Zone Parser
	 */
	
	BOOL (^scanLine)(NSScanner *) = ^ BOOL (NSScanner *scanner) {
		/*
			Line Parser
		 */
		
		// Directive
		if ([scanner scanString:@"$" intoString:NULL]) {
			if ([scanner scanString:@"ORIGIN" intoString:NULL]) {
				if (!scanWs(scanner, 1, NSUIntegerMax)) {
					return NO;
				}
				
				NSString *fqdn = scanFqdn(scanner);
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
			else if ([scanner scanString:@"TTL" intoString:NULL]) {
				if (!scanWs(scanner, 1, NSUIntegerMax)) {
					return NO;
				}
				
				NSTimeInterval ttl = [self _scanTimeValue:scanner];
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
		
		// Record
		else if ([self _scanRecord:scanner intoArray:records]) {
			
		}
		
		// Blank
		else if (1) {
			
		}
		
		// LWS
		
		scanLws(scanner);
		
		// Comment
		
		scanComment(scanner);
		
		return YES;
	};
	
	NSScanner *zoneScanner = [NSScanner scannerWithString:zoneString];
	[zoneScanner setCharactersToBeSkipped:nil];
	
	do {
		BOOL firstLine = scanLine(zoneScanner);
		if (!firstLine) {
			return nil;
		}
		
		NSUInteger lastLocation = [zoneScanner scanLocation];
		
		while (1) {
			BOOL newline = scanNewline(zoneScanner);
			if (!newline) {
				break;
			}
			
			BOOL line = scanLine(zoneScanner);
			if (!line) {
				break;
			}
			
			lastLocation = [zoneScanner scanLocation];
		}
	} while (0);
	
	if (![zoneScanner isAtEnd]) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : @"Couldn\u2019t parse all the zone file entries, some data may be missing",
			};
			*errorRef = [NSError errorWithDomain:AFDomainServerErrorDomain code:AFNetworkErrorUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
	return [NSSet setWithArray:records];
}

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

static void tryMatch(NSScanner *scanner, NSUInteger *longestMatchScanLocationRef, NSString **longestMatchRef, NSString * (^block)(NSScanner *))
{
	NSScanner *currentScanner = [[scanner copy] autorelease];
	NSString *name = block(currentScanner);
	if (name == nil) {
		return;
	}
	
	NSUInteger currentScanLocation = [currentScanner scanLocation];
	if (currentScanLocation <= *longestMatchScanLocationRef) {
		return;
	}
	
	*longestMatchScanLocationRef = currentScanLocation;
	*longestMatchRef = name;
}

static NSString *scanName(NSScanner *scanner)
{
	NSUInteger longestNameScanLocation = 0;
	NSString *longestName = nil;
	
	tryMatch(scanner, &longestNameScanLocation, &longestName, ^ NSString * (NSScanner *innerScanner) {
		NSString *name = nil;
		
		if ([innerScanner scanString:@"@" intoString:&name] ||
			[innerScanner scanString:@"*" intoString:&name]) {
			return name;
		}
		
		return nil;
	});
	
	tryMatch(scanner, &longestNameScanLocation, &longestName, ^ NSString * (NSScanner *innerScanner) {
		NSMutableString *cumulative = [NSMutableString string];
		
		NSString *prefix = nil;
		if ([innerScanner scanString:@"*." intoString:&prefix]) {
			[cumulative appendString:prefix];
		}
		
		NSUInteger longestDnScanLocation = 0;
		NSString *longestDn = nil;
		
		tryMatch(innerScanner, &longestDnScanLocation, &longestDn, ^ NSString * (NSScanner *innerScanner1) {
			return scanFqdn(innerScanner1);
		});
		tryMatch(innerScanner, &longestDnScanLocation, &longestDn, ^ NSString * (NSScanner *innerScanner1) {
			return scanDn(innerScanner1);
		});
		if (longestDn == nil) {
			return nil;
		}
		[cumulative appendString:longestDn];
		
		[innerScanner setScanLocation:longestDnScanLocation];
		return cumulative;
	});
	
	if (longestName == nil) {
		return nil;
	}
	
	[scanner setScanLocation:longestNameScanLocation];
	return longestName;
}

static NSString *scanClass(NSScanner *scanner)
{
	return scanStringFromArray(scanner, @[ @"IN" ]);
}

static NSString *scanType(NSScanner *scanner)
{
	return scanStringFromArray(scanner, @[ @"A", @"AAAA", @"MX", @"NS", @"PTR", @"SOA", @"SRV", @"TXT", @"CNAME", @"NAPTR", @"SPF" ]);
}

static NSCharacterSet * (^commonExcludedCharacterSet)(void) = ^ NSCharacterSet * (void)
{
	NSMutableCharacterSet *characterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[characterSet addCharactersInString:@";()"];
	[characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
	return characterSet;
};

static NSCharacterSet * (^excludedCharacterSet)(void) = ^ NSCharacterSet * (void)
{
	NSMutableCharacterSet *characterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[characterSet addCharactersInString:@"\""];
	[characterSet formUnionWithCharacterSet:commonExcludedCharacterSet()];
	return characterSet;
};

static NSString *scanInnerData(NSScanner *scanner, NSUInteger min, NSUInteger max)
{
	NSMutableCharacterSet *innerDataCharacterSet = [[textCharacterSet() mutableCopy] autorelease];
	[innerDataCharacterSet formIntersectionWithCharacterSet:[excludedCharacterSet() invertedSet]];
	return scanCharacterSetMinMax(scanner, innerDataCharacterSet, min, max);
}

static NSString *scanQuotedPair(NSScanner *scanner)
{
	NSUInteger startLocation = [scanner scanLocation];
	
	if (![scanner scanString:@"\\" intoString:NULL]) {
		return nil;
	}
	
	NSCharacterSet *charCharacterSet = [NSCharacterSet characterSetWithRange:NSMakeRange(0, 128)];
	NSString *character = scanCharacterFromSet(scanner, charCharacterSet);
	if (character == nil) {
		[scanner setScanLocation:startLocation];
		return nil;
	}
	
	return character;
}

static NSString *scanQuotedData(NSScanner *scanner)
{
	NSUInteger startLocation = [scanner scanLocation];
	
	if (![scanner scanString:@"\"" intoString:NULL]) {
		return nil;
	}
	
	NSMutableString *cumulative = [NSMutableString string];
	
	while (1) {
		NSUInteger longestCurrentScanLocation = 0;
		NSString *current = nil;
		
		tryMatch(scanner, &longestCurrentScanLocation, &current, ^ NSString * (NSScanner *innerScanner) {
			return scanInnerData(innerScanner, 1, 1);
		});
		
		tryMatch(scanner, &longestCurrentScanLocation, &current, ^ NSString * (NSScanner *innerScanner) {
			return scanCharacterFromSet(innerScanner, commonExcludedCharacterSet());
		});
		
		tryMatch(scanner, &longestCurrentScanLocation, &current, ^ NSString * (NSScanner *innerScanner) {
			return scanQuotedPair(innerScanner);
		});
		
		if (current == nil) {
			break;
		}
		
		[cumulative appendString:current];
		
		[scanner setScanLocation:longestCurrentScanLocation];
		continue;
	}
	
	if (![scanner scanString:@"\"" intoString:NULL]) {
		[scanner setScanLocation:startLocation];
		return nil;
	}
	
	return cumulative;
}

static NSString *scanDataField(NSScanner *scanner)
{
	NSString *current = scanQuotedData(scanner);
	if (current != nil) {
		return current;
	}
	
	current = scanInnerData(scanner, 1, NSUIntegerMax);
	if (current != nil) {
		return current;
	}
	
	return nil;
}

static NSArray *scanData(NSScanner *scanner)
{
	NSUInteger startLocation = [scanner scanLocation];
	
	do {
		NSString *dataField = scanDataField(scanner);
		if (dataField != nil) {
			return @[ dataField ];
		}
	} while (0);
	
	do {
		if (![scanner scanString:@"(" intoString:NULL]) {
			break;
		}
		
		NSMutableArray *cumulative = [NSMutableArray array];
		
		while (1) {
			scanLws(scanner);
			
			BOOL accumulate = YES;
			do {
				NSString *dataField = scanDataField(scanner);
				if (dataField != nil) {
					[cumulative addObject:dataField];
					break;
				}
				
				NSString *comment = scanComment(scanner);
				if (comment != nil) {
					break;
				}
				
				BOOL newline = scanNewline(scanner);
				if (newline) {
					break;
				}
				
				accumulate = NO;
			} while (0);
			
			if (!accumulate) {
				break;
			}
		}
		
		if ([cumulative count] == 0 ||
			![scanner scanString:@")" intoString:NULL]) {
			break;
		}
		
		return cumulative;
	} while (0);
	
	[scanner setScanLocation:startLocation];
	return nil;
}

static NSArray *scanRdata(NSScanner *scanner)
{
	NSArray *firstFields = scanData(scanner);
	if (firstFields == nil) {
		return nil;
	}
	
	NSMutableArray *cumulative = [NSMutableArray arrayWithArray:firstFields];
	NSUInteger lastLocation = [scanner scanLocation];
	
	while (1) {
		BOOL ws = scanWs(scanner, 1, NSUIntegerMax);
		if (!ws) {
			break;
		}
		
		NSArray *fields = scanData(scanner);
		if (fields == nil) {
			break;
		}
		
		[cumulative addObjectsFromArray:fields];
		
		lastLocation = [scanner scanLocation];
	}
	
	[scanner setScanLocation:lastLocation];
	return cumulative;
}

- (BOOL)_scanRecord:(NSScanner *)recordScanner intoArray:(NSMutableArray *)records
{
	NSUInteger startLocation = [recordScanner scanLocation];
	
	AFNetworkDomainRecord *previousRecord = [records lastObject];
	
	NSString *recordName = nil;
	do {
		recordName = scanName(recordScanner);
		if (recordName != nil) {
			BOOL ws = scanWs(recordScanner, 1, NSUIntegerMax);
			if (!ws) {
				recordName = nil;
			}
			break;
		}
		
		BOOL ws = scanWs(recordScanner, 1, NSUIntegerMax);
		if (ws) {
			if (previousRecord == nil) {
#warning return error
			}
			
			recordName = [previousRecord fullyQualifiedDomainName];
		}
	} while (0);
	
	if (recordName == nil) {
		[recordScanner setScanLocation:startLocation];
		return NO;
	}
	else if ([recordName isEqualToString:@"@"]) {
		recordName = self.origin;
	}
	else if (![recordName hasSuffix:@"."]) {
		recordName = [recordName stringByAppendingFormat:@".%@", self.origin];
	}
	
	NSTimeInterval recordTtl = -1;
	do {
		NSUInteger ttlStartLocation = [recordScanner scanLocation];
		
		NSTimeInterval ttl = [self _scanTimeValue:recordScanner];
		if (ttl == -1) {
			break;
		}
		
		BOOL ws = scanWs(recordScanner, 1, NSUIntegerMax);
		if (!ws) {
			[recordScanner setScanLocation:ttlStartLocation];
			break;
		}
		
		recordTtl = ttl;
	} while (0);
	
	if (recordTtl == -1) {
		if (self.ttl == -1) {
#warning return error
		}
		else {
			recordTtl = self.ttl;
		}
	}
	
	NSString *recordClass = nil;
	do {
		NSUInteger classStartLocation = [recordScanner scanLocation];
		
		recordClass = scanClass(recordScanner);
		if (recordClass != nil) {
			BOOL ws = scanWs(recordScanner, 1, NSUIntegerMax);
			if (ws) {
				break;
			}
			
			[recordScanner setScanLocation:classStartLocation];
		}
		
		recordClass = [previousRecord recordClass];
	} while (0);
	
	if (recordClass == nil) {
#warning return error
		return NO;
	}
	
	NSString *recordType = scanType(recordScanner);
	do {
		if (recordType == nil) {
#warning return error
			return NO;
		}
		
		BOOL ws = scanWs(recordScanner, 1, NSUIntegerMax);
		if (!ws) {
			return NO;
		}
	} while (0);
	
	NSArray *recordFields = scanRdata(recordScanner);
	if (recordFields == nil) {
		[recordScanner setScanLocation:startLocation];
		return NO;
	}
	
	AFNetworkDomainRecord *newRecord = [[[AFNetworkDomainRecord alloc] initWithFullyQualifiedDomainName:recordName recordClass:recordClass recordType:recordType fields:recordFields] autorelease];
	[records addObject:newRecord];
	
	return YES;
}

- (NSSet *)recordsForFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType
{
	return nil;
}

@end
