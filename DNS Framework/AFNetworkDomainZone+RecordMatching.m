//
//  AFNetworkDomainZone+RecordMatching.m
//  DNS Server
//
//  Created by Keith Duncan on 17/02/2013.
//  Copyright (c) 2013 Keith Duncan. All rights reserved.
//

#import "AFNetworkDomainZone+RecordMatching.h"
#import "AFNetworkDomainZone+AFNetworkPrivate.h"

#import "AFNetworkDomainRecord.h"

@implementation AFNetworkDomainZone (AFNetworkRecordMatching)

- (NSSet *)_recordsMatchingName:(NSString *)fullyQualifiedDomainName recordClass:(NSString *)recordClass recordType:(NSString *)recordType
{
	NSPredicate *namePredicate = [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"fullyQualifiedDomainName"]
																	rightExpression:[NSExpression expressionForConstantValue:fullyQualifiedDomainName]
																		   modifier:NSDirectPredicateModifier
																			   type:NSEqualToPredicateOperatorType
																			options:NSCaseInsensitivePredicateOption];
	
	NSArray *classSubpredicates = @[
		[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:recordClass]
										   rightExpression:[NSExpression expressionForConstantValue:@"ANY"]
												  modifier:NSDirectPredicateModifier
													  type:NSEqualToPredicateOperatorType
												   options:NSCaseInsensitivePredicateOption],
		[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:recordClass]
										   rightExpression:[NSExpression expressionForKeyPath:@"recordClass"]
												  modifier:NSDirectPredicateModifier
													  type:NSEqualToPredicateOperatorType
												   options:NSCaseInsensitivePredicateOption],
	];
	NSPredicate *classPredicate = [NSCompoundPredicate orPredicateWithSubpredicates:classSubpredicates];
	
	NSArray *typeSubpredicates = @[
		[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:recordType]
										   rightExpression:[NSExpression expressionForConstantValue:@"ANY"]
												  modifier:NSDirectPredicateModifier
													  type:NSEqualToPredicateOperatorType
												   options:NSCaseInsensitivePredicateOption],
		[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:recordType]
										   rightExpression:[NSExpression expressionForKeyPath:@"recordType"]
												  modifier:NSDirectPredicateModifier
													  type:NSEqualToPredicateOperatorType
												   options:NSCaseInsensitivePredicateOption],
	];
	NSPredicate *typePredicate = [NSCompoundPredicate orPredicateWithSubpredicates:typeSubpredicates];
	
	NSArray *matchSubpredicates = @[
		namePredicate,
		classPredicate,
		typePredicate,
	];
	NSPredicate *matchPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:matchSubpredicates];
	
	return [self.records filteredSetUsingPredicate:matchPredicate];
}

@end
