//
//  main.m
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"
#import "DNS/AFNetworkDomain.h"

#import "AFNetworkDomainZoneLoader.h"

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

static AFNetworkDomainMulticastServer *domain_server_main(AFNetworkSchedule *schedule, NSSet *zones, NSError **errorRef)
{
	AFNetworkDomainMulticastServer *server = [AFNetworkDomainMulticastServer server];
	server.schedule = schedule;
	server.zones = zones;
	
	BOOL openSockets = [server openInternetSockets:errorRef];
	if (!openSockets) {
		return nil;
	}

#if 0
	NSSet *options = [NSSet setWithObject:[AFNetworkSocketOption optionWithLevel:SOL_SOCKET option:SO_REUSEPORT value:@((int)1)]];
	BOOL openUnicast = [server openInternetSocketsWithSignature:AFNetworkSocketSignatureInternetUDP options:options scope:AFNetworkInternetSocketScopeLocalOnly port:5656 errorHandler:^ (NSData *address, NSError *error) {
		if (errorRef != NULL) {
			*errorRef = error;
		}
		return NO;
	}];
	if (!openUnicast) {
		return nil;
	}
#endif
	
	return server;
}

static AFNetworkDomainMulticastServer *domain_server = nil;

static void server_main(AFNetworkSchedule *schedule)
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
	domain_server = [domain_server_main(schedule, zones, &serverError) retain];
	if (domain_server == nil) {
		log_error(serverError);
		exit(0); // Fatal error
	}
	
	[zones release];
}

int main(int argc, char const **argv)
{
	@autoreleasepool {
		AFNetworkSchedule *newSchedule = [[[AFNetworkSchedule alloc] init] autorelease];
		[newSchedule scheduleInQueue:dispatch_queue_create("com.keith-duncan.domain.server.main", DISPATCH_QUEUE_SERIAL)];
		
		server_main(newSchedule);
	}
	
	dispatch_main();
    return 0;
}
