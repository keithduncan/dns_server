//
//  AFNetworkMulticastDomainServer.h
//  DNS Server
//
//  Created by Keith Duncan on 10/03/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainServer.h"

@interface AFNetworkDomainMulticastServer : AFNetworkDomainServer

/*!
	\brief
	Multicast DNS uses special purpose multicast IP addresses, these are known to this object
 */
- (BOOL)openInternetSockets:(NSError **)errorRef;

@end
