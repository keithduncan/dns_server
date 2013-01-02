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

static AFNetworkServer *StartDomainServer(void) {
	AFNetworkDomainServer *server = [AFNetworkDomainServer server];
	
	BOOL openSockets = [server openInternetSocketsWithSocketSignature:AFNetworkSocketSignatureInternetUDP scope:AFNetworkInternetSocketScopeLocalOnly port:5353 errorHandler:nil];
	NSCParameterAssert(openSockets);
	
	return server;
}

void server_main(void) {
	__unused AFNetworkDomainServer *domainServer = StartDomainServer();
	
	CFRunLoopRun();
}

int main(int argc, const char **argv) {
	@autoreleasepool {
		server_main();
	}
    return 0;
}
