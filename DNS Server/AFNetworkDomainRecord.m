//
//  AFNetworkDomainRecord.m
//  DNS Server
//
//  Created by Keith Duncan on 06/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainRecord.h"

#import <dns_util.h>
#import "CoreNetworking/CoreNetworking.h"

#import "AFNEtworkDomainZone.h"

@interface AFNetworkDomainRecord ()
@property (readwrite, copy, nonatomic) NSString *fullyQualifiedDomainName;

@property (readwrite, assign, nonatomic) NSTimeInterval ttl;

@property (readwrite, copy, nonatomic) NSString *recordClass;
@property (readwrite, copy, nonatomic) NSString *recordType;

@property (readwrite, copy, nonatomic) NSArray *fields;
@end

@implementation AFNetworkDomainRecord

- (id)initWithFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName ttl:(NSTimeInterval)ttl recordClass:(NSString *)recordClass recordType:(NSString *)recordType fields:(NSArray *)fields
{
	self = [self init];
	if (self == nil) {
		return nil;
	}
	
	_fullyQualifiedDomainName = [fullyQualifiedDomainName copy];
	
	_ttl = ttl;
	
	_recordClass = [recordClass copy];
	_recordType = [recordType copy];
	
	_fields = [fields copy];
	
	return self;
}

- (void)dealloc {
	[_fullyQualifiedDomainName release];
	
	[_recordClass copy];
	[_recordType copy];
	
	[_fields release];
	
	[super dealloc];
}

- (NSData *)encodeRecord:(NSError **)errorRef {
	// <http://tools.ietf.org/html/rfc1035#section-4.1.3>
	
	NSMutableData *encodedRecord = [NSMutableData data];
	
	NSData *encodedName = [self _encodedFullyQualifiedDomainName:errorRef];
	if (encodedName == nil) {
		return nil;
	}
	[encodedRecord appendData:encodedName];
	
	NSData *encodedType = [self _encodeType:errorRef];
	if (encodedType == nil) {
		return nil;
	}
	[encodedRecord appendData:encodedType];
	
	NSData *encodedClass = [self _encodeClass:errorRef];
	if (encodedClass == nil) {
		return nil;
	}
	[encodedRecord appendData:encodedClass];
	
	[encodedRecord appendData:[self _encodeTtl]];
	
	NSData *encodedFields = [self _encodeFields:errorRef];
	if (encodedFields == nil) {
		return nil;
	}
	[encodedRecord appendData:encodedFields];
	
	return encodedRecord;
}

- (NSData *)_encodedFullyQualifiedDomainName:(NSError **)errorRef {
	NSMutableData *encodedName = [NSMutableData data];
	for (NSString *currentLabel in [self.fullyQualifiedDomainName componentsSeparatedByString:@"."]) {
		NSData *currentLabelData = [currentLabel dataUsingEncoding:NSASCIIStringEncoding];
		if (currentLabelData == nil) {
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Label \u201c%@\u201d cannot be encoded as ASCII", @"AFNetworkDomainRecord encode name charset error description"), currentLabel],
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return nil;
		}
		
		NSUInteger labelLength = [currentLabelData length];
		if (labelLength > 63) {
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Label \u201c%@\u201d is longer than 63 characters, labels must be 63 characters or fewer", @"AFNetworkDomainRecord encode name length error description"), currentLabel],
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return nil;
		}
		
		uint8_t length = htons(labelLength);
		[encodedName appendBytes:&length length:1];
		
		[encodedName appendData:currentLabelData];
	}
	return encodedName;
}

typedef int32_t (*DNSRecordNumberFunction)(NSString *, uint16_t *);

static int32_t DNSRecordTypeFunction(NSString *type, uint16_t *numberRef)
{
	NSDictionary *map = @{
		@"SPF" : @(99),
	};
	NSNumber *value = map[[type uppercaseString]];
	if (value != nil) {
		*numberRef = [value integerValue];
		return (int32_t)0;
	}
	
	return dns_type_number([type UTF8String], numberRef);
}

- (NSData *)_encodeType:(NSError **)errorRef {
	NSString *recordType = [self recordType];
	NSData *encodedType = [self _encodeString:recordType function:(DNSRecordNumberFunction)DNSRecordTypeFunction];
	if (encodedType == nil) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode type \u201c%@\u201d", @"AFNetworkDomainRecord encode type error description"), recordType],
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return nil;
	}
	
	return encodedType;
}

static int32_t DNSRecordClassFunction(NSString *class, uint16_t *numberRef)
{
	return dns_class_number([class UTF8String], numberRef);
}

- (NSData *)_encodeClass:(NSError **)errorRef {
	NSString *recordClass = [self recordClass];
	NSData *encodedClass = [self _encodeString:recordClass function:(DNSRecordNumberFunction)DNSRecordClassFunction];
	if (encodedClass == nil) {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode class \u201c%@\u201d", @"AFNetworkDomainRecord encode class error description"), recordClass],
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return nil;
	}
	
	return encodedClass;
}

- (NSData *)_encodeString:(NSString *)string function:(DNSRecordNumberFunction)function {
	uint16_t number = 0;
	int32_t numberError = function(string, &number);
	if (numberError != 0) {
		return nil;
	}
	
	return [NSData dataWithBytes:&number length:sizeof(number)];
}

- (NSData *)_encodeTtl {
	uint32_t integerTtl = htonl((uint32_t)self.ttl);
	return [NSData dataWithBytes:&integerTtl length:sizeof(integerTtl)];
}

- (NSData *)_encodeFields:(NSError **)errorRef {
	NSMutableData *encodedFields = [NSMutableData data];
	
	NSData *encodedRdata = [self _encodedRdata:errorRef];
	if (encodedRdata == nil) {
		return nil;
	}
	
	uint16_t rdlength = htons((uint16_t)[encodedRdata length]);
	[encodedFields appendBytes:&rdlength length:sizeof(rdlength)];
	
	[encodedFields appendData:encodedRdata];
	
	return encodedFields;
}

- (NSData *)_encodedRdata:(NSError **)errorRef {
	NSString *type = self.recordType;
	NSArray *fields = self.fields;
	
	NSError * (^invalidFieldsError)(NSUInteger) = ^ NSError * (NSUInteger expectedCount) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode data fields given for type \u201c%@\u201d, expected %lu fields", @"AFNetworkDomainRecord encode fields error description"), type, expectedCount],
		};
		return [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
	};
	
	NSString * (^onlyField)(void) = ^ NSString * (void) {
		if (fields == nil || fields.count != 1) {
			if (errorRef != NULL) {
				*errorRef = invalidFieldsError(1);
			}
			return nil;
		}
		return [fields lastObject];
	};
	
	if ([type caseInsensitiveCompare:@"A"] == NSOrderedSame) {
		// <http://tools.ietf.org/html/rfc1035#section-3.4.1>
		
		NSString *presentation = onlyField();
		if (presentation == nil) {
			return nil;
		}
		
		NSError *addressError = nil;
		NSData *address = AFNetworkSocketPresentationToAddress(presentation, &addressError);
		if (address == nil) {
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode IPv4 address for string \u201c%@\u201d", @"AFNetworkDomainRecord encode IPv4 address error description"), presentation],
					NSUnderlyingErrorKey : addressError,
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return nil;
		}
		
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"AAAA"] == NSOrderedSame) {
		// <http://tools.ietf.org/html/rfc3596#section-2.2>
		
		NSString *presentation = onlyField();
		if (presentation == nil) {
			return nil;
		}
		
		NSError *addressError = nil;
		NSData *address = AFNetworkSocketPresentationToAddress(presentation, &addressError);
		if (address == nil) {
			if (errorRef != NULL) {
				NSDictionary *errorInfo = @{
					NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode IPv4 address for string \u201c%@\u201d", @"AFNetworkDomainRecord encode IPv4 address error description"), presentation],
					NSUnderlyingErrorKey : addressError,
				};
				*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
			}
			return nil;
		}
		
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"MX"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"NS"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"PTR"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"SOA"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"SRV"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"TXT"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"CNAME"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"NAPTR"]) {
#warning complete me
		return [NSData data];
	}
	else if ([type caseInsensitiveCompare:@"SPF"]) {
#warning complete me
		return [NSData data];
	}
	
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode data for type \u201c%@\u201d", @"AFNetworkDomainRecord encode data error description"), type],
		};
		*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
	}
	return nil;
}

@end
