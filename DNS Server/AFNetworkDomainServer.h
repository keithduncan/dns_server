//
//  AFNetworkDomainServer.h
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <CoreNetworking/CoreNetworking.h>

@class AFNetworkDomainZone;

@interface AFNetworkDomainServer : AFNetworkServer

- (BOOL)openInternetSockets:(NSError **)errorRef;

@property (strong, atomic) NSSet *zones;

@end
