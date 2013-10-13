//
//  AFNetworkDomainRecord.m
//  DNS Server
//
//  Created by Keith Duncan on 06/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainRecord.h"

#import <objc/message.h>
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

		[encodedName appendBytes:&labelLength length:1];
		
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

	number = htons(number);

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
	
	NSString *encodeSelectorString = [NSString stringWithFormat:@"_encode%@:", [type uppercaseString]];
	SEL encodeSelector = NSSelectorFromString(encodeSelectorString);
	if ([self respondsToSelector:encodeSelector]) {
		NSData *encoded = ((NSData * (*)(id, SEL, NSError **))objc_msgSend)(self, encodeSelector, errorRef);
		return encoded;
	}
	
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode data for type \u201c%@\u201d", @"AFNetworkDomainRecord encode data error description"), type],
		};
		*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
	}
	return nil;
}

- (NSString *)_onlyField:(NSError **)errorRef
{
	NSArray *fields = self.fields;
	
	if (fields == nil || fields.count != 1) {
		return [self _invalidFields:1 error:errorRef];
	}
	
	return [fields lastObject];
}

- (NSString *)_invalidFields:(NSUInteger)expectedCount error:(NSError **)errorRef
{
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode data fields given for type \u201c%@\u201d, expected %lu fields", @"AFNetworkDomainRecord encode fields error description"), self.recordType, expectedCount],
		};
		*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
	}
	return nil;
}

- (NSData *)_encodeA:(NSError **)errorRef
{
	// <http://tools.ietf.org/html/rfc1035#section-3.4.1>
	
	NSString *presentation = [self _onlyField:errorRef];
	if (presentation == nil) {
		return nil;
	}
	
	NSError *socketAddressDataError = nil;
	NSData *socketAddressData = AFNetworkSocketPresentationToAddress(presentation, &socketAddressDataError);
	if (socketAddressData == nil) {
		return [self _cannotEncodeIpv4:presentation error:errorRef];
	}
	
	if ([socketAddressData length] != sizeof(struct sockaddr_in)) {
		return [self _cannotEncodeIpv4:presentation error:errorRef];
	}
	
	CFRetain(socketAddressData);
	struct sockaddr_storage const *socketAddress = (struct sockaddr_storage const *)[socketAddressData bytes];
	
	if (socketAddress->ss_family != AF_INET) {
		CFRelease(socketAddressData);
		
		return [self _cannotEncodeIpv4:presentation error:errorRef];
	}
	
	struct sockaddr_in const *socketAddressV4 = (struct sockaddr_in const *)socketAddress;
	struct in_addr internetAddress = socketAddressV4->sin_addr;
	
	CFRelease(socketAddressData);
	
	return [NSData dataWithBytes:&internetAddress length:sizeof(internetAddress)];
}

- (NSData *)_cannotEncodeIpv4:(NSString *)presentation error:(NSError **)errorRef
{
	return [self __cannotEncodeIPv:@"IPv4" presentation:presentation error:errorRef];
}

- (NSData *)_encodeAAAA:(NSError **)errorRef
{
	// <http://tools.ietf.org/html/rfc3596#section-2.2>
	
	NSString *presentation = [self _onlyField:errorRef];
	if (presentation == nil) {
		return nil;
	}
	
	NSError *socketAddressDataError = nil;
	NSData *socketAddressData = AFNetworkSocketPresentationToAddress(presentation, &socketAddressDataError);
	if (socketAddressData == nil) {
		return [self _cannotEncodeIpv6:presentation error:errorRef];
	}
	
	if ([socketAddressData length] != sizeof(struct sockaddr_in6)) {
		return [self _cannotEncodeIpv6:presentation error:errorRef];
	}
	
	CFRetain(socketAddressData);
	struct sockaddr_storage const *socketAddress = (struct sockaddr_storage const *)[socketAddressData bytes];
	
	if (socketAddress->ss_family != AF_INET6) {
		CFRelease(socketAddressData);
		
		return [self _cannotEncodeIpv6:presentation error:errorRef];
	}
	
	struct sockaddr_in6 const *socketAddressV6 = (struct sockaddr_in6 const *)socketAddress;
	struct in6_addr internetAddress = socketAddressV6->sin6_addr;
	
	CFRelease(socketAddressData);
	
#define BYTES internetAddress.__u6_addr.__u6_addr8
	NSUInteger length = (sizeof(BYTES) / sizeof(*BYTES));
	return [NSData dataWithBytes:&BYTES length:length];
#undef BYTES
}

- (NSData *)_cannotEncodeIpv6:(NSString *)presentation error:(NSError **)errorRef
{
	return [self __cannotEncodeIPv:@"IPv6" presentation:presentation error:errorRef];
}

- (NSData *)__cannotEncodeIPv:(NSString *)ipv presentation:(NSString *)presentation error:(NSError **)errorRef
{
	if (errorRef != NULL) {
		NSDictionary *errorInfo = @{
			NSLocalizedDescriptionKey : [NSString stringWithFormat:NSLocalizedString(@"Cannot encode %@ address for string \u201c%@\u201d", @"AFNetworkDomainRecord encode IPv6 address error description"), ipv, presentation],
		};
		*errorRef = [NSError errorWithDomain:AFNetworkDomainZoneErrorDomain code:AFNetworkDomainZoneErrorCodeUnknown userInfo:errorInfo];
	}
	return nil;
}

- (NSData *)_encodeMX:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeNS:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodePTR:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeSOA:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeSRV:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeTXT:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeCNAME:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeNAPTR:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

- (NSData *)_encodeSPF:(NSError **)errorRef
{
#warning complete me
	return [NSData data];
}

@end