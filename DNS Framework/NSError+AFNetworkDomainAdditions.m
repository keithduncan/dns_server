//
//  NSError+AFNetworkDomainAdditions.m
//  DNS Server
//
//  Created by Keith Duncan on 22/09/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "NSError+AFNetworkDomainAdditions.h"

@implementation NSError (AFNetworkDomainAdditions)

+ (NSMutableDictionary *)_afnetworkdomain_errorAsDictionary:(NSError *)error
{
	NSMutableDictionary *errorDictionary = [NSMutableDictionary dictionary];
	
	errorDictionary[@"domain"] = [error domain];
	errorDictionary[@"code"] = @([error code]);
	
	NSString *description = [error localizedDescription];
	if (description != nil) {
		errorDictionary[@"description"] = description;
	}
	
	NSString *recoverySuggestion = [error localizedRecoverySuggestion];
	if (recoverySuggestion != nil) {
		errorDictionary[@"suggestion"] = recoverySuggestion;
	}
	
	return errorDictionary;
}

- (id)afnetworkdomain_recursiveJsonRepresentation
{
	NSMutableDictionary *rootErrorDictionary = [NSError _afnetworkdomain_errorAsDictionary:self];
	
	NSMutableDictionary *currentErrorDictionary = rootErrorDictionary;
	NSError *currentError = [self userInfo][NSUnderlyingErrorKey];
	
	while (currentError != nil) {
		NSMutableDictionary *underlyingErrorDictionary = [NSError _afnetworkdomain_errorAsDictionary:currentError];
		currentErrorDictionary[@"underlying"] = underlyingErrorDictionary;
		
		currentErrorDictionary = underlyingErrorDictionary;
		currentError = [currentError userInfo][NSUnderlyingErrorKey];
	}
	
	return rootErrorDictionary;
}

@end
