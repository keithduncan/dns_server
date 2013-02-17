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

typedef uint16_t (*DNSRecordNumberFunction)(char const *, uint16_t *);

- (NSData *)_encodeType:(NSError **)errorRef {
	NSString *recordType = [self recordType];
	NSData *encodedType = [self _encodeString:recordType function:(DNSRecordNumberFunction)dns_type_number];
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

- (NSData *)_encodeClass:(NSError **)errorRef {
	NSString *recordClass = [self recordClass];
	NSData *encodedClass = [self _encodeString:recordClass function:(DNSRecordNumberFunction)dns_class_number];
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
	char const *stringBytes = [string UTF8String];
	uint16_t stringLength = strlen(stringBytes);
	
	int16_t number = htons(function(stringBytes, &stringLength));
	if (number == 0) {
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
		
		
	}
	else {
		if (errorRef != NULL) {
			NSDictionary *errorInfo = @{
				NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode data for type \u201c%@\u201d", @"AFNetworkDomainRecord encode data error description"), type],
			};
			*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
		}
		return nil;
	}
}

@end
