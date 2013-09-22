//
//  AFNetworkDomainZoneLoader.h
//  DNS Server
//
//  Created by Keith Duncan on 22/09/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFNetworkDomainZoneLoader : NSObject

+ (NSSet *)loadZones:(NSError **)errorRef;

@end
