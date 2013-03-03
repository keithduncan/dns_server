//
//  AFNetworkDomainZone_ZoneTests.m
//  DNS Server
//
//  Created by Keith Duncan on 02/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone_ZoneTests.h"

#import "AFNetworkDomainZone.h"

@implementation AFNetworkDomainZone_ZoneTests

#define TestFileNamed(fileName) \
do {\
	AFNetworkDomainZone *zone = [[[AFNetworkDomainZone alloc] init] autorelease];\
	NSURL *fileLocation = [[[NSBundle bundleWithIdentifier:@"com.keith-duncan.dns-server.tests"] resourceURL] URLByAppendingPathComponent:fileName];\
	NSError *readError = nil;\
	BOOL read = [zone readFromURL:fileLocation options:nil error:&readError];\
	STAssertTrue(read, ([NSString stringWithFormat:@"should be able to read file %@", fileName]));\
} while (0)

- (void)testBlankCom
{
	TestFileNamed(@"db.blank.com");
}

- (void)testTestExampleCom
{
	TestFileNamed(@"db.test.example.com");
}

- (void)testExampleCom
{
	TestFileNamed(@"db.example.com");
}

- (void)testExampleLocal
{
	TestFileNamed(@"db.example.local");
}

- (void)testExampleComZone
{
	TestFileNamed(@"example.com.zone");
}

- (void)testExample2ComZone
{
	TestFileNamed(@"example2.com.zone");
}

- (void)testExample3ComZone
{
	TestFileNamed(@"example3.com.zone");
}

@end
