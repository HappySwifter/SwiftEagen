//
//  SEWrapper.h
//  Prometheus
//
//  Created by Alexander Belbakov on 18/07/16.
//  Copyright © 2016 PochtaBank. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

@interface RecognitionField : NSObject

@property (nonatomic, strong) NSString* Name;
@property (nonatomic, strong) NSString* Value;
@property (nonatomic, assign) bool IsAccepted;
@property (nonatomic, assign) double Confidence;

- (instancetype) initWithName:(NSString*)name value:(NSString*)value isAccepted:(BOOL)isAccepted confidence:(double)confidence;

@end

@protocol SEResultDelegate <NSObject>

- (void) didRecognize:(NSDictionary*)fields;
- (void) didUpdateHint:(NSArray*)points;

@end

typedef NS_ENUM(NSUInteger, SESessionType)
{
    SESessionTypeSmartId = 0,
    SESessionTypeMRZ,
    SESessionTypePassport,
    SESessionTypeCardReader,
    SESessionTypeUniversal,
    SESessionTypeDriverLicense,
    SESessionTypeSTS,
    SESessionTypeSNILS
};

@interface SEWrapper : NSObject

@property (nonatomic, weak) id<SEResultDelegate> delegate;

@property (nonatomic, assign) CGSize videoSize;

- (id) initWithDelegate:(id<SEResultDelegate>)delegate type:(SESessionType)type;

- (void) dispose;

- (void) processSampleBuffer:(CMSampleBufferRef)sampleBuffer roi:(CGRect) roi;

@end
