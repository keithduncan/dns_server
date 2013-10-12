//
//  NSData+AFNetworkAdditions.m
//  DNS Server
//
//  Created by Keith Duncan on 15/09/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "NSData+AFNetworkAdditions.h"

@implementation NSData (AFNetworkAdditions)

- (NSString *)base2String {
	if ([self length] == 0) {
		return @"";
	}
	
	NSUInteger groupLimit = 2;
	NSMutableData *base2Data = [NSMutableData dataWithCapacity:([self length] * 9) + ([self length] / groupLimit)];
	
	uint8_t *const bytes = (uint8_t *)[self bytes];
	NSUInteger currentByte = 0;
	
	NSUInteger group = 0;
	while (currentByte < [self length]) {
		char characters[] = {
			(*(bytes + currentByte) & /* 0b10000000 */ 128) ? '1' : '0',
			(*(bytes + currentByte) & /* 0b01000000 */ 64)  ? '1' : '0',
			(*(bytes + currentByte) & /* 0b00100000 */ 32)  ? '1' : '0',
			(*(bytes + currentByte) & /* 0b00010000 */ 16)  ? '1' : '0',
			(*(bytes + currentByte) & /* 0b00001000 */ 8)   ? '1' : '0',
			(*(bytes + currentByte) & /* 0b00000100 */ 4)   ? '1' : '0',
			(*(bytes + currentByte) & /* 0b00000010 */ 2)   ? '1' : '0',
			(*(bytes + currentByte) & /* 0b00000001 */ 1)   ? '1' : '0',
			' ',
		};
		[base2Data appendBytes:characters length:sizeof(characters)/sizeof(*characters)];
		
		if (++group % groupLimit == 0) {
			char newline = '\n';
			[base2Data appendBytes:&newline length:1];
		}
		
		currentByte++;
	}
	
	return [[[NSString alloc] initWithData:base2Data encoding:NSASCIIStringEncoding] autorelease];
}

@end
