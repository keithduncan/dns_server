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

- (void)_testFileNamed:(NSString *)fileName
{
	AFNetworkDomainZone *zone = [[[AFNetworkDomainZone alloc] init] autorelease];
	
	NSURL *fileLocation = [[[NSBundle bundleWithIdentifier:@"com.keith-duncan.dns-server.tests"] resourceURL] URLByAppendingPathComponent:fileName];
	
	NSError *readError = nil;
	BOOL read = [zone readFromURL:fileLocation options:nil error:&readError];
	STAssertTrue(read, ([NSString stringWithFormat:@"should be able to read file %@", fileName]));
}

- (void)testTestExampleCom
{
	[self _testFileNamed:@"db.test.example.com"];
}

- (void)testExampleCom
{
	[self _testFileNamed:@"db.example.com"];
}

- (void)testExampleLocal
{
	[self _testFileNamed:@"db.example.local"];
}

@end
