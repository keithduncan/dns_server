//
//  AFNetworkDomainServer.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainServer.h"

#define __APPLE_USE_RFC_3542
#import <netinet/in.h>
#import <dns_util.h>

#import "AFNetworkDomainZone.h"
#import "AFNetworkDomainRecord.h"

@interface AFNetworkDomainServer () <AFNetworkSocketHostDelegate>
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

/*
	Note
	
	implemented on the basis of <http://tools.ietf.org/html/rfc1035>
 */

typedef enum {
	DNSFlag_QueryResponse,
	DNSFlag_Opcode,
	DNSFlag_AuthoritativeAnswer,
	DNSFlag_Truncated,
	DNSFlag_RecursionDesired,
	DNSFlag_RecursionAvailable,
	DNSFlag_Zero,
	DNSFlag_Rcode,
} DNSFlag;

static struct _DNSFlagMap {
	DNSFlag flag;
	int mask;
	int shift;
} const flagsMap[] = {
	{ .flag = DNSFlag_QueryResponse, .mask = 1, .shift = 15, },
	{ .flag = DNSFlag_Opcode, .mask = 15, .shift = 11, },
	{ .flag = DNSFlag_AuthoritativeAnswer, .mask = 1, .shift = 10, },
	{ .flag = DNSFlag_Truncated, .mask = 1, .shift = 9, },
	{ .flag = DNSFlag_RecursionDesired, .mask = 1, .shift = 8, },
	{ .flag = DNSFlag_RecursionAvailable, .mask = 1, .shift = 7, },
	{ .flag = DNSFlag_Zero, .mask = 7, .shift = 4, },
	{ .flag = DNSFlag_Rcode, .mask = 15, .shift = 0, },
};

static struct _DNSFlagMap const *_DNSFlagMapForFlag(DNSFlag flag)
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

static int DNSFlagsGet(uint16_t flags, DNSFlag flag)
{
	struct _DNSFlagMap const *mapRef = _DNSFlagMapForFlag(flag);
	NSCParameterAssert(mapRef != NULL);

	return (ntohs(flags) >> mapRef->shift) & mapRef->mask;
}

static void DNSFlagsSet(uint16_t *flagsRef, DNSFlag flag, int value)
{
	struct _DNSFlagMap const *mapRef = _DNSFlagMapForFlag(flag);
	NSCParameterAssert(mapRef != NULL);
	
	NSCParameterAssert((mapRef->mask & value) == value);
	
	*flagsRef = htons(ntohs(*flagsRef) | (value << mapRef->shift));
}

enum DNSQueryResponse : int
{
	DNSQueryResponse_Query = 0,
	DNSQueryResponse_Response = 1,
};

enum DNSAuthoritativeAnswer : int
{
	DNSAuthoritativeAnswer_NotAuthoritative = 0,
	DNSAuthoritativeAnswer_Authoritative = 1,
};

enum DNSOpcode : int
{
	DNSOpcode_Standard = 0,
	DNSOpcode_Inverse = 1,
	DNSOpcode_Status = 2,
};

enum DNSRcode : int
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

typedef enum : NSUInteger
{
	DNSLengthType_Invalid,
	DNSLengthType_Root,
	DNSLengthType_Length,
	DNSLengthType_Pointer,
} DNSLengthType;

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

- (void)networkLayer:(AFNetworkSocket *)receiver didReceiveDatagram:(AFNetworkDatagram *)datagram
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
		
		DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, DNSQueryResponse_Response);
		DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_NotImplemented);
		
		[self _socket:receiver didReceiveQuery:datagram shouldSendResponse:[NSData dataWithBytes:&responseHeader length:sizeof(responseHeader)] preferUnicast:NO];
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_RecursionDesired) != 0) {
		dns_header_t responseHeader = {
			.xid = requestHeader.xid,
		};
		
		DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, DNSQueryResponse_Response);
		DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_Refused);
		
		[self _socket:receiver didReceiveQuery:datagram shouldSendResponse:[NSData dataWithBytes:&responseHeader length:sizeof(responseHeader)] preferUnicast:NO];
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_Zero) != 0) {
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
		
		NSRange currentQuestionClassRange = NSMakeRange(currentCursor, 2);
		if (!SafeGetBytes(message, (uint8_t *)&currentQuestion.dnsclass, currentQuestionClassRange)) {
			return;
		}
		currentCursor = NSMaxRange(currentQuestionClassRange);
		
		[questions addPointer:&currentQuestion];
		
		cursor = currentCursor;
	}
	
	NSMutableSet *answerRecords = [NSMutableSet set];
	
	NSSet *zones = self.zones;
	
	BOOL preferUnicast = NO;
	
	for (NSUInteger idx = 0; idx < questions.count; idx++) {
		dns_question_t *currentQuestion = [questions pointerAtIndex:idx];
		
		uint16_t class = ntohs(currentQuestion->dnsclass);
		
		/*
			mDNS extension
			
			if the top bit is set of the class, a unicast response is preferred
		 */
		if (class >> 15 == 1) {
			class = class & ~(1 << 15);
			preferUnicast |= YES;
		}
		
		char const *classStringBytes = dns_class_string(class);
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
		
		for (AFNetworkDomainZone *currentZone in zones) {
			[answerRecords unionSet:[currentZone recordsForFullyQualifiedDomainName:nameString recordClass:classString recordType:typeString]];
		}
	}

	if (answerRecords.count == 0) {
		return;
	}
	
	dns_header_t responseHeader = {
		.xid = requestHeader.xid,
		.ancount = htons(answerRecords.count),
	};
	
	DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, DNSQueryResponse_Response);
	DNSFlagsSet(&responseHeader.flags, DNSFlag_AuthoritativeAnswer, DNSAuthoritativeAnswer_Authoritative);
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
	
	[self _socket:receiver didReceiveQuery:datagram shouldSendResponse:response preferUnicast:preferUnicast];
}

- (void)_socket:(AFNetworkSocket *)receiver didReceiveQuery:(AFNetworkDatagram *)query shouldSendResponse:(NSData *)response preferUnicast:(BOOL)preferUnicast
{
#warning needs to respect the 512 byte limit for unicast DNS and the destination interface MTU for multicast DNS responses (and set the truncation bit)
	NSData *receiverAddressData = receiver.localAddress;
	CFRetain(receiverAddressData);
	af_scoped_block_t cleanupReceiverAddressData = ^ {
		CFRelease(receiverAddressData);
	};
	struct sockaddr_storage const *receiverAddress = (struct sockaddr_storage const *)receiverAddressData.bytes;
	
	NSData *senderAddressData = query.senderAddress;
	CFRetain(senderAddressData);
	af_scoped_block_t cleanupSenderAddressData = ^ {
		CFRelease(senderAddressData);
	};
	struct sockaddr_storage const *senderAddress = (struct sockaddr_storage const *)senderAddressData.bytes;
	
	CFSocketNativeHandle newSocketNative = socket(receiverAddress->ss_family, SOCK_DGRAM, IPPROTO_UDP);
	if (newSocketNative == -1) {
		return;
	}
	af_scoped_block_t cleanupSocketNative = ^ {
		close(newSocketNative);
	};
	
	if (af_sockaddr_is_multicast(receiverAddress)) {
		NSError *setOutboundError = nil;
		BOOL setOutbound = [self _setOutboundInterface:newSocketNative forReceiver:receiverAddress datagram:query error:&setOutboundError];
		if (!setOutbound) {
			return;
		}
		
		NSError *setTTLError = nil;
		BOOL setTTL = [self _setTTL:newSocketNative forReceiver:receiverAddress error:&setTTLError];
		if (!setTTL) {
			return;
		}
		
		int reuseAddress = 1;
		int reuseAddressError = setsockopt(newSocketNative, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, sizeof(reuseAddress));
		if (reuseAddressError != 0) {
			return;
		}
	}
	else {
		int reusePort = 1;
		int reusePortError = setsockopt(newSocketNative, SOL_SOCKET, SO_REUSEPORT, &reusePort, sizeof(reusePort));
		if (reusePortError != 0) {
			return;
		}
		
		int bindError = af_bind(newSocketNative, receiverAddress);
		if (bindError != 0) {
			return;
		}
	}
	
	CFRetain(response);
	af_scoped_block_t cleanupResponse = ^ {
		CFRelease(response);
	};
	
	struct sockaddr_storage const *destination = (af_sockaddr_is_multicast(receiverAddress) && !preferUnicast) ? receiverAddress : senderAddress;
	ssize_t sent = sendto(newSocketNative, response.bytes, response.length, /* int flags */ 0, (struct sockaddr const *)destination, destination->ss_len);
	
	if (sent == -1) {
		__unused int error = errno;
		return;
	}
}

- (BOOL)_setOutboundInterface:(int)socket forReceiver:(struct sockaddr_storage const *)receiverAddress datagram:(AFNetworkDatagram *)datagram error:(NSError **)errorRef
{
	if (!af_sockaddr_is_multicast(receiverAddress)) {
		return YES;
	}
	
	AFNetworkSocketOption *info = [[[datagram metadata] objectsPassingTest:^ BOOL (AFNetworkSocketOption *obj, BOOL *stop) {
		return ([obj level] == IPPROTO_IP && [obj option] == IP_PKTINFO) || ([obj level] == IPPROTO_IPV6 && [obj option] == IPV6_PKTINFO);
	}] anyObject];
	if (info == nil) {
		return YES;
	}

	int setMulticastInterfaceError = 0;
	if (receiverAddress->ss_family == AF_INET) {
		struct in_pktinfo *packetInfo = (struct in_pktinfo *)[info.data bytes];
		setMulticastInterfaceError = setsockopt(socket, IPPROTO_IP, IP_MULTICAST_IFINDEX, &packetInfo->ipi_ifindex, sizeof(packetInfo->ipi_ifindex));
	}
	else if (receiverAddress->ss_family == AF_INET6) {
		struct in6_pktinfo *packetInfo = (struct in6_pktinfo *)[info.data bytes];
		setMulticastInterfaceError = setsockopt(socket, IPPROTO_IPV6, IPV6_MULTICAST_IF, &packetInfo->ipi6_ifindex, sizeof(packetInfo->ipi6_ifindex));
	}
	else {
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"unsupported family %lu", (unsigned long)receiverAddress->ss_family] userInfo:nil];
	}
	if (setMulticastInterfaceError != 0) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		}
		return NO;
	}

	return YES;
}

- (BOOL)_setTTL:(int)socket forReceiver:(struct sockaddr_storage const *)receiverAddress error:(NSError **)errorRef
{
	int setTTLError = 0;
	if (receiverAddress->ss_family == AF_INET) {
		u_char ttl = 255;
		setTTLError = setsockopt(socket, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));
	}
	else if (receiverAddress->ss_family == AF_INET6) {
		int ttl = 255;
		setTTLError = setsockopt(socket, IPPROTO_IPV6, IPV6_MULTICAST_HOPS, &ttl, sizeof(ttl));
	}
	else {
		@throw [NSException exceptionWithName:NSInvalidArgumentException reason:[NSString stringWithFormat:@"unsupported family %lu", (unsigned long)receiverAddress->ss_family] userInfo:nil];
	}
	if (setTTLError != 0) {
		if (errorRef != NULL) {
			*errorRef = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		}
		return NO;
	}

	return YES;
}

@end
