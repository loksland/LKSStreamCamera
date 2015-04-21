//
//  ViewController.m
//  LKSStreamCamera
//
//  Created by Lachlan Nuttall on 4/04/2015.
//  Copyright (c) 2015 Loksland. All rights reserved.
//

#import "ViewController.h"
#import "LKSStreamCamera.h"
#import "UIViewController+Container.h"

@interface ViewController ()

@property (nonatomic,strong) LKSStreamCamera *streamCamera;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.streamCamera = [[LKSStreamCamera alloc] initWithViewFrame:self.view.frame scaleMode:kLKSStreamCameraModeLetterbox tapToFocusEnabled:YES];
    [self containerAddChildViewController:self.streamCamera];
    [self.view sendSubviewToBack:self.streamCamera.view];
    
}

- (IBAction)takePhoto:(id)sender {
    
    [self.streamCamera takeSnapShot:^(UIImage *image, NSError *error) {
        
        self.imageView.image = image;
        NSLog(@"Img %fx%f:", image.size.width, image.size.height);
        [self.streamCamera lockSettings];
        self.streamCamera.tapToFocusEnabled = NO;
    }];
    
    /*
    
     [stillCamera capturePhotoProcessedUpToFilter:filter withCompletionHandler:^(UIImage *processedImage, NSError *error){
     NSData *dataForJPEGFile = UIImageJPEGRepresentation(processedImage, 0.8);
     
     NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
     NSString *documentsDirectory = [paths objectAtIndex:0];
     
     NSError *error2 = nil;
     if (![dataForJPEGFile writeToFile:[documentsDirectory stringByAppendingPathComponent:@"FilteredPhoto.jpg"] options:NSAtomicWrite error:&error2])
     {
     return;
     }
     }];
     
   */
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
