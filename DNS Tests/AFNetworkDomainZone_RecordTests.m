//
//  AFNetworkDomainZone_RecordTests.m
//  DNS Server
//
//  Created by Keith Duncan on 09/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone_RecordTests.h"

#import "AFNetworkDomainZone.h"
#import "AFNetworkDomainZone+RecordParsing.h"

@implementation AFNetworkDomainZone_RecordTests

#define AssertReadString(str, desc) \
do {\
AFNetworkDomainZone *zone = [[[AFNetworkDomainZone alloc] init] autorelease];\
\
BOOL read = [zone _readFromString:str error:NULL];\
XCTAssertTrue(read, desc);\
} while (0)\

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
