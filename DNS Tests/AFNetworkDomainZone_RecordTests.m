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
@property (strong, nonatomic) AFNetworkDomainRecord *parsedRecord;
@property (assign, nonatomic) dns_resource_record_t *decodedRecord;
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

	self.parsedRecord = nil;

	if (self.decodedRecord != NULL) {
		dns_free_resource_record(self.decodedRecord);
		self.decodedRecord = NULL;
	}
}

#define DATA(var) [NSData dataWithBytes:&var length:sizeof(var)]

- (void)_readString:(NSString *)string encode:(BOOL)encode description:(NSString *)description
{
	BOOL read = [self.zone _readFromString:string error:NULL];
	XCTAssertTrue(read, @"should parse record from string, %@", description);
	if (!read) {
		return;
	}

	AFNetworkDomainRecord *record = [self.zone.records anyObject];
	self.parsedRecord = record;

	if (!encode) return;

	NSError *encodedError = nil;
	NSData *encoded = [record encodeRecord:&encodedError];
	XCTAssertNotNil(encoded, @"should encode the record for transport");

	dns_resource_record_t *decodedRecord = dns_parse_resource_record((char const *)[encoded bytes], (uint32_t)[encoded length]);
	XCTAssert(decodedRecord, @"should parse the encoded record");
	self.decodedRecord = decodedRecord;
}

- (void)testARecord
{
	NSString *records = @"example.com. IN A 127.0.0.1";
	[self _readString:records encode:YES description:nil];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"A", @"should be Address type");

	in_addr_t address = htonl(INADDR_LOOPBACK);
	XCTAssertEqualObjects(DATA(address), DATA(self.decodedRecord->data.A->addr), @"should encode 127.0.0.1 to the network order value of INADDR_LOOPBACK");
}

- (void)testAAAARecord
{
	NSString *records = @"example.com. IN AAAA ::1";
	[self _readString:records encode:YES description:nil];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"AAAA", @"should be AAAAddress type");

	struct in6_addr address = IN6ADDR_LOOPBACK_INIT;
	XCTAssertEqualObjects(DATA(address), DATA(self.decodedRecord->data.AAAA->addr), @"should encode ::1 to the value of IN6ADDR_LOOPBACK_INIT");
}

- (void)testNAPTRRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"sip       IN  NAPTR 100 10 \"U\" \"E2U+sip\" \"!^.*$!sip:cs@example.com!i\" .   ; NAPTR record\n"
	@"sip2          NAPTR 100 10 \"\" \"\" \"/urn:cid:.+@([^\\.]+\\.)(.*)$/\\2/i\" .  ; another one";
	[self _readString:records encode:NO description:@"cannot read NAPTR record containing inner-data excluded characters"];

	XCTAssert([self.parsedRecord.fullyQualifiedDomainName hasSuffix:@"example.com."], @"should be a subdomain of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"NAPTR", @"should be NAPTR type");
}

- (void)testSRVRecord
{
	NSString *records = @"_xmpp-server._tcp.example.com. IN SRV 5 0 5269 xmpp-server.l.google.com.  ; SRV record";
	[self _readString:records encode:YES description:@"cannot read SRV record with underscore prefixed labels"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"_xmpp-server._tcp.example.com.", @"should have an FQDN of _xmpp-server._tcp.example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"SRV", @"should be SRV type");

	dns_SRV_record_t *SRV = self.decodedRecord->data.SRV;
	XCTAssertEqual(SRV->priority, (uint16_t)5, @"should decode a priority of 5");
	XCTAssertEqual(SRV->weight, (uint16_t)0, @"should decode a weight of 0");
	XCTAssertEqual(SRV->port, (uint16_t)5269, @"should decode a port of 5269");
	XCTAssertEqualObjects(@(SRV->target), @"xmpp-server.l.google.com", @"should decode a target of xmpp-server.l.google.com.");
}

- (void)testTXTRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"txt        IN TXT \"key=value;key2=value2\" \"key4=\\\"value4\\\"\" ; TXT record";
	[self _readString:records encode:YES description:@"cannot read TXT record containing inner-data excluded characters"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"txt.example.com.", @"should have an FQDN of txt.example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"TXT", @"should be TXT type");
}

- (void)testSPFRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"@          IN SPF   \"v=spf1 a a:other.domain.com ~all\"";
	[self _readString:records encode:YES description:@"cannot read SPF record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"SPF", @"should be SPF type");
}

@end
