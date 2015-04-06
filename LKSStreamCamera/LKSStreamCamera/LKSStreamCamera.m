//
//  LKSStreamCamera.m
//  LKSStreamCamera
//
//  Created by Lachlan Nuttall on 28/03/2015.
//  Copyright (c) 2015 Lachlan Nuttall. All rights reserved.
//

#import "LKSStreamCamera.h"
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>

#define kSupressErrors YES

typedef enum {
    kLKSStreamCameraFocusModeContinuous = 0, // Continunally auto focus and expose in the center but don't monitor subject area for changes
    kLKSStreamCameraFocusModeAuto, // Auto focus and expose - not continuous, and listen for subject area changes
    kLKSStreamCameraFocusModeLocked
} LKSStreamCameraFocusMode;

@interface LKSStreamCamera ()

// Session management.
@property (nonatomic) dispatch_queue_t sessionQueue; // Communicate with the session and other session objects on this queue.
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *captureDeviceInput;
@property (nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (nonatomic) AVCaptureVideoPreviewLayer *captureVideoPreviewLayer;

@property (nonatomic,assign) BOOL authOK;
@property (nonatomic,assign) BOOL deviceExists;

// Utilities.
@property (nonatomic) id runtimeErrorHandlingObserver;

@property (nonatomic,assign,readwrite) LKSStreamCameraScaleMode scaleMode;
@property (nonatomic,assign) CGRect viewFrame;
@property (nonatomic,assign) BOOL tapToFocusEnabled;

@property (nonatomic,assign,readonly) BOOL isRunning;

@end

@implementation LKSStreamCamera

-(id) initWithViewFrame:(CGRect)viewFrame scaleMode:(LKSStreamCameraScaleMode)scaleMode tapToFocusEnabled:(BOOL)tapToFocusEnabled {
    
    if (self = [super init]){
        
        self.scaleMode = scaleMode;
        self.viewFrame = viewFrame;
        self.tapToFocusEnabled = tapToFocusEnabled;
        
    }
    
    return self;
}

- (void)viewDidLoad {
    
    [super viewDidLoad];
    
    self.view.frame = self.viewFrame;
  
    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    self.session = session;
    
    [self.view setBackgroundColor:[UIColor clearColor]];
    
    // Check if camera exists

    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Camera not found", nil)
                                    message:NSLocalizedString(@"A camera is requried to take photos", nil)
                                   delegate:self
                          cancelButtonTitle:NSLocalizedString(@"OK", nil)
                          otherButtonTitles:nil] show];
        
        return;
    }
    
    self.deviceExists = YES;

    dispatch_queue_t sessionQueue = dispatch_queue_create("session queue", DISPATCH_QUEUE_SERIAL);
    self.sessionQueue = sessionQueue;
    
    // Check auth
    [self checkDeviceAuthorizationStatus];

    dispatch_async(self.sessionQueue, ^{
        
        // AV Foundation
        // =============
        // https://developer.apple.com/library/ios/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/04_MediaCapture.html
        
        if ([session canSetSessionPreset:AVCaptureSessionPresetPhoto]) {
            session.sessionPreset = AVCaptureSessionPresetPhoto;
        } else {
            [self onError:@"Ivalid session preset"];
        }
        
        // Find device
        // -----------
        
        AVCaptureDevice *device;
        
        NSArray *devices = [AVCaptureDevice devices];
        
        for (AVCaptureDevice *aDevice in devices) {
            if ([aDevice hasMediaType:AVMediaTypeVideo]) {
                if ([aDevice position] == AVCaptureDevicePositionBack) {
                    NSLog(@"Device name: %@", [aDevice localizedName]);
                    device = aDevice;
                }
            }
        }
        
        if (!device) {
            [self onError:@"Back camera not present"];
            return;
        }
        
        // Configure device
        // ----------------
        
        // An instance of AVCaptureDevice to represent the input device, such as a camera or microphone
        
        [self focusAtPoint:CGPointMake(0.5f, 0.5f) mode:kLKSStreamCameraFocusModeContinuous];
        
        // Flash set to Auto for Still Capture
        [self setFlashMode:AVCaptureFlashModeAuto];
        
        // An instance of a concrete subclass of AVCaptureInput to configure the ports from the input device
        
        // Hookup device
        // -------------
        
        NSError *deviceInputError;
        self.captureDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&deviceInputError];
        if (!self.captureDeviceInput){
            [self onError:deviceInputError.localizedDescription];
        }
        if ([session canAddInput:self.captureDeviceInput]) {
            [session addInput:self.captureDeviceInput];
        } else {
            [self onError:@"Unable to add device input"];
            return;
        }
        
        // Create capture output
        // ---------------------
        
        // An instance of a concrete subclass of AVCaptureOutput to manage the output to a movie file or still image
        
        self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
        if (self.stillImageOutput.stillImageStabilizationSupported){
            [self.stillImageOutput automaticallyEnablesStillImageStabilizationWhenAvailable];
        }
        self.stillImageOutput.highResolutionStillImageOutputEnabled = YES;
        NSDictionary *outputSettings = @{ AVVideoCodecKey : AVVideoCodecJPEG};
        [self.stillImageOutput setOutputSettings:outputSettings];
        if ([session canAddOutput:self.stillImageOutput]) {
            [session addOutput:self.stillImageOutput];
        } else {
            [self onError:@"Unable to add output"];
            return;
        }
        
        // Hookup video preview
        // --------------------
        
        // NOTE: Maybe this goes after auth?
       
        AVCaptureVideoPreviewLayer *captureVideoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
        self.captureVideoPreviewLayer = captureVideoPreviewLayer;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if (self.scaleMode == kLKSStreamCameraModeCrop){
                [self.view.layer setMasksToBounds:YES];
                captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            } else {
                captureVideoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
            }
            captureVideoPreviewLayer.frame = self.view.bounds;
            [self.view.layer addSublayer:captureVideoPreviewLayer];
            //
            if ([captureVideoPreviewLayer.connection isVideoOrientationSupported]){
                [captureVideoPreviewLayer.connection setVideoOrientation:(AVCaptureVideoOrientation)[self interfaceOrientation]];
            }
        });
        
    });
}

- (void)viewWillAppear:(BOOL)animated {
    
    if (!self.sessionQueue){
        return;
    }
    
    dispatch_async(self.sessionQueue, ^{
        
        [self listenForFocusEvents:YES];
        
        // Attempt session reboot
        __weak LKSStreamCamera *weakSelf = self;
        [self setRuntimeErrorHandlingObserver:[[NSNotificationCenter defaultCenter] addObserverForName:AVCaptureSessionRuntimeErrorNotification object:self.session queue:nil usingBlock:^(NSNotification *note) {
            
            LKSStreamCamera *strongSelf = weakSelf;
            dispatch_async([strongSelf sessionQueue], ^{
                // Manually restarting the session since it must have been stopped due to an error.
                [self.session startRunning];
            });
        }]];
        
        [self.session startRunning];
        
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    
    if (!self.sessionQueue){
        return;
    }
    
    dispatch_async(self.sessionQueue, ^{
        
        [self listenForFocusEvents:NO];
        
        [self.session stopRunning];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self.runtimeErrorHandlingObserver];
        
    });
}

-(void) viewDidAppear:(BOOL)animated {
    
    [super viewDidAppear:animated];
    
    
}
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Actions

// Returns nil |image| nil |error| when busy
-(void) takeSnapShot: (void (^)(UIImage *image, NSError *error)) handler {
    
    //CGSize size = CMVideoFormatDescriptionGetPresentationDimensions(camera.activeFormat.formatDescription, YES, YES);
    
    if (!self.isRunning){
        return;
    }
    
    dispatch_async([self sessionQueue], ^{
        
        // Update the orientation on the still image output video connection before capturing.
        [[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] setVideoOrientation:  self.captureVideoPreviewLayer.connection.videoOrientation];
        
        if (self.stillImageOutput.capturingStillImage){
            handler(nil,nil);
            return;
        }
        
        // Capture a still image.
        [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:[self.stillImageOutput connectionWithMediaType:AVMediaTypeVideo] completionHandler:^(CMSampleBufferRef imageDataSampleBuffer, NSError *error) {
            
            if (error){
                handler(nil, error);
            } else if (imageDataSampleBuffer){
                
                //CFDictionaryRef exifAttachments = CMGetAttachment(imageDataSampleBuffer, kCGImagePropertyExifDictionary, NULL);
                //if (exifAttachments) {
                    // Do something with the attachments.
                //}
                
                NSData *imageData = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageDataSampleBuffer];
                UIImage *image = [[UIImage alloc] initWithData:imageData];
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(image, nil);
                });
                
                // [[[ALAssetsLibrary alloc] init] writeImageToSavedPhotosAlbum:[image CGImage] orientation:(ALAssetOrientation)[image imageOrientation] completionBlock:nil];
               
            }
        }];
    });
}

#pragma mark - Orientation

- (BOOL)shouldAutorotate {
    
    return YES;
    
}

- (NSUInteger)supportedInterfaceOrientations {
    
    return UIInterfaceOrientationMaskLandscape;
    
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    
    if ([self.captureVideoPreviewLayer.connection isVideoOrientationSupported]){
        [self.captureVideoPreviewLayer.connection setVideoOrientation:(AVCaptureVideoOrientation)toInterfaceOrientation];
    }
    
}

#pragma mark - Focus

-(void) listenForFocusEvents:(BOOL)listen {
    
    // Tap to focus
    // ------------
    
    if (self.tapToFocusEnabled){
        
        if (listen){
            
            UITapGestureRecognizer *singleFingerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleFocusTap:)];
            [self.view addGestureRecognizer:singleFingerTap];
            
        } else {
            
            for (NSUInteger i = 0; i < self.view.gestureRecognizers.count; i++){
                [self.view removeGestureRecognizer:[self.view.gestureRecognizers objectAtIndex:i]];
                i--;
            }
        }
    }
    
    // Subject area changes
    // --------------------
    
    if (listen){
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(subjectAreaDidChange:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object: self.captureDeviceInput.device];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.captureDeviceInput.device];
    }
}

-(void) handleFocusTap: (UITapGestureRecognizer*)recognizer {
    
    CGPoint location = [recognizer locationInView: recognizer.view];
    CGPoint focalPoint = [self.captureVideoPreviewLayer captureDevicePointOfInterestForPoint:location];
   
    focalPoint.x = fmaxf(focalPoint.x, 0.0f);
    focalPoint.x = fminf(focalPoint.x, 1.0f);
    focalPoint.y = fmaxf(focalPoint.y, 0.0f);
    focalPoint.y = fminf(focalPoint.y, 1.0f);
 
    [self focusAtPoint:focalPoint mode:kLKSStreamCameraFocusModeAuto];
    
}

// |continuousMode| Do not monitor subject area for changes but adjust
// exposure and focus continuously
// !|continuousMode| Auto focus and exposure at point and listen for subject
// matter changes
-(void) focusAtPoint:(CGPoint)focalPoint mode:(LKSStreamCameraFocusMode)mode {
    
    dispatch_async([self sessionQueue], ^{
        
        AVCaptureExposureMode exposureMode;
        AVCaptureWhiteBalanceMode whiteBalanceMode;
        AVCaptureFocusMode focusMode;
        BOOL monitorSubjectArea;
        
        if (mode == kLKSStreamCameraFocusModeContinuous){
            
            exposureMode = AVCaptureExposureModeContinuousAutoExposure;
            whiteBalanceMode = AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance;
            focusMode = AVCaptureFocusModeContinuousAutoFocus;
            monitorSubjectArea = false;
            
        } else if (mode == kLKSStreamCameraFocusModeAuto){
            
            exposureMode = AVCaptureExposureModeAutoExpose;
            whiteBalanceMode = AVCaptureWhiteBalanceModeAutoWhiteBalance;
            focusMode = AVCaptureFocusModeAutoFocus;
            monitorSubjectArea = true;
            
        } else { // Locked
          
            exposureMode = AVCaptureExposureModeLocked;
            whiteBalanceMode = AVCaptureWhiteBalanceModeLocked;
            focusMode = AVCaptureFocusModeLocked;
            monitorSubjectArea = false;
            
        }
        
        AVCaptureDevice *device = self.captureDeviceInput.device;
        
        NSError *error = nil;
        if ([device lockForConfiguration:&error]){
            
            if ([device isFocusPointOfInterestSupported] && [device isFocusModeSupported:focusMode]){
                [device setFocusMode:focusMode];
                [device setFocusPointOfInterest:focalPoint];
            }
            
            if ([device isExposurePointOfInterestSupported] && [device isExposureModeSupported:exposureMode]) {
                [device setExposureMode:exposureMode];
                [device setExposurePointOfInterest:focalPoint];
            }
            
            if ([device isWhiteBalanceModeSupported:whiteBalanceMode]) {
                [device setWhiteBalanceMode:whiteBalanceMode];
            }
            
            // Indicates whether the device should monitor the subject area for changes.
            [device setSubjectAreaChangeMonitoringEnabled:monitorSubjectArea];
            
            [device unlockForConfiguration];
            
        } else {
            
            [self onError:error.localizedDescription];
            
        }
    });
}

- (void)subjectAreaDidChange:(NSNotification *)notification {
    
    [self focusAtPoint:CGPointMake(0.5f, 0.5f) mode:kLKSStreamCameraFocusModeContinuous];
    
}

-(void)setFlashMode:(AVCaptureFlashMode)flashMode {
    
    AVCaptureDevice *device = self.captureDeviceInput.device;
    
    if ([device hasFlash] && [device isFlashModeSupported:flashMode]){
        
        NSError *error = nil;
        if ([device lockForConfiguration:&error]){
            [device setFlashMode:flashMode];
            [device unlockForConfiguration];
        } else {
            [self onError:error.localizedDescription];
        }
        
    }
}

#pragma mark - Authorization

- (void)checkDeviceAuthorizationStatus {
    
    NSString *mediaType = AVMediaTypeVideo;
    
    [AVCaptureDevice requestAccessForMediaType:mediaType completionHandler:^(BOOL granted) {

        if (granted){
            
            self.authOK = YES;
            
        } else {
            
            //Not granted access to mediaType
            dispatch_async(dispatch_get_main_queue(), ^{
                
                [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Camera access required", nil)
                                            message:NSLocalizedString(@"This app does not have permission to access the camera. Please enable camera access in settings to continue", nil)
                                           delegate:self
                                  cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                  otherButtonTitles:nil] show];
                
                self.authOK = NO;
                
            });
        }
    }];
}

#pragma mark - Error handling

-(void) onError:(NSString*)msg {
    
    // Choose to suppress these or not down the track
    
    dispatch_async(dispatch_get_main_queue(), ^{
    
        if (kSupressErrors){
            
            NSLog(@"ERROR:%@",msg);
            
        } else {
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ERROR", nil)
                                        message:msg
                                       delegate:self
                              cancelButtonTitle:NSLocalizedString(@"OK", nil)
                              otherButtonTitles:nil] show];
            
        }
    });
}

#pragma mark - Check status

-(BOOL) isRunning {
    
    return self.authOK && self.deviceExists && self.session && self.session.isRunning;
    
}


@end
