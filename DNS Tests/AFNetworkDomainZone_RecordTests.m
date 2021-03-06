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
	XCTAssert(record, @"should parse at least one record from %@", string);

	if (!encode) return;

	NSError *encodedError = nil;
	NSData *encoded = [record encodeRecord:&encodedError];
	XCTAssertNotNil(encoded, @"should encode the record for transport");

	dns_resource_record_t *decodedRecord = dns_parse_resource_record((char const *)[encoded bytes], (uint32_t)[encoded length]);
	self.decodedRecord = decodedRecord;
	XCTAssert(decodedRecord, @"should decode the encoded record");
}

- (void)testARecord
{
	NSString *records = @"example.com. IN A 127.0.0.1";
	[self _readString:records encode:YES description:nil];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"A", @"should be Address type");

	if (self.decodedRecord == NULL) return;

	dns_address_record_t *IN = self.decodedRecord->data.A;
	XCTAssert(IN, @"should have a non NULL A data");
	if (IN == NULL) return;

	in_addr_t address = htonl(INADDR_LOOPBACK);
	XCTAssertEqualObjects(DATA(address), DATA(IN->addr), @"should encode 127.0.0.1 to the network order value of INADDR_LOOPBACK");
}

- (void)testAAAARecord
{
	NSString *records = @"example.com. IN AAAA ::1";
	[self _readString:records encode:YES description:nil];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"AAAA", @"should be AAAAddress type");

	if (self.decodedRecord == NULL) return;

	dns_in6_address_record_t *IN6 = self.decodedRecord->data.AAAA;
	XCTAssert(IN6, @"should have a non NULL AAAA data");
	if (IN6 == NULL) return;

	struct in6_addr address = IN6ADDR_LOOPBACK_INIT;
	XCTAssertEqualObjects(DATA(address), DATA(IN6->addr), @"should encode ::1 to the value of IN6ADDR_LOOPBACK_INIT");
}

- (void)testNAPTRRecord
{
	NSString *records =
	@"$ORIGIN example.com.\n"
	@"$TTL 1h\n"
	@"sip       IN  NAPTR 100 10 \"U\" \"E2U+sip\" \"!^.*$!sip:cs@example.com!i\" .   ; NAPTR record\n"
	@"sip2          NAPTR 100 10 \"\" \"\" \"/urn:cid:.+@([^\\.]+\\.)(.*)$/\\2/i\" .  ; another one";
	[self _readString:records encode:NO description:@"should read NAPTR record containing inner-data excluded characters"];

	XCTAssert([self.parsedRecord.fullyQualifiedDomainName hasSuffix:@"example.com."], @"should be a subdomain of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"NAPTR", @"should be NAPTR type");
}

- (void)testSRVRecord
{
	NSString *records = @"_xmpp-server._tcp.example.com. IN SRV 5 0 5269 xmpp-server.l.google.com.  ; SRV record";
	[self _readString:records encode:YES description:@"should read SRV record with underscore prefixed labels"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"_xmpp-server._tcp.example.com.", @"should have an FQDN of _xmpp-server._tcp.example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"SRV", @"should be SRV type");

	if (self.decodedRecord == NULL) return;

	dns_SRV_record_t *SRV = self.decodedRecord->data.SRV;
	XCTAssert(SRV, @"should have a non NULL SRV data");
	if (SRV == NULL) return;

	XCTAssertEqual(SRV->priority, (uint16_t)5, @"should decode a priority of 5");
	XCTAssertEqual(SRV->weight, (uint16_t)0, @"should decode a weight of 0");
	XCTAssertEqual(SRV->port, (uint16_t)5269, @"should decode a port of 5269");
	XCTAssertEqualObjects(@(SRV->target), @"xmpp-server.l.google.com", @"should decode a target of xmpp-server.l.google.com.");
}

- (void)testTXTRecord
{
	NSString *records = @"txt.example.com. IN TXT \"key=value;key2=value2\" \"key4=\\\"value4\\\"\" ; TXT record";
	[self _readString:records encode:YES description:@"should read TXT record containing inner-data excluded characters"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"txt.example.com.", @"should have an FQDN of txt.example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"TXT", @"should be TXT type");

	if (self.decodedRecord == NULL) return;

	dns_TXT_record_t *TXT = self.decodedRecord->data.TXT;
	XCTAssert(TXT, @"should have a non NULL TXT data");
	if (TXT == NULL) return;

	XCTAssertEqual(TXT->string_count, (uint32_t)2, @"should decode 2 strings");
	if (TXT->string_count >= 1) XCTAssertEqualObjects(@(TXT->strings[0]), @"key=value;key2=value2", @"should decode the first string");
	if (TXT->string_count >= 2) XCTAssertEqualObjects(@(TXT->strings[1]), @"key4=\"value4\"", @"should decode the second string");
}

- (void)testSPFRecord
{
	NSString *records = @"example.com. IN SPF \"v=spf1 a a:other.domain.com ~all\"";
	[self _readString:records encode:YES description:@"should read SPF record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"SPF", @"should be SPF type");

	if (self.decodedRecord == NULL) return;

	dns_raw_resource_record_t *SPF = self.decodedRecord->data.DNSNULL;
	XCTAssert(SPF, @"should have a non NULL DNSNULL data");
	if (SPF == NULL) return;

	NSData *data = [NSData dataWithBytes:SPF->data length:SPF->length];
	XCTAssert([data length] == 33, @"should decode non zero length data");
	uint8_t stringLength = ((uint8_t *)[data bytes])[0];
	XCTAssert(stringLength == 32, @"should decode the leading length byte");
	XCTAssertEqualObjects([[NSString alloc] initWithBytes:[data bytes] + 1 length:stringLength encoding:NSASCIIStringEncoding], @"v=spf1 a a:other.domain.com ~all", @"should decode the SPF rule");
}

- (void)testCNAMERecord
{
	NSString *records = @"example.com. IN CNAME www.example.com.";
	[self _readString:records encode:YES description:@"should read CNAME record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"CNAME", @"should be CNAME type");

	if (self.decodedRecord == nil) return;

	dns_domain_name_record_t *CNAME = self.decodedRecord->data.CNAME;
	XCTAssert(CNAME, @"should have a non NULL CNAME data");
	if (CNAME == NULL) return;

	XCTAssertEqualObjects(@(CNAME->name), @"www.example.com", @"should decode a target of www.example.com.");
}

- (void)testMXRecord
{
	NSString *records = @"example.com. IN MX 10 mail.example.com.";
	[self _readString:records encode:YES description:@"should read MX record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"MX", @"should be MX type");

	if (self.decodedRecord == NULL) return;

	dns_MX_record_t *MX = self.decodedRecord->data.MX;
	XCTAssert(MX, @"should have a non NULL MX data");
	if (MX == NULL) return;

	XCTAssertEqual(MX->preference, (uint16_t)10, @"should decode a preference of 10");
	XCTAssertEqualObjects(@(MX->name), @"mail.example.com", @"should decode an exchange of mail.example.com");
}

- (void)testNSRecord
{
	NSString *records = @"example.com. IN NS ns.example.com.";
	[self _readString:records encode:YES description:@"should read NS record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"NS", @"should be NS type");

	if (self.decodedRecord == NULL) return;

	dns_domain_name_record_t *NS = self.decodedRecord->data.NS;
	XCTAssert(NS, @"should have a non NULL NS data");
	if (NS == NULL) return;

	XCTAssertEqualObjects(@(NS->name), @"ns.example.com", @"should decode an nsdname of ns.example.com.");
}

- (void)testPTRRecord
{
	NSString *records = @"example.com. IN PTR other.example.com.";
	[self _readString:records encode:YES description:@"should read PTR record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"PTR", @"should be PTR type");

	if (self.decodedRecord == NULL) return;

	dns_domain_name_record_t *PTR = self.decodedRecord->data.PTR;
	XCTAssert(PTR, @"should have a non NULL PTR data");
	if (PTR == NULL) return;

	XCTAssertEqualObjects(@(PTR->name), @"other.example.com", @"should decode an nsdname of other.example.com.");
}

- (void)testSOARecord
{
	NSString *records =
	@"example.com. IN SOA example.com. admin.example.com. (\n"
	@"2000000000 ; serial\n"
	@"123456 ; refresh\n"
	@"567890 ; retry\n"
	@"901234 ; expire\n"
	@"345678 ; minimum\n"
	@")";
	[self _readString:records encode:YES description:@"should read SOA record"];

	XCTAssertEqualObjects(self.parsedRecord.fullyQualifiedDomainName, @"example.com.", @"should have an FQDN of example.com.");
	XCTAssertEqualObjects(self.parsedRecord.recordClass, @"IN", @"should be INternet class");
	XCTAssertEqualObjects(self.parsedRecord.recordType, @"SOA", @"should be StartOfAuthority type");

	if (self.decodedRecord == nil) return;

	dns_SOA_record_t *SOA = self.decodedRecord->data.SOA;
	XCTAssert(SOA, @"should have a non NULL SOA data");
	if (SOA == NULL) return;

	XCTAssertEqualObjects(@(SOA->mname), @"example.com", @"should decode an mname of example.com");
	XCTAssertEqualObjects(@(SOA->rname), @"admin.example.com", @"should decode an rname of admin.example.com");
	XCTAssertEqual(SOA->serial, (uint32_t)2000000000, @"should decode a serial of 2000000000");
	XCTAssertEqual(SOA->refresh, (uint32_t)123456, @"should decode a refresh interval of 123456");
	XCTAssertEqual(SOA->retry, (uint32_t)567890, @"should decode a retry interval of 567890");
	XCTAssertEqual(SOA->expire, (uint32_t)901234, @"should decode an expire interval of 901234");
	XCTAssertEqual(SOA->minimum, (uint32_t)345678, @"should decode a minimum interval of 345678");
}

@end
