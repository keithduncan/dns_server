//
//  AFNetworkDomainRecord.h
//  DNS Server
//
//  Created by Keith Duncan on 06/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFNetworkDomainRecord : NSObject

- (id)initWithFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName ttl:(NSTimeInterval)ttl recordClass:(NSString *)recordClass recordType:(NSString *)recordType fields:(NSArray *)fields;

@property (readonly, copy, nonatomic) NSString *fullyQualifiedDomainName;

@property (readonly, assign, nonatomic) NSTimeInterval ttl;

@property (readonly, copy, nonatomic) NSString *recordClass;
@property (readonly, copy, nonatomic) NSString *recordType;

@property (readonly, copy, nonatomic) NSArray *fields;

- (NSData *)encodeRecord:(NSError **)errorRef;

@end
