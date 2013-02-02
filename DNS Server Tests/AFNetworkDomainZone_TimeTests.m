//
//  AFNetworkDomainZone_Tests.m
//  DNS Server
//
//  Created by Keith Duncan on 12/01/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone_TimeTests.h"

#import "AFNetworkDomainZone+AFNetworkPrivate.h"

@implementation AFNetworkDomainZone_TimeTests

- (NSTimeInterval)_testString:(NSString *)timeValue
{
	return [[[[AFNetworkDomainZone alloc] init] autorelease] _scanTimeValue:[NSScanner scannerWithString:timeValue]];
}

#define TestInvalidFormat(var) STAssertEquals([self _testString:(var)], (NSTimeInterval)-1, @"invalid format should return -1")
#define TestValidFormat(var, val) STAssertEquals([self _testString:(var)], (NSTimeInterval)val, ([NSString stringWithFormat:@"valid format should return %f", val]))

- (void)testInvalidTimeFormat1
{
	TestInvalidFormat(@"abcd");
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
	TestValidFormat(@"1W1D1H1M1S", (604800. + 86400. + 3600. + 60. + 1.));
}

- (void)testValidTimeFormat5
{
	/*
		Note
		
		while not a valid unit this is a valid time string
		
		the "1" is treated as a unitless second time value and the "p" while ignored will not be valid in the productions that contain a ttl-value
	 */
	TestValidFormat(@"1p", 1.);
}

@end
