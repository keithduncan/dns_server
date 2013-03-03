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

static AFNetworkDomainServer *StartDomainServer(AFNetworkSchedule *schedule)
{
	AFNetworkDomainServer *server = [AFNetworkDomainServer server];
	server.schedule = schedule;
	
	/*
		Internet Layer + Options
	 */
	
	NSMutableSet *addresses = [NSMutableSet setWithObjects:
							   AFNetworkSocketPresentationToAddress(@"224.0.0.251", NULL),
							   AFNetworkSocketPresentationToAddress(@"ff02::fb", NULL),
							   nil];
	
	/*
		Note
		
		IN_MULTICAST(0);
		IN6_IS_ADDR_MULTICAST(0);
		
		join multicast groups automatically based on whether the address is a multicast group, or provide configurable IP layer options on AFNetworkSocket
		
		we need to join the multicast group on all interfaces, therefore we need to track changes to interfaces
		consult the mDNSResponder code to see what mechanism it uses to monitor interfaces, probably the SystemConfiguration framework
		
		can we open a wildcard IPv4/IPv6 socket address and join the group using that, this would avoid tracking interface changes as we avoided tracking interface changes in AFNetworkServer
		though we still need to track address family availablity changes which we don't current handle in AFNetworkServer :(
	 */
#warning this relies on mDNSResponder joining the multicast group, we should join it too so not to rely on that
	
	/*
		Transport Layer + Options
	 */
	
	/*
		Note
		
		needs to set SO_REUSEADDR on the socket for the bind to succeed when mDNSResponder is already bound to the port
	 */
	uint16_t port = 5353;
#warning this relies on the debug-only options set in AFNetworkSocket for reuse address and reuse port, these need to be configurable for use in release configuration too for binding these addresses to work in the presence of mDNSResponder
	
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

static void server_main(AFNetworkSchedule *schedule)
{
	AFNetworkDomainServer *domainServer = [StartDomainServer(schedule) retain];
	
	AFNetworkDomainZone *zone = [[AFNetworkDomainZone alloc] init];
	
	NSError *readZoneError = nil;
	BOOL readZone = [zone readFromURL:[[NSBundle mainBundle] URLForResource:@"db.example" withExtension:@"local"] options:nil error:&readZoneError];
	NSCParameterAssert(readZone);
	
	[domainServer addZone:zone];
}

static void runloop_main(void)
{
	AFNetworkSchedule *newSchedule = [[[AFNetworkSchedule alloc] init] autorelease];
	[newSchedule scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	
	server_main(newSchedule);
	
	[[NSRunLoop currentRunLoop] run];
}

int main(int argc, const char **argv)
{
	@autoreleasepool {
		runloop_main();
	}
    return 0;
}
