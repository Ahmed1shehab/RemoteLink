import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// The application title
  ///
  /// In en, this message translates to:
  /// **'Remote Link'**
  String get appTitle;

  /// No description provided for @desktopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Desktop'**
  String get desktopSubtitle;

  /// Connected device count label in tray or status
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No devices connected} =1{1 device connected} other{{count} devices connected}}'**
  String connectedStatusLabel(int count);

  /// No description provided for @allowNewDevicesToPair.
  ///
  /// In en, this message translates to:
  /// **'Allow new devices to pair'**
  String get allowNewDevicesToPair;

  /// No description provided for @openProduct.
  ///
  /// In en, this message translates to:
  /// **'Open {productName}'**
  String openProduct(String productName);

  /// No description provided for @quitProduct.
  ///
  /// In en, this message translates to:
  /// **'Quit {productName}'**
  String quitProduct(String productName);

  /// No description provided for @startupError.
  ///
  /// In en, this message translates to:
  /// **'Failed to start {productName}: {error}'**
  String startupError(String productName, String error);

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @doneButton.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @copyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyButton;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get copied;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @navOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get navOverview;

  /// No description provided for @navDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get navDevices;

  /// No description provided for @navSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get navSend;

  /// No description provided for @navTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get navTransfers;

  /// No description provided for @navClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get navClipboard;

  /// No description provided for @sidebarReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get sidebarReady;

  /// No description provided for @sidebarRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get sidebarRunning;

  /// No description provided for @sidebarStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get sidebarStopped;

  /// No description provided for @tooltipDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get tooltipDiagnostics;

  /// No description provided for @tooltipSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tooltipSettings;

  /// No description provided for @workspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get workspaceTitle;

  /// No description provided for @workspaceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage connections, permissions, and transfers from one place.'**
  String get workspaceSubtitle;

  /// No description provided for @overviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overviewTitle;

  /// No description provided for @statConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statConnected;

  /// No description provided for @statConnectedDevices.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 connected} =1{1 connected} other{{count} connected}}'**
  String statConnectedDevices(int count);

  /// No description provided for @statTransfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get statTransfers;

  /// No description provided for @statRecentTransfers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 recent} =1{1 recent} other{{count} recent}}'**
  String statRecentTransfers(int count);

  /// No description provided for @statClipboardSync.
  ///
  /// In en, this message translates to:
  /// **'Clipboard Sync'**
  String get statClipboardSync;

  /// No description provided for @clipboardActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get clipboardActive;

  /// No description provided for @clipboardPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get clipboardPaused;

  /// No description provided for @screenSharingActive.
  ///
  /// In en, this message translates to:
  /// **'Sharing screen'**
  String get screenSharingActive;

  /// No description provided for @screenSharingDesc.
  ///
  /// In en, this message translates to:
  /// **'Screen streaming is currently active with {name}.'**
  String screenSharingDesc(String name);

  /// No description provided for @bannerInputBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Input simulation blocked'**
  String get bannerInputBlockedTitle;

  /// No description provided for @bannerInputBlockedDesc.
  ///
  /// In en, this message translates to:
  /// **'Accessibility permissions are required on macOS to simulate mouse and keyboard input.'**
  String get bannerInputBlockedDesc;

  /// No description provided for @bannerOpenSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open System Settings'**
  String get bannerOpenSystemSettings;

  /// No description provided for @devicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// No description provided for @devicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Phones and tablets that can reach this computer'**
  String get devicesSubtitle;

  /// No description provided for @pairPhoneButton.
  ///
  /// In en, this message translates to:
  /// **'Pair a phone'**
  String get pairPhoneButton;

  /// No description provided for @disconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectButton;

  /// No description provided for @noDevicesConnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'No devices connected'**
  String get noDevicesConnectedTitle;

  /// No description provided for @noDevicesConnectedMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap “Pair a phone” to connect your phone or tablet.'**
  String get noDevicesConnectedMessage;

  /// No description provided for @tierViewOnly.
  ///
  /// In en, this message translates to:
  /// **'View-only'**
  String get tierViewOnly;

  /// No description provided for @tierInteractive.
  ///
  /// In en, this message translates to:
  /// **'Interactive'**
  String get tierInteractive;

  /// No description provided for @tierElevated.
  ///
  /// In en, this message translates to:
  /// **'Elevated'**
  String get tierElevated;

  /// No description provided for @rememberDevice.
  ///
  /// In en, this message translates to:
  /// **'Remember this device'**
  String get rememberDevice;

  /// No description provided for @deviceAwaitingPairing.
  ///
  /// In en, this message translates to:
  /// **'Awaiting pairing confirmation'**
  String get deviceAwaitingPairing;

  /// No description provided for @deviceStreamingScreen.
  ///
  /// In en, this message translates to:
  /// **'Streaming screen'**
  String get deviceStreamingScreen;

  /// No description provided for @deviceLatency.
  ///
  /// In en, this message translates to:
  /// **'{latency} ms'**
  String deviceLatency(String latency);

  /// No description provided for @sendCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Send files to phone'**
  String get sendCardTitle;

  /// No description provided for @sendCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drag and drop files here, or click to browse'**
  String get sendCardSubtitle;

  /// No description provided for @browseFilesButton.
  ///
  /// In en, this message translates to:
  /// **'Browse files'**
  String get browseFilesButton;

  /// No description provided for @transfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfersTitle;

  /// No description provided for @transfersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Files sent and received with connected devices'**
  String get transfersSubtitle;

  /// No description provided for @noTransfersTitle.
  ///
  /// In en, this message translates to:
  /// **'No transfers yet'**
  String get noTransfersTitle;

  /// No description provided for @noTransfersMessage.
  ///
  /// In en, this message translates to:
  /// **'Files sent to or received from connected devices will appear here.'**
  String get noTransfersMessage;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @clearTransferHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearTransferHistory;

  /// No description provided for @transferWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation'**
  String get transferWaiting;

  /// No description provided for @transferTransferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring'**
  String get transferTransferring;

  /// No description provided for @transferCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get transferCompleted;

  /// No description provided for @transferDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get transferDeclined;

  /// No description provided for @transferCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get transferCancelled;

  /// No description provided for @transferFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get transferFailed;

  /// No description provided for @transferFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String transferFilesCount(int count);

  /// No description provided for @transferSpeed.
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String transferSpeed(String speed);

  /// No description provided for @transferEta.
  ///
  /// In en, this message translates to:
  /// **'ETA: {eta}'**
  String transferEta(String eta);

  /// No description provided for @missingFilesError.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file is no longer available. Choose it again.} other{{count} files are no longer available. Choose them again.}}'**
  String missingFilesError(int count);

  /// No description provided for @clipboardHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Clipboard history'**
  String get clipboardHistoryTitle;

  /// No description provided for @clipboardHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quickly reuse recent content from this computer'**
  String get clipboardHistorySubtitle;

  /// No description provided for @clipboardCleared.
  ///
  /// In en, this message translates to:
  /// **'Clipboard history cleared.'**
  String get clipboardCleared;

  /// No description provided for @persistenceEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Kept on this computer, encrypted. Content marked confidential by a password manager is never recorded.'**
  String get persistenceEncrypted;

  /// No description provided for @persistenceMemoryOnly.
  ///
  /// In en, this message translates to:
  /// **'Kept in memory only — this list is gone when Remote Link quits. Nothing is written to disk.'**
  String get persistenceMemoryOnly;

  /// No description provided for @persistenceEnabledSnackBar.
  ///
  /// In en, this message translates to:
  /// **'Clipboard history will be kept, encrypted, on this computer.'**
  String get persistenceEnabledSnackBar;

  /// No description provided for @persistenceDisabledSnackBar.
  ///
  /// In en, this message translates to:
  /// **'Stored clipboard history deleted. Keeping it in memory only.'**
  String get persistenceDisabledSnackBar;

  /// No description provided for @nothingCopiedYetTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing copied yet'**
  String get nothingCopiedYetTitle;

  /// No description provided for @nothingCopiedYetMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The last item you copy will appear here.} other{The last {count} items you copy will appear here.}}'**
  String nothingCopiedYetMessage(int count);

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @removeFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Remove from history'**
  String get removeFromHistory;

  /// No description provided for @clipboardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The clipboard is unavailable.'**
  String get clipboardUnavailable;

  /// No description provided for @pinLimitReached.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You can pin up to 1 item. Unpin one first.} other{You can pin up to {count} items. Unpin one first.}}'**
  String pinLimitReached(int count);

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min ago} other{{count} min ago}}'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 h ago} other{{count} h ago}}'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 d ago} other{{count} d ago}}'**
  String timeDaysAgo(int count);

  /// No description provided for @pairingRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Device Pairing Request'**
  String get pairingRequestTitle;

  /// No description provided for @pairingRequestMessage.
  ///
  /// In en, this message translates to:
  /// **'“{name}” wants to pair with this computer. Verify that the security code matches:'**
  String pairingRequestMessage(String name);

  /// No description provided for @incomingConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming Connection'**
  String get incomingConnectionTitle;

  /// No description provided for @incomingConnectionMessage.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is asking to connect. Allow this connection?'**
  String incomingConnectionMessage(String name);

  /// No description provided for @rememberDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember Device'**
  String get rememberDeviceTitle;

  /// No description provided for @rememberDeviceMessage.
  ///
  /// In en, this message translates to:
  /// **'Do you want to remember “{name}” so it connects automatically in the future?'**
  String rememberDeviceMessage(String name);

  /// No description provided for @rememberAlways.
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get rememberAlways;

  /// No description provided for @rememberThisSession.
  ///
  /// In en, this message translates to:
  /// **'This session only'**
  String get rememberThisSession;

  /// No description provided for @rememberDecline.
  ///
  /// In en, this message translates to:
  /// **'Don\'t allow'**
  String get rememberDecline;

  /// No description provided for @incomingTransferTitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming File Transfer'**
  String get incomingTransferTitle;

  /// No description provided for @incomingTransferMessage.
  ///
  /// In en, this message translates to:
  /// **'“{name}” wants to send {count, plural, =1{1 file ({size})} other{{count} files ({size})}}:'**
  String incomingTransferMessage(String name, int count, String size);

  /// No description provided for @acceptButton.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get acceptButton;

  /// No description provided for @declineButton.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineButton;

  /// No description provided for @permissionRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Request'**
  String get permissionRequestTitle;

  /// No description provided for @permissionRequestMessage.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is requesting {tier} permission. Allow this tier?'**
  String permissionRequestMessage(String name, String tier);

  /// No description provided for @securityCodeSpoken.
  ///
  /// In en, this message translates to:
  /// **'Security code: {digits}'**
  String securityCodeSpoken(String digits);

  /// No description provided for @pairPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair a phone'**
  String get pairPhoneTitle;

  /// No description provided for @pairPhoneInstruction.
  ///
  /// In en, this message translates to:
  /// **'Open Remote Link on your phone and tap “Scan code”.'**
  String get pairPhoneInstruction;

  /// No description provided for @pairPhoneMultipleAddresses.
  ///
  /// In en, this message translates to:
  /// **'This computer has more than one address. If the phone cannot reach it, try another.'**
  String get pairPhoneMultipleAddresses;

  /// No description provided for @addressLabel.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressLabel;

  /// No description provided for @copyAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get copyAddress;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @startupSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get startupSectionTitle;

  /// No description provided for @startAtLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Start when I log in'**
  String get startAtLoginTitle;

  /// No description provided for @startAtLoginSubtitleOn.
  ///
  /// In en, this message translates to:
  /// **'Starts hidden, so your phone can reach this computer without anyone opening a window first.'**
  String get startAtLoginSubtitleOn;

  /// No description provided for @startAtLoginSubtitleOff.
  ///
  /// In en, this message translates to:
  /// **'Your phone will not find this computer until you open Remote Link yourself.'**
  String get startAtLoginSubtitleOff;

  /// No description provided for @connectionsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get connectionsSectionTitle;

  /// No description provided for @askBeforeConnectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask before a paired device connects'**
  String get askBeforeConnectingTitle;

  /// No description provided for @askBeforeConnectingSubtitleOn.
  ///
  /// In en, this message translates to:
  /// **'A device you have paired with waits until you allow it. Asked once per device each time Remote Link starts, so a dropped Wi-Fi connection does not ask again.'**
  String get askBeforeConnectingSubtitleOn;

  /// No description provided for @askBeforeConnectingSubtitleOff.
  ///
  /// In en, this message translates to:
  /// **'Any device you have paired with connects straight away, whoever is holding it.'**
  String get askBeforeConnectingSubtitleOff;

  /// No description provided for @windowSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Closing the window'**
  String get windowSectionTitle;

  /// No description provided for @closingWindowKeepsServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Closing this window keeps the service running'**
  String get closingWindowKeepsServiceTitle;

  /// No description provided for @closingWindowKeepsServiceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your paired phones stay connected, and transfers in progress finish. Reopen or quit Remote Link from its icon in {location}.'**
  String closingWindowKeepsServiceSubtitle(String location);

  /// No description provided for @menuBarLocationMac.
  ///
  /// In en, this message translates to:
  /// **'the menu bar at the top of the screen'**
  String get menuBarLocationMac;

  /// No description provided for @notificationAreaLocationOther.
  ///
  /// In en, this message translates to:
  /// **'the notification area beside the clock'**
  String get notificationAreaLocationOther;

  /// No description provided for @savingSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Saving received files'**
  String get savingSectionTitle;

  /// No description provided for @folderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get folderLabel;

  /// No description provided for @saveFolderChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get saveFolderChecking;

  /// No description provided for @saveFolderError.
  ///
  /// In en, this message translates to:
  /// **'Could not work out where to save files.'**
  String get saveFolderError;

  /// No description provided for @useDownloadsButton.
  ///
  /// In en, this message translates to:
  /// **'Use Downloads'**
  String get useDownloadsButton;

  /// No description provided for @changeFolderButton.
  ///
  /// In en, this message translates to:
  /// **'Change…'**
  String get changeFolderButton;

  /// No description provided for @saveFilesHerePrompt.
  ///
  /// In en, this message translates to:
  /// **'Save files here'**
  String get saveFilesHerePrompt;

  /// No description provided for @thisComputerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'This computer'**
  String get thisComputerSectionTitle;

  /// No description provided for @computerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get computerNameLabel;

  /// No description provided for @computerNameSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{name} — this is what your phone shows in its list.'**
  String computerNameSubtitle(String name);

  /// No description provided for @renameButton.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameButton;

  /// No description provided for @renameComputerDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename this computer'**
  String get renameComputerDialogTitle;

  /// No description provided for @supportSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportSectionTitle;

  /// No description provided for @diagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// No description provided for @diagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connection counters, permissions, and a log you can copy into a bug report.'**
  String get diagnosticsSubtitle;

  /// No description provided for @diagnosticsScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsScreenTitle;

  /// No description provided for @systemHealthTitle.
  ///
  /// In en, this message translates to:
  /// **'System health'**
  String get systemHealthTitle;

  /// No description provided for @systemHealthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Network, permissions, connected devices, and live logs.'**
  String get systemHealthSubtitle;

  /// No description provided for @copyAllButton.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get copyAllButton;

  /// No description provided for @fullDiagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Full diagnostics copied to clipboard'**
  String get fullDiagnosticsCopied;

  /// No description provided for @logsCopied.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopied;

  /// No description provided for @copiedLogRecords.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Copied 0 log records to clipboard} =1{Copied 1 log record to clipboard} other{Copied {count} log records to clipboard}}'**
  String copiedLogRecords(int count);

  /// No description provided for @serviceNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Service & Network'**
  String get serviceNetworkTitle;

  /// No description provided for @statusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get statusRunning;

  /// No description provided for @statusStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get statusStopped;

  /// No description provided for @deviceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Device Name'**
  String get deviceNameLabel;

  /// No description provided for @boundPortLabel.
  ///
  /// In en, this message translates to:
  /// **'Bound Port'**
  String get boundPortLabel;

  /// No description provided for @boundPortValue.
  ///
  /// In en, this message translates to:
  /// **'Port {port}'**
  String boundPortValue(int port);

  /// No description provided for @deviceIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceIdLabel;

  /// No description provided for @lanAddressesTitle.
  ///
  /// In en, this message translates to:
  /// **'LAN Addresses for Phone Connection:'**
  String get lanAddressesTitle;

  /// No description provided for @noLanAddresses.
  ///
  /// In en, this message translates to:
  /// **'No LAN addresses detected'**
  String get noLanAddresses;

  /// No description provided for @discoveryBeaconTitle.
  ///
  /// In en, this message translates to:
  /// **'Discovery Beacon'**
  String get discoveryBeaconTitle;

  /// No description provided for @advertisingLabel.
  ///
  /// In en, this message translates to:
  /// **'Advertising'**
  String get advertisingLabel;

  /// No description provided for @activeLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeLabel;

  /// No description provided for @offLabel.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get offLabel;

  /// No description provided for @interfacesLabel.
  ///
  /// In en, this message translates to:
  /// **'Advertising Interface(s):'**
  String get interfacesLabel;

  /// No description provided for @noInterfacesDetected.
  ///
  /// In en, this message translates to:
  /// **'No interfaces bound'**
  String get noInterfacesDetected;

  /// No description provided for @lastErrorLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Discovery Error'**
  String get lastErrorLabel;

  /// No description provided for @dispatcherCountersTitle.
  ///
  /// In en, this message translates to:
  /// **'Command Dispatcher'**
  String get dispatcherCountersTitle;

  /// No description provided for @appliedLabel.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get appliedLabel;

  /// No description provided for @deniedLabel.
  ///
  /// In en, this message translates to:
  /// **'Denied'**
  String get deniedLabel;

  /// No description provided for @unsupportedLabel.
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get unsupportedLabel;

  /// No description provided for @backendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Backend Availability'**
  String get backendsTitle;

  /// No description provided for @availableLabel.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get availableLabel;

  /// No description provided for @unavailableLabel.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailableLabel;

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String reasonLabel(String reason);

  /// No description provided for @connectedDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Connected Devices (0)} =1{Connected Devices (1)} other{Connected Devices ({count})}}'**
  String connectedDevicesTitle(int count);

  /// No description provided for @noDevicesConnectedDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'No devices connected'**
  String get noDevicesConnectedDiagnostics;

  /// No description provided for @systemLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'System Logs'**
  String get systemLogsTitle;

  /// No description provided for @allLevelsLabel.
  ///
  /// In en, this message translates to:
  /// **'All Levels'**
  String get allLevelsLabel;

  /// No description provided for @copyLogsButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Logs'**
  String get copyLogsButton;

  /// No description provided for @failedToLoadDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Failed to load diagnostics: {error}'**
  String failedToLoadDiagnostics(String error);

  /// No description provided for @showingLogsCount.
  ///
  /// In en, this message translates to:
  /// **'Showing {filtered} of {total}'**
  String showingLogsCount(int filtered, int total);

  /// No description provided for @noLogsRecorded.
  ///
  /// In en, this message translates to:
  /// **'No logs recorded yet'**
  String get noLogsRecorded;

  /// No description provided for @serviceOnline.
  ///
  /// In en, this message translates to:
  /// **'Service online'**
  String get serviceOnline;

  /// No description provided for @serviceOffline.
  ///
  /// In en, this message translates to:
  /// **'Service offline'**
  String get serviceOffline;

  /// No description provided for @navActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get navActivity;

  /// No description provided for @alreadyRunningTitle.
  ///
  /// In en, this message translates to:
  /// **'{productName} is already running'**
  String alreadyRunningTitle(String productName);

  /// No description provided for @alreadyRunningSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your phone can already reach this computer. Open the copy that is running from its icon in {where} — you don\'t need this second one.'**
  String alreadyRunningSubtitle(String where);

  /// No description provided for @closeThisWindow.
  ///
  /// In en, this message translates to:
  /// **'Close this window'**
  String get closeThisWindow;

  /// No description provided for @couldNotStartTitle.
  ///
  /// In en, this message translates to:
  /// **'{productName} could not start'**
  String couldNotStartTitle(String productName);

  /// No description provided for @screenWatchingBanner.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} is watching this screen} other{{count} devices are watching this screen: {names}}}'**
  String screenWatchingBanner(int count, String name, String names);

  /// No description provided for @stopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get stopSharing;

  /// No description provided for @screenRecordingPermissionReason.
  ///
  /// In en, this message translates to:
  /// **'Remote Link needs Screen Recording permission before it can share this screen.'**
  String get screenRecordingPermissionReason;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @statusDiscoverable.
  ///
  /// In en, this message translates to:
  /// **'Discoverable on this network'**
  String get statusDiscoverable;

  /// No description provided for @statusNotRunning.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get statusNotRunning;

  /// No description provided for @devicePortInfo.
  ///
  /// In en, this message translates to:
  /// **'{name} · port {port}'**
  String devicePortInfo(String name, int port);

  /// No description provided for @readyToShareScreenPrompt.
  ///
  /// In en, this message translates to:
  /// **'Ready to share this screen — start it from the phone, using the monitor button at the top of its remote screen.'**
  String get readyToShareScreenPrompt;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @sendToDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Send to device'**
  String get sendToDeviceTitle;

  /// No description provided for @sendToDeviceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share files, links, or notes with a connected phone'**
  String get sendToDeviceSubtitle;

  /// No description provided for @connectDeviceToSendPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connect a device to send files or text.'**
  String get connectDeviceToSendPrompt;

  /// No description provided for @sendToLabel.
  ///
  /// In en, this message translates to:
  /// **'Send to'**
  String get sendToLabel;

  /// No description provided for @transfersNotPermitted.
  ///
  /// In en, this message translates to:
  /// **' · transfers not permitted'**
  String get transfersNotPermitted;

  /// No description provided for @tabFileDragDrop.
  ///
  /// In en, this message translates to:
  /// **'File / Drag & Drop'**
  String get tabFileDragDrop;

  /// No description provided for @tabTextUrl.
  ///
  /// In en, this message translates to:
  /// **'Text / URL'**
  String get tabTextUrl;

  /// No description provided for @dragAndDropPrompt.
  ///
  /// In en, this message translates to:
  /// **'Drag and drop files here to send'**
  String get dragAndDropPrompt;

  /// No description provided for @chooseFilesButton.
  ///
  /// In en, this message translates to:
  /// **'Choose files'**
  String get chooseFilesButton;

  /// No description provided for @addMoreFilesButton.
  ///
  /// In en, this message translates to:
  /// **'Add more files'**
  String get addMoreFilesButton;

  /// No description provided for @removeFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove {fileName}'**
  String removeFileTooltip(String fileName);

  /// No description provided for @textSnippetLabel.
  ///
  /// In en, this message translates to:
  /// **'Text or URL snippet'**
  String get textSnippetLabel;

  /// No description provided for @textSnippetHint.
  ///
  /// In en, this message translates to:
  /// **'Enter text to send directly to the phone…'**
  String get textSnippetHint;

  /// No description provided for @fileNameOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'File name (optional)'**
  String get fileNameOptionalLabel;

  /// No description provided for @fileNameOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'snippet.txt'**
  String get fileNameOptionalHint;

  /// No description provided for @sendFileButton.
  ///
  /// In en, this message translates to:
  /// **'Send File'**
  String get sendFileButton;

  /// No description provided for @sendTextButton.
  ///
  /// In en, this message translates to:
  /// **'Send Text'**
  String get sendTextButton;

  /// No description provided for @foldersNotSupportedError.
  ///
  /// In en, this message translates to:
  /// **'Folders cannot be sent yet: {folders}'**
  String foldersNotSupportedError(String folders);

  /// No description provided for @openFileDialogError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file dialog: {error}'**
  String openFileDialogError(String error);

  /// No description provided for @selectTargetDeviceError.
  ///
  /// In en, this message translates to:
  /// **'Please select a target device'**
  String get selectTargetDeviceError;

  /// No description provided for @chooseAtLeastOneFileError.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one file to send'**
  String get chooseAtLeastOneFileError;

  /// No description provided for @filesNoLongerThere.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{fileName} is no longer there.} other{{count} files are no longer there.}}'**
  String filesNoLongerThere(int count, String fileName);

  /// No description provided for @enterTextToSendError.
  ///
  /// In en, this message translates to:
  /// **'Please enter text to send'**
  String get enterTextToSendError;

  /// No description provided for @sendFailedError.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String sendFailedError(String error);

  /// No description provided for @transfersActiveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Completed and active transfers appear here'**
  String get transfersActiveSubtitle;

  /// No description provided for @transfersRecentCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recent transfer} other{{count} recent transfers}}'**
  String transfersRecentCount(int count);

  /// No description provided for @noActiveOrRecentTransfers.
  ///
  /// In en, this message translates to:
  /// **'No active or recent transfers.'**
  String get noActiveOrRecentTransfers;

  /// No description provided for @transferFromPeer.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String transferFromPeer(String name);

  /// No description provided for @transferToPeer.
  ///
  /// In en, this message translates to:
  /// **'To {name}'**
  String transferToPeer(String name);

  /// No description provided for @transferStatusWaitingForYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get transferStatusWaitingForYou;

  /// No description provided for @transferStatusAwaitingResponse.
  ///
  /// In en, this message translates to:
  /// **'Awaiting response'**
  String get transferStatusAwaitingResponse;

  /// No description provided for @transferStatusOffered.
  ///
  /// In en, this message translates to:
  /// **'Offered'**
  String get transferStatusOffered;

  /// No description provided for @removeButton.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeButton;

  /// No description provided for @fileMovedOrDeleted.
  ///
  /// In en, this message translates to:
  /// **'File was moved or deleted'**
  String get fileMovedOrDeleted;

  /// No description provided for @showInFinder.
  ///
  /// In en, this message translates to:
  /// **'Show {fileName} in Finder'**
  String showInFinder(String fileName);

  /// No description provided for @showInFolder.
  ///
  /// In en, this message translates to:
  /// **'Show {fileName} in folder'**
  String showInFolder(String fileName);

  /// No description provided for @openFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open {fileName}'**
  String openFileTooltip(String fileName);

  /// No description provided for @incomingTransferFromPeer.
  ///
  /// In en, this message translates to:
  /// **'Incoming transfer from {name}'**
  String incomingTransferFromPeer(String name);

  /// No description provided for @incomingTransferFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} wants to send 1 file:} other{{name} wants to send {count} files:}}'**
  String incomingTransferFilesCount(String name, int count);

  /// No description provided for @totalSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total size:'**
  String get totalSizeLabel;

  /// No description provided for @firstTransferNote.
  ///
  /// In en, this message translates to:
  /// **'First transfer from this device.\nFiles will be saved in: {path}'**
  String firstTransferNote(String path);

  /// No description provided for @permissionElevationRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission elevation request'**
  String get permissionElevationRequestTitle;

  /// No description provided for @peerIsRequesting.
  ///
  /// In en, this message translates to:
  /// **' is requesting '**
  String get peerIsRequesting;

  /// No description provided for @accessToThisComputer.
  ///
  /// In en, this message translates to:
  /// **' access to this computer.'**
  String get accessToThisComputer;

  /// No description provided for @tierTitleViewOnly.
  ///
  /// In en, this message translates to:
  /// **'View Only'**
  String get tierTitleViewOnly;

  /// No description provided for @tierTitleControl.
  ///
  /// In en, this message translates to:
  /// **'Control'**
  String get tierTitleControl;

  /// No description provided for @tierTitleControlAndApps.
  ///
  /// In en, this message translates to:
  /// **'Control + Launch Apps'**
  String get tierTitleControlAndApps;

  /// No description provided for @tierTitleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator (Full Access)'**
  String get tierTitleAdmin;

  /// No description provided for @tierExplViewOnly.
  ///
  /// In en, this message translates to:
  /// **'Allows viewing system status, media state, and the display layout — but not the contents of the screen.'**
  String get tierExplViewOnly;

  /// No description provided for @tierExplControl.
  ///
  /// In en, this message translates to:
  /// **'Allows sending keyboard and mouse input, synchronizing clipboard, controlling media, viewing this screen, and transferring files — every transfer is still confirmed here before it starts.'**
  String get tierExplControl;

  /// No description provided for @tierExplExtended.
  ///
  /// In en, this message translates to:
  /// **'Allows launching applications and running pre-registered commands without a further prompt.'**
  String get tierExplExtended;

  /// No description provided for @tierExplAdmin.
  ///
  /// In en, this message translates to:
  /// **'Allows controlling power (shutdown, restart, sleep, lock) and managing paired devices.'**
  String get tierExplAdmin;

  /// No description provided for @whatThisAllows.
  ///
  /// In en, this message translates to:
  /// **'What this allows:'**
  String get whatThisAllows;

  /// No description provided for @messageFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Message from device:'**
  String get messageFromDevice;

  /// No description provided for @adminWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Admin access allows restarting or shutting down your machine and discarding unsaved work.'**
  String get adminWarningMessage;

  /// No description provided for @automaticallyDeniedInSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Automatically denied in 1 second} other{Automatically denied in {count} seconds}}'**
  String automaticallyDeniedInSeconds(int count);

  /// No description provided for @temporary30Minutes.
  ///
  /// In en, this message translates to:
  /// **'Temporary · 30 minutes'**
  String get temporary30Minutes;

  /// No description provided for @permanent.
  ///
  /// In en, this message translates to:
  /// **'Permanent'**
  String get permanent;

  /// No description provided for @denyButton.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get denyButton;

  /// No description provided for @approveButton.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approveButton;

  /// No description provided for @waitingForPairingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for pairing approval'**
  String get waitingForPairingApproval;

  /// No description provided for @deviceConnectionStats.
  ///
  /// In en, this message translates to:
  /// **'{address} · {latency} ms · {bars}/4'**
  String deviceConnectionStats(String address, String latency, int bars);

  /// No description provided for @clipboardSyncEnabledTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync enabled'**
  String get clipboardSyncEnabledTooltip;

  /// No description provided for @clipboardSyncDisabledTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync disabled'**
  String get clipboardSyncDisabledTooltip;

  /// No description provided for @clipboardSyncNotPermittedTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync not permitted at current tier'**
  String get clipboardSyncNotPermittedTooltip;

  /// No description provided for @renameDeviceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename this device'**
  String get renameDeviceTooltip;

  /// No description provided for @rememberedDeviceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remembered — connects without being asked. Click to start asking again.'**
  String get rememberedDeviceTooltip;

  /// No description provided for @notRememberedDeviceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Not remembered. Click to let it connect without asking.'**
  String get notRememberedDeviceTooltip;

  /// No description provided for @forgetDeviceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Forget this device'**
  String get forgetDeviceTooltip;

  /// No description provided for @tierLabelViewOnly.
  ///
  /// In en, this message translates to:
  /// **'View only'**
  String get tierLabelViewOnly;

  /// No description provided for @tierLabelControl.
  ///
  /// In en, this message translates to:
  /// **'Control'**
  String get tierLabelControl;

  /// No description provided for @tierLabelControlAndApps.
  ///
  /// In en, this message translates to:
  /// **'Control + apps'**
  String get tierLabelControlAndApps;

  /// No description provided for @tierLabelFullAccess.
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get tierLabelFullAccess;

  /// No description provided for @renameDeviceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename device'**
  String get renameDeviceDialogTitle;

  /// No description provided for @invalidDeviceNameError.
  ///
  /// In en, this message translates to:
  /// **'Invalid name: 1–64 characters, no control codes or line breaks.'**
  String get invalidDeviceNameError;

  /// No description provided for @pairingDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair this device?'**
  String get pairingDialogTitle;

  /// No description provided for @pairingDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to control this computer.'**
  String pairingDialogMessage(String name);

  /// No description provided for @pairingDialogInstructions.
  ///
  /// In en, this message translates to:
  /// **'Approve only if your phone is showing exactly these six digits, or if you just scanned the code on this screen with it. Different numbers mean something is intercepting the connection.'**
  String get pairingDialogInstructions;

  /// No description provided for @theNumbersMatchButton.
  ///
  /// In en, this message translates to:
  /// **'The numbers match'**
  String get theNumbersMatchButton;

  /// No description provided for @connectionRequestDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow this device to connect?'**
  String get connectionRequestDialogTitle;

  /// No description provided for @connectionRequestPeerMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} is asking to connect to this computer.'**
  String connectionRequestPeerMessage(String name);

  /// No description provided for @connectionRequestExplanation.
  ///
  /// In en, this message translates to:
  /// **'You paired with it before, so its identity has already been checked. This is only about now: allow it if the device is in your hands, and turn it away if it is not.'**
  String get connectionRequestExplanation;

  /// No description provided for @connectionRequestSessionNote.
  ///
  /// In en, this message translates to:
  /// **'Remote Link will not ask about this device again until you quit the app.'**
  String get connectionRequestSessionNote;

  /// No description provided for @dontAllowButton.
  ///
  /// In en, this message translates to:
  /// **'Don\'t allow'**
  String get dontAllowButton;

  /// No description provided for @allowButton.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allowButton;

  /// No description provided for @rememberDeviceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember this device?'**
  String get rememberDeviceDialogTitle;

  /// No description provided for @rememberDeviceIntro.
  ///
  /// In en, this message translates to:
  /// **'{name} is connected. Remote Link can let it straight in next time, with nothing to scan and nobody to ask.'**
  String rememberDeviceIntro(String name);

  /// No description provided for @rememberDeviceExplanation.
  ///
  /// In en, this message translates to:
  /// **'{name} is being asked the same thing. Both devices have to agree, and either one can change its mind later in Devices.'**
  String rememberDeviceExplanation(String name);

  /// No description provided for @keepAskingButton.
  ///
  /// In en, this message translates to:
  /// **'Keep asking'**
  String get keepAskingButton;

  /// No description provided for @rememberButton.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get rememberButton;

  /// No description provided for @rememberDeviceAgreedSnackBar.
  ///
  /// In en, this message translates to:
  /// **'{name} will be remembered once it agrees too.'**
  String rememberDeviceAgreedSnackBar(String name);

  /// No description provided for @couldNotRetryError.
  ///
  /// In en, this message translates to:
  /// **'Could not retry: {error}'**
  String couldNotRetryError(String error);

  /// No description provided for @invalidDeviceNameSnackBar.
  ///
  /// In en, this message translates to:
  /// **'Invalid device name. Names must be 1–64 characters with no control characters.'**
  String get invalidDeviceNameSnackBar;

  /// No description provided for @waitingForDevicesMessage.
  ///
  /// In en, this message translates to:
  /// **'Waiting for devices to connect…'**
  String get waitingForDevicesMessage;

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorMessage(String error);

  /// No description provided for @noDevicesConnectedPrompt.
  ///
  /// In en, this message translates to:
  /// **'No devices connected. Open Remote Link on your phone — it should find this computer automatically, or you can show it a code to scan.'**
  String get noDevicesConnectedPrompt;

  /// No description provided for @showPairingCodeButton.
  ///
  /// In en, this message translates to:
  /// **'Show pairing code'**
  String get showPairingCodeButton;

  /// No description provided for @connectedDevicesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected devices'**
  String get connectedDevicesSectionTitle;

  /// No description provided for @connectedDevicesCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Phones connected to this computer appear here} =1{1 connected} other{{count} connected}}'**
  String connectedDevicesCountSubtitle(int count);

  /// No description provided for @transferFailureTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Transfer timed out'**
  String get transferFailureTimedOut;

  /// No description provided for @transferFailureHashMismatch.
  ///
  /// In en, this message translates to:
  /// **'File integrity hash mismatch'**
  String get transferFailureHashMismatch;

  /// No description provided for @transferFailureNoSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage space'**
  String get transferFailureNoSpace;

  /// No description provided for @transferFailureNoSpaceOnPeer.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage space on peer'**
  String get transferFailureNoSpaceOnPeer;

  /// No description provided for @transferFailureChunkRefused.
  ///
  /// In en, this message translates to:
  /// **'File chunk refused'**
  String get transferFailureChunkRefused;

  /// No description provided for @transferFailureCancelledByPeer.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by {peerName}'**
  String transferFailureCancelledByPeer(String peerName);

  /// No description provided for @transferFailureCancelledByYou.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by you'**
  String get transferFailureCancelledByYou;

  /// No description provided for @transferFailureDeclinedByPeer.
  ///
  /// In en, this message translates to:
  /// **'Declined by {peerName}'**
  String transferFailureDeclinedByPeer(String peerName);

  /// No description provided for @transferFailureDeclinedByYou.
  ///
  /// In en, this message translates to:
  /// **'Declined by you'**
  String get transferFailureDeclinedByYou;

  /// No description provided for @transferFailureConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get transferFailureConnectionLost;

  /// No description provided for @transferFailureDeviceDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Device disconnected'**
  String get transferFailureDeviceDisconnected;

  /// No description provided for @transferFailureIoError.
  ///
  /// In en, this message translates to:
  /// **'I/O error during transfer'**
  String get transferFailureIoError;

  /// No description provided for @transferFailureReceiverUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Receiver unavailable'**
  String get transferFailureReceiverUnavailable;

  /// No description provided for @transferFailureStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Storage unavailable'**
  String get transferFailureStorageUnavailable;

  /// No description provided for @transferFailureCouldNotComplete.
  ///
  /// In en, this message translates to:
  /// **'File could not be completed'**
  String get transferFailureCouldNotComplete;

  /// No description provided for @transferFailureCouldNotAccept.
  ///
  /// In en, this message translates to:
  /// **'Could not accept transfer'**
  String get transferFailureCouldNotAccept;

  /// No description provided for @transferFailureRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry failed'**
  String get transferFailureRetryFailed;

  /// No description provided for @startingService.
  ///
  /// In en, this message translates to:
  /// **'Starting the service…'**
  String get startingService;

  /// No description provided for @filterLevel.
  ///
  /// In en, this message translates to:
  /// **'Filter Level:'**
  String get filterLevel;

  /// No description provided for @phoneControlCapabilityMissing.
  ///
  /// In en, this message translates to:
  /// **'Controlling a phone from this computer is not available. iPhones offer no way to allow it at all, Android needs a service this build does not include, and there is no viewer here yet.'**
  String get phoneControlCapabilityMissing;

  /// No description provided for @phoneControlReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Raise this device above read-only to control it.'**
  String get phoneControlReadOnly;

  /// No description provided for @backendInputName.
  ///
  /// In en, this message translates to:
  /// **'Input injection'**
  String get backendInputName;

  /// No description provided for @backendClipboardName.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync'**
  String get backendClipboardName;

  /// No description provided for @backendMediaName.
  ///
  /// In en, this message translates to:
  /// **'Media control'**
  String get backendMediaName;

  /// No description provided for @backendClipboardUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync is not supported on {platform}'**
  String backendClipboardUnsupported(String platform);

  /// No description provided for @backendClipboardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Clipboard backend unavailable'**
  String get backendClipboardUnavailable;

  /// No description provided for @backendMediaUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Media control is not supported on {platform}'**
  String backendMediaUnsupported(String platform);

  /// No description provided for @backendMediaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Media backend unavailable'**
  String get backendMediaUnavailable;

  /// No description provided for @inputAccessibilityPermission.
  ///
  /// In en, this message translates to:
  /// **'Remote Link needs Accessibility permission. Enable it in System Settings › Privacy & Security › Accessibility, then quit and reopen Remote Link.'**
  String get inputAccessibilityPermission;

  /// No description provided for @backendInputUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Input control is not supported on {platform}.'**
  String backendInputUnsupported(String platform);

  /// No description provided for @backendInputLibrariesUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Input control could not start on this computer.'**
  String get backendInputLibrariesUnavailable;

  /// No description provided for @backendUnavailableGeneric.
  ///
  /// In en, this message translates to:
  /// **'This control is unavailable right now.'**
  String get backendUnavailableGeneric;

  /// No description provided for @thisPlatform.
  ///
  /// In en, this message translates to:
  /// **'this platform'**
  String get thisPlatform;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
