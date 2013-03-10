//
//  main.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkMulticastDomainServer.h"
#import "AFNetworkDomainZone.h"

static AFNetworkDomainServer *StartDomainServer(AFNetworkSchedule *schedule)
{
	AFNetworkMulticastDomainServer *server = [AFNetworkMulticastDomainServer server];
	server.schedule = schedule;
	
	NSError *openSocketsError = nil;
	BOOL openSockets = [server openInternetSockets:&openSocketsError];
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
