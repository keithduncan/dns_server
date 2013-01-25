//
//  AFNetworkDomainRecord.h
//  DNS Server
//
//  Created by Keith Duncan on 06/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface AFNetworkDomainRecord : NSObject

- (id)initWithFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType value:(NSString *)value;

@property (readonly, copy, nonatomic) NSString *fullyQualifiedDomainName;

@property (readonly, copy, nonatomic) NSString *recordClass;
@property (readonly, copy, nonatomic) NSString *recordType;

@property (readonly, copy, nonatomic) NSString *value;

@end
