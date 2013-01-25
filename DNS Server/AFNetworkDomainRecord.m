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

@property (readwrite, copy, nonatomic) NSString *recordClass;
@property (readwrite, copy, nonatomic) NSString *recordType;

@property (readwrite, copy, nonatomic) NSString *value;
@end

@implementation AFNetworkDomainRecord

- (id)initWithFullyQualifiedDomainName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType value:(NSString *)value
{
	self = [self init];
	if (self == nil) {
		return nil;
	}
	
	_fullyQualifiedDomainName = [fullyQualifiedDomainName copy];
	
	_recordClass = [recordClass copy];
	_recordType = [recordType copy];
	
	_value = [value copy];
	
	return self;
}

- (void)dealloc {
	[_fullyQualifiedDomainName release];
	
	[_recordClass copy];
	[_recordType copy];
	
	[_value release];
	
	[super dealloc];
}

@end
