//
//  AFNetworkDomainZone+RecordMatching.h
//  DNS Server
//
//  Created by Keith Duncan on 17/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone.h"

@interface AFNetworkDomainZone (AFNetworkRecordMatching)

- (NSSet *)_recordsMatchingName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType;

@end
