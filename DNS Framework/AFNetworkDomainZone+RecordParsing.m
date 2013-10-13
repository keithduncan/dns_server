//
//  AFNetworkDomainZone.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone+RecordParsing.h"
#import "AFNetworkDomainZone+AFNetworkPrivate.h"

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkDomainRecord.h"

@implementation AFNetworkDomainZone (AFNetworkRecordParsing)

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

static NSString *scanStringFromArray(NSScanner *scanner, NSArray *strings)
{
	NSUInteger longestMatchScanLocation = 0;
	NSString *longestMatch = nil;
	
	for (NSString *currentString in strings) {
		tryMatch(scanner, &longestMatchScanLocation, &longestMatch, ^ NSString * (NSScanner *innerScanner) {
			NSString *match = nil;
			if (![innerScanner scanString:currentString intoString:&match]) {
				return nil;
			}
			
			return match;
		});
	}
	
	if (longestMatch == nil) {
		return nil;
	}
	
	[scanner setScanLocation:longestMatchScanLocation];
	return longestMatch;
}

static NSString *scanCharacterFromSet(NSScanner *scanner, NSCharacterSet *characterSet)
{
	NSString *originalString = [scanner string];
	NSRange characterRange = [originalString rangeOfCharacterFromSet:characterSet options:NSAnchoredSearch range:NSMakeRange([scanner scanLocation], [originalString length] - [scanner scanLocation])];
	if (characterRange.location == NSNotFound) {
		return nil;
	}
	
	[scanner setScanLocation:NSMaxRange(characterRange)];
	
	return [originalString substringWithRange:characterRange];
}

static NSString *scanCharacterSetMinMax(NSScanner *scanner, NSCharacterSet *characterSet, NSUInteger min, NSUInteger max)
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
	NSString *newline = scanStringFromArray(scanner, @[ @"\n", @"\r\n" ]);
	if (newline == nil) {
		return NO;
	}
	return YES;
}

static BOOL scanWs(NSScanner *scanner, NSUInteger min, NSUInteger max)
{
	NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
	return (scanCharacterSetMinMax(scanner, whitespaceCharacterSet, min, max) != nil);
}

static void scanLws(NSScanner *scanner)
{
	scanWs(scanner, 0, NSUIntegerMax);
}

static NSCharacterSet *makeAlphaCharacterSet(void)
{
	NSMutableCharacterSet *alphaCharacterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	NSString *alphaCharacters = @"abcdefghijklmnopqrstuvwxyz";
	[alphaCharacterSet addCharactersInString:[alphaCharacters lowercaseString]];
	[alphaCharacterSet addCharactersInString:[alphaCharacters uppercaseString]];
	return alphaCharacterSet;
}

static NSCharacterSet *makeLabelCharacterSet(void)
{
	NSCharacterSet *alphaCharacterSet = makeAlphaCharacterSet();
	
	NSString *digitCharacters = @"0123456789";
	NSCharacterSet *digitCharacterSet = [NSCharacterSet characterSetWithCharactersInString:digitCharacters];
	
	NSMutableCharacterSet *labelCharacterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[labelCharacterSet formUnionWithCharacterSet:alphaCharacterSet];
	[labelCharacterSet formUnionWithCharacterSet:digitCharacterSet];
	[labelCharacterSet addCharactersInString:@"-"];
	[labelCharacterSet addCharactersInString:@"_"];
	
	return labelCharacterSet;
}

static NSString *scanLabel(NSScanner *scanner)
{
	return scanCharacterSetMinMax(scanner, makeLabelCharacterSet(), 1, NSUIntegerMax);
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

static NSCharacterSet *makeTextCharacterSet(void)
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
	return scanCharacterSetMinMax(scanner, makeTextCharacterSet(), 0, NSUIntegerMax);
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

static BOOL scanEof(NSScanner *scanner)
{
	return [scanner isAtEnd];
}

static BOOL scanEol(NSScanner *scanner)
{
	return (scanNewline(scanner) || scanEof(scanner));
}

#pragma mark -

- (NSSet *)_parseRecordsFromZoneString:(NSString *)zoneString error:(NSError **)errorRef
{
	NSScanner *zoneScanner = [NSScanner scannerWithString:zoneString];
	[zoneScanner setCharactersToBeSkipped:nil];
	
	NSSet *records = [self _scanZone:zoneScanner error:errorRef];
	if (records == nil) {
		return nil;
	}
	
	if (![zoneScanner isAtEnd]) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : @"Couldn\u2019t parse all the zone file entries, some data may be missing",
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
	return records;
}

- (NSSet *)_scanZone:(NSScanner *)zoneScanner error:(NSError **)errorRef
{
	NSUInteger recordCapacityHint = [[[zoneScanner string] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] count];
	// The order the records are read in is important for back references to record names and classes
	NSMutableArray *records = [NSMutableArray arrayWithCapacity:recordCapacityHint];
	
	while (![zoneScanner isAtEnd]) {
		BOOL scanLine = [self _scanLine:zoneScanner records:records error:errorRef];
		if (!scanLine) {
			break;
		}
	}
	
	return [NSSet setWithArray:records];
}

- (BOOL)_scanLine:(NSScanner *)scanner records:(NSMutableArray *)records error:(NSError **)errorRef
{
	NSUInteger lineNumber = [self _lineNumberForScanner:scanner];
	
	NSError *scanLineError = nil;
	BOOL scanLine = [self __scanLine:scanner records:records error:&scanLineError];
	if (!scanLine) {
		if (errorRef != NULL) {
			NSDictionary * (^dictionaryByAddingEntries)(NSDictionary *, NSDictionary *) = ^ NSDictionary * (NSDictionary *dictionary, NSDictionary *entries) {
				NSMutableDictionary *newDictionary = [NSMutableDictionary dictionaryWithDictionary:dictionary];
				[newDictionary addEntriesFromDictionary:entries];
				return newDictionary;
			};
			
			NSDictionary *errorInfo = dictionaryByAddingEntries([scanLineError userInfo], @{
				NSLocalizedFailureReasonErrorKey : [NSString stringWithFormat:NSLocalizedString(@"Line %lu is invalid", @"AFNetworkDomainZone RecordParsing error failure reason"), (unsigned long)lineNumber],
			});
			*errorRef = [NSError errorWithDomain:[scanLineError domain] code:[scanLineError code] userInfo:errorInfo];
		}
		return NO;
	}
	return YES;
}

- (NSUInteger)_lineNumberForScanner:(NSScanner *)scanner
{
	NSUInteger startLocation = [scanner scanLocation];
	
	__block NSUInteger lineIndex = 0;
	NSString *fullString = [scanner string];
	[fullString enumerateSubstringsInRange:NSMakeRange(0, [fullString length]) options:(NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired) usingBlock:^ (NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
		if (!NSLocationInRange(startLocation, enclosingRange)) {
			lineIndex++;
			return;
		}
		
		*stop = YES;
	}];
	return lineIndex + 1;
}

- (BOOL)__scanLine:(NSScanner *)scanner records:(NSMutableArray *)records error:(NSError **)errorRef
{
	BOOL match = NO;
	
	// Directive
	do {
		if (match) {
			break;
		}
		
		NSError *scanDirectiveError = nil;
		BOOL scanDirective = [self _scanDirective:scanner error:&scanDirectiveError];
		if (scanDirective) {
			match = YES;
			break;
		}
		
		if ([[scanDirectiveError domain] isEqualToString:AFNetworkDomainZoneInternalErrorDomain] && [scanDirectiveError code] == AFNetworkDomainZoneInternalErrorCodeNotMatch) {
			break;
		}
		
		if (errorRef != NULL) {
			*errorRef = scanDirectiveError;
		}
		return NO;
	} while (0);
	
	// Record
	do {
		if (match) {
			break;
		}
		
		NSError *scanRecordError = nil;
		BOOL scanRecord = [self _scanRecord:scanner intoArray:records error:&scanRecordError];
		if (scanRecord) {
			match = YES;
			break;
		}
		
		break;
	} while (0);
	
	// Blank
	do {
		if (match) {
			break;
		}
		
		scanLws(scanner);
		
		match = YES;
	} while (0);
	
	if (!match) {
		return [self __scanLineError:errorRef];
	}
	
	// LWS
	
	scanLws(scanner);
	
	// Comment
	
	__unused NSString *comment = scanComment(scanner);
	
	BOOL endOfLine = scanEol(scanner);
	if (!endOfLine) {
		return [self __scanLineError:errorRef];
	}
	
	return YES;
}

- (BOOL)__scanLineError:(NSError **)errorRef
{
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : NSLocalizedString(@"Lines must be directives, records or blank (with optional comment)", @"AFNetworkDomainZone RecordParsing line no match error description"),
		};
		*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneInternalErrorDomain code:AFNetworkDomainZoneInternalErrorCodeUnknown userInfo:errorInfo];
	}
	return NO;
}

- (BOOL)_scanDirective:(NSScanner *)scanner error:(NSError **)errorRef
{
	// Directive
	if (![scanner scanString:@"$" intoString:NULL]) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneInternalErrorDomain code:AFNetworkDomainZoneInternalErrorCodeNotMatch userInfo:nil];
		}
		return NO;
	}
	
	NSString *directiveName = scanCharacterSetMinMax(scanner, makeAlphaCharacterSet(), 1, NSUIntegerMax);
	
	if ([directiveName caseInsensitiveCompare:@"ORIGIN"] == NSOrderedSame) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"ORIGIN directive must be followed by a fully qualified domain name", @"AFNetworkDomainZone RecordParsing origin directive without fqdn error description"),
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		
		if (!scanWs(scanner, 1, NSUIntegerMax)) {
			return NO;
		}
		
		NSString *fqdn = scanFqdn(scanner);
		if (fqdn == nil) {
			return NO;
		}
		
		self.origin = fqdn;
		return YES;
	}
	
	if ([directiveName caseInsensitiveCompare:@"TTL"] == NSOrderedSame) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"TTL directive must be followed by a time value", @"AFNetworkDomainZone RecordParsing ttl directive without time value error description"),
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		
		if (!scanWs(scanner, 1, NSUIntegerMax)) {
			return NO;
		}
		
		NSTimeInterval ttl = [self _scanTimeValue:scanner];
		if (ttl == -1) {
			return NO;
		}
		
		self.ttl = ttl;
		return YES;
	}
	
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot process directive \u201c%@\u201d", @"AFNetworkDomainZone RecordParsing unknown directive error description"), directiveName],
		};
		*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
	}
	return NO;
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
	NSCharacterSet *alphaCharacterSet = makeAlphaCharacterSet();
	return scanCharacterSetMinMax(scanner, alphaCharacterSet, 1, NSUIntegerMax);
}

static NSCharacterSet *commonExcludedCharacterSet(void)
{
	NSMutableCharacterSet *characterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[characterSet addCharactersInString:@";()"];
	[characterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
	return characterSet;
}

static NSCharacterSet *makeExcludedCharacterSet(void)
{
	NSMutableCharacterSet *characterSet = [[[NSMutableCharacterSet alloc] init] autorelease];
	[characterSet addCharactersInString:@"\""];
	[characterSet formUnionWithCharacterSet:commonExcludedCharacterSet()];
	return characterSet;
}

static NSCharacterSet *makeInnerDataCharacterSet(void)
{
	NSMutableCharacterSet *innerDataCharacterSet = [[makeTextCharacterSet() mutableCopy] autorelease];
	[innerDataCharacterSet formIntersectionWithCharacterSet:[makeExcludedCharacterSet() invertedSet]];
	return innerDataCharacterSet;
}

static NSString *scanInnerData(NSScanner *scanner, NSUInteger min, NSUInteger max)
{
	return scanCharacterSetMinMax(scanner, makeInnerDataCharacterSet(), min, max);
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

- (BOOL)_scanRecord:(NSScanner *)recordScanner intoArray:(NSMutableArray *)records error:(NSError **)errorRef
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
				break;
			}
			
			recordName = [previousRecord fullyQualifiedDomainName];
		}
	} while (0);
	
	if (recordName == nil) {
		[recordScanner setScanLocation:startLocation];
		
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"No record name given and no prior record name to use", @"AFNetworkDomainZone ResourceParsing no name error description"),
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
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
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : NSLocalizedString(@"No record TTL given and no $TTL directive to give a default", @"AFNetworkDomainZone ResourceParsing no TTL error description"),
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return NO;
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
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"No record class given and no prior record class to use", @"AFNetworkDomainZone ResourceParsing no class error description"),
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
	NSString *recordType = scanType(recordScanner);
	do {
		if (recordType == nil) {
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : NSLocalizedString(@"No record type given, type is required", @"AFNetworkDomainZone ResourceParsing no type error description"),
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return NO;
		}
		
		BOOL ws = scanWs(recordScanner, 1, NSUIntegerMax);
		if (!ws) {
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : NSLocalizedString(@"No whitespace following record type, this is required to separate the type from the record data", @"AFNetworkDomainZone ResourceParsing no whitespace after type error description"),
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return NO;
		}
	} while (0);
	
	NSArray *recordFields = scanRdata(recordScanner);
	if (recordFields == nil) {
		[recordScanner setScanLocation:startLocation];
		
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : NSLocalizedString(@"No record data given, record data is required", @"AFNetworkDomainZone ResourceParsing no record data error description"),
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return NO;
	}
	
	AFNetworkDomainRecord *newRecord = [[[AFNetworkDomainRecord alloc] initWithFullyQualifiedDomainName:recordName ttl:recordTtl recordClass:recordClass recordType:recordType fields:recordFields] autorelease];
	
	[records addObject:newRecord];
	return YES;
}

@end
