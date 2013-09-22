//
//  NSError+AFNetworkDomainAdditions.h
//  DNS Server
//
//  Created by Keith Duncan on 22/09/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSError (AFNetworkDomainAdditions)

/*!
	\brief
	Encode the receiver and any underlying errors as a JSON compatible object
	graph
 */
- (id)afnetworkdomain_recursiveJsonRepresentation;

@end
