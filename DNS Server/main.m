//
//  main.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkDomainServer.h"
#import "AFNetworkDomainZone.h"

static AFNetworkDomainServer *StartDomainServer(void) {
	AFNetworkDomainServer *server = [AFNetworkDomainServer server];
	
	AFNetworkSchedule *newSchedule = [[[AFNetworkSchedule alloc] init] autorelease];
	[newSchedule scheduleInQueue:dispatch_get_main_queue()];
	server.schedule = newSchedule;
	
	NSMutableSet *addresses = [NSMutableSet setWithObjects:
							   AFNetworkSocketPresentationToAddress(@"224.0.0.251", NULL),
							   AFNetworkSocketPresentationToAddress(@"ff02::fb", NULL),
							   nil];
	
	uint16_t port = 5353;
	
#warning this relies on the debug-only options set in AFNetworkSocket for reuse address and reuse port, these need to be configurable for use in release configuration too for binding these addresses to work in the presence of mDNSResponder
	
#warning this relies on mDNSResponder joining the multicast group, we should join it too so not to rely on that
	
	NSMutableSet *newAddresses = [NSMutableSet set];
	for (NSData *currentAddress in addresses) {
		NSMutableData *newAddress = [[currentAddress mutableCopy] autorelease];
		af_sockaddr_in_write_port((struct sockaddr_storage *)[newAddress bytes], port);
		[newAddresses addObject:newAddress];
	}
	
	BOOL openSockets = [server openInternetSocketsWithSocketSignature:AFNetworkSocketSignatureInternetUDP socketAddresses:newAddresses errorHandler:nil];
	NSCParameterAssert(openSockets);
	
	return server;
}

void server_main(void) {
	__unused AFNetworkDomainServer *domainServer = [StartDomainServer() retain];
	
	AFNetworkDomainZone *zone = [[AFNetworkDomainZone alloc] init];
	
	NSError *readZoneError = nil;
	BOOL readZone = [zone readFromURL:[NSURL fileURLWithPath:@"/Users/keith/Projects/Source/DNS Server/DNS Server/db.example.local"] options:nil error:&readZoneError];
	NSCParameterAssert(readZone);
	
	[domainServer addZone:zone];
	
	dispatch_main();
}

int main(int argc, const char **argv) {
	@autoreleasepool {
		server_main();
	}
    return 0;
}
