//
//  AFNetworkDomainZone_Tests.m
//  DNS Server
//
//  Created by Keith Duncan on 12/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone_Tests.h"

#import "AFNetworkDomainZone+AFNetworkPrivate.h"

@implementation AFNetworkDomainZone_Tests

- (NSTimeInterval)_testString:(NSString *)timeValue
{
	return [[[[AFNetworkDomainZone alloc] init] autorelease] _parseTimeValue:timeValue];
}

#define TestInvalidFormat(var) STAssertEquals([self _testString:(var)], (NSTimeInterval)-1, @"invalid format should return -1");
#define TestValidFormat(var, val) STAssertEquals([self _testString:(var)], (NSTimeInterval)val, @"invalid format should return -1");

- (void)testInvalidTimeFormat1
{
	TestInvalidFormat(@"abcd");
}

- (void)testInvalidTimeFormat2
{
	TestInvalidFormat(@"1d 1h");
}

- (void)testInvalidTimeFormat3
{
	TestInvalidFormat(@"1d 1p");
}

- (void)testValidTimeFormat1
{
	TestValidFormat(@"1", 1.);
}

- (void)testValidTimeFormat2
{
	TestValidFormat(@"1d", 86400.);
}

- (void)testValidTimeFormat3
{
	TestValidFormat(@"1D", 86400.);
}

- (void)testValidTimeFormat4
{
	TestValidFormat(@"1D1H1M1S", (86400. + 3600. + 60. + 1.));
}

@end
