//
//  AFNetworkDomainServer.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainServer.h"

#import <dns_util.h>

#import "AFNetworkDomainZone.h"
#import "AFNetworkDomainRecord.h"

@interface AFNetworkDomainServer () <AFNetworkSocketHostDelegate>
@property (retain, nonatomic) NSMutableSet *zones;
@end

@implementation AFNetworkDomainServer

- (id)init
{
	self = [super init];
	if (self == nil) {
		return nil;
	}
	
	_zones = [[NSMutableSet alloc] init];
	
	return self;
}

- (void)dealloc
{
	[_zones release];
	
	[super dealloc];
}

- (void)addZone:(AFNetworkDomainZone *)zone
{
	[self.zones addObject:zone];
}

/*
	Note
	
	implemented on the basis of <http://tools.ietf.org/html/rfc1035>
 */

enum DNSFlag {
	DNSFlag_QueryResponse,
	DNSFlag_Opcode,
	DNSFlag_AA,
	DNSFlag_TC,
	DNSFlag_RD,
	DNSFlag_RA,
	DNSFlag_Z,
	DNSFlag_Rcode,
};

struct _DNSFlagMap {
	enum DNSFlag flag;
	int mask;
	int shift;
} const flagsMap[] = {
	{ .flag = DNSFlag_QueryResponse, .mask = 1, .shift = 16, },
	{ .flag = DNSFlag_Opcode, .mask = 15, .shift = 11, },
	{ .flag = DNSFlag_AA, .mask = 1, .shift = 8, },
	{ .flag = DNSFlag_TC, .mask = 1, .shift = 7, },
	{ .flag = DNSFlag_RD, .mask = 1, .shift = 6, },
	{ .flag = DNSFlag_RA, .mask = 1, .shift = 5, },
	{ .flag = DNSFlag_Z, .mask = 7, .shift = 4, },
	{ .flag = DNSFlag_Rcode, .mask = 15, .shift = 0, },
};

static struct _DNSFlagMap const *_DNSFlagMapForFlag(enum DNSFlag flag)
{
	struct _DNSFlagMap const *mapRef = NULL;
	for (size_t idx = 0; idx < sizeof(flagsMap)/sizeof(*flagsMap); idx++) {
		if (flagsMap[idx].flag != flag) {
			continue;
		}
		
		mapRef = &flagsMap[idx];
		break;
	}
	return mapRef;
}

static int DNSFlagsGet(uint16_t flags, enum DNSFlag flag)
{
	struct _DNSFlagMap const *mapRef = _DNSFlagMapForFlag(flag);
	NSCParameterAssert(mapRef != NULL);
	
	int shift = mapRef->shift;
	return (flags & (mapRef->mask << shift)) >> shift;
}

static void DNSFlagsSet(uint16_t *flagsRef, enum DNSFlag flag, int value)
{
	struct _DNSFlagMap const *mapRef = _DNSFlagMapForFlag(flag);
	NSCParameterAssert(mapRef != NULL);
	
	NSCParameterAssert((mapRef->mask & value) == value);
	
	*flagsRef = (*flagsRef | (value << mapRef->shift));
}

typedef NS_ENUM(int, DNSQueryResponse)
{
	DNSQueryResponse_Query = 0,
	DNSQueryResponse_Response = 1,
};

typedef NS_ENUM(int, DNSOpcode)
{
	DNSOpcode_Standard = 0,
	DNSOpcode_Inverse = 1,
	DNSOpcode_Status = 2,
};

typedef NS_ENUM(int, DNSRcode)
{
	DNSRcode_OK = 0,
	DNSRcode_FormatError = 1,
	DNSRcode_ServerFailure = 2,
	DNSRcode_NameError = 3,
	DNSRcode_NotImplemented = 4,
	DNSRcode_Refused = 5,
};

static BOOL SafeGetBytes(NSData *data, uint8_t *bytes, NSRange range)
{
	NSRange intersection = NSIntersectionRange(NSMakeRange(0, [data length]), range);
	if (!NSEqualRanges(intersection, range)) {
		return NO;
	}
	
	[data getBytes:bytes range:range];
	return YES;
}

static BOOL LengthByteIsLength(uint8_t length)
{
	return (length & /* 0b11000000 */ 192) == 0;
}

static BOOL LengthByteIsPointer(uint8_t length)
{
	return (length & /* 0b11000000 */ 192) == 192;
}

typedef NS_ENUM(NSUInteger, DNSLengthType)
{
	DNSLengthType_Invalid,
	DNSLengthType_Root,
	DNSLengthType_Length,
	DNSLengthType_Pointer,
};

static DNSLengthType LengthByteGetType(uint8_t length)
{
	if (LengthByteIsLength(length)) {
		if (length == 0) {
			return DNSLengthType_Root;
		}
		else {
			return DNSLengthType_Length;
		}
	}
	else if (LengthByteIsPointer(length)) {
		return DNSLengthType_Pointer;
	}
	else {
		return DNSLengthType_Invalid;
	}
}

static NSString *ParseNameFromMessage(NSData *message, /* inout */ size_t *cursorRef)
{
	NSMutableArray *accumulation = [NSMutableArray array];
	
	size_t startCursor = *cursorRef;
	
	while (1) {
		uint8_t lengthByte = 0;
		NSRange lengthByteRange = NSMakeRange(*cursorRef, sizeof(lengthByte));
		
		if (!SafeGetBytes(message, &lengthByte, lengthByteRange)) {
			return nil;
		}
		*cursorRef = NSMaxRange(lengthByteRange);
		
		switch (LengthByteGetType(lengthByte)) {
			case DNSLengthType_Invalid:
			{
				return nil;
			}
			case DNSLengthType_Root:
			{
				[accumulation addObject:@""];
				goto Return;
			}
			case DNSLengthType_Length:
			{
				uint8_t labelBytes[lengthByte];
				if (!SafeGetBytes(message, labelBytes, NSMakeRange(*cursorRef, lengthByte))) {
					return nil;
				}
				*cursorRef += lengthByte;
				
				NSString *label = [[[NSString alloc] initWithBytes:labelBytes length:lengthByte encoding:NSASCIIStringEncoding] autorelease];
				[accumulation addObject:label];
				break;
			}
			case DNSLengthType_Pointer:
			{
				uint8_t suffixCursorTopBits = (lengthByte & /* 0b00111111 */ 63);
				
				uint8_t suffixCursorBottomBits = 0;
				NSRange suffixCursorBottomBitsRange = NSMakeRange(*cursorRef, 1);
				if (!SafeGetBytes(message, &suffixCursorBottomBits, suffixCursorBottomBitsRange)) {
					return nil;
				}
				*cursorRef = NSMaxRange(suffixCursorBottomBitsRange);
				
				size_t suffixCursor = (uint16_t)suffixCursorTopBits | (uint16_t)suffixCursorBottomBits;
				
				/*
					Note
					
					<http://tools.ietf.org/html/rfc1035#section-4.1.4> limits pointers to prior occurrences to prevent infinite loops
				 */
				if (suffixCursor >= startCursor) {
					return nil;
				}
				
				NSString *suffix = ParseNameFromMessage(message, &suffixCursor);
				if (suffix == nil) {
					return nil;
				}
				
				[accumulation addObject:suffix];
				goto Return;
			}
		}
	}
	
Return:
	return [accumulation componentsJoinedByString:@"."];
}

static NSUInteger DNSQuestionSizeFunction(void const *item)
{
	return sizeof(dns_question_t);
}

static void *DNSQuestionAcquireFunction(const void *src, NSUInteger (*size)(const void *item), BOOL shouldCopy)
{
	NSCParameterAssert(size(src) == DNSQuestionSizeFunction(src));
	NSCParameterAssert(shouldCopy);
	
	dns_question_t *originalQuestion = (dns_question_t *)src;
	
	dns_question_t *newQuestion = malloc(sizeof(dns_question_t));
	newQuestion->name = strdup(originalQuestion->name);
	newQuestion->dnstype = originalQuestion->dnstype;
	newQuestion->dnsclass = originalQuestion->dnsclass;
	return newQuestion;
}

static void DNSQuestionRelinquishFunction(const void *item, NSUInteger (*size)(const void *item))
{
	dns_question_t *question = (dns_question_t *)item;
	free(question->name);
	free(question);
}

- (void)networkLayer:(AFNetworkSocket *)socket didReceiveDatagram:(AFNetworkDatagram *)datagram
{
	NSData *message = datagram.data;
	
	size_t cursor = 0;
	
	dns_header_t requestHeader = {};
	NSRange requestHeaderRange = NSMakeRange(cursor, sizeof(requestHeader));
	
	if (!SafeGetBytes(message, (uint8_t *)&requestHeader, requestHeaderRange)) {
		return;
	}
	cursor = NSMaxRange(requestHeaderRange);
	
	uint16_t flags = requestHeader.flags;
	
	if (DNSFlagsGet(flags, DNSFlag_QueryResponse) != DNSQueryResponse_Query) {
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_Opcode) != DNSOpcode_Standard) {
		dns_header_t responseHeader = {
			.xid = requestHeader.xid,
		};
		
		DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, 1);
		DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_NotImplemented);
		
		[self _sendResponse:[NSData dataWithBytes:&responseHeader length:sizeof(responseHeader)] from:socket forRequest:datagram];
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_RD) != 0) {
		dns_header_t responseHeader = {
			.xid = requestHeader.xid,
		};
		
		DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, 1);
		DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_Refused);
		
		[self _sendResponse:[NSData dataWithBytes:(uint8_t const *)&responseHeader length:sizeof(responseHeader)] from:socket forRequest:datagram];
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_Z) != 0) {
		return;
	}
	
	NSPointerFunctions *questionsPointerFunctions = [[NSPointerFunctions alloc] initWithOptions:(NSPointerFunctionsMallocMemory | NSPointerFunctionsStructPersonality | NSPointerFunctionsCopyIn)];
	questionsPointerFunctions.sizeFunction = DNSQuestionSizeFunction;
	questionsPointerFunctions.acquireFunction = DNSQuestionAcquireFunction;
	questionsPointerFunctions.relinquishFunction = DNSQuestionRelinquishFunction;
	
	NSPointerArray *questions = [NSPointerArray pointerArrayWithPointerFunctions:questionsPointerFunctions];
	
	uint16_t questionCount = ntohs(requestHeader.qdcount);
	for (size_t questionIdx = 0; questionIdx < questionCount; questionIdx++) {
		size_t currentCursor = cursor;
		
		dns_question_t currentQuestion = {};
		
		NSString *name = ParseNameFromMessage(message, &currentCursor);
		if (name == nil) {
			return;
		}
		currentQuestion.name = (char *)[name UTF8String];
		
		NSRange currentQuestionTypeRange = NSMakeRange(currentCursor, 2);
		if (!SafeGetBytes(message, (uint8_t *)&currentQuestion.dnstype, currentQuestionTypeRange)) {
			return;
		}
		currentCursor = NSMaxRange(currentQuestionTypeRange);
		
		/*
			Note
			
			need to disambiguate QU (question unicast) from QM (question multicast)
			
			<https://tools.ietf.org/html/draft-cheshire-dnsext-multicastdns-15#section-5.4>
			
			without building multicast specific support into the generic domain server
		 */
#warning if the top bit of the class (in network order) is set this is a QU (question unicast), rather than a QM (question multicast), class IN (Internet) therefore has the class 0x8001
		
		NSRange currentQuestionClassRange = NSMakeRange(currentCursor, 2);
		if (!SafeGetBytes(message, (uint8_t *)&currentQuestion.dnsclass, currentQuestionClassRange)) {
			return;
		}
		currentCursor = NSMaxRange(currentQuestionClassRange);
		
		[questions addPointer:&currentQuestion];
		
		cursor = currentCursor;
	}
	
	NSMutableSet *answerRecords = [NSMutableSet set];
	
	for (NSUInteger idx = 0; idx < questions.count; idx++) {
		dns_question_t *currentQuestion = [questions pointerAtIndex:idx];
		
		char const *classStringBytes = dns_class_string(ntohs(currentQuestion->dnsclass));
		if (classStringBytes == NULL) {
			continue;
		}
		NSString *classString = [[NSString stringWithUTF8String:classStringBytes] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		
		char const *typeStringBytes = dns_type_string(ntohs(currentQuestion->dnstype));
		if (typeStringBytes == NULL) {
			continue;
		}
		NSString *typeString = [[NSString stringWithUTF8String:typeStringBytes] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		
		char const *nameStringBytes = currentQuestion->name;
		NSString *nameString = [NSString stringWithUTF8String:nameStringBytes];
		
		for (AFNetworkDomainZone *currentZone in self.zones) {
			[answerRecords unionSet:[currentZone recordsForFullyQualifiedDomainName:nameString recordClass:classString recordType:typeString]];
		}
	}
	
	dns_header_t responseHeader = {
		.xid = requestHeader.xid,
		.ancount = htons(answerRecords.count),
	};
	
	DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, 1);
	DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_OK);
	
	NSMutableData *response = [NSMutableData data];
	[response appendBytes:&responseHeader length:sizeof(responseHeader)];
	
	for (AFNetworkDomainRecord *currentRecord in answerRecords) {
		NSData *currentRecordData = [currentRecord encodeRecord:NULL];
		if (currentRecordData == nil) {
			return;
		}
		
		[response appendData:currentRecordData];
	}
	
	[self _sendResponse:response from:socket forRequest:datagram];
}

- (void)_sendResponse:(NSData *)response from:(AFNetworkSocket *)receiver forRequest:(AFNetworkDatagram *)datagram
{
#warning needs to branch based on the transport type and prepend a 16-bit (network byte order) message length for TCP transports
	
#warning needs to respect the 512 byte limit for unicast DNS and the destination interface MTU for multicast DNS responses (and set the truncation bit)
	
	NSData *localAddressData = [receiver localAddress];
	
	CFRetain(localAddressData);
	struct sockaddr_storage const *localAddress = (struct sockaddr_storage const *)[localAddressData bytes];
	
	CFSocketNativeHandle newSocketNative = socket(localAddress->ss_family, SOCK_DGRAM, IPPROTO_UDP);
	if (newSocketNative == -1) {
		CFRelease(localAddressData);
		return;
	}
	
	int reuseAddress = 1;
	__unused int reuseAddressError = setsockopt(newSocketNative, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, sizeof(reuseAddress));
	if (reuseAddressError != 0) {
		CFRelease(localAddressData);
		
		close(newSocketNative);
		return;
	}
	
	int bindError = bind(newSocketNative, (struct sockaddr const *)localAddress, localAddress->ss_len);
	if (bindError != 0) {
		CFRelease(localAddressData);
		
		close(newSocketNative);
		return;
	}
	
	CFRetain(response);
	
	ssize_t sent = sendto(newSocketNative, [response bytes], [response length], /* int flags */ 0, localAddress, localAddress->ss_len);
	
	CFRelease(localAddressData);
	CFRelease(response);

	if (sent == -1) {
		return;
	}
}

@end
