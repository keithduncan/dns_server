//
//  AFNetworkDomainZone.h
//  DNS Server
//
//  Created by Keith Duncan on 02/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

@class AFNetworkDomainRecord;

extern NSString *const AFNetworkDomainZoneErrorDomain;

typedef enum : NSInteger {
	AFNetworkDomainZoneErrorCodeUnknown = 0,
} AFNetworkDomainZoneErrorCode;

@interface AFNetworkDomainZone : NSObject

- (BOOL)readFromURL:(NSURL *)URL options:(NSDictionary *)options error:(NSError **)errorRef;

- (NSSet *)recordsForFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType;

@end
