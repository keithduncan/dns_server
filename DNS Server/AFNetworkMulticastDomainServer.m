//
//  AFNetworkMulticastDomainServer.m
//  DNS Server
//
//  Created by Keith Duncan on 10/03/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkMulticastDomainServer.h"

#define __APPLE_USE_RFC_3542
#import <netinet/in.h>

#import "CoreNetworking/CoreNetworking.h"

@implementation AFNetworkMulticastDomainServer

- (BOOL)openInternetSockets:(NSError **)errorRef
{
	/*
		Internet Layer + Options
	 */
	
	NSArray *addresses = @[
		AFNetworkSocketPresentationToAddress(@"224.0.0.251", NULL),
		AFNetworkSocketPresentationToAddress(@"ff02::fb", NULL),
	];
	
	/*
		Note
		
		IN_MULTICAST(0);
		IN6_IS_ADDR_MULTICAST(0);
		
		join multicast groups automatically based on whether the address is a multicast group, or provide configurable IP layer options on AFNetworkSocket
		
		we need to join the multicast group on all interfaces, therefore we need to track changes to interfaces
		consult the mDNSResponder code to see what mechanism it uses to monitor interfaces, probably the SystemConfiguration framework
		
		can we open a wildcard IPv4/IPv6 socket address and join the group using that, this would avoid tracking interface changes as we avoided tracking interface changes in AFNetworkServer
		though we still need to track address family availability changes which we don't current handle in AFNetworkServer :(
	 */
#warning this relies on mDNSResponder joining the multicast group, we should join it too so not to rely on that
	
	uint16_t port = 5353;
	
	NSMutableSet *newAddresses = [NSMutableSet setWithCapacity:[addresses count]];
	for (NSData *currentAddress in addresses) {
		NSMutableData *newAddress = [[currentAddress mutableCopy] autorelease];
		af_sockaddr_in_write_port((struct sockaddr_storage *)[newAddress bytes], port);
		[newAddresses addObject:newAddress];
	}
	
	for (NSData *currentAddress in newAddresses) {
		NSMutableSet *options = [NSMutableSet set];
		
		int reuseAddress = 1;
		AFNetworkSocketOption *reuseAddressOption = [AFNetworkSocketOption optionWithLevel:SOL_SOCKET option:SO_REUSEADDR value:[NSData dataWithBytes:&reuseAddress length:sizeof(reuseAddress)]];
		[options addObject:reuseAddressOption];
		
		sa_family_t protocolFamily = ((struct sockaddr_storage const *)[currentAddress bytes])->ss_family;
		if (protocolFamily == PF_INET) {
			int on = 1;
			AFNetworkSocketOption *receiveAddress = [AFNetworkSocketOption optionWithLevel:IPPROTO_IP option:IP_RECVDSTADDR value:[NSData dataWithBytes:&on length:sizeof(on)]];
			AFNetworkSocketOption *receiveInterface = [AFNetworkSocketOption optionWithLevel:IPPROTO_IP option:IP_RECVIF value:[NSData dataWithBytes:&on length:sizeof(on)]];
			[options addObjectsFromArray:@[ receiveAddress, receiveInterface ]];
		}
		else if (protocolFamily == PF_INET6) {
			int on = 1;
			AFNetworkSocketOption *receivePacketInfo = [AFNetworkSocketOption optionWithLevel:IPPROTO_IPV6 option:IPV6_PKTINFO value:[NSData dataWithBytes:&on length:sizeof(on)]];
			[options addObject:receivePacketInfo];
		}
		
		BOOL open = [self openSocketWithSignature:AFNetworkSocketSignatureInternetUDP address:currentAddress options:options error:errorRef];
		if (!open) {
			return NO;
		}
	}
	
	return YES;
}

@end
