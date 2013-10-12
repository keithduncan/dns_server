//
//  AFNetworkDomainServer.h
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "CoreNetworking/CoreNetworking.h"

@class AFNetworkDomainZone;

@interface AFNetworkDomainServer : AFNetworkServer

@property (strong, atomic) NSSet *zones;

@end
