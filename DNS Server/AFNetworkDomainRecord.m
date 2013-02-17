//
//  AFNetworkDomainRecord.m
//  DNS Server
//
//  Created by Keith Duncan on 06/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainRecord.h"

@interface AFNetworkDomainRecord ()
@property (readwrite, copy, nonatomic) NSString *fullyQualifiedDomainName;

@property (readwrite, assign, nonatomic) NSTimeInterval ttl;

@property (readwrite, copy, nonatomic) NSString *recordClass;
@property (readwrite, copy, nonatomic) NSString *recordType;

@property (readwrite, copy, nonatomic) NSArray *fields;
@end

@implementation AFNetworkDomainRecord

- (id)initWithFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName ttl:(NSTimeInterval)ttl recordClass:(NSString *)recordClass recordType:(NSString *)recordType fields:(NSArray *)fields
{
	self = [self init];
	if (self == nil) {
		return nil;
	}
	
	_fullyQualifiedDomainName = [fullyQualifiedDomainName copy];
	
	_ttl = ttl;
	
	_recordClass = [recordClass copy];
	_recordType = [recordType copy];
	
	_fields = [fields copy];
	
	return self;
}

- (void)dealloc {
	[_fullyQualifiedDomainName release];
	
	[_recordClass copy];
	[_recordType copy];
	
	[_fields release];
	
	[super dealloc];
}

@end
