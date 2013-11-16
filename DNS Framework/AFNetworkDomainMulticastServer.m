//
//  AFNetworkMulticastDomainServer.m
//  DNS Server
//
//  Created by Keith Duncan on 10/03/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainMulticastServer.h"

#define __APPLE_USE_RFC_3542
#import <netinet/in.h>

#import "CoreNetworking/CoreNetworking.h"

@implementation AFNetworkDomainMulticastServer

- (BOOL)openInternetSockets:(NSError **)errorRef
{
	/*
		Internet Layer + Options
	 */
	
	NSArray *addresses = @[
		AFNetworkSocketPresentationToAddress(@"224.0.0.251", NULL),
		AFNetworkSocketPresentationToAddress(@"ff02::fb", NULL),
	];
	
	uint16_t port = 5353;
	
	NSMutableSet *newAddresses = [NSMutableSet setWithCapacity:[addresses count]];
	for (NSData *currentAddress in addresses) {
		NSMutableData *newAddress = [[currentAddress mutableCopy] autorelease];
		af_sockaddr_in_write_port((struct sockaddr_storage *)[newAddress bytes], port);
		[newAddresses addObject:newAddress];
	}
	
#warning should join on all interfaces and track interface changes to rejoin
	
	for (NSData *currentAddressData in newAddresses) {
		NSMutableSet *options = [NSMutableSet set];
		
		AFNetworkSocketOption *reuseAddressOption = [AFNetworkSocketOption optionWithLevel:SOL_SOCKET option:SO_REUSEADDR value:@((int)1)];
		[options addObject:reuseAddressOption];

		AFNetworkSocketOption *receivePacketInfo = nil;
		sa_family_t protocolFamily = ((struct sockaddr_storage const *)currentAddressData.bytes)->ss_family;
		if (protocolFamily == PF_INET) {
			receivePacketInfo = [AFNetworkSocketOption optionWithLevel:IPPROTO_IP option:IP_RECVPKTINFO value:@((int)1)];
		}
		else if (protocolFamily == PF_INET6) {
			receivePacketInfo = [AFNetworkSocketOption optionWithLevel:IPPROTO_IPV6 option:IPV6_RECVPKTINFO value:@((int)1)];
		}
		[options addObject:receivePacketInfo];
		
		AFNetworkSocket *socket = [self openSocketWithSignature:AFNetworkSocketSignatureInternetUDP options:options address:currentAddressData error:errorRef];
		if (socket == nil) {
#warning could fail to open IPv6 socket, the server open shouldn't fail
			return NO;
		}
		
		AFNetworkSocketOption *multicastMembershipOption = nil;
		if (protocolFamily == PF_INET) {
			struct sockaddr_in const *address = (struct sockaddr_in const *)currentAddressData.bytes;
			
			struct ip_mreq multicastMembership = {
				.imr_multiaddr = address->sin_addr,
				.imr_interface = {},
			};
			multicastMembershipOption = [AFNetworkSocketOption optionWithLevel:IPPROTO_IP option:IP_ADD_MEMBERSHIP data:[NSData dataWithBytes:&multicastMembership length:sizeof(multicastMembership)]];
		}
		else if (protocolFamily == PF_INET6) {
			struct sockaddr_in6 const *address = (struct sockaddr_in6 const *)currentAddressData.bytes;
			
			struct ipv6_mreq multicastMembership = {
				.ipv6mr_multiaddr = address->sin6_addr,
				.ipv6mr_interface = 0,
			};
			
			multicastMembershipOption = [AFNetworkSocketOption optionWithLevel:IPPROTO_IPV6 option:IPV6_JOIN_GROUP data:[NSData dataWithBytes:&multicastMembership length:sizeof(multicastMembership)]];
		}
		
		if (multicastMembershipOption != nil && ![socket setOption:multicastMembershipOption error:errorRef]) {
			return NO;
		}
	}
	
	return YES;
}

@end
