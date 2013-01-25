//
//  AFNetworkDomainServer.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainServer.h"

#import <dns_util.h>

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

static struct _DNSFlagMap const *_DNSFlagMapForFlag(enum DNSFlag flag) {
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

static int DNSFlagsGet(uint16_t flags, enum DNSFlag flag) {
	struct _DNSFlagMap const *mapRef = _DNSFlagMapForFlag(flag);
	NSCParameterAssert(mapRef != NULL);
	
	int shift = mapRef->shift;
	return (flags & (mapRef->mask << shift)) >> shift;
}

static void DNSFlagsSet(uint16_t *flagsRef, enum DNSFlag flag, int value) {
	struct _DNSFlagMap const *mapRef = _DNSFlagMapForFlag(flag);
	NSCParameterAssert(mapRef != NULL);
	
	NSCParameterAssert((mapRef->mask & value) == value);
	
	*flagsRef = (*flagsRef | (value << mapRef->shift));
}

typedef NS_ENUM(int, DNSQueryResponse) {
	DNSQueryResponse_Query = 0,
	DNSQueryResponse_Response = 1,
};

typedef NS_ENUM(int, DNSOpcode) {
	DNSOpcode_Standard = 0,
	DNSOpcode_Inverse = 1,
	DNSOpcode_Status = 2,
};

typedef NS_ENUM(int, DNSRcode) {
	DNSRcode_OK = 0,
	DNSRcode_FormatError = 1,
	DNSRcode_ServerFailure = 2,
	DNSRcode_NameError = 3,
	DNSRcode_NotImplemented = 4,
	DNSRcode_Refused = 5,
};

- (void)networkLayer:(AFNetworkSocket *)socket didReceiveMessage:(NSData *)message fromSender:(AFNetworkSocket *)sender
{
	dns_header_t requestHeader = {};
	
	size_t cursor = 0;
	if ((cursor + sizeof(requestHeader)) > [message length]) {
		return;
	}
	
	[message getBytes:&requestHeader range:NSMakeRange(cursor, sizeof(requestHeader))];
	cursor += sizeof(requestHeader);
	
	uint16_t flags = requestHeader.flags;
	
	if (DNSFlagsGet(flags, DNSFlag_QueryResponse) != DNSQueryResponse_Query) {
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_Opcode) != DNSOpcode_Standard) {
		dns_header_t responseHeader = {};
		responseHeader.xid = requestHeader.xid;
		
		DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, 1);
		DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_NotImplemented);
		
		[self _sendResponse:&responseHeader to:sender];
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_RD) != 0) {
		dns_header_t responseHeader = {};
		responseHeader.xid = requestHeader.xid;
		
		DNSFlagsSet(&responseHeader.flags, DNSFlag_QueryResponse, 1);
		DNSFlagsSet(&responseHeader.flags, DNSFlag_Rcode, DNSRcode_Refused);
		
		[self _sendResponse:&responseHeader to:sender];
		return;
	}
	
	if (DNSFlagsGet(flags, DNSFlag_Z) != 0) {
		return;
	}
	
	for (size_t questionIdx = 0; questionIdx < requestHeader.qdcount; questionIdx++) {
		
	}
}

- (void)_sendResponse:(dns_header_t *)responseHeaderRef to:(AFNetworkSocket *)destination
{
	AFNetworkTransport *transport = [[[AFNetworkTransport alloc] initWithLowerLayer:(id)destination] autorelease];
	transport.delegate = (id)self;
	
	NSData *response = [NSData dataWithBytes:responseHeaderRef length:sizeof(*responseHeaderRef)];
	[transport performWrite:response withTimeout:-1 context:NULL];
	
	[transport performWrite:[[[AFNetworkPacketClose alloc] init] autorelease] withTimeout:-1 context:NULL];
	
	[transport open];
}

@end
