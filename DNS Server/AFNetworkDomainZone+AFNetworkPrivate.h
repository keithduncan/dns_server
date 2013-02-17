//
//  AFNetworkDomainZone+AFNetworkPrivate.h
//  DNS Server
//
//  Created by Keith Duncan on 17/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"

extern NSString *const AFDomainServerErrorDomain;

@interface AFNetworkDomainZone ()
@property (retain, nonatomic) NSSet *records;
@end

@interface AFNetworkDomainZone (AFNetworkPrivate)

@end
