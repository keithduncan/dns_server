//
//  main.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

#import "AFNetworkDomainZoneLoader.h"
#import "AFNetworkDomainMulticastServer.h"

#import "NSError+AFNetworkDomainAdditions.h"

#import "DNS Server-Constants.h"

/*!
	\brief
	Log in JSON because it's human and machine readable
 */
static void log_error(NSError *error)
{
	NSMutableDictionary *logDictionary = [NSMutableDictionary dictionary];
	
	NSString *failingPath = [[error userInfo][NSURLErrorKey] path];
	if (failingPath != nil) {
		logDictionary[@"description"] = NSLocalizedStringFromTableInBundle(@"Couldn\u2019t read zone file", nil, [NSBundle bundleWithIdentifier:AFNetworkDomainServerBundleIdentifier], @"main, log specific path failure, error description"),
		logDictionary[@"path"] = failingPath;
		logDictionary[@"underlying"] = [error afnetworkdomain_recursiveJsonRepresentation];
	}
	else {
		[logDictionary addEntriesFromDictionary:[error afnetworkdomain_recursiveJsonRepresentation]];
	}
	
	NSData *logData = [NSJSONSerialization dataWithJSONObject:@{ @"error" : logDictionary } options:NSJSONWritingPrettyPrinted error:NULL];
	
	fprintf(stderr, "%.*s\n", (int)[logData length], [logData bytes]);
}

static AFNetworkDomainServer *start_domain_server(AFNetworkSchedule *schedule, NSSet *zones, NSError **errorRef)
{
	AFNetworkDomainMulticastServer *server = [AFNetworkDomainMulticastServer server];
	server.schedule = schedule;
	server.zones = zones;
	
	BOOL openSockets = [server openInternetSockets:errorRef];
	if (!openSockets) {
		return nil;
	}
	
	return server;
}

static AFNetworkDomainServer *server_main(AFNetworkSchedule *schedule)
{
	NSSet *zones = nil;
	
	@autoreleasepool {
		NSError *loadZonesError = nil;
		zones = [[AFNetworkDomainZoneLoader loadZones:&loadZonesError] retain];
		
		if (zones == nil) {
			log_error(loadZonesError);
		}
	}
	
	NSError *serverError = nil;
	AFNetworkDomainServer *server = start_domain_server(schedule, zones, &serverError);
	if (server == nil) {
		log_error(serverError);
		exit(0); // Fatal error
	}
	
	[zones release];
	
	return server;
}

static AFNetworkDomainServer *domain_server = nil;

static void runloop_main(void)
{
	AFNetworkSchedule *newSchedule = [[[AFNetworkSchedule alloc] init] autorelease];
	[newSchedule scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
	
	domain_server = [server_main(newSchedule) retain];
	
	[[NSRunLoop currentRunLoop] run];
}

int main(int argc, const char **argv)
{
	@autoreleasepool {
		runloop_main();
	}
    return 0;
}
