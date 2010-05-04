#import "ApplicationPickerController.h"

#import "ApplicationCell.h"
#import "Preferences.h"

// SpringBoardServices
extern NSString * SBSCopyLocalizedApplicationNameForDisplayIdentifier(NSString *identifier);
extern NSString * SBSCopyIconImagePathForDisplayIdentifier(NSString *identifier);

@interface UIProgressHUD : UIView

- (id)initWithWindow:(id)fp8;
- (void)setText:(id)fp8;
- (void)show:(BOOL)fp8;
- (void)hide;

@end

//==============================================================================

static NSInteger compareDisplayNames(NSString *a, NSString *b, void *context)
{
    NSInteger ret;

    NSString *name_a = SBSCopyLocalizedApplicationNameForDisplayIdentifier(a);
    NSString *name_b = SBSCopyLocalizedApplicationNameForDisplayIdentifier(b);
    ret = [name_a caseInsensitiveCompare:name_b];
    [name_a release];
    [name_b release];

    return ret;
}

//==============================================================================

static NSArray *applicationDisplayIdentifiers()
{
    // First, get a list of all possible application paths
    NSMutableArray *paths = [NSMutableArray array];

    // ... scan /Applications (System/Jailbreak applications)
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in [fileManager directoryContentsAtPath:@"/Applications"]) {
        if ([path hasSuffix:@".app"] && ![path hasPrefix:@"."])
           [paths addObject:[NSString stringWithFormat:@"/Applications/%@", path]];
    }

    // ... scan /var/mobile/Applications (AppStore applications)
    for (NSString *path in [fileManager directoryContentsAtPath:@"/var/mobile/Applications"]) {
        for (NSString *subpath in [fileManager directoryContentsAtPath:
                [NSString stringWithFormat:@"/var/mobile/Applications/%@", path]]) {
            if ([subpath hasSuffix:@".app"])
                [paths addObject:[NSString stringWithFormat:@"/var/mobile/Applications/%@/%@", path, subpath]];
        }
    }

    // Then, go through paths and record valid application identifiers
    NSMutableArray *identifiers = [NSMutableArray array];

    for (NSString *path in paths) {
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (bundle) {
            NSString *identifier = [bundle bundleIdentifier];

            // Filter out non-applications and apps that should remain hidden
            // FIXME: The proper fix is to only show non-hidden apps and apps
            //        that are in Categories; unfortunately, the design of
            //        Categories does not make it easy to determine what apps
            //        a given folder contains.
            if (identifier &&
                ![identifier hasPrefix:@"jp.ashikase.springjumps."] &&
                ![identifier isEqualToString:@"com.iptm.bigboss.sbsettings"] &&
                ![identifier isEqualToString:@"com.apple.webapp"])
            [identifiers addObject:identifier];
        }
    }

    return identifiers;
}

//==============================================================================

// Create an array to cache the result of application enumeration
// NOTE: Once created, this global will exist until program termination.
static NSArray *allApplications = nil;

@interface ApplicationPickerController (Private)
- (void)findAvailableItems;
@end

@implementation ApplicationPickerController

@synthesize delegate;

- (id)initWithDelegate:(id<ApplicationPickerControllerDelegate>)delegate_
{
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		delegate = delegate_;
	}
	return self;
}

- (void)loadView
{
	// Create a navigation bar
	UINavigationBar *navBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, 320.0f, 44.0f)];
	navBar.barStyle = UIBarStyleBlackOpaque;
    navBar.tintColor = [UIColor colorWithWhite:0.23 alpha:1];
	navBar.delegate = self;

	// Add title and buttons to navigation bar
	UINavigationItem *navItem = [[UINavigationItem alloc] initWithTitle:@"Applications"];
    navItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"Done"
            style:UIBarButtonItemStyleBordered target:self action:@selector(doneButtonTapped)] autorelease];
	[navBar pushNavigationItem:navItem animated:NO];
	[navItem release];

	// Create a table
	// NOTE: Height is screen height - nav bar
	appsTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 44.0f, 320.0f, 460.0f - 44.0f)];
	appsTableView.dataSource = self;
	appsTableView.delegate = self;
	//[appsTableView setSeparatorStyle:2]; /* 0 no lines, 1 thin lines, 2 bold lines */

	// Create a view to hold the navigation bar and table
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    [view addSubview:navBar]; 
    [view addSubview:appsTableView]; 
	[navBar release];

    self.view = view;
}

- (void)dealloc
{
    [busyIndicator release];
    [appsTableView release];
    [applications release];

    [super dealloc];
}

- (void)loadFilteredList
{
    [applications release];
    applications = [allApplications mutableCopy];
    [applications removeObjectsInArray:[[[Preferences sharedInstance] objectForKey:kOverrides] allKeys]];
}

- (void)enumerateApplications
{
    NSArray *array = applicationDisplayIdentifiers();
    NSArray *sortedArray = [array sortedArrayUsingFunction:compareDisplayNames context:NULL];
    allApplications = [sortedArray retain];
    [self loadFilteredList];
    [appsTableView reloadData];

    // Remove the progress indicator
    [busyIndicator hide];
    [busyIndicator release];
    busyIndicator = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    // Reset the table by deselecting the current selection
    [appsTableView deselectRowAtIndexPath:[appsTableView indexPathForSelectedRow] animated:YES];

    if (allApplications != nil) {
        // Application list already loaded
        [self loadFilteredList];
        [appsTableView reloadData];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    // NOTE: The initial list is loaded after the view appears for style considerations.
    // FIXME: Show busy indicator *before* the view appears.
    if (allApplications == nil) {
        // Show a progress indicator
        busyIndicator = [[UIProgressHUD alloc] initWithWindow:[[UIApplication sharedApplication] keyWindow]];
        [busyIndicator setText:@"Loading applications..."];
        [busyIndicator show:YES];

        // Enumerate applications
        // NOTE: Must call via performSelector, or busy indicator does not show in time
        [self performSelector:@selector(enumerateApplications) withObject:nil afterDelay:0.1f];
    }
}

#pragma mark - UITableViewDataSource

- (int)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(int)section
{
    return nil;
}

- (int)tableView:(UITableView *)tableView numberOfRowsInSection:(int)section
{
    NSLog(@"=== returning: %d", [applications count]);
    return [applications count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *reuseIdentifier = @"ApplicationCell";

    // Try to retrieve from the table view a now-unused cell with the given identifier
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        // Cell does not exist, create a new one
        cell = [[[ApplicationCell alloc] initWithFrame:CGRectZero reuseIdentifier:reuseIdentifier] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        //cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    NSString *identifier = [applications objectAtIndex:indexPath.row];
    NSLog(@"=== cell is: %@", identifier);

    NSString *displayName = SBSCopyLocalizedApplicationNameForDisplayIdentifier(identifier);
    [cell setText:displayName];
    [displayName release];

    UIImage *icon = nil;
    NSString *iconPath = SBSCopyIconImagePathForDisplayIdentifier(identifier);
    if (iconPath != nil) {
        icon = [UIImage imageWithContentsOfFile:iconPath];
        [iconPath release];
    }
    [cell setImage:icon];

    return cell;
}

#pragma mark - UITableViewCellDelegate methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath 
{
	if ([delegate respondsToSelector:@selector(applicationPickerController:didSelectAppWithDisplayIdentifier:)])
		[delegate applicationPickerController:self didSelectAppWithDisplayIdentifier:[applications objectAtIndex:indexPath.row]];
}

#pragma mark - Navigation-bar button actions

- (void)doneButtonTapped
{
	[self.parentViewController dismissModalViewControllerAnimated:YES];

	if ([delegate respondsToSelector:@selector(applicationPickerControllerDidFinish:)])
		[delegate applicationPickerControllerDidFinish:self];
}

@end

/* vim: set syntax=objc sw=4 ts=4 sts=4 expandtab textwidth=80 ff=unix: */