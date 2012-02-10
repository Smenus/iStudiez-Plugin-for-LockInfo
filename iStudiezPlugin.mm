#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>
#import <sqlite3.h>

#include "LockInfo/Plugin.h"

#define TITLE_LABEL_TAG             331
#define LECTURE_TITLE_LABEL_TAG     332
#define LECTURE_TIME_LABEL_TAG      333
#define LECTURE_LOCATION_LABEL_TAG  334
#define LECTURE_TYPE_LABEL_TAG      335
#define LECTURE_DOT_TAG             336

#ifdef DEBUG
#   define DLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
#   define DLog(...)
#endif
#define ALog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__);


@interface iStudiezPlugin : NSObject <LIPluginController, LITableViewDelegate, UITableViewDataSource> 

@property (nonatomic, retain) LIPlugin *plugin;
@property (nonatomic, retain) NSString *databasePath;
@property (nonatomic, retain) NSBundle *bundle;
@property (nonatomic, retain) NSLock* lock;
@property (nonatomic, retain) NSArray *sqlList;
@property (nonatomic, retain) NSArray *lectureList;
@property (nonatomic, retain) NSDate *lastUpdated;
@property (nonatomic, readonly) NSDate *lastDBChange;
@property (nonatomic, readonly) int nextCount;
@property (nonatomic, readonly) BOOL showEarlier;
@property (nonatomic, readonly) BOOL showFuture;
@property (nonatomic, readonly) int futureDays;

@end


@interface iStudiezPlugin (Private)

- (void)_initVariables;
- (void)update:(NSNotification*)notif;
- (void)_generateSQL;
- (void)_updateLectures;
- (NSDictionary *)_lectureFromStatement:(sqlite3_stmt *)statement;

- (UITableViewCell *)_tableView:(LITableView *)tableView cellWithTitle:(NSString *)title;
- (UITableViewCell *)_tableView:(LITableView *)tableView cellWithLecture:(NSDictionary *)lecture;

@end


@implementation iStudiezPlugin

@synthesize plugin = _plugin;
@synthesize databasePath = _databasePath;
@synthesize bundle = _bundle;
@synthesize lock = _lock;
@synthesize sqlList = _sqlList;
@synthesize lectureList = _lectureList;
@synthesize lastUpdated = _lastUpdated;
@synthesize lastDBChange = _lastDBChange;


- (NSDate *)lastDBChange {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:self.databasePath error:nil] fileModificationDate];
}

- (int)nextCount {
    int start = [self.lectureList indexOfObject:@"Next"];
    
    if (start == NSNotFound)
        return 0;
    
    for (unsigned int i = start + 1; i < [self.lectureList count]; i++) {
        if ([[self.lectureList objectAtIndex:i] isKindOfClass:[NSString class]])
            return i - start - 1;
    }
    
    return [self.lectureList count] - start - 1;
}

- (BOOL)showEarlier {
    NSNumber *value = [self.plugin.preferences valueForKey:@"ShowEarlier"];
    return [value boolValue];
}

- (BOOL)showFuture {
    if (self.futureDays == -1)
        return NO;
    else
        return YES;
}

- (int)futureDays {
    NSNumber *value = [self.plugin.preferences valueForKey:@"FutureDays"];
    return [value intValue];
}


- (id)initWithPlugin:(LIPlugin*)thePlugin {
    self = [super init];

    self.plugin = thePlugin;
        
    self.plugin.tableViewDataSource = self;
    self.plugin.tableViewDelegate = self;
    
    [self _initVariables];
    
    // notification
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(update:) name:LITimerNotification object:nil];
    [center addObserver:self selector:@selector(update:) name:LIViewReadyNotification object:nil];
    [center addObserver:self selector:@selector(update:) name:[self.plugin.bundleIdentifier stringByAppendingString:LIPrefsUpdatedNotification] object:nil];
    [center addObserver:self selector:@selector(update:) name:[self.bundle.bundleIdentifier stringByAppendingString:LIApplicationDeactivatedNotification] object:nil];
    
    return self;
}

- (void)_initVariables {
    self.lastUpdated = [NSDate distantPast];
    
    self.lock = [[NSLock alloc] init];
    
    SBApplication* iStudiezApp = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithDisplayIdentifier:@"com.kachalobalashoff.iStudent"];
    NSString *iStudiezPath = [[iStudiezApp path] stringByDeletingLastPathComponent];
    self.databasePath = [[iStudiezPath stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:(@"iStudiez.sqlite")];
    self.bundle = [NSBundle bundleWithPath:[iStudiezApp path]];
    
    self.lectureList = [NSArray array];
    self.sqlList = [NSArray array];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    self.plugin = nil;
    _databasePath = nil;
    _bundle = nil;
    [self.lock release];
    _lock = nil;
    self.sqlList = nil;
    self.lectureList = nil;
    self.lastUpdated = nil;
    _lastDBChange = nil;

    [super dealloc];
}

#pragma mark UITableViewDataSource
//Total number of rows in table
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    DLog(@"iSP: numberOfRowsInSection - %d", [self.lectureList count]);
    return [self.lectureList count];
}

//Number to be displayed in header
-(NSInteger) tableView:(LITableView*)tableView numberOfItemsInSection:(NSInteger)section {
    DLog(@"iSP: numberOfItemsInSection - %d", self.nextCount);
    return self.nextCount;
}

//Display number in header
- (BOOL)tableView:(LITableView*) tableView showCountForHeaderInSection:(NSInteger) section {
    if (self.nextCount > 0)
        return YES;
    else
        return NO;
}

- (CGFloat)tableView:(LITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    id object = [self.lectureList objectAtIndex:indexPath.row];

    if ([object isKindOfClass:[NSString class]]) {
        // title
        return 20;
    } else {
        return 35;
    }
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    id object = [self.lectureList objectAtIndex:indexPath.row];

    UITableViewCell *cell = nil;
    if ([object isKindOfClass:[NSString class]]) {
        cell = [self _tableView:tableView cellWithTitle:object];
    } else {
        cell = [self _tableView:tableView cellWithLecture:object];
    }

    return cell;
}

- (UITableViewCell *)_tableView:(LITableView *)tableView cellWithTitle:(NSString *)title {
    NSString *reuseId = @"TitleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId] autorelease];
        
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        LILabel *titleLabel = [tableView labelWithFrame:CGRectMake(9, 2, 302, 17)];
        titleLabel.style = tableView.theme.headerStyle;
        titleLabel.numberOfLines = 1;
        titleLabel.backgroundColor = [UIColor clearColor];
        titleLabel.textAlignment = UITextAlignmentLeft;

        titleLabel.tag = TITLE_LABEL_TAG;
        [cell.contentView addSubview:titleLabel];
    }

    LILabel *titleLabel = [cell.contentView viewWithTag:TITLE_LABEL_TAG];
    titleLabel.text = title;

    return cell;
}

- (UITableViewCell *)_tableView:(LITableView *)tableView cellWithLecture:(NSDictionary *)lecture {
    NSString *reuseId = @"LectureCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId] autorelease];

        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        CGRect titleLabelFrame = CGRectMake(24, 3, 246, 15);
        CGRect timeLabelFrame = CGRectMake(270, 3, 45, 15);
        CGRect locationLabelFrame = CGRectMake(24, 18, 150, 14);
        CGRect typeLabelFrame = CGRectMake(174, 18, 141, 14);
        CGRect dotFrame = CGRectMake(6, 12, 10, 10);

        LILabel *titleLabel = [tableView labelWithFrame:titleLabelFrame];
        titleLabel.backgroundColor = [UIColor clearColor];
        titleLabel.style = tableView.theme.summaryStyle;
        titleLabel.tag = LECTURE_TITLE_LABEL_TAG;
        [cell.contentView addSubview:titleLabel];

        LILabel *timeLabel = [tableView labelWithFrame:timeLabelFrame];
        timeLabel.backgroundColor = [UIColor clearColor];
        timeLabel.style = tableView.theme.summaryStyle;
        timeLabel.tag = LECTURE_TIME_LABEL_TAG;
        [cell.contentView addSubview:timeLabel];
        
        LILabel *locationLabel = [tableView labelWithFrame:locationLabelFrame];
        locationLabel.backgroundColor = [UIColor clearColor];
        locationLabel.style = tableView.theme.detailStyle;
        locationLabel.tag = LECTURE_LOCATION_LABEL_TAG;
        [cell.contentView addSubview:locationLabel];
        
        LILabel *typeLabel = [tableView labelWithFrame:typeLabelFrame];
        typeLabel.backgroundColor = [UIColor clearColor];
        typeLabel.style = tableView.theme.detailStyle;
        typeLabel.tag = LECTURE_TYPE_LABEL_TAG;
        [cell.contentView addSubview:typeLabel];
        
        UIImageView *dot = [[UIImageView alloc] initWithImage:[UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"dotmask" ofType:@"png"]]];
        dot.frame = dotFrame;
        dot.layer.cornerRadius = 5;
        dot.tag = LECTURE_DOT_TAG;
        [cell.contentView addSubview:dot];
        [dot release];
    }

    LILabel *titleLabel = [cell.contentView viewWithTag:LECTURE_TITLE_LABEL_TAG];
    titleLabel.text = [lecture objectForKey:@"title"];

    LILabel *timeLabel = [cell.contentView viewWithTag:LECTURE_TIME_LABEL_TAG];
    timeLabel.text = [lecture objectForKey:@"start"];
    timeLabel.textAlignment = UITextAlignmentRight;
    
    LILabel *locationLabel = [cell.contentView viewWithTag:LECTURE_LOCATION_LABEL_TAG];
    locationLabel.text = [lecture objectForKey:@"location"];
    
    LILabel *typeLabel = [cell.contentView viewWithTag:LECTURE_TYPE_LABEL_TAG];
    typeLabel.text = [lecture objectForKey:@"type"];
    typeLabel.textAlignment = UITextAlignmentRight;
    
    UIImageView *dot = [cell.contentView viewWithTag:LECTURE_DOT_TAG];
    NSNumber *hue = [lecture objectForKey:@"hue"];
    NSNumber *saturation = [lecture objectForKey:@"saturation"];
    NSNumber *brightness = [lecture objectForKey:@"brightness"];
    dot.backgroundColor = [UIColor colorWithHue:[hue floatValue] saturation:[saturation floatValue] brightness:[brightness floatValue] alpha:1.0];

    return cell;
}


- (void)update:(NSNotification*)notif
{
    if (!self.plugin.enabled) {
        return;
    }
    
    DLog(@"iSP: update started - %@", notif.name);

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    @try {
        BOOL dbChanged = [self.lastUpdated timeIntervalSinceDate:self.lastDBChange] < 0 ? YES : NO;
        BOOL force = [notif.name isEqualToString:[self.plugin.bundleIdentifier stringByAppendingString:LIPrefsUpdatedNotification]] ||
                     [notif.name isEqualToString:[self.bundle.bundleIdentifier stringByAppendingString:LIApplicationDeactivatedNotification]] ||
                     [[NSDate date] timeIntervalSinceDate:self.lastUpdated] > 60;
        DLog(@"iSP: force - %@ (%@, %@), dbChanged - %@", force ? @"YES" : @"NO", notif.name, self.lastUpdated, dbChanged ? @"YES" : @"NO");

        if (force || dbChanged) {
            if ([self.lock tryLock]) {
                [self _generateSQL];
                DLog(@"iSP: updating");
                [self _updateLectures];
        		[self.lock unlock];
        	}
        }
    }
    @catch (id theException) {
		DLog(@"iSP: %@", theException);
	}
    
    DLog(@"iSP: update done");
    
    [pool release];
}

- (void)_generateSQL {
    NSMutableArray *newSQL = [NSMutableArray array];
    
    DLog(@"iSP: generating SQL");

    NSString *basicSQL = @"SELECT "
        " infocourse.ZNAME1 AS course, "
        " infolocation.ZBUILDING || ' ' || infolocation.ZROOM AS location, "
        " info.ZTYPEIDENTIFIER AS type, "
        " info.ZICONIDENTIFIER AS icon, "
        " infocolour.ZHUEVALUE AS hue, "
        " infocolour.ZSATURATIONVALUE AS saturation, "
        " infocolour.ZBRIGHTNESSVALUE AS brightness, "
        " strftime('%H:%M', strftime('%s', event.ZSTARTDATE, 'unixepoch') + strftime('%s', '2001-01-01 00:00:00'), 'unixepoch') as start, "
        " strftime('%H:%M', strftime('%s', event.ZENDDATE, 'unixepoch') + strftime('%s', '2001-01-01 00:00:00'), 'unixepoch') as end "
        "FROM ZCALENDARITEM AS event "
        "INNER JOIN ZMERGEABLE AS info ON info.Z_PK=event.ZOCCURRENCE "
        "INNER JOIN ZMERGEABLE AS infolocation ON infolocation.Z_PK=info.ZLOCATION1 "
        "INNER JOIN ZMERGEABLE AS infocourse ON infocourse.Z_PK=info.ZCOURSE4 "
        "INNER JOIN ZMERGEABLE AS infocolour ON infocolour.Z_PK=infocourse.ZCOLOR ";

    if (self.showEarlier) {
        [newSQL addObject:@"Earlier"];
        [newSQL addObject:[basicSQL stringByAppendingString:@"WHERE "
            " event.ZENDDATE < strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00') AND "
            " event.ZDATE = strftime('%s', 'now', 'start of day') - strftime('%s', '2001-01-01 00:00:00') "
            "ORDER BY start;"]];
    }

    [newSQL addObject:@"Now"];
    [newSQL addObject:[basicSQL stringByAppendingString:@"WHERE "
        " event.ZSTARTDATE <= strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00') AND "
        " event.ZENDDATE >= strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00');"]];

    [newSQL addObject:@"Next"];
    [newSQL addObject:[basicSQL stringByAppendingString:@"WHERE "
        " event.ZSTARTDATE > strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00') AND"
        " event.ZDATE = strftime('%s', 'now', 'start of day') - strftime('%s', '2001-01-01 00:00:00') "
        "ORDER BY start;"]];

    if (self.showFuture) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.timeStyle = NSDateFormatterNoStyle;
        dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEE, d MMMM" options:0 locale:[NSLocale currentLocale]];

        for (int i = 1; i <= self.futureDays; i++) {
            [newSQL addObject:i == 1 ? @"Tomorrow" : [dateFormatter stringFromDate:[[NSDate date] dateByAddingTimeInterval:i*24*60*60]]];
            [newSQL addObject:[basicSQL stringByAppendingString:[NSString stringWithFormat:@"WHERE "
                " event.ZDATE = strftime('%%s', 'now', 'start of day', '+%d days') - strftime('%%s', '2001-01-01 00:00:00') "
                "ORDER BY start;", i]]];
        }

        [dateFormatter release];
    }

    DLog(@"iSP: generated SQL");
    
    self.sqlList = [newSQL copy];
}

- (void)_updateLectures {
    int ret;
    NSMutableArray *newLectureList = [NSMutableArray array];

    sqlite3 *database = NULL;
    
    DLog(@"iSP: updating lectures");
    
    @try {
        ret = sqlite3_open([self.databasePath UTF8String], &database);
        if (ret != SQLITE_OK) {
            ALog(@"iSP: sqlite3_open ret %d", ret);
            return;
        }
        
        for (unsigned int i = 0; i < [self.sqlList count]; i++) {
            sqlite3_stmt *statement = NULL;
            @try {
                NSString *title = [self.sqlList objectAtIndex:i];
                NSString *sql = [self.sqlList objectAtIndex:++i];
                
                DLog(@"iSP: %d, %@", i, title);
                
                ret = (sqlite3_prepare_v2 (database, [sql UTF8String], -1, &statement, NULL) != SQLITE_OK) ;
                if (ret != SQLITE_OK) {
                    ALog(@"iSP: prepare failed %d", ret);
                    ALog(@"iSP: SQL - %@", sql);
                    return;
                }

                BOOL titleAdded = NO;
                while (sqlite3_step(statement) == SQLITE_ROW) {
                    if (!titleAdded) {
                        [newLectureList addObject:title];
                        titleAdded = YES;
                    }

                    [newLectureList addObject:[self _lectureFromStatement:statement]];
                }
            }
            @finally {
                if (statement != NULL) {
                    sqlite3_finalize(statement);
                    statement = NULL;
                }
            }
        }
    }
    @finally {
        if (database != NULL) {
            sqlite3_close(database);
            self.lectureList = [newLectureList copy];
            self.lastUpdated = [NSDate date];
            [[NSNotificationCenter defaultCenter] postNotificationName:LIUpdateViewNotification object:self.plugin userInfo:nil];
        }
    }
    
    DLog(@"iSP: updated lectures");
}

- (NSDictionary *)_lectureFromStatement:(sqlite3_stmt *)statement {
    const char *titlePtr = (const char*) sqlite3_column_text (statement, 0);
    const char *locationPtr = (const char*) sqlite3_column_text (statement, 1);
    const char *typePtr = (const char*) sqlite3_column_text (statement, 2);
    const char *iconPtr = (const char*) sqlite3_column_text (statement, 3);
    double hue  = sqlite3_column_double (statement, 4);
    double saturation  = sqlite3_column_double (statement, 5);
    double brightness  = sqlite3_column_double (statement, 6);
    const char *startPtr = (const char*) sqlite3_column_text (statement, 7);
    const char *endPtr = (const char*) sqlite3_column_text (statement, 8);

    NSString *title = [NSString stringWithUTF8String:(titlePtr == NULL ? "" : titlePtr)];
    NSString *location = [NSString stringWithUTF8String:(locationPtr == NULL ? "" : locationPtr)];
    NSString *type = [NSString stringWithUTF8String:(typePtr == NULL ? "" : typePtr)];
    type = [self.bundle localizedStringForKey:type value:type table:nil];
    NSString *icon = [NSString stringWithUTF8String:(iconPtr == NULL ? "" : iconPtr)];
    NSString *start = [NSString stringWithUTF8String:(startPtr == NULL ? "" : startPtr)];
    NSString *end = [NSString stringWithUTF8String:(endPtr == NULL ? "" : endPtr)];
    NSDictionary *lecture = [NSDictionary dictionaryWithObjectsAndKeys:title, @"title",
        location, @"location",
        type, @"type",
        icon, @"icon",
        [NSNumber numberWithDouble:hue], @"hue",
        [NSNumber numberWithDouble:saturation], @"saturation",
        [NSNumber numberWithDouble:brightness], @"brightness",
        start, @"start",
        end, @"end", nil];
    
    return lecture;
}

@end
