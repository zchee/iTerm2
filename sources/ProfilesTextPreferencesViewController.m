//
//  ProfilesTextPreferencesViewController.m
//  iTerm
//
//  Created by George Nachman on 4/15/14.
//
//

#import "ProfilesTextPreferencesViewController.h"
#import "FutureMethods.h"
#import "ITAddressBookMgr.h"
#import "iTermFontPanel.h"
#import "iTermWarning.h"
#import "NSFont+iTerm.h"
#import "NSStringITerm.h"
#import "PreferencePanel.h"

// Tag on button to open font picker for non-ascii font.
typedef NS_ENUM(NSInteger, FontPrefButtonTag) {
    kGlobalFontButtonTag = 1,
    kEastAsianFontButtonTag,
    kPrivateUseAreaFontButtonTag,
    kNonAsciiFontButtonTag,
};

@interface ProfilesTextPreferencesViewController ()
@property(nonatomic, retain) NSFont *normalFont;
@property(nonatomic, retain) NSFont *eastAsianFont;
@property(nonatomic, retain) NSFont *privateUseAreaFont;
@property(nonatomic, retain) NSFont *nonAsciiFont;
@end

@implementation ProfilesTextPreferencesViewController {
    // cursor type: underline/vertical bar/box
    // See ITermCursorType. One of: CURSOR_UNDERLINE, CURSOR_VERTICAL, CURSOR_BOX
    IBOutlet NSMatrix *_cursorType;
    IBOutlet NSButton *_blinkingCursor;
    IBOutlet NSButton *_useBoldFont;
    IBOutlet NSButton *_useBrightBold;  // Bold text in bright colors
    IBOutlet NSButton *_blinkAllowed;
    IBOutlet NSButton *_useItalicFont;
    IBOutlet NSButton *_ambiguousIsDoubleWidth;
    IBOutlet NSButton *_useHFSPlusMapping;
    IBOutlet NSSlider *_horizontalSpacing;
    IBOutlet NSSlider *_verticalSpacing;
    IBOutlet NSButton *_useEastAsianFont;
    IBOutlet NSButton *_usePrivateUseAreaFont;
    IBOutlet NSButton *_useNonAsciiFont;
    IBOutlet NSButton *_asciiAntiAliased;
    IBOutlet NSButton *_eastAsianAntiAliased;
    IBOutlet NSButton *_privateUseAreaAntiAliased;
    IBOutlet NSButton *_nonasciiAntiAliased;
    IBOutlet NSPopUpButton *_thinStrokes;

    // Labels indicating current font. Not registered as controls.
    IBOutlet NSTextField *_normalFontDescription;
    IBOutlet NSTextField *_eastAsianFontDescription;
    IBOutlet NSTextField *_privateUseAreaFontDescription;
    IBOutlet NSTextField *_nonAsciiFontDescription;

    // Warning labels
    IBOutlet NSTextField *_normalFontWantsAntialiasing;
    IBOutlet NSTextField *_eastAsianFontWantsAntialiasing;
    IBOutlet NSTextField *_privateUseAreaFontWantsAntialiasing;
    IBOutlet NSTextField *_nonasciiFontWantsAntialiasing;

    // Hide this view to hide all non-ASCII font settings.
    IBOutlet NSView *_nonAsciiFontView;
    IBOutlet NSView *_eastAsianFontView;
    IBOutlet NSView *_privateUseAreaView;

    // If set, the font picker was last opened to change the non-ascii font.
    // Used to interpret messages from it.
    FontPrefButtonTag _fontPickerTag;

    // This view is added to the font panel.
    IBOutlet NSView *_displayFontAccessoryView;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_normalFont release];
    [_eastAsianFont release];
    [_privateUseAreaFont release];
    [_nonAsciiFont release];
    [super dealloc];
}

- (void)awakeFromNib {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reloadProfiles)
                                                 name:kReloadAllProfiles
                                               object:nil];
    [self defineControl:_cursorType
                    key:KEY_CURSOR_TYPE
                   type:kPreferenceInfoTypeMatrix
         settingChanged:^(id sender) { [self setInt:[[sender selectedCell] tag] forKey:KEY_CURSOR_TYPE]; }
                 update:^BOOL{ [_cursorType selectCellWithTag:[self intForKey:KEY_CURSOR_TYPE]]; return YES; }];

    [self defineControl:_blinkingCursor
                    key:KEY_BLINKING_CURSOR
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_useBoldFont
                    key:KEY_USE_BOLD_FONT
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_thinStrokes
                    key:KEY_THIN_STROKES
                   type:kPreferenceInfoTypePopup];

    [self defineControl:_useBrightBold
                    key:KEY_USE_BRIGHT_BOLD
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_blinkAllowed
                    key:KEY_BLINK_ALLOWED
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_useItalicFont
                    key:KEY_USE_ITALIC_FONT
                   type:kPreferenceInfoTypeCheckbox];

    PreferenceInfo *info = [self defineControl:_ambiguousIsDoubleWidth
                                           key:KEY_AMBIGUOUS_DOUBLE_WIDTH
                                          type:kPreferenceInfoTypeCheckbox];
    info.customSettingChangedHandler = ^(id sender) {
        BOOL isOn = [sender state] == NSOnState;
        if (isOn) {
            static NSString *const kWarnAboutAmbiguousWidth = @"NoSyncWarnAboutAmbiguousWidth";
            // This is a feature of dubious value inherited from iTerm 0.1. Some users who work in
            // mixed Asian/non-asian environments find it useful but almost nobody should turn it on
            // unless they really know what they're doing.
            iTermWarningSelection selection =
                [iTermWarning showWarningWithTitle:@"You probably don't want to turn this on. "
                                                   @"It will confuse interactive programs. "
                                                   @"You might want it if you work mostly with "
                                                   @"East Asian text combined with legacy or "
                                                   @"mathematical character sets. "
                                                   @"Are you sure you want this?"
                                           actions:@[ @"Enable", @"Cancel" ]
                                        identifier:kWarnAboutAmbiguousWidth
                                       silenceable:kiTermWarningTypePermanentlySilenceable];
            if (selection == kiTermWarningSelection0) {
                [self setBool:YES forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
            }
        } else {
            [self setBool:NO forKey:KEY_AMBIGUOUS_DOUBLE_WIDTH];
        }
    };

    [self defineControl:_useHFSPlusMapping
                    key:KEY_USE_HFS_PLUS_MAPPING
                   type:kPreferenceInfoTypeCheckbox];

    [self defineControl:_horizontalSpacing
                    key:KEY_HORIZONTAL_SPACING
                   type:kPreferenceInfoTypeSlider];

    [self defineControl:_verticalSpacing
                    key:KEY_VERTICAL_SPACING
                   type:kPreferenceInfoTypeSlider];

    info = [self defineControl:_useEastAsianFont
                           key:KEY_USE_EAST_ASIAN_FONT
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateNonAsciiFontViewVisibility]; };


    info = [self defineControl:_usePrivateUseAreaFont
                           key:KEY_USE_PUA_FONT
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateNonAsciiFontViewVisibility]; };

    info = [self defineControl:_useNonAsciiFont
                           key:KEY_USE_NONASCII_FONT
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateNonAsciiFontViewVisibility]; };

    info = [self defineControl:_asciiAntiAliased
                           key:KEY_ASCII_ANTI_ALIASED
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateWarnings]; };

    info = [self defineControl:_eastAsianAntiAliased
                           key:KEY_EAST_ASIAN_ALIASED
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateWarnings]; };

    info = [self defineControl:_privateUseAreaAntiAliased
                           key:KEY_PUA_ALIASED
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateWarnings]; };

    info = [self defineControl:_nonasciiAntiAliased
                           key:KEY_NONASCII_ANTI_ALIASED
                          type:kPreferenceInfoTypeCheckbox];
    info.observer = ^{ [self updateWarnings]; };

    [self updateFontsDescriptions];
    [self updateNonAsciiFontViewVisibility];
}

- (void)reloadProfile {
    [super reloadProfile];
    [self updateFontsDescriptions];
    [self updateNonAsciiFontViewVisibility];
}

- (NSArray *)keysForBulkCopy {
    NSArray *keys = @[ KEY_NORMAL_FONT, KEY_EAST_ASIAN_FONT, KEY_PUA_FONT, KEY_NON_ASCII_FONT ];
    return [[super keysForBulkCopy] arrayByAddingObjectsFromArray:keys];
}

- (void)setViewControlState:(NSView *)view enabled:(BOOL)enabled {
    for (NSView *subview in [view subviews]) {
        if ([subview isKindOfClass:[NSControl class]]) {
            [(NSControl *)subview setEnabled:enabled];
        }
    }
}

- (void)updateNonAsciiFontViewVisibility {
    [self setViewControlState:_eastAsianFontView enabled:[self boolForKey:KEY_USE_EAST_ASIAN_FONT]];
    [self setViewControlState:_privateUseAreaView enabled:[self boolForKey:KEY_USE_PUA_FONT]];
    [self setViewControlState:_nonAsciiFontView enabled:[self boolForKey:KEY_USE_NONASCII_FONT]];
}

- (void)updateFontsDescriptions {
    // Update the fonts.
    self.normalFont = [[self stringForKey:KEY_NORMAL_FONT] fontValue];
    self.eastAsianFont = [[self stringForKey:KEY_EAST_ASIAN_FONT] fontValue];
    self.privateUseAreaFont = [[self stringForKey:KEY_PUA_FONT] fontValue];
    self.nonAsciiFont = [[self stringForKey:KEY_NON_ASCII_FONT] fontValue];

    // Update the descriptions.
    NSString *fontName;
    if (_normalFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@",
                    [_normalFont pointSize], [_normalFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [_normalFontDescription setStringValue:fontName];

    if (_eastAsianFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@",
                    [_eastAsianFont pointSize], [_eastAsianFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [_eastAsianFontDescription setStringValue:fontName];

    if (_privateUseAreaFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@",
                    [_privateUseAreaFont pointSize], [_privateUseAreaFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [_privateUseAreaFontDescription setStringValue:fontName];

    if (_nonAsciiFont != nil) {
        fontName = [NSString stringWithFormat: @"%gpt %@",
                    [_nonAsciiFont pointSize], [_nonAsciiFont displayName]];
    } else {
        fontName = @"Unknown Font";
    }
    [_nonAsciiFontDescription setStringValue:fontName];

    [self updateWarnings];
}

- (void)updateWarnings {
    [_normalFontWantsAntialiasing setHidden:!self.normalFont.futureShouldAntialias];
    [_eastAsianFontWantsAntialiasing setHidden:!self.eastAsianFont.futureShouldAntialias];
    [_privateUseAreaFontWantsAntialiasing setHidden:!self.privateUseAreaFont.futureShouldAntialias];
    [_nonasciiFontWantsAntialiasing setHidden:!self.nonAsciiFont.futureShouldAntialias];
}


#pragma mark - Actions

- (IBAction)openFontPicker:(id)sender {
    _fontPickerTag = [sender tag];
    [self showFontPanel];
}

#pragma mark - NSFontPanel and NSFontManager

- (void)showFontPanel {
    // make sure we get the messages from the NSFontManager
    [[self.view window] makeFirstResponder:self];

    NSFontPanel* aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
    [aFontPanel setAccessoryView:_displayFontAccessoryView];
    NSFont *theFont;

    switch (_fontPickerTag) {
        case kGlobalFontButtonTag:
            theFont = _normalFont;
            break;
        case kEastAsianFontButtonTag:
            theFont = _eastAsianFont;
            break;
        case kPrivateUseAreaFontButtonTag:
            theFont = _privateUseAreaFont;
            break;
        case kNonAsciiFontButtonTag:
            theFont = _nonAsciiFont;
            break;
    }

    if (theFont == nil) {
        theFont = _normalFont;
    }

    [[NSFontManager sharedFontManager] setSelectedFont:theFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (NSUInteger)validModesForFontPanel:(NSFontPanel *)fontPanel {
    return kValidModesForFontPanel;
}

// sent by NSFontManager up the responder chain
- (void)changeFont:(id)fontManager {
    NSFont *theFont;
    NSString *key;

    switch (_fontPickerTag) {
        case kGlobalFontButtonTag:
            theFont = _normalFont;
            key = KEY_NORMAL_FONT;
            break;
        case kEastAsianFontButtonTag:
            theFont = _eastAsianFont;
            key = KEY_EAST_ASIAN_FONT;
            break;
        case kPrivateUseAreaFontButtonTag:
            theFont = _privateUseAreaFont;
            key = KEY_PUA_FONT;
            break;
        case kNonAsciiFontButtonTag:
            theFont = _nonAsciiFont;
            key = KEY_NON_ASCII_FONT;
            break;
    }
    [self setString:[[fontManager convertFont:theFont] stringValue] forKey:key];
    [self updateFontsDescriptions];
}

#pragma mark - Notifications

- (void)reloadProfiles {
    [self updateFontsDescriptions];
}

@end
