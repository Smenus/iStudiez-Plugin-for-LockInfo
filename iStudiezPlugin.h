#import <Foundation/Foundation.h>
#include "LockInfo/Plugin.h"

@interface iStudiezPlugin : NSObject <LIPluginController, LITableViewDelegate, UITableViewDataSource> 
{

}

@property (nonatomic, retain) LIPlugin *plugin;
@property (nonatomic, retain) NSString *databasePath;
@property (nonatomic, retain) NSBundle *bundle;
@property (nonatomic, retain) NSConditionLock* lock;
@property (nonatomic, retain) NSMutableArray *lectureList;
@property (nonatomic, retain) NSMutableArray *assignmentList;
@property (nonatomic, assign) int nextCount;
@property (nonatomic, retain) NSDate *lastChanged;
@property (nonatomic, assign) BOOL prefsChanged;
@property (nonatomic, assign) BOOL showEarlier;
@property (nonatomic, assign) BOOL showFuture;
@property (nonatomic, assign) int futureDays;

@end
