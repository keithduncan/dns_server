//
//  AFNetworkDomainZone+AFNetworkPrivate.h
//  DNS Server
//
//  Created by Keith Duncan on 12/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"

@interface AFNetworkDomainZone ()

- (BOOL)_readFromString:(NSString *)zoneString error:(NSError **)errorRef;

- (NSTimeInterval)_scanTimeValue:(NSScanner *)timeScanner;

@end
