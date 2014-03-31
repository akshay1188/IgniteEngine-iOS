//
//  IXPropertyBag.m
//  Ignite iOS Engine (IX)
//
//  Created by Robert Walsh on 10/7/13.
//  Copyright (c) 2013 Apigee, Inc. All rights reserved.
//

#import "IXPropertyContainer.h"

#import "IXAppManager.h"
#import "IXSandbox.h"
#import "IXProperty.h"
#import "IXControlLayoutInfo.h"
#import "IXPathHandler.h"

#import "IXBaseObject.h"
#import "ColorUtils.h"
#import "SDWebImageManager.h"
#import "UIImage+IXAdditions.h"
#import "IXLogger.h"

@interface IXPropertyContainer ()

@property (nonatomic,strong) NSMutableDictionary* propertiesDict;

@end

@implementation IXPropertyContainer

-(instancetype)init
{
    self = [super init];
    if( self )
    {
        _ownerObject = nil;
        _propertiesDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

-(instancetype)copyWithZone:(NSZone *)zone
{
    IXPropertyContainer* propertyContainerCopy = [[[self class] allocWithZone:zone] init];
    [propertyContainerCopy setOwnerObject:[self ownerObject]];
    [[self propertiesDict] enumerateKeysAndObjectsUsingBlock:^(NSString* propertyName, NSArray* propertyArray, BOOL *stop) {
        NSMutableArray* propertyArrayCopy = [[NSMutableArray alloc] initWithArray:propertyArray copyItems:YES];
        [propertyContainerCopy addProperties:propertyArrayCopy];
    }];
    return propertyContainerCopy;
}

+(instancetype)propertyContainerWithJSONDict:(NSDictionary*)propertyJSONDictionary
{
    IXPropertyContainer* propertyContainer = nil;
    if( [propertyJSONDictionary isKindOfClass:[NSDictionary class]] && [[propertyJSONDictionary allValues] count] > 0 )
    {
        propertyContainer = [[[self class] alloc] init];
        [IXPropertyContainer populatePropertyContainer:propertyContainer withPropertyJSONDict:propertyJSONDictionary keyPrefix:nil];
    }
    return propertyContainer;
}

+(void)populatePropertyContainer:(IXPropertyContainer*)propertyContainer withPropertyJSONDict:(NSDictionary*)propertyJSONDictionary keyPrefix:(NSString*)keyPrefix
{
    [propertyJSONDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        
        NSString* propertiesKey = key;
        if( [keyPrefix length] > 0 )
        {
            propertiesKey = [NSString stringWithFormat:@"%@%@%@",keyPrefix,kIX_PERIOD_SEPERATOR,key];
        }
        
        if( [obj isKindOfClass:[NSArray class]] ) {
            [propertyContainer addProperties:[IXProperty propertiesWithPropertyName:propertiesKey propertyValueJSONArray:obj]];
        }
        else if( [obj isKindOfClass:[NSDictionary class]] ) {
            [IXPropertyContainer populatePropertyContainer:propertyContainer withPropertyJSONDict:obj keyPrefix:propertiesKey];
        }
        else {
            [propertyContainer addProperty:[IXProperty propertyWithPropertyName:propertiesKey jsonObject:obj]];
        }
    }];
}

-(NSMutableArray*)propertiesForPropertyNamed:(NSString*)propertyName
{
    return [self propertiesDict][propertyName];
}

-(BOOL)propertyExistsForPropertyNamed:(NSString*)propertyName
{
    return ([self getPropertyToEvaluate:propertyName] != nil);
}

-(BOOL)hasLayoutProperties
{
    BOOL hasLayoutProperties = NO;
    for( NSString* propertyName in [[self propertiesDict] allKeys] )
    {
        hasLayoutProperties = [IXControlLayoutInfo doesPropertyNameTriggerLayout:propertyName];
        if( hasLayoutProperties )
            break;
    }
    return hasLayoutProperties;
}

-(void)addProperties:(NSArray*)properties
{
    [self addProperties:properties replaceOtherPropertiesWithTheSameName:NO];
}

-(void)addProperties:(NSArray*)properties replaceOtherPropertiesWithTheSameName:(BOOL)replaceOtherProperties
{
    for( IXProperty* property in properties )
    {
        [self addProperty:property replaceOtherPropertiesWithTheSameName:replaceOtherProperties];
    }
}

-(void)addProperty:(IXProperty*)property
{
    [self addProperty:property replaceOtherPropertiesWithTheSameName:NO];
}

-(void)addProperty:(IXProperty*)property replaceOtherPropertiesWithTheSameName:(BOOL)replaceOtherProperties
{
    NSString* propertyName = [property propertyName];
    if( property == nil || propertyName == nil )
    {
        DDLogError(@"ERROR from %@ in %@ : TRYING TO ADD PROPERTY THAT IS NIL OR PROPERTIES NAME IS NIL",THIS_FILE,THIS_METHOD);
        return;
    }
    
    [property setPropertyContainer:self];
    
    NSMutableArray* propertyArray = [self propertiesForPropertyNamed:propertyName];
    if( propertyArray == nil )
    {
        propertyArray = [[NSMutableArray alloc] initWithObjects:property, nil];
        [self propertiesDict][propertyName] = propertyArray;
    }
    else if( replaceOtherProperties )
    {
        [propertyArray removeAllObjects];
        [propertyArray addObject:property];
    }
    else if( ![propertyArray containsObject:property] )
    {
        [propertyArray addObject:property];
    }
}

-(void)addPropertiesFromPropertyContainer:(IXPropertyContainer*)propertyContainer evaluateBeforeAdding:(BOOL)evaluateBeforeAdding replaceOtherPropertiesWithTheSameName:(BOOL)replaceOtherProperties
{
    NSArray* propertyNames = [[propertyContainer propertiesDict] allKeys];
    for( NSString* propertyName in propertyNames )
    {
        if( evaluateBeforeAdding )
        {
            NSString* propertyValue = [propertyContainer getStringPropertyValue:propertyName defaultValue:nil];
            if( propertyValue )
            {
                IXProperty* property = [[IXProperty alloc] initWithPropertyName:propertyName rawValue:propertyValue];
                [self addProperty:property replaceOtherPropertiesWithTheSameName:replaceOtherProperties];
            }
        }
        else
        {
            NSMutableArray* propertyArray = [[NSMutableArray alloc] initWithArray:[propertyContainer propertiesForPropertyNamed:propertyName]
                                                                        copyItems:YES];
            for( IXProperty* property in propertyArray )
            {
                [property setPropertyContainer:self];
            }
            
            [self propertiesDict][propertyName] = propertyArray;
        }
    }
}

-(NSDictionary*)getAllPropertiesStringValues
{
    NSMutableDictionary* returnDictionary = [[NSMutableDictionary alloc] init];
    
    NSArray* propertyNames = [[self propertiesDict] allKeys];
    for( NSString* propertyName in propertyNames )
    {
        NSString* propertyValue = [self getStringPropertyValue:propertyName defaultValue:kIX_EMPTY_STRING];
        
        [returnDictionary setObject:propertyValue forKey:propertyName];
    }
    
    return returnDictionary;
}

-(IXProperty*)getPropertyToEvaluate:(NSString*)propertyName
{
    if( propertyName == nil )
        return nil;
    
    IXProperty* propertyToEvaluate = nil;
    NSArray* propertyArray = [self propertiesForPropertyNamed:propertyName];
    if( [propertyArray count] > 0 )
    {
        UIInterfaceOrientation currentOrientation = [IXAppManager currentInterfaceOrientation];
        for( IXProperty* property in [propertyArray reverseObjectEnumerator] )
        {
            if( [property areConditionalAndOrientationMaskValid:currentOrientation] )
            {
                propertyToEvaluate = property;
                break;
            }
        }
    }
    return propertyToEvaluate;
}

-(NSString*)getStringPropertyValue:(NSString*)propertyName defaultValue:(NSString*)defaultValue
{
    IXProperty* propertyToEvaluate = [self getPropertyToEvaluate:propertyName];
    NSString* returnValue =  ( propertyToEvaluate != nil ) ? [propertyToEvaluate getPropertyValue] : defaultValue;
    return [returnValue copy];
}

-(NSArray*)getCommaSeperatedArrayListValue:(NSString*)propertyName defaultValue:(NSArray*)defaultValue
{
    NSArray* returnArray = defaultValue;
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    if( stringValue != nil )
    {
        returnArray = [stringValue componentsSeparatedByString:kIX_COMMA_SEPERATOR];
    }
    return returnArray;
}

-(NSArray*)getPipeSeperatedArrayListValue:(NSString*)propertyName defaultValue:(NSArray*)defaultValue
{
    NSArray* returnArray = defaultValue;
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    if( stringValue != nil )
    {
        returnArray = [stringValue componentsSeparatedByString:kIX_PIPE_SEPERATOR];
    }
    return returnArray;
}

-(BOOL)getBoolPropertyValue:(NSString*)propertyName defaultValue:(BOOL)defaultValue
{
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    BOOL returnValue =  ( stringValue != nil ) ? [stringValue boolValue] : defaultValue;
    return returnValue;
}

-(int)getIntPropertyValue:(NSString*)propertyName defaultValue:(int)defaultValue
{
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    int returnValue =  ( stringValue != nil ) ? (int) [stringValue integerValue] : defaultValue;
    return returnValue;
}

-(float)getFloatPropertyValue:(NSString*)propertyName defaultValue:(float)defaultValue
{
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    float returnValue =  ( stringValue != nil ) ? [stringValue floatValue] : defaultValue;
    return returnValue;
}

-(float)getSizeValue:(NSString*)propertyName maximumSize:(float)maxSize defaultValue:(float)defaultValue
{
    IXSizeValuePercentage sizeValuePercentage = ixSizePercentageValueWithStringOrDefaultValue([self getStringPropertyValue:propertyName defaultValue:nil], defaultValue);
    float returnValue = ixEvaluateSizeValuePercentageForMaxValue(sizeValuePercentage, maxSize);
    return returnValue;
}

-(UIColor*)getColorPropertyValue:(NSString*)propertyName defaultValue:(UIColor*)defaultValue
{
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    UIColor* returnValue =  ( stringValue != nil ) ? [UIColor colorWithString:stringValue] : defaultValue;
    return returnValue;
}

+(void)storeImageInCache:(UIImage*)image withImageURL:(NSURL*)imageURL toDisk:(BOOL)toDisk
{
    if( image && [imageURL absoluteString].length > 0 )
    {
        [[[SDWebImageManager sharedManager] imageCache] storeImage:image forKey:[imageURL absoluteString] toDisk:toDisk];
    }
}

-(void)getImageProperty:(NSString*)propertyName successBlock:(IXPropertyContainerImageSuccessCompletedBlock)successBlock failBlock:(IXPropertyContainerImageFailedCompletedBlock)failBlock
{
    [self getImageProperty:propertyName successBlock:successBlock failBlock:failBlock shouldRefreshCachedImage:NO];
}

-(void)getImageProperty:(NSString*)propertyName successBlock:(IXPropertyContainerImageSuccessCompletedBlock)successBlock failBlock:(IXPropertyContainerImageFailedCompletedBlock)failBlock shouldRefreshCachedImage:(BOOL)refreshCachedImage
{
    NSURL* imageURL = [self getURLPathPropertyValue:propertyName basePath:nil defaultValue:nil];
    /*
     Added in a fallback so that if images.touch (etc.) don't exist, it tries again with "images.default".
     This way we don't have to specify several of the same image in the JSON.
     - B
    */
    if( imageURL == nil )
    {
        if ([propertyName hasSuffix:@"icon"])
            imageURL = [self getURLPathPropertyValue:@"icon" basePath:nil defaultValue:nil];
        if ([propertyName hasPrefix:@"images"])
            imageURL = [self getURLPathPropertyValue:@"images.default" basePath:nil defaultValue:nil];
    }
    
    if( imageURL != nil )
    {
        NSString* imageURLPath = [imageURL absoluteString];
        
        if ( [IXPathHandler pathIsAssetsLibrary:imageURLPath] )
        {
            ALAssetsLibrary* library = [[ALAssetsLibrary alloc] init];
            [library assetForURL:imageURL
                     resultBlock:^(ALAsset *asset) {
                         
                         ALAssetRepresentation *rep = [asset defaultRepresentation];
                         CGImageRef iref = [rep fullResolutionImage];
                         if (iref)
                         {
                             UIImage* image = [UIImage imageWithCGImage:iref];
                             if( image )
                             {
                                 if( successBlock )
                                 {
                                     successBlock(image);
                                 }
                             }
                         }
                         
                     } failureBlock:^(NSError *err) {
                         DDLogError(@"ERROR from %@ in %@ : Failed to load image from assets-library: %@",THIS_FILE,THIS_METHOD,[err localizedDescription]);
                    }];
        }
        else
        {
            if( !refreshCachedImage && [IXPathHandler pathIsLocal:imageURLPath] )
            {
                UIImage* image = [[[SDWebImageManager sharedManager] imageCache] imageFromMemoryCacheForKey:[imageURL absoluteString]];
                if( image )
                {
                    if( successBlock )
                    {
                        successBlock(image);
                        return;
                    }
                }            
            }
            
            if( refreshCachedImage )
            {
                [[[SDWebImageManager sharedManager] imageCache] removeImageForKey:[imageURL absoluteString] fromDisk:YES];
            }
            
            [[SDWebImageManager sharedManager] downloadWithURL:imageURL
                                                       options:SDWebImageCacheMemoryOnly
                                                      progress:nil
                                                     completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, BOOL finished){
                                                         if (image) {
                                                             if( successBlock )
                                                                 successBlock([UIImage imageWithCGImage:[image CGImage]]);
                                                         } else {
                                                             if( failBlock )
                                                                 failBlock(error);
                                                         }
                                                     }];
        }
    }
    else
    {
        if( failBlock != nil )
        {
            failBlock(nil);
        }
    }
}

-(NSURL*)getURLPathPropertyValue:(NSString*)propertyName basePath:(NSString*)basePath defaultValue:(NSURL*)defaultValue
{
    NSURL* returnURL = defaultValue;
    NSString* stringSettingValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    if( stringSettingValue != nil )
    {
        returnURL = [IXPathHandler normalizedURLPath:stringSettingValue
                                            basePath:basePath
                                            rootPath:[[[self ownerObject] sandbox] rootPath]];
    }
    return returnURL;
}

-(NSString*)getPathPropertyValue:(NSString*)propertyName basePath:(NSString*)basePath defaultValue:(NSString*)defaultValue
{
    NSString* returnPath = defaultValue;
    NSString* stringSettingValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    if( stringSettingValue != nil )
    {
        returnPath = [IXPathHandler normalizedPath:stringSettingValue
                                          basePath:basePath
                                          rootPath:[[[self ownerObject] sandbox] rootPath]];
    }
    return returnPath;
}

-(UIFont*)getFontPropertyValue:(NSString*)propertyName defaultValue:(UIFont*)defaultValue
{
    UIFont* returnFont = defaultValue;
    NSString* stringValue = [self getStringPropertyValue:propertyName defaultValue:nil];
    if( stringValue )
    {
        NSArray* fontComponents = [stringValue componentsSeparatedByString:kIX_COLON_SEPERATOR];
        
        NSString* fontName = [fontComponents firstObject];
        CGFloat fontSize = [[fontComponents lastObject] floatValue];
        
        if( fontName )
        {
            returnFont = [UIFont fontWithName:fontName size:fontSize];
        }
    }
    return returnFont;
}

-(NSString*)description
{
    NSMutableString* description = [NSMutableString string];
    NSArray* properties = [[self propertiesDict] allKeys];
    for( NSString* propertyKey in properties )
    {
        IXProperty* propertyToEvaluate = [self getPropertyToEvaluate:propertyKey];
        [description appendFormat:@"\t%@: %@",propertyKey, [propertyToEvaluate getPropertyValue]];
        if( [propertyToEvaluate shortCodes] )
        {
            [description appendFormat:@" (%@)",[propertyToEvaluate originalString]];
        }
        [description appendString:@"\n"];
    }
    return description;
}

@end
