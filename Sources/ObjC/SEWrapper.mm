//
//  SEWrapper.mm
//  Prometheus
//
//  Created by Alexander Belbakov on 18/07/16.
//  Copyright © 2016 PochtaBank. All rights reserved.
//

#import "SEWrapper.h"
#import <UIKit/UIKit.h>
//#import "smartid_engine.h"
#include <smartIdEngine/smartid_engine.h>

struct SmartIDResultReporter : public se::smartid::ResultReporterInterface {
    __weak SEWrapper *wrapper; // to pass data back
    SESessionType sessionType;
    
    virtual BOOL HasAnyValue(const se::smartid::RecognitionResult &result);
    virtual void SnapshotRejected();
    virtual void DocumentMatched(const se::smartid::MatchResult &result);
    virtual void SnapshotProcessed(const se::smartid::RecognitionResult &result);
    virtual ~SmartIDResultReporter();
};

@implementation RecognitionField

- (instancetype) initWithName:(NSString *)name value:(NSString *)value isAccepted:(BOOL)isAccepted confidence:(double)confidence {
    if (self = [super init]) {
        self.Name = name;
        self.Value = value;
        self.IsAccepted = isAccepted;
        self.Confidence = confidence;
    }
    return self;
}

@end

@interface SEWrapper() {
    SmartIDResultReporter resultReporter_;
    std::unique_ptr<se::smartid::SessionSettings> sessionSettings_;
    std::unique_ptr<se::smartid::RecognitionEngine> engine_;
    std::unique_ptr<se::smartid::RecognitionSession> session_;
    BOOL initialized;
    BOOL processing;
    BOOL delayDespose;
}
@end

@implementation SEWrapper

- (id) init {
    if (self = [super init]) {
        // warning: linked to capture session preset
        self.videoSize = CGSizeMake(720,1280);
        initialized = false;
        processing = false;
        delayDespose = false;
    }
    return self;
}

- (id) initWithDelegate:(id<SEResultDelegate>)delegate type:(SESessionType)type {
    if (self = [self init]) {
        self.delegate = delegate;
        __weak typeof(self) weakSelf = self;
        resultReporter_.wrapper = weakSelf;
        resultReporter_.sessionType = type;

        NSString *dataPath = [self pathForSingleDataArchive];
        try {
            dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                // create recognition engine
                self->engine_.reset(new se::smartid::RecognitionEngine(dataPath.UTF8String));
                // create default session settings
                self->sessionSettings_.reset(self->engine_->CreateSessionSettings());
                [self initializeSessionWithReporter:&self->resultReporter_];
                self->initialized = true;
                self->processing = false;
                self->delayDespose = false;
            });
        } catch (const std::exception &e) {
            NSLog(@"Exception thrown during initialization: %s", e.what());
        }
    }
    return self;
}

- (void) initializeSessionWithReporter:(SmartIDResultReporter *)resultReporter {
    try {
        const std::vector<std::vector<std::string> > &supportedDocumentTypes = sessionSettings_->GetSupportedDocumentTypes();
        NSLog(@"Supported document types for configured engine:");
        for (size_t i = 0; i < supportedDocumentTypes.size(); ++i) {
            const std::vector<std::string> &supportedGroup = supportedDocumentTypes[i];
            NSMutableString *supportedGroupString = [NSMutableString string];
            for (size_t j = 0; j < supportedGroup.size(); ++j) {
                [supportedGroupString appendFormat:@"%s", supportedGroup[j].c_str()];
                if (j + 1 != supportedGroup.size()) {
                    [supportedGroupString appendString:@", "];
                }
            }
            NSLog(@"[%zu]: [%@]", i, supportedGroupString);
        }

        const std::vector<std::string> &documentTypes = sessionSettings_->GetEnabledDocumentTypes();
        NSLog(@"Enabled document types for recognition session to be created:");
        for (size_t i = 0; i < documentTypes.size(); ++i) {
            NSLog(@"%s", documentTypes[i].c_str());
        }

        [self enableDocuments];
        session_.reset(engine_->SpawnSession(*sessionSettings_, resultReporter));
    } catch (const std::exception &e) {
        [NSException raise:@"SmartIDException" format:@"Exception thrown during initialization: %s", e.what()];
    }
}

- (void) dispose {
    if (initialized) {
        @synchronized (self) {
            delayDespose = processing;
        }
        if (!delayDespose) {
            session_.reset();
            engine_.reset();
        }
    }
}

- (void) enableDocuments {
    switch (resultReporter_.sessionType) {
        case SESessionTypeMRZ:
            sessionSettings_->AddEnabledDocumentTypes("mrz.*");
            break;
        case SESessionTypePassport:
            sessionSettings_->AddEnabledDocumentTypes("rus.passport.national");
            break;
        case SESessionTypeCardReader:
            sessionSettings_->AddEnabledDocumentTypes("card.*");
            break;
        case SESessionTypeDriverLicense:
            sessionSettings_->AddEnabledDocumentTypes("rus.drvlic.*");
            break;
        case SESessionTypeSTS:
            sessionSettings_->AddEnabledDocumentTypes("rus.sts.*");
            break;
        case SESessionTypeSNILS:
            sessionSettings_->AddEnabledDocumentTypes("rus.snils.*");
            break;
        default:
            NSLog(@"There are no documents enabled for OCR");
            break;
    }
}

- (void) processSampleBuffer:(CMSampleBufferRef)sampleBuffer roi:(CGRect) roi {
    if (!initialized) return;
    @synchronized (self) {
        processing = true;
    }
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    uint8_t *basePtr = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    const int bytesPerRow = (int)CVPixelBufferGetBytesPerRow(imageBuffer);
    const int width = (int)CVPixelBufferGetWidth(imageBuffer);
    const int height = (int)CVPixelBufferGetHeight(imageBuffer);
    const int channels = 4; // assuming BGRA

    if (basePtr == 0 || bytesPerRow == 0 || width == 0 || height == 0)
        NSLog(@"%s - sample buffer is bad", __func__);

    const int dataLength = height * bytesPerRow;
    se::smartid::Rectangle roi_ = se::smartid::Rectangle(roi.origin.x,roi.origin.y,roi.size.width,roi.size.height);
    // warning: image orientation is hardcoded
    session_->ProcessSnapshot(basePtr, dataLength, width, height, bytesPerRow, channels, roi_, se::smartid::ImageOrientation::Portrait);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    @synchronized (self) {
        processing = false;
    }
    if (delayDespose) {
        delayDespose = false;
        session_.reset();
        engine_.reset();
    }
}

- (NSString *) pathForLazyConfig {
    NSString *dataPath = [[NSBundle mainBundle] pathForResource:@"data-zip" ofType:nil];
    NSString *configPath = [dataPath stringByAppendingPathComponent:@"smartid.json"];
    return configPath;
}

- (NSString *) pathForSingleDataArchive {
    NSBundle *bundle = [NSBundle bundleForClass:[self classForCoder]];
    NSString *dataPath = [bundle pathForResource:@"data-zip" ofType:nil];
    NSArray *listdir = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dataPath error:nil];
    NSPredicate *zipFilter = [NSPredicate predicateWithFormat:@"self ENDSWITH '.zip'"];
    NSArray *zipArchives = [listdir filteredArrayUsingPredicate:zipFilter];
    NSAssert(zipArchives.count == 1, @"data-zip folder must contain single .zip archive");
    NSString *zipName = [zipArchives objectAtIndex:0];
    NSString *zipPath = [dataPath stringByAppendingPathComponent:zipName];
    return zipPath;
}

//#pragma mark SmartIDResultReporter implementation
//
//BOOL SmartIDResultReporter::HasAnyValue(const se::smartid::RecognitionResult &result) {
//    const std::vector<std::string> &stringFieldNames = result.GetStringFieldNames();
//    for (size_t i = 0; i < stringFieldNames.size(); ++i) {
//        const se::smartid::StringField &field = result.GetStringField(stringFieldNames[i]);
//        if (sessionType != SESessionTypeCardReader && field.IsAccepted())
//            return true;
//        else if (field.GetConfidence() > 0.25)
//            return true;
//    }
//    return false;
//}
//
//void SmartIDResultReporter::SnapshotRejected() {
//    dispatch_async(dispatch_get_main_queue(), ^{
//        [wrapper.delegate didUpdateHint:nil];
//    });
//}
//
//void SmartIDResultReporter::DocumentMatched(const se::smartid::MatchResult &result) {
//    // this method is useless,
//    // SE will not perform additional checks to ensure matched quad is actual document
//}
//
//void SmartIDResultReporter::SnapshotProcessed(const se::smartid::RecognitionResult &result) {
//    // TODO: check for session type and check for any value on non-card sessions
//    //if(HasAnyValue(result) && result.GetMatchResults().size() > 0) {
//    if (result.GetMatchResults().size() > 0) {
//        se::smartid::Quadrangle quad = result.GetMatchResults()[0].GetQuadrangle();
//        NSArray* cardPoints = [NSArray arrayWithObjects:
//                               [NSValue valueWithCGPoint:CGPointMake(quad.GetPoint(0).x, quad.GetPoint(0).y)],
//                               [NSValue valueWithCGPoint:CGPointMake(quad.GetPoint(1).x, quad.GetPoint(1).y)],
//                               [NSValue valueWithCGPoint:CGPointMake(quad.GetPoint(2).x, quad.GetPoint(2).y)],
//                               [NSValue valueWithCGPoint:CGPointMake(quad.GetPoint(3).x, quad.GetPoint(3).y)],
//                               nil];
//         dispatch_async(dispatch_get_main_queue(), ^{
//             [wrapper.delegate didUpdateHint:cardPoints];
//         });
//    } else {
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [wrapper.delegate didUpdateHint:nil];
//        });
//    }
//
//    if (!result.IsTerminal())
//        return;
//
//    NSMutableDictionary *fields = [[NSMutableDictionary alloc] init];
//    const std::vector<std::string> &stringFieldNames = result.GetStringFieldNames();
//    for (size_t i = 0; i < stringFieldNames.size(); ++i) {
//        const se::smartid::StringField &field = result.GetStringField(stringFieldNames[i]);
//        RecognitionField* rf = [[RecognitionField alloc] initWithName:[NSString stringWithUTF8String:field.GetName().c_str()]
//                                                                value:[NSString stringWithUTF8String:field.GetUtf8Value().c_str()]
//                                                           isAccepted:field.IsAccepted()
//                                                           confidence:field.GetConfidence()];
//        [fields setObject:rf forKey:rf.Name];
//    }
//
//    if ([NSThread isMainThread]) {
//        [wrapper.delegate didRecognize:fields];
//    } else {
//        dispatch_sync(dispatch_get_main_queue(), ^{
//            [wrapper.delegate didRecognize:fields];
//        });
//    }
//}
//
//SmartIDResultReporter::~SmartIDResultReporter() {
//    wrapper = nil;
//}
//
@end
