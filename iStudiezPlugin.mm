#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>
#import <objc/runtime.h>
#import <sqlite3.h>

#import "iStudiezPlugin.h"

extern "C" CFStringRef UIDateFormatStringForFormatType(CFStringRef type);

#define TITLE_LABEL_TAG             331
#define LECTURE_TITLE_LABEL_TAG     332
#define LECTURE_TIME_LABEL_TAG      333
#define LECTURE_LOCATION_LABEL_TAG  334
#define LECTURE_TYPE_LABEL_TAG      335
#define LECTURE_DOT_TAG             336

// plugin
@interface iStudiezPlugin (Private)

- (void)update;
- (void)updateLectures;
- (void)updatePreference;
- (void)addLectureFromStatement:(sqlite3_stmt *)statement;

- (UITableViewCell *)tableView:(LITableView *)tableView cellWithTitle:(NSString *)title;
- (UITableViewCell *)tableView:(LITableView *)tableView cellWithLecture:(NSArray *)lecture;

@end

@implementation iStudiezPlugin

@synthesize plugin, databasePath, bundle, lock, lectureList, assignmentList, nextCount, lastChanged, prefsChanged, showEarlier, showFuture, futureDays;

- (id)initWithPlugin:(LIPlugin*)thePlugin
{
    self = [super init];
    self.plugin = thePlugin;

    self.lectureList = [NSMutableArray array];
    self.assignmentList = [NSMutableArray array];
    
    self.prefsChanged = YES;
    self.lastChanged = [NSDate distantPast];
    
    lock = [[NSConditionLock alloc] init];

    plugin.tableViewDataSource = self;
    plugin.tableViewDelegate = self;

    // get DB path
    SBApplication* iStudiezApp = [[objc_getClass("SBApplicationController") sharedInstance] applicationWithDisplayIdentifier:@"com.kachalobalashoff.iStudent"];
    NSString *iStudiezPath = [[iStudiezApp path] stringByDeletingLastPathComponent];
    self.databasePath = [[iStudiezPath stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:(@"iStudiez.sqlite")];
    self.bundle = [NSBundle bundleWithPath:[iStudiezApp path]];
    
    // notification
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(update) name:LITimerNotification object:nil];
    //[center addObserver:self selector:@selector(update) name:LIPrefsUpdatedNotification object:nil];
    [center addObserver:self selector:@selector(update) name:LIViewReadyNotification object:nil];

    return self;
}

- (void)dealloc
{
    self.plugin = nil;
    self.lectureList = nil;
    self.assignmentList = nil;
    self.databasePath = nil;
    self.bundle = nil;
    self.lastChanged = nil;
    [self.lock release];
    self.lock = nil;

    [super dealloc];
}

#pragma mark UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section 
{
    return [self.lectureList count];
}

-(NSInteger) tableView:(LITableView*)tableView numberOfItemsInSection:(NSInteger)section
{
    return self.nextCount;
}

- (BOOL)tableView:(LITableView*) tableView showCountForHeaderInSection:(NSInteger) section
{
    if (self.nextCount > 0)
        return YES;
    else
        return NO;
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath 
{
    id object = [self.lectureList objectAtIndex:indexPath.row];

    UITableViewCell *cell = nil;
    if ([object isKindOfClass:[NSString class]]) {
        cell = [self tableView:tableView cellWithTitle:object];
    } else {
        cell = [self tableView:tableView cellWithLecture:object];
    }

    return cell;
}

- (CGFloat)tableView:(LITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    id object = [self.lectureList objectAtIndex:indexPath.row];

    if ([object isKindOfClass:[NSString class]]) {
        // title
        return 20;
    } else {
        return 35;
    }
}

- (UITableViewCell *)tableView:(LITableView *)tableView cellWithTitle:(NSString *)title
{
    NSString *reuseId = @"TitleCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseId];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseId] autorelease];
        
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        LILabel *titleLabel = [tableView labelWithFrame:CGRectMake(9, 2, 302, 16)];
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

- (UITableViewCell *)tableView:(LITableView *)tableView cellWithLecture:(NSArray *)lecture
{
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
        
        UIImageView *dot = [[[UIImageView alloc] initWithImage:[UIImage li_imageWithContentsOfResolutionIndependentFile:[self.plugin.bundle pathForResource:@"dotmask" ofType:@"png"]]] autorelease];
        dot.frame = dotFrame;
        dot.layer.cornerRadius = 5;
        dot.tag = LECTURE_DOT_TAG;
        [cell.contentView addSubview:dot];
    }

    LILabel *titleLabel = [cell.contentView viewWithTag:LECTURE_TITLE_LABEL_TAG];
    titleLabel.text = (NSString *) [lecture objectAtIndex:0];

    LILabel *timeLabel = [cell.contentView viewWithTag:LECTURE_TIME_LABEL_TAG];
    timeLabel.text = (NSString *) [lecture objectAtIndex:7];
    timeLabel.textAlignment = UITextAlignmentRight;
    
    LILabel *locationLabel = [cell.contentView viewWithTag:LECTURE_LOCATION_LABEL_TAG];
    locationLabel.text = (NSString *) [lecture objectAtIndex:1];
    
    LILabel *typeLabel = [cell.contentView viewWithTag:LECTURE_TYPE_LABEL_TAG];
    typeLabel.text = (NSString *) [lecture objectAtIndex:2];
    typeLabel.textAlignment = UITextAlignmentRight;
    
    UIImageView *dot = [cell.contentView viewWithTag:LECTURE_DOT_TAG];
    NSNumber *hue = [lecture objectAtIndex:4];
    NSNumber *saturation = [lecture objectAtIndex:5];
    NSNumber *brightness = [lecture objectAtIndex:6];
    dot.backgroundColor = [UIColor colorWithHue:[hue floatValue] saturation:[saturation floatValue] brightness:[brightness floatValue] alpha:1.0];

    return cell;
}


- (void)update
{
    if (!self.plugin.enabled) {
        return;
    }

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [self updatePreference];
    
    NSDate *modificationDate = [[[NSFileManager defaultManager] attributesOfItemAtPath:self.databasePath error:nil] fileModificationDate];
    
    if (self.prefsChanged || [self.lastChanged compare:modificationDate] == NSOrderedAscending) {
        if ([lock tryLock]) {
            [self updateLectures];
            self.prefsChanged = NO;
            self.lastChanged = modificationDate;
    		[lock unlock];
    	}
    }
    
    [pool release];
}

- (void)updateLectures
{
    int ret;

    [self.lectureList removeAllObjects];

    NSString *sqlLectureNoWhere = @"SELECT "
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

    sqlite3 *database = NULL;
    @try {
        ret = sqlite3_open([self.databasePath UTF8String], &database);
        if (ret != SQLITE_OK) {
            NSLog(@"iSP: sqlite3_open ret %d", ret);
            return;
        }

        // earlier
        if (self.showEarlier) {
            sqlite3_stmt *statement = NULL;
            @try {
                NSString *sqlForEarlier = [sqlLectureNoWhere stringByAppendingString:@"WHERE "
                    " event.ZENDDATE < strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00') AND "
                    " event.ZDATE = strftime('%s', 'now', 'start of day') - strftime('%s', '2001-01-01 00:00:00') "
                    "ORDER BY start;"];
                ret = (sqlite3_prepare_v2 (database, [sqlForEarlier UTF8String], -1, &statement, NULL) != SQLITE_OK) ;
                if (ret != SQLITE_OK) {
                    NSLog(@"iSP: prepare failed %d", ret);
                    return;
                }

                //NSLog(@"LI: iStudiez Earlier SQL: %@", sqlForEarlier);

                BOOL titleAdded = NO;
                while (sqlite3_step (statement) == SQLITE_ROW) {
                    if (!titleAdded) {
                        [lectureList addObject:@"Earlier"];
                        titleAdded = YES;
                    }

                    [self addLectureFromStatement:statement];
                }
            }
            @finally {
                if (statement != NULL) {
                    sqlite3_finalize(statement);
                    statement = NULL;
                }
            }
        }

        // now
        sqlite3_stmt *statement = NULL;
        @try {
            NSString *sqlForNow = [sqlLectureNoWhere stringByAppendingString:@"WHERE "
                " event.ZSTARTDATE <= strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00') AND "
                " event.ZENDDATE >= strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00');"];
            ret = (sqlite3_prepare_v2 (database, [sqlForNow UTF8String], -1, &statement, NULL) != SQLITE_OK) ;
            if (ret != SQLITE_OK) {
                NSLog(@"iSP: prepare failed %d", ret);
                return;
            }

            //NSLog(@"LI: iStudiez Now SQL: %@", sqlForNow);

            BOOL titleAdded = NO;
            while (sqlite3_step (statement) == SQLITE_ROW) {
                if (!titleAdded) {
                    [lectureList addObject:@"Now"];
                    titleAdded = YES;
                }

                [self addLectureFromStatement:statement];
            }
        }
        @finally {
            if (statement != NULL) {
                sqlite3_finalize(statement);
                statement = NULL;
            }
        }

        // next
        @try {
            NSString *sqlForNext = [sqlLectureNoWhere stringByAppendingString:@"WHERE "
                " event.ZSTARTDATE > strftime('%s', 'now') - strftime('%s', '2001-01-01 00:00:00') AND"
                " event.ZDATE = strftime('%s', 'now', 'start of day') - strftime('%s', '2001-01-01 00:00:00') "
                "ORDER BY start;"];
            ret = (sqlite3_prepare_v2 (database, [sqlForNext UTF8String], -1, &statement, NULL) != SQLITE_OK);
            if (ret != SQLITE_OK) {
                NSLog(@"iSP: prepare failed %d", ret);
                return;
            }

            //NSLog(@"LI: iStudiez Next SQL: %@", sqlForNext);

            BOOL titleAdded = NO;
            self.nextCount = 0;
            while (sqlite3_step (statement) == SQLITE_ROW) {
                if (!titleAdded) {
                    [lectureList addObject:@"Next"];
                    titleAdded = YES;
                }

                self.nextCount++;
                [self addLectureFromStatement:statement];
            }
        }
        @finally {
            if (statement != NULL) {
                sqlite3_finalize(statement);
            }
        }

        // future
        if (self.showFuture) {
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            dateFormatter.timeStyle = NSDateFormatterNoStyle;
            dateFormatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEE, d MMMM" options:0 locale:[NSLocale currentLocale]];

            @try {
                for (int i = 1; i <= self.futureDays; i++) {
                    NSString *sqlForFuture = [sqlLectureNoWhere stringByAppendingString:[NSString stringWithFormat:@"WHERE "
                        " event.ZDATE = strftime('%%s', 'now', 'start of day', '+%d days') - strftime('%%s', '2001-01-01 00:00:00') "
                        "ORDER BY start;", i]];
                    ret = (sqlite3_prepare_v2 (database, [sqlForFuture UTF8String], -1, &statement, NULL) != SQLITE_OK);
                    if (ret != SQLITE_OK) {
                        NSLog(@"iSP: prepare failed %d", ret);
                        return;
                    }

                    //NSLog(@"LI: iStudiez Future SQL: %@", sqlForFuture);

                    BOOL titleAdded = NO;
                    while (sqlite3_step (statement) == SQLITE_ROW) {
                        if (!titleAdded) {
                            if (i == 1) {
                                [lectureList addObject:@"Tomorrow"];
                            } else {
                                [lectureList addObject:[dateFormatter stringFromDate:[[NSDate date] dateByAddingTimeInterval:i*24*60*60]]];
                            }
                            titleAdded = YES;
                        }

                        [self addLectureFromStatement:statement];
                    }
                }
            }
            @finally {
                if (statement != NULL) {
                    sqlite3_finalize(statement);
                }
                [dateFormatter release];
            }
        }

    }
    @finally {
        if (database != NULL) {
            sqlite3_close(database);
        }
    }

    //[[NSNotificationCenter defaultCenter] postNotificationName:LIUpdateViewNotification object:self.plugin userInfo:nil];
}

- (void)addLectureFromStatement:(sqlite3_stmt *)statement
{
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
    NSArray *lecture = [NSArray arrayWithObjects:title, location, type, icon, [NSNumber numberWithDouble:hue], [NSNumber numberWithDouble:saturation], [NSNumber numberWithDouble:brightness], start, end, nil];
    [lectureList addObject:lecture];
}

- (void)updatePreference
{
    NSNumber *value = nil;

    value = [self.plugin.preferences valueForKey:@"ShowEarlier"];
    if ([value boolValue] != self.showEarlier)
        prefsChanged = YES;
    self.showEarlier = [value boolValue];

    value = [self.plugin.preferences valueForKey:@"FutureDays"];
    if ([value intValue] != self.futureDays)
        prefsChanged = YES;
    switch ([value intValue]) {
        case -1:
        self.showFuture = NO;
        self.futureDays = -1;
        break;
        default:
        self.showFuture = YES;
        self.futureDays = [value intValue];
        break;
    }
}

@end
