//
//  AFNetworkDomainZone_RecordTests.m
//  DNS Server
//
//  Created by Keith Duncan on 09/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone_RecordTests.h"

#define __APPLE_USE_RFC_3542
#import <netinet/in.h>
#import <dns_util.h>

#import "CoreNetworking/CoreNetworking.h"
#import "DNS/AFNetworkDomain.h"

#import "AFNetworkDomainZone+AFNetworkPrivate.h"
#import "AFNetworkDomainZone+RecordParsing.h"

@interface AFNetworkDomainZone_RecordTests ()
@property (strong, nonatomic) AFNetworkDomainZone *zone;
@end

@implementation AFNetworkDomainZone_RecordTests

- (void)setUp
{
	[super setUp];

	self.zone = [[[AFNetworkDomainZone alloc] init] autorelease];
}

- (void)tearDown
{
	[super tearDown];

	self.zone = nil;
}

#define AssertReadString(str, desc) \
do {\
BOOL read = [self.zone _readFromString:str error:NULL];\
XCTAssertTrue(read, desc);\
} while (0)

#define AssertEncodeRecords(desc) \
do {\
AFNetworkDomainRecord *record = [self.zone.records anyObject];\
BOOL encode = ([record encodeRecord:NULL] != nil);\
XCTAssertTrue(encode, desc);\
} while (0)

#define DATA(var) [NSData dataWithBytes:&var length:sizeof(var)]

- (void)testARecord
{
	NSString *records =
	@"example.com. IN A 127.0.0.1";
	AssertReadString(records, @"cannot read A record");

	AFNetworkDomainRecord *record = [self.zone.records anyObject];
	XCTAssertEqualObjects(record.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(record.recordType, @"A", @"should be Address type");

	NSError *encodeError = nil;
	NSData *encode = [record encodeRecord:&encodeError];
	XCTAssertNotNil(encode, @"should encode IN A record for transport");

	dns_resource_record_t *encodedRecord = dns_parse_resource_record((char const *)[encode bytes], (uint32_t)[encode length]);
	af_scoped_block_t  cleanupAddress = ^ {
		if (encodedRecord != NULL) dns_free_resource_record(encodedRecord);
	};
	XCTAssert(encodedRecord, @"should parse the encoded record");

	in_addr_t address = htonl(INADDR_LOOPBACK);
	XCTAssertEqualObjects(DATA(address), DATA(encodedRecord->data.A->addr), @"should encode 127.0.0.1 to the network order value of INADDR_LOOPBACK");
}

- (void)testAAAARecord
{
	NSString *records =
	@"example.com. IN AAAA ::1";
	AssertReadString(records, @"cannot read AAAA record");
}

- (void)testNAPTRRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"sip       IN  NAPTR 100 10 \"U\" \"E2U+sip\" \"!^.*$!sip:cs@example.com!i\" .   ; NAPTR record\n"
	@"sip2          NAPTR 100 10 \"\" \"\" \"/urn:cid:.+@([^\\.]+\\.)(.*)$/\\2/i\" .  ; another one";
	
	AssertReadString(records, @"cannot read NAPTR record containing inner-data excluded characters");
}

- (void)testSRVRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"_xmpp-server._tcp IN SRV 5 0 5269 xmpp-server.l.google.com.  ; SRV record";
	
	AssertReadString(records, @"cannot read SRV record with underscore prefixed labels");
}

- (void)testTXTRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"txt        IN TXT \"key=value;key2=value2\" \"key4=\\\"value4\\\"\" ; TXT record";
	
	AssertReadString(records, @"cannot read TXT record containing inner-data excluded characters");
}

- (void)testSPFRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"@          IN SPF   \"v=spf1 a a:other.domain.com ~all\"";
	
	AssertReadString(records, @"cannot read SPF record");
}

@end
