//
//  AFNetworkDomainZone+AFNetworkPrivate.h
//  DNS Server
//
//  Created by Keith Duncan on 17/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"

extern NSString *const AFNetworkDomainZoneInternalErrorDomain;

typedef NS_ENUM(NSInteger, AFNetworkDomainZoneInternalErrorCode) {
	AFNetworkDomainZoneInternalErrorCodeUnknown = 0,
	
	AFNetworkDomainZoneInternalErrorCodeNotMatch = -100,
};

@interface AFNetworkDomainZone ()
@property (retain, nonatomic) NSSet *records;
@end

@interface AFNetworkDomainZone (AFNetworkPrivate)

@end
