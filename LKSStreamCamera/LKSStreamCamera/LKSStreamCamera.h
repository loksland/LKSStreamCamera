//
//  LKSStreamCamera.h
//  LKSStreamCamera
//
//  Created by Lachlan Nuttall on 28/03/2015.
//  Copyright (c) 2015 Lachlan Nuttall. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef enum {
    kLKSStreamCameraModeLetterbox = 0,
    kLKSStreamCameraModeCrop
} LKSStreamCameraScaleMode;

@interface LKSStreamCamera : UIViewController

-(id) initWithViewFrame:(CGRect)viewFrame scaleMode:(LKSStreamCameraScaleMode)scaleMode tapToFocusEnabled:(BOOL)tapToFocusEnabled;

@property (nonatomic,assign,readonly) BOOL deviceIsAuthorized;
@property (nonatomic,assign,readonly) LKSStreamCameraScaleMode scaleMode;
@property (nonatomic,assign,readonly) BOOL tapToFocusEnabled;

@property (nonatomic,assign) BOOL locked;

// Returns NO if busy
-(BOOL) takeSnapShot: (void (^)(UIImage *image, NSError *error)) handler;

@property (nonatomic,assign) BOOL busy;

@end
