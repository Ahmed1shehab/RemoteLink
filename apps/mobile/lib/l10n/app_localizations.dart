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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Link'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @searchAgain.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// No description provided for @scanCode.
  ///
  /// In en, this message translates to:
  /// **'Scan code'**
  String get scanCode;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @notConnectedPeriod.
  ///
  /// In en, this message translates to:
  /// **'Not connected.'**
  String get notConnectedPeriod;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get reconnecting;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get connecting;

  /// No description provided for @pairing.
  ///
  /// In en, this message translates to:
  /// **'Pairing'**
  String get pairing;

  /// No description provided for @waitingToBeLetIn.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be let in'**
  String get waitingToBeLetIn;

  /// No description provided for @connectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get connectionFailed;

  /// No description provided for @connectionStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Connection status: {status}'**
  String connectionStatusLabel(String status);

  /// No description provided for @shareSent.
  ///
  /// In en, this message translates to:
  /// **'Sent {description} to {peerName}.'**
  String shareSent(String description, String peerName);

  /// No description provided for @shareWaiting.
  ///
  /// In en, this message translates to:
  /// **'Holding {description} until your computer is back.'**
  String shareWaiting(String description);

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send that: {reason}'**
  String shareFailed(String reason);

  /// No description provided for @devicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// No description provided for @reconnectingTo.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to {name}'**
  String reconnectingTo(String name);

  /// No description provided for @chooseDifferentComputer.
  ///
  /// In en, this message translates to:
  /// **'Choose a different computer'**
  String get chooseDifferentComputer;

  /// No description provided for @deviceConnectedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get deviceConnectedSubtitle;

  /// No description provided for @tapForControls.
  ///
  /// In en, this message translates to:
  /// **' · tap for the controls'**
  String get tapForControls;

  /// No description provided for @deviceAccessRevoked.
  ///
  /// In en, this message translates to:
  /// **'This computer removed your access'**
  String get deviceAccessRevoked;

  /// No description provided for @pairedTapToScan.
  ///
  /// In en, this message translates to:
  /// **'Paired · tap to scan its code'**
  String get pairedTapToScan;

  /// No description provided for @pairedWithAddress.
  ///
  /// In en, this message translates to:
  /// **'Paired · {host}'**
  String pairedWithAddress(String host);

  /// No description provided for @pairedNotSeen.
  ///
  /// In en, this message translates to:
  /// **'Paired · not seen right now · {host}'**
  String pairedNotSeen(String host);

  /// No description provided for @tapToPair.
  ///
  /// In en, this message translates to:
  /// **'Tap to pair · {host}'**
  String tapToPair(String host);

  /// No description provided for @pairAgain.
  ///
  /// In en, this message translates to:
  /// **'Pair again'**
  String get pairAgain;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @renameComputer.
  ///
  /// In en, this message translates to:
  /// **'Rename computer'**
  String get renameComputer;

  /// No description provided for @computerName.
  ///
  /// In en, this message translates to:
  /// **'Computer name'**
  String get computerName;

  /// No description provided for @invalidComputerName.
  ///
  /// In en, this message translates to:
  /// **'Invalid name: 1–64 characters, no control codes or line breaks.'**
  String get invalidComputerName;

  /// No description provided for @switchComputersTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch computers?'**
  String get switchComputersTitle;

  /// No description provided for @switchComputersMessage.
  ///
  /// In en, this message translates to:
  /// **'This phone talks to one computer at a time, so connecting to {name} will disconnect the one you are on. Anything still transferring will stop.'**
  String switchComputersMessage(String name);

  /// No description provided for @stay.
  ///
  /// In en, this message translates to:
  /// **'Stay'**
  String get stay;

  /// No description provided for @switchToComputer.
  ///
  /// In en, this message translates to:
  /// **'Switch to {name}'**
  String switchToComputer(String name);

  /// No description provided for @deviceCantSearch.
  ///
  /// In en, this message translates to:
  /// **'This device can’t search automatically'**
  String get deviceCantSearch;

  /// No description provided for @lookingForComputers.
  ///
  /// In en, this message translates to:
  /// **'Looking for computers'**
  String get lookingForComputers;

  /// No description provided for @noComputersFound.
  ///
  /// In en, this message translates to:
  /// **'No computers found'**
  String get noComputersFound;

  /// No description provided for @deviceCantSearchExplanation.
  ///
  /// In en, this message translates to:
  /// **'iPhones need a special Apple permission to search the local network, and some Wi-Fi networks block it entirely.\n\nScan the code your computer shows instead — it carries the address, so searching is not needed. Everything else works exactly the same.'**
  String get deviceCantSearchExplanation;

  /// No description provided for @lookingForComputersExplanation.
  ///
  /// In en, this message translates to:
  /// **'Make sure Remote Link is running on your computer and both devices are on the same Wi-Fi network.'**
  String get lookingForComputersExplanation;

  /// No description provided for @noComputersFoundExplanation.
  ///
  /// In en, this message translates to:
  /// **'Check that Remote Link is running on your computer and that both devices are on the same Wi-Fi.\n\nSome networks — guest Wi-Fi in particular — block the traffic that finds computers automatically. If yours does, click “Pair a phone” on the computer and scan the code it shows. It is remembered afterwards.'**
  String get noComputersFoundExplanation;

  /// No description provided for @platformMac.
  ///
  /// In en, this message translates to:
  /// **'Mac'**
  String get platformMac;

  /// No description provided for @platformWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows PC'**
  String get platformWindows;

  /// No description provided for @platformLinux.
  ///
  /// In en, this message translates to:
  /// **'Linux computer'**
  String get platformLinux;

  /// No description provided for @platformComputer.
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get platformComputer;

  /// No description provided for @tabTouchpad.
  ///
  /// In en, this message translates to:
  /// **'Touchpad'**
  String get tabTouchpad;

  /// No description provided for @tabKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get tabKeyboard;

  /// No description provided for @tabMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get tabMedia;

  /// No description provided for @tabClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get tabClipboard;

  /// No description provided for @tabSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get tabSend;

  /// No description provided for @tooltipShowTabs.
  ///
  /// In en, this message translates to:
  /// **'Show the tabs again'**
  String get tooltipShowTabs;

  /// No description provided for @tooltipExpandGesture.
  ///
  /// In en, this message translates to:
  /// **'Expand the gesture area'**
  String get tooltipExpandGesture;

  /// No description provided for @tooltipScreenStream.
  ///
  /// In en, this message translates to:
  /// **'Screen Stream'**
  String get tooltipScreenStream;

  /// No description provided for @clipboardSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Clipboard sync'**
  String get clipboardSyncTitle;

  /// No description provided for @clipboardConnectedActive.
  ///
  /// In en, this message translates to:
  /// **'Connected and active'**
  String get clipboardConnectedActive;

  /// No description provided for @clipboardSyncPaused.
  ///
  /// In en, this message translates to:
  /// **'Sync is paused'**
  String get clipboardSyncPaused;

  /// No description provided for @clipboardReadyToSync.
  ///
  /// In en, this message translates to:
  /// **'Ready to sync'**
  String get clipboardReadyToSync;

  /// No description provided for @clipboardFromComputer.
  ///
  /// In en, this message translates to:
  /// **'From {name}'**
  String clipboardFromComputer(String name);

  /// No description provided for @clipboardFromYourComputer.
  ///
  /// In en, this message translates to:
  /// **'From your computer'**
  String get clipboardFromYourComputer;

  /// No description provided for @clipboardFromThisPhone.
  ///
  /// In en, this message translates to:
  /// **'From this phone'**
  String get clipboardFromThisPhone;

  /// No description provided for @clipboardPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your latest clipboard item will appear here.'**
  String get clipboardPlaceholder;

  /// No description provided for @clipboardSendButton.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get clipboardSendButton;

  /// No description provided for @clipboardGetButton.
  ///
  /// In en, this message translates to:
  /// **'Get'**
  String get clipboardGetButton;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @historySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap an item to copy it again'**
  String get historySubtitle;

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

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @deletedFromHistory.
  ///
  /// In en, this message translates to:
  /// **'Deleted from history'**
  String get deletedFromHistory;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied.'**
  String get copied;

  /// No description provided for @itemCantBeCopied.
  ///
  /// In en, this message translates to:
  /// **'That item can’t be copied here.'**
  String get itemCantBeCopied;

  /// No description provided for @pinLimitReached.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You can pin up to 1 item. Unpin one first.} other{You can pin up to {count} items. Unpin one first.}}'**
  String pinLimitReached(int count);

  /// No description provided for @systemBatteryCharging.
  ///
  /// In en, this message translates to:
  /// **'Computer battery {percent} percent, charging'**
  String systemBatteryCharging(int percent);

  /// No description provided for @systemBattery.
  ///
  /// In en, this message translates to:
  /// **'Computer battery {percent} percent'**
  String systemBattery(int percent);

  /// No description provided for @systemProcessor.
  ///
  /// In en, this message translates to:
  /// **'Processor {percent} percent'**
  String systemProcessor(String percent);

  /// No description provided for @systemMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory {percent} percent'**
  String systemMemory(String percent);

  /// No description provided for @systemUptime.
  ///
  /// In en, this message translates to:
  /// **'Up {uptime}'**
  String systemUptime(String uptime);

  /// No description provided for @touchpadLabel.
  ///
  /// In en, this message translates to:
  /// **'Touchpad'**
  String get touchpadLabel;

  /// No description provided for @touchpadHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to move the pointer. Double tap to click. Swipe with three fingers to scroll. Directional controls are available below.'**
  String get touchpadHint;

  /// No description provided for @touchpadWatermarkHint.
  ///
  /// In en, this message translates to:
  /// **'Drag to move · Tap to click\nTwo fingers to scroll or right-click\nHold to drag\n\nAdjust sensitivity anytime in Settings'**
  String get touchpadWatermarkHint;

  /// No description provided for @sensitivityBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Pointer Sensitivity'**
  String get sensitivityBannerTitle;

  /// No description provided for @sensitivityBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap for tutorial or adjust in Settings'**
  String get sensitivityBannerSubtitle;

  /// No description provided for @adjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get adjust;

  /// No description provided for @dismissHint.
  ///
  /// In en, this message translates to:
  /// **'Dismiss hint'**
  String get dismissHint;

  /// No description provided for @pointerControlsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pointer controls'**
  String get pointerControlsTitle;

  /// No description provided for @hidePointerControls.
  ///
  /// In en, this message translates to:
  /// **'Hide pointer controls'**
  String get hidePointerControls;

  /// No description provided for @showPointerControls.
  ///
  /// In en, this message translates to:
  /// **'Show pointer controls'**
  String get showPointerControls;

  /// No description provided for @stepSizeAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Step size, currently {stepName}'**
  String stepSizeAnnouncement(String stepName);

  /// No description provided for @stepFine.
  ///
  /// In en, this message translates to:
  /// **'Fine'**
  String get stepFine;

  /// No description provided for @stepNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get stepNormal;

  /// No description provided for @stepCoarse.
  ///
  /// In en, this message translates to:
  /// **'Coarse'**
  String get stepCoarse;

  /// No description provided for @stepTooltip.
  ///
  /// In en, this message translates to:
  /// **'{stepName} — {pixels, plural, =1{1 pixel per press} other{{pixels} pixels per press}}'**
  String stepTooltip(String stepName, int pixels);

  /// No description provided for @movePointerLeft.
  ///
  /// In en, this message translates to:
  /// **'{pixels, plural, =1{Move pointer left 1 pixel} other{Move pointer left {pixels} pixels}}'**
  String movePointerLeft(int pixels);

  /// No description provided for @movePointerRight.
  ///
  /// In en, this message translates to:
  /// **'{pixels, plural, =1{Move pointer right 1 pixel} other{Move pointer right {pixels} pixels}}'**
  String movePointerRight(int pixels);

  /// No description provided for @movePointerUp.
  ///
  /// In en, this message translates to:
  /// **'{pixels, plural, =1{Move pointer up 1 pixel} other{Move pointer up {pixels} pixels}}'**
  String movePointerUp(int pixels);

  /// No description provided for @movePointerDown.
  ///
  /// In en, this message translates to:
  /// **'{pixels, plural, =1{Move pointer down 1 pixel} other{Move pointer down {pixels} pixels}}'**
  String movePointerDown(int pixels);

  /// No description provided for @leftClick.
  ///
  /// In en, this message translates to:
  /// **'Left click'**
  String get leftClick;

  /// No description provided for @rightClick.
  ///
  /// In en, this message translates to:
  /// **'Right click'**
  String get rightClick;

  /// No description provided for @middleClick.
  ///
  /// In en, this message translates to:
  /// **'Middle click'**
  String get middleClick;

  /// No description provided for @scrollUp.
  ///
  /// In en, this message translates to:
  /// **'Scroll up'**
  String get scrollUp;

  /// No description provided for @scrollDown.
  ///
  /// In en, this message translates to:
  /// **'Scroll down'**
  String get scrollDown;

  /// No description provided for @padButtonLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get padButtonLeft;

  /// No description provided for @padButtonMid.
  ///
  /// In en, this message translates to:
  /// **'Mid'**
  String get padButtonMid;

  /// No description provided for @padButtonRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get padButtonRight;

  /// No description provided for @sensitivityTutorialTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pointer sensitivity tutorial'**
  String get sensitivityTutorialTooltip;

  /// No description provided for @tutorialTitle.
  ///
  /// In en, this message translates to:
  /// **'Pointer sensitivity'**
  String get tutorialTitle;

  /// No description provided for @tutorialMessage.
  ///
  /// In en, this message translates to:
  /// **'Moving the cursor feels natural when the sensitivity matches your screen resolution.\n\nAdjust it at any time in Settings › Touchpad to match your preference.'**
  String get tutorialMessage;

  /// No description provided for @openSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettingsButton;

  /// No description provided for @gotItButton.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotItButton;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @volumePercent.
  ///
  /// In en, this message translates to:
  /// **'Volume {percent} percent'**
  String volumePercent(int percent);

  /// No description provided for @display.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get display;

  /// No description provided for @screenBrightnessPercent.
  ///
  /// In en, this message translates to:
  /// **'Screen brightness {percent} percent'**
  String screenBrightnessPercent(int percent);

  /// No description provided for @nothingPlaying.
  ///
  /// In en, this message translates to:
  /// **'Nothing playing'**
  String get nothingPlaying;

  /// No description provided for @mediaControls.
  ///
  /// In en, this message translates to:
  /// **'Media controls'**
  String get mediaControls;

  /// No description provided for @playSomethingHint.
  ///
  /// In en, this message translates to:
  /// **'Play something and it will appear here. Controls work with any app, including browsers.'**
  String get playSomethingHint;

  /// No description provided for @trackDetailsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Track details are unavailable on this computer. Playback and volume controls still work.'**
  String get trackDetailsUnavailable;

  /// No description provided for @previousTrack.
  ///
  /// In en, this message translates to:
  /// **'Previous track'**
  String get previousTrack;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @nextTrack.
  ///
  /// In en, this message translates to:
  /// **'Next track'**
  String get nextTrack;

  /// No description provided for @mediaControlUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Media control isn’t available'**
  String get mediaControlUnavailable;

  /// No description provided for @mediaControlUnavailableExplanation.
  ///
  /// In en, this message translates to:
  /// **'This computer didn’t offer media control. It is implemented on macOS; Windows support is still to come.'**
  String get mediaControlUnavailableExplanation;

  /// No description provided for @sendToSubtitleNoDevice.
  ///
  /// In en, this message translates to:
  /// **'No device connected'**
  String get sendToSubtitleNoDevice;

  /// No description provided for @sendToSubtitleSingle.
  ///
  /// In en, this message translates to:
  /// **'to {name}'**
  String sendToSubtitleSingle(String name);

  /// No description provided for @sendToSubtitleMultiple.
  ///
  /// In en, this message translates to:
  /// **'to {name}, of {total}'**
  String sendToSubtitleMultiple(String name, int total);

  /// No description provided for @nowhereToSendYet.
  ///
  /// In en, this message translates to:
  /// **'Nowhere to send yet'**
  String get nowhereToSendYet;

  /// No description provided for @nowhereToSendExplanation.
  ///
  /// In en, this message translates to:
  /// **'Connect to a computer, or open Remote Link on another phone on the same Wi-Fi and it will appear here.'**
  String get nowhereToSendExplanation;

  /// No description provided for @addMedia.
  ///
  /// In en, this message translates to:
  /// **'Add media'**
  String get addMedia;

  /// No description provided for @media.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get media;

  /// No description provided for @addFiles.
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get addFiles;

  /// No description provided for @files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get files;

  /// No description provided for @pickedFilesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item · {size}} other{{count} items · {size}}}'**
  String pickedFilesCount(int count, String size);

  /// No description provided for @removeFileTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}'**
  String removeFileTooltip(String name);

  /// No description provided for @deletedFromSelection.
  ///
  /// In en, this message translates to:
  /// **'Deleted from selection'**
  String get deletedFromSelection;

  /// No description provided for @chooseSomethingToSend.
  ///
  /// In en, this message translates to:
  /// **'Choose something to send first.'**
  String get chooseSomethingToSend;

  /// No description provided for @filesNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{name} is no longer available. Choose it again.} other{{count} files are no longer available. Choose them again.}}'**
  String filesNoLongerAvailable(int count, String name);

  /// No description provided for @offeredItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Offered 1 item to {target}.} other{Offered {count} items to {target}.}}'**
  String offeredItems(int count, String target);

  /// No description provided for @couldNotRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not retry: {error}'**
  String couldNotRetry(String error);

  /// No description provided for @transferDeleted.
  ///
  /// In en, this message translates to:
  /// **'Transfer deleted'**
  String get transferDeleted;

  /// No description provided for @connectToDeviceToSend.
  ///
  /// In en, this message translates to:
  /// **'Connect to a device to send.'**
  String get connectToDeviceToSend;

  /// No description provided for @chooseMediaOrFilesAbove.
  ///
  /// In en, this message translates to:
  /// **'Choose media or files above.'**
  String get chooseMediaOrFilesAbove;

  /// No description provided for @previewFile.
  ///
  /// In en, this message translates to:
  /// **'Preview {name}'**
  String previewFile(String name);

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

  /// No description provided for @transferFileItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item · {size}} other{{count} items · {size}}}'**
  String transferFileItemCount(int count, String size);

  /// No description provided for @deleteTransfer.
  ///
  /// In en, this message translates to:
  /// **'Delete transfer'**
  String get deleteTransfer;

  /// No description provided for @fileNoLongerStored.
  ///
  /// In en, this message translates to:
  /// **'This file is no longer stored on your phone.'**
  String get fileNoLongerStored;

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open {name}'**
  String openFile(String name);

  /// No description provided for @shareFile.
  ///
  /// In en, this message translates to:
  /// **'Share {name}'**
  String shareFile(String name);

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed: {error}'**
  String sendFailed(String error);

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @transferEta.
  ///
  /// In en, this message translates to:
  /// **'ETA: {eta}'**
  String transferEta(String eta);

  /// No description provided for @statusWaitingForYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get statusWaitingForYou;

  /// No description provided for @statusAwaitingResponse.
  ///
  /// In en, this message translates to:
  /// **'Awaiting response'**
  String get statusAwaitingResponse;

  /// No description provided for @statusOffered.
  ///
  /// In en, this message translates to:
  /// **'Offered'**
  String get statusOffered;

  /// No description provided for @statusTransferring.
  ///
  /// In en, this message translates to:
  /// **'Transferring'**
  String get statusTransferring;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusDeclined.
  ///
  /// In en, this message translates to:
  /// **'Declined'**
  String get statusDeclined;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @keyboardModeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get keyboardModeText;

  /// No description provided for @keyboardModeKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get keyboardModeKeys;

  /// No description provided for @modifierLockedOn.
  ///
  /// In en, this message translates to:
  /// **'{name}, locked on'**
  String modifierLockedOn(String name);

  /// No description provided for @sentToComputer.
  ///
  /// In en, this message translates to:
  /// **'Sent to your computer'**
  String get sentToComputer;

  /// No description provided for @clearTranscript.
  ///
  /// In en, this message translates to:
  /// **'Clear the transcript'**
  String get clearTranscript;

  /// No description provided for @tapHereThenType.
  ///
  /// In en, this message translates to:
  /// **'Tap here, then type.'**
  String get tapHereThenType;

  /// No description provided for @sectionShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get sectionShortcuts;

  /// No description provided for @sectionModifiers.
  ///
  /// In en, this message translates to:
  /// **'Modifiers'**
  String get sectionModifiers;

  /// No description provided for @sectionKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get sectionKeys;

  /// No description provided for @shortcutCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shortcutCopy;

  /// No description provided for @shortcutPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get shortcutPaste;

  /// No description provided for @shortcutCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get shortcutCut;

  /// No description provided for @shortcutUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get shortcutUndo;

  /// No description provided for @shortcutRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get shortcutRedo;

  /// No description provided for @shortcutSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get shortcutSelectAll;

  /// No description provided for @shortcutSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get shortcutSave;

  /// No description provided for @shortcutFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get shortcutFind;

  /// No description provided for @shortcutSwitchApp.
  ///
  /// In en, this message translates to:
  /// **'Switch app'**
  String get shortcutSwitchApp;

  /// No description provided for @shortcutCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close tab'**
  String get shortcutCloseTab;

  /// No description provided for @shortcutRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get shortcutRefresh;

  /// No description provided for @shortcutTaskManager.
  ///
  /// In en, this message translates to:
  /// **'Task manager'**
  String get shortcutTaskManager;

  /// No description provided for @scanCodeToPair.
  ///
  /// In en, this message translates to:
  /// **'Scan code to pair'**
  String get scanCodeToPair;

  /// No description provided for @scanCodeInstructions.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at the code on your computer\'s screen.'**
  String get scanCodeInstructions;

  /// No description provided for @verifyingSecurityCode.
  ///
  /// In en, this message translates to:
  /// **'Verifying security code…'**
  String get verifyingSecurityCode;

  /// No description provided for @pairingFailed.
  ///
  /// In en, this message translates to:
  /// **'Pairing failed: {reason}'**
  String pairingFailed(String reason);

  /// No description provided for @securityCodeMatchesPrompt.
  ///
  /// In en, this message translates to:
  /// **'Compare the code below with the one shown on “{name}”:'**
  String securityCodeMatchesPrompt(String name);

  /// No description provided for @securityCodeDoesNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Codes do not match'**
  String get securityCodeDoesNotMatch;

  /// No description provided for @securityCodeMatches.
  ///
  /// In en, this message translates to:
  /// **'Codes match'**
  String get securityCodeMatches;

  /// No description provided for @waitingForApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for “{name}” to approve the connection…'**
  String waitingForApproval(String name);

  /// No description provided for @incomingConnectionRequest.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is asking to connect'**
  String incomingConnectionRequest(String name);

  /// No description provided for @incomingConnectionExplanation.
  ///
  /// In en, this message translates to:
  /// **'Allow this device to interact with your phone?'**
  String get incomingConnectionExplanation;

  /// No description provided for @allowButton.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allowButton;

  /// No description provided for @declineButton.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get declineButton;

  /// No description provided for @incomingFilePrompt.
  ///
  /// In en, this message translates to:
  /// **'“{name}” wants to send you {count, plural, =1{1 file ({size})} other{{count} files ({size})}}'**
  String incomingFilePrompt(String name, int count, String size);

  /// No description provided for @connectionHoldWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for “{name}” to respond…'**
  String connectionHoldWaiting(String name);

  /// No description provided for @connectionHoldDeclined.
  ///
  /// In en, this message translates to:
  /// **'“{name}” declined the connection.'**
  String connectionHoldDeclined(String name);

  /// No description provided for @connectionHoldApproved.
  ///
  /// In en, this message translates to:
  /// **'Connected to “{name}”.'**
  String connectionHoldApproved(String name);

  /// No description provided for @sectionThisPhone.
  ///
  /// In en, this message translates to:
  /// **'This Phone'**
  String get sectionThisPhone;

  /// No description provided for @deviceName.
  ///
  /// In en, this message translates to:
  /// **'Device name'**
  String get deviceName;

  /// No description provided for @renameThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Rename this phone'**
  String get renameThisPhone;

  /// No description provided for @renamePhoneDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename this phone'**
  String get renamePhoneDialogTitle;

  /// No description provided for @deviceId.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceId;

  /// No description provided for @publicKeyFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Public-key fingerprint'**
  String get publicKeyFingerprint;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get sectionAppearance;

  /// No description provided for @themeModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeModeLabel;

  /// No description provided for @themeModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeModeDark;

  /// No description provided for @sectionTouchpad.
  ///
  /// In en, this message translates to:
  /// **'Touchpad'**
  String get sectionTouchpad;

  /// No description provided for @pointerSpeed.
  ///
  /// In en, this message translates to:
  /// **'Pointer speed'**
  String get pointerSpeed;

  /// No description provided for @pointerAcceleration.
  ///
  /// In en, this message translates to:
  /// **'Pointer acceleration'**
  String get pointerAcceleration;

  /// No description provided for @scrollSpeed.
  ///
  /// In en, this message translates to:
  /// **'Scroll speed'**
  String get scrollSpeed;

  /// No description provided for @naturalScrolling.
  ///
  /// In en, this message translates to:
  /// **'Natural scrolling'**
  String get naturalScrolling;

  /// No description provided for @naturalScrollingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Content moves in the direction of your fingers'**
  String get naturalScrollingSubtitle;

  /// No description provided for @hapticFeedback.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get hapticFeedback;

  /// No description provided for @hapticFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on clicks and gestures'**
  String get hapticFeedbackSubtitle;

  /// No description provided for @sectionReceiving.
  ///
  /// In en, this message translates to:
  /// **'Receiving'**
  String get sectionReceiving;

  /// No description provided for @allowFileTransfers.
  ///
  /// In en, this message translates to:
  /// **'Allow incoming transfers'**
  String get allowFileTransfers;

  /// No description provided for @allowFileTransfersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prompt when nearby devices want to send files'**
  String get allowFileTransfersSubtitle;

  /// No description provided for @sectionPairedComputers.
  ///
  /// In en, this message translates to:
  /// **'Paired Computers'**
  String get sectionPairedComputers;

  /// No description provided for @noPairedComputers.
  ///
  /// In en, this message translates to:
  /// **'No paired computers yet'**
  String get noPairedComputers;

  /// No description provided for @forgetDevice.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forgetDevice;

  /// No description provided for @forgetDeviceConfirm.
  ///
  /// In en, this message translates to:
  /// **'Forget “{name}”? You will need to pair again to connect.'**
  String forgetDeviceConfirm(String name);

  /// No description provided for @sectionClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clipboard'**
  String get sectionClipboard;

  /// No description provided for @syncFromDesktop.
  ///
  /// In en, this message translates to:
  /// **'Sync from computer'**
  String get syncFromDesktop;

  /// No description provided for @syncFromDesktopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically update phone clipboard when copying on computer'**
  String get syncFromDesktopSubtitle;

  /// No description provided for @syncToDesktop.
  ///
  /// In en, this message translates to:
  /// **'Sync to computer'**
  String get syncToDesktop;

  /// No description provided for @syncToDesktopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send copied text to computer'**
  String get syncToDesktopSubtitle;

  /// No description provided for @sectionBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get sectionBackground;

  /// No description provided for @keepConnectionAlive.
  ///
  /// In en, this message translates to:
  /// **'Keep connection alive in background'**
  String get keepConnectionAlive;

  /// No description provided for @keepConnectionAliveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Maintain link when app is minimised'**
  String get keepConnectionAliveSubtitle;

  /// No description provided for @sectionDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get sectionDiagnostics;

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export Logs'**
  String get exportLogs;

  /// No description provided for @exportLogsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share diagnostic logs for troubleshooting'**
  String get exportLogsSubtitle;

  /// No description provided for @logsExported.
  ///
  /// In en, this message translates to:
  /// **'Logs exported.'**
  String get logsExported;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get sectionAbout;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String version(String version);

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get openSourceLicenses;

  /// No description provided for @connectionDeclined.
  ///
  /// In en, this message translates to:
  /// **'{name} did not allow the connection.'**
  String connectionDeclined(String name);

  /// No description provided for @connectionTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Nobody answered on {name}, so the connection was not allowed.'**
  String connectionTimedOut(String name);

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @waitingToBeLetInTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be let in'**
  String get waitingToBeLetInTitle;

  /// No description provided for @waitingToBeLetInMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} is asking whether to allow this connection.'**
  String waitingToBeLetInMessage(String name);

  /// No description provided for @waitingToBeLetInInstructions.
  ///
  /// In en, this message translates to:
  /// **'Go to it and tap Allow. Nothing is sent until someone does.'**
  String get waitingToBeLetInInstructions;

  /// No description provided for @stopWaiting.
  ///
  /// In en, this message translates to:
  /// **'Stop waiting'**
  String get stopWaiting;

  /// No description provided for @rememberConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Remember this connection?'**
  String get rememberConnectionTitle;

  /// No description provided for @rememberConnectionMessage.
  ///
  /// In en, this message translates to:
  /// **'Remote Link can reconnect to {name} by itself next time — no code to scan, and nobody asked to allow it.'**
  String rememberConnectionMessage(String name);

  /// No description provided for @rememberConnectionExplanation.
  ///
  /// In en, this message translates to:
  /// **'{name} is being asked the same thing. Both devices have to agree, and either one can change its mind later.'**
  String rememberConnectionExplanation(String name);

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @remember.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get remember;

  /// No description provided for @nothingCopiedYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing copied yet'**
  String get nothingCopiedYet;

  /// No description provided for @nothingCopiedYetExplanation.
  ///
  /// In en, this message translates to:
  /// **'Recent items appear here. Anything your password manager marks confidential is never recorded.'**
  String get nothingCopiedYetExplanation;

  /// No description provided for @securityCodeSpoken.
  ///
  /// In en, this message translates to:
  /// **'Security code: {code}'**
  String securityCodeSpoken(String code);

  /// No description provided for @pairWithDevice.
  ///
  /// In en, this message translates to:
  /// **'Pair with {name}'**
  String pairWithDevice(String name);

  /// No description provided for @checkingTheCode.
  ///
  /// In en, this message translates to:
  /// **'Checking the code…'**
  String get checkingTheCode;

  /// No description provided for @connectingSecurely.
  ///
  /// In en, this message translates to:
  /// **'Connecting securely…'**
  String get connectingSecurely;

  /// No description provided for @checkDigitsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Check that your computer is showing these digits'**
  String get checkDigitsPrompt;

  /// No description provided for @numbersDifferentWarning.
  ///
  /// In en, this message translates to:
  /// **'If the numbers are different, something is intercepting the connection. Cancel and try again on a network you trust.'**
  String get numbersDifferentWarning;

  /// No description provided for @theNumbersMatch.
  ///
  /// In en, this message translates to:
  /// **'The numbers match'**
  String get theNumbersMatch;

  /// No description provided for @notTheComputerOnCode.
  ///
  /// In en, this message translates to:
  /// **'This is not the computer on the code'**
  String get notTheComputerOnCode;

  /// No description provided for @notTheComputerOnCodeExplanation.
  ///
  /// In en, this message translates to:
  /// **'Something answered at that address with a different identity than the code showed. Remote Link did not pair with it and did not send it anything.\n\nOn a network you trust this should never happen. Show the code again on {name} and scan the new one.'**
  String notTheComputerOnCodeExplanation(String name);

  /// No description provided for @couldNotEstablishSecureConnection.
  ///
  /// In en, this message translates to:
  /// **'Could not establish a secure connection'**
  String get couldNotEstablishSecureConnection;

  /// No description provided for @pairingFailedRefusedOrMismatched.
  ///
  /// In en, this message translates to:
  /// **'The computer refused the connection, or its identity did not match what this phone had stored.'**
  String get pairingFailedRefusedOrMismatched;

  /// No description provided for @torchTooltip.
  ///
  /// In en, this message translates to:
  /// **'Torch'**
  String get torchTooltip;

  /// No description provided for @scannerInstructions.
  ///
  /// In en, this message translates to:
  /// **'On your computer, open Remote Link and click “Pair a phone”.'**
  String get scannerInstructions;

  /// No description provided for @foreignCodeWarning.
  ///
  /// In en, this message translates to:
  /// **'That code is not from Remote Link.'**
  String get foreignCodeWarning;

  /// No description provided for @cameraPermissionDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Link cannot use the camera'**
  String get cameraPermissionDeniedTitle;

  /// No description provided for @cameraPermissionDeniedDesc.
  ///
  /// In en, this message translates to:
  /// **'Turn the camera on for Remote Link in your device’s Settings, under Apps.\n\nYou can pair without it: go back, and the computer appears in the list on its own as long as both are on the same Wi-Fi.'**
  String get cameraPermissionDeniedDesc;

  /// No description provided for @cameraUnsupportedTitle.
  ///
  /// In en, this message translates to:
  /// **'This device has no camera to scan with'**
  String get cameraUnsupportedTitle;

  /// No description provided for @cameraUnsupportedDesc.
  ///
  /// In en, this message translates to:
  /// **'Go back — the computer appears in the list on its own as long as both are on the same Wi-Fi.'**
  String get cameraUnsupportedDesc;

  /// No description provided for @cameraErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'The camera could not start'**
  String get cameraErrorTitle;

  /// No description provided for @cameraErrorDesc.
  ///
  /// In en, this message translates to:
  /// **'Something stopped the camera from starting. Try again, or go back and pick the computer from the list.'**
  String get cameraErrorDesc;

  /// No description provided for @incomingDevicePrompt.
  ///
  /// In en, this message translates to:
  /// **'A device wants to connect'**
  String get incomingDevicePrompt;

  /// No description provided for @pairingPromptHelp.
  ///
  /// In en, this message translates to:
  /// **'Connect only if the other device is showing these same six digits. If they differ, something else is answering — decline and try again.'**
  String get pairingPromptHelp;

  /// No description provided for @codesMatch.
  ///
  /// In en, this message translates to:
  /// **'Codes match'**
  String get codesMatch;

  /// No description provided for @allowDeviceToConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow this device to connect?'**
  String get allowDeviceToConnectTitle;

  /// No description provided for @allowDeviceToConnectHelp.
  ///
  /// In en, this message translates to:
  /// **'You have paired with it before, so its identity is already checked. This is only about now — allow it if the device is in your hands, and turn it away if it is not.'**
  String get allowDeviceToConnectHelp;

  /// No description provided for @allowDeviceToConnectRestartHelp.
  ///
  /// In en, this message translates to:
  /// **'You will not be asked about it again until Remote Link restarts.'**
  String get allowDeviceToConnectRestartHelp;

  /// No description provided for @rememberDevicePromptHelp.
  ///
  /// In en, this message translates to:
  /// **'Remote Link can let {name} straight in next time — no code to scan, and nobody asked to allow it.'**
  String rememberDevicePromptHelp(String name);

  /// No description provided for @rememberDevicePromptBothAgree.
  ///
  /// In en, this message translates to:
  /// **'{name} is being asked the same thing. Both devices have to agree, and either one can change its mind later.'**
  String rememberDevicePromptBothAgree(String name);

  /// No description provided for @incomingFileTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, zero{Incoming files} one{Incoming file} two{Incoming files} few{Incoming files} many{Incoming files} other{Incoming files}}'**
  String incomingFileTitle(int count);

  /// No description provided for @incomingMoreFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, zero{and none more} one{and 1 more} two{and 2 more} few{and {count} more} many{and {count} more} other{and {count} more}}'**
  String incomingMoreFiles(int count);

  /// No description provided for @incomingDestinationExplanation.
  ///
  /// In en, this message translates to:
  /// **'Photos and videos are saved to your Photos library. Anything else opens the share sheet so you can choose where it goes. Recent arrivals stay openable from this list.'**
  String get incomingDestinationExplanation;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @customiseCursorSpeed.
  ///
  /// In en, this message translates to:
  /// **'Customise cursor speed'**
  String get customiseCursorSpeed;

  /// No description provided for @tutorialIntro.
  ///
  /// In en, this message translates to:
  /// **'Cursor moving too fast or too slow? You can easily fine-tune pointer speed to suit your workflow:'**
  String get tutorialIntro;

  /// No description provided for @tutorialStep1Title.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get tutorialStep1Title;

  /// No description provided for @tutorialStep1Desc.
  ///
  /// In en, this message translates to:
  /// **'Tap the Settings gear icon in the top right corner of the app bar.'**
  String get tutorialStep1Desc;

  /// No description provided for @tutorialStep2Title.
  ///
  /// In en, this message translates to:
  /// **'Pointer Sensitivity'**
  String get tutorialStep2Title;

  /// No description provided for @tutorialStep2Desc.
  ///
  /// In en, this message translates to:
  /// **'Under Touchpad, drag the sensitivity slider between 0.5x and 3.5x.'**
  String get tutorialStep2Desc;

  /// No description provided for @tutorialStep3Title.
  ///
  /// In en, this message translates to:
  /// **'Gestures & Scrolling'**
  String get tutorialStep3Title;

  /// No description provided for @tutorialStep3Desc.
  ///
  /// In en, this message translates to:
  /// **'Toggle Natural Scrolling or Tap to Click to match your trackpad habits.'**
  String get tutorialStep3Desc;

  /// No description provided for @currentSensitivityLabel.
  ///
  /// In en, this message translates to:
  /// **'Current sensitivity: '**
  String get currentSensitivityLabel;

  /// No description provided for @screenStreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Screen Stream'**
  String get screenStreamTitle;

  /// No description provided for @startStream.
  ///
  /// In en, this message translates to:
  /// **'Start Streaming'**
  String get startStream;

  /// No description provided for @stopStream.
  ///
  /// In en, this message translates to:
  /// **'Stop Streaming'**
  String get stopStream;

  /// No description provided for @stopSharing.
  ///
  /// In en, this message translates to:
  /// **'Stop Sharing'**
  String get stopSharing;

  /// No description provided for @waitingForScreenFrames.
  ///
  /// In en, this message translates to:
  /// **'Waiting for screen frames...'**
  String get waitingForScreenFrames;

  /// No description provided for @screenSharingUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Screen sharing isn’t available'**
  String get screenSharingUnavailableTitle;

  /// No description provided for @screenSharingUnavailableDesc.
  ///
  /// In en, this message translates to:
  /// **'This computer cannot share its screen. Screen capture is supported on macOS when Screen Recording permission is granted.'**
  String get screenSharingUnavailableDesc;

  /// No description provided for @couldNotLoadIdentity.
  ///
  /// In en, this message translates to:
  /// **'Could not load device identity: {error}'**
  String couldNotLoadIdentity(String error);

  /// No description provided for @appleWatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Apple Watch'**
  String get appleWatchTitle;

  /// No description provided for @noWatchPaired.
  ///
  /// In en, this message translates to:
  /// **'No Apple Watch paired'**
  String get noWatchPaired;

  /// No description provided for @noWatchPairedDesc.
  ///
  /// In en, this message translates to:
  /// **'Pair a watch with this iPhone and Remote Link appears on it.'**
  String get noWatchPairedDesc;

  /// No description provided for @watchNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed on your watch'**
  String get watchNotInstalled;

  /// No description provided for @watchNotInstalledDesc.
  ///
  /// In en, this message translates to:
  /// **'Install Remote Link from the Watch app on this iPhone.'**
  String get watchNotInstalledDesc;

  /// No description provided for @watchOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Watch out of range'**
  String get watchOutOfRange;

  /// No description provided for @watchOutOfRangeDesc.
  ///
  /// In en, this message translates to:
  /// **'The watch controls the pointer whenever it can reach this iPhone.'**
  String get watchOutOfRangeDesc;

  /// No description provided for @watchReady.
  ///
  /// In en, this message translates to:
  /// **'Ready on your wrist'**
  String get watchReady;

  /// No description provided for @watchReadyDesc.
  ///
  /// In en, this message translates to:
  /// **'Drag on the watch to move the pointer, tap to click, and turn the Digital Crown to scroll.'**
  String get watchReadyDesc;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @logsCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard'**
  String get logsCopiedToClipboard;

  /// No description provided for @logFilter.
  ///
  /// In en, this message translates to:
  /// **'Log filter:'**
  String get logFilter;

  /// No description provided for @allLevels.
  ///
  /// In en, this message translates to:
  /// **'All Levels'**
  String get allLevels;

  /// No description provided for @logRecordsStored.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, zero{0 log records stored in memory} one{1 log record stored in memory} two{2 log records stored in memory} few{{count} log records stored in memory} many{{count} log records stored in memory} other{{count} log records stored in memory}}'**
  String logRecordsStored(int count);

  /// No description provided for @connectionStateLabel.
  ///
  /// In en, this message translates to:
  /// **'Connection state'**
  String get connectionStateLabel;

  /// No description provided for @roundTripTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Round-trip time'**
  String get roundTripTimeLabel;

  /// No description provided for @discoveryRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Discovery route'**
  String get discoveryRouteLabel;

  /// No description provided for @measuring.
  ///
  /// In en, this message translates to:
  /// **'Measuring…'**
  String get measuring;

  /// No description provided for @stateIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle (Not connected)'**
  String get stateIdle;

  /// No description provided for @letNearbyDevicesSendTitle.
  ///
  /// In en, this message translates to:
  /// **'Let nearby devices send to this phone'**
  String get letNearbyDevicesSendTitle;

  /// No description provided for @askBeforeConnectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask before a paired device connects'**
  String get askBeforeConnectingTitle;

  /// No description provided for @waitBeforeConnectingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Wait for approval before connecting'**
  String get waitBeforeConnectingSubtitle;

  /// No description provided for @connectAutomaticallySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect automatically without asking'**
  String get connectAutomaticallySubtitle;

  /// No description provided for @connectedNow.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, zero{No devices connected now} one{1 connected now} two{2 connected now} few{{count} connected now} many{{count} connected now} other{{count} connected now}}'**
  String connectedNow(int count);

  /// No description provided for @permissionsFor.
  ///
  /// In en, this message translates to:
  /// **'Permissions for {name}'**
  String permissionsFor(String name);

  /// No description provided for @renameNamed.
  ///
  /// In en, this message translates to:
  /// **'Rename {name}'**
  String renameNamed(String name);

  /// No description provided for @forgetNamed.
  ///
  /// In en, this message translates to:
  /// **'Forget {name}'**
  String forgetNamed(String name);

  /// No description provided for @forgetNamedQuestion.
  ///
  /// In en, this message translates to:
  /// **'Forget {name}?'**
  String forgetNamedQuestion(String name);

  /// No description provided for @forgotNamed.
  ///
  /// In en, this message translates to:
  /// **'Forgot {name}'**
  String forgotNamed(String name);

  /// No description provided for @phoneName.
  ///
  /// In en, this message translates to:
  /// **'Phone name'**
  String get phoneName;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen: {address}'**
  String lastSeen(String address);

  /// No description provided for @noAddressRecorded.
  ///
  /// In en, this message translates to:
  /// **'No address recorded'**
  String get noAddressRecorded;

  /// No description provided for @keepHistoryOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Keep history on this phone'**
  String get keepHistoryOnThisPhone;

  /// No description provided for @secureStorageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This phone’s secure storage is unavailable, so history stays in memory only.'**
  String get secureStorageUnavailable;

  /// No description provided for @whyPhoneOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Why does my phone need to be open?'**
  String get whyPhoneOpenTitle;

  /// No description provided for @whyPhoneOpenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'OS security requires Remote Link to be open to read clipboard.'**
  String get whyPhoneOpenSubtitle;

  /// No description provided for @backgroundClipboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Copying while Remote Link is closed'**
  String get backgroundClipboardTitle;

  /// No description provided for @batteryGuidanceTitle.
  ///
  /// In en, this message translates to:
  /// **'If Remote Link keeps disconnecting'**
  String get batteryGuidanceTitle;

  /// No description provided for @closeButton.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButton;

  /// No description provided for @openBatterySettings.
  ///
  /// In en, this message translates to:
  /// **'Open battery settings'**
  String get openBatterySettings;

  /// No description provided for @turnItOn.
  ///
  /// In en, this message translates to:
  /// **'Turn it on'**
  String get turnItOn;

  /// No description provided for @themeModeFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow the phone’s setting'**
  String get themeModeFollowSystem;

  /// No description provided for @themeModeAlwaysLight.
  ///
  /// In en, this message translates to:
  /// **'Always light'**
  String get themeModeAlwaysLight;

  /// No description provided for @themeModeAlwaysDark.
  ///
  /// In en, this message translates to:
  /// **'Always dark'**
  String get themeModeAlwaysDark;

  /// No description provided for @receivingVisibleWifi.
  ///
  /// In en, this message translates to:
  /// **'Visible on this Wi-Fi as “{name}”'**
  String receivingVisibleWifi(String name);

  /// No description provided for @receivingStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get receivingStarting;

  /// No description provided for @receivingHidden.
  ///
  /// In en, this message translates to:
  /// **'This phone will not appear on other devices'**
  String get receivingHidden;

  /// No description provided for @couldNotLoadPairedComputers.
  ///
  /// In en, this message translates to:
  /// **'Could not load paired computers: {error}'**
  String couldNotLoadPairedComputers(String error);

  /// No description provided for @noPairedComputersExplanation.
  ///
  /// In en, this message translates to:
  /// **'No paired computers yet. Pair with a computer on your Wi-Fi network to start.'**
  String get noPairedComputersExplanation;

  /// No description provided for @pairedDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Paired Devices'**
  String get pairedDevicesTitle;

  /// No description provided for @rememberAutoConnectTooltip.
  ///
  /// In en, this message translates to:
  /// **'{name} connects without being asked. Tap to start asking again.'**
  String rememberAutoConnectTooltip(String name);

  /// No description provided for @rememberAskFirstTooltip.
  ///
  /// In en, this message translates to:
  /// **'Tap to let {name} connect without being asked.'**
  String rememberAskFirstTooltip(String name);

  /// No description provided for @forgetComputerConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will remove this computer from your trusted list. You will need to pair again to reconnect.'**
  String get forgetComputerConfirmation;

  /// No description provided for @renameComputerTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename computer'**
  String get renameComputerTitle;

  /// No description provided for @invalidDeviceName.
  ///
  /// In en, this message translates to:
  /// **'Invalid name: 1–64 characters, no control codes or line breaks.'**
  String get invalidDeviceName;

  /// No description provided for @permissionsNamed.
  ///
  /// In en, this message translates to:
  /// **'Permissions · {name}'**
  String permissionsNamed(String name);

  /// No description provided for @currentPermissionTier.
  ///
  /// In en, this message translates to:
  /// **'Current Permission Tier'**
  String get currentPermissionTier;

  /// No description provided for @requestHigherTier.
  ///
  /// In en, this message translates to:
  /// **'Request Higher Tier'**
  String get requestHigherTier;

  /// No description provided for @whatTierAllows.
  ///
  /// In en, this message translates to:
  /// **'What {tier} allows:'**
  String whatTierAllows(String tier);

  /// No description provided for @reasonJustificationOptional.
  ///
  /// In en, this message translates to:
  /// **'Reason / Justification (optional)'**
  String get reasonJustificationOptional;

  /// No description provided for @reasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Need to transfer files'**
  String get reasonHint;

  /// No description provided for @requestElevation.
  ///
  /// In en, this message translates to:
  /// **'Request Elevation'**
  String get requestElevation;

  /// No description provided for @tierReadOnlyTitle.
  ///
  /// In en, this message translates to:
  /// **'View Only'**
  String get tierReadOnlyTitle;

  /// No description provided for @tierStandardTitle.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get tierStandardTitle;

  /// No description provided for @tierExtendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Extended'**
  String get tierExtendedTitle;

  /// No description provided for @tierAdminTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get tierAdminTitle;

  /// No description provided for @tierReadOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows viewing system status, media state, and screen stream.'**
  String get tierReadOnlyDesc;

  /// No description provided for @tierStandardDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows sending keyboard and mouse input, synchronizing clipboard, controlling media, viewing this screen, and transferring files.'**
  String get tierStandardDesc;

  /// No description provided for @tierExtendedDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows launching applications and running pre-registered commands.'**
  String get tierExtendedDesc;

  /// No description provided for @tierAdminDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows controlling power (shutdown, restart, sleep, lock) and managing paired devices.'**
  String get tierAdminDesc;

  /// No description provided for @connectToRequestElevation.
  ///
  /// In en, this message translates to:
  /// **'Connect to {name} to request permission elevation.'**
  String connectToRequestElevation(String name);

  /// No description provided for @permissionRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Permission request sent to {name}.'**
  String permissionRequestSent(String name);

  /// No description provided for @permissionRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to send permission request.'**
  String get permissionRequestFailed;

  /// No description provided for @pointerSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Pointer sensitivity'**
  String get pointerSensitivity;

  /// No description provided for @naturalScrollingMatches.
  ///
  /// In en, this message translates to:
  /// **'Content direction matches finger movement'**
  String get naturalScrollingMatches;

  /// No description provided for @tapToClick.
  ///
  /// In en, this message translates to:
  /// **'Tap to click'**
  String get tapToClick;

  /// No description provided for @tapToClickSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One finger left-clicks, two fingers right-click'**
  String get tapToClickSubtitle;

  /// No description provided for @hapticFeedbackDetail.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on gestures, keyboard taps, and buttons'**
  String get hapticFeedbackDetail;

  /// No description provided for @syncFromDesktopDetail.
  ///
  /// In en, this message translates to:
  /// **'Automatically receive clipboard copied on your computer'**
  String get syncFromDesktopDetail;

  /// No description provided for @syncToDesktopDetail.
  ///
  /// In en, this message translates to:
  /// **'Send phone clipboard when opening app or pressing Send'**
  String get syncToDesktopDetail;

  /// No description provided for @historyPersistentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted and saved securely on this device.'**
  String get historyPersistentSubtitle;

  /// No description provided for @historyMemoryOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Off — the list is kept in memory and disappears when you close Remote Link.'**
  String get historyMemoryOnlySubtitle;

  /// No description provided for @stayConnectedBackground.
  ///
  /// In en, this message translates to:
  /// **'Stay connected in the background'**
  String get stayConnectedBackground;

  /// No description provided for @stayConnectedBackgroundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Keeps transfers running when you switch apps. Shows a notification while connected.'**
  String get stayConnectedBackgroundSubtitle;

  /// No description provided for @keepsStoppingQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remote Link keeps stopping?'**
  String get keepsStoppingQuestion;

  /// No description provided for @keepsStoppingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Some phones close it anyway. Here is how to stop that.'**
  String get keepsStoppingSubtitle;

  /// No description provided for @copyInAnyApp.
  ///
  /// In en, this message translates to:
  /// **'Copy in any app, paste on your computer'**
  String get copyInAnyApp;

  /// No description provided for @backgroundClipboardOn.
  ///
  /// In en, this message translates to:
  /// **'On. What you copy anywhere goes to your computer.'**
  String get backgroundClipboardOn;

  /// No description provided for @backgroundClipboardOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Android only allows this through Accessibility settings.'**
  String get backgroundClipboardOff;

  /// No description provided for @couldNotOpenAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Could not open Accessibility settings.'**
  String get couldNotOpenAccessibility;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// No description provided for @accessibilityDialogPara1.
  ///
  /// In en, this message translates to:
  /// **'Android does not let an app read the clipboard unless it is the app you are looking at. That is why copying in Chrome does not reach your computer on its own.'**
  String get accessibilityDialogPara1;

  /// No description provided for @accessibilityDialogPara2.
  ///
  /// In en, this message translates to:
  /// **'The one exception is an accessibility service, which you turn on yourself in Android settings. Remote Link uses it for the clipboard and nothing else: it cannot read your screen, and it does not see what you type.'**
  String get accessibilityDialogPara2;

  /// No description provided for @accessibilityDialogPara3.
  ///
  /// In en, this message translates to:
  /// **'Settings › Accessibility › Remote Link › turn it on. Some phones refuse the read even then — if nothing arrives after enabling it, yours is one of them.'**
  String get accessibilityDialogPara3;

  /// No description provided for @batteryGuidancePara1.
  ///
  /// In en, this message translates to:
  /// **'Android stops apps it thinks you are not using, and some phones are stricter than others. Remote Link asks to keep running, but only you can grant it.'**
  String get batteryGuidancePara1;

  /// No description provided for @batteryGuidanceAnyPhone.
  ///
  /// In en, this message translates to:
  /// **'On any phone'**
  String get batteryGuidanceAnyPhone;

  /// No description provided for @batteryGuidanceAnyPhoneDesc.
  ///
  /// In en, this message translates to:
  /// **'Allow unrestricted battery use for Remote Link.'**
  String get batteryGuidanceAnyPhoneDesc;

  /// No description provided for @batteryGuidanceXiaomi.
  ///
  /// In en, this message translates to:
  /// **'Xiaomi, Redmi and POCO'**
  String get batteryGuidanceXiaomi;

  /// No description provided for @batteryGuidanceXiaomiDesc.
  ///
  /// In en, this message translates to:
  /// **'Settings › Apps › Remote Link: turn on Autostart, and set Battery saver to No restrictions. Then hold Remote Link in the recent-apps list and tap the lock.'**
  String get batteryGuidanceXiaomiDesc;

  /// No description provided for @batteryGuidanceOther.
  ///
  /// In en, this message translates to:
  /// **'Huawei, Oppo, vivo and OnePlus'**
  String get batteryGuidanceOther;

  /// No description provided for @batteryGuidanceOtherDesc.
  ///
  /// In en, this message translates to:
  /// **'Add Remote Link to the protected or auto-launch list in your battery settings.'**
  String get batteryGuidanceOtherDesc;

  /// No description provided for @noBatterySettingsScreen.
  ///
  /// In en, this message translates to:
  /// **'This phone has no battery settings screen to open. Look under Settings › Apps › Remote Link.'**
  String get noBatterySettingsScreen;

  /// No description provided for @stateConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get stateConnected;

  /// No description provided for @stateConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get stateConnecting;

  /// No description provided for @stateReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get stateReconnecting;

  /// No description provided for @statePairing.
  ///
  /// In en, this message translates to:
  /// **'Pairing…'**
  String get statePairing;

  /// No description provided for @stateAwaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be let in…'**
  String get stateAwaitingApproval;

  /// No description provided for @stateFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get stateFailed;

  /// No description provided for @routeBonjourUdp.
  ///
  /// In en, this message translates to:
  /// **'Bonjour & UDP beacon'**
  String get routeBonjourUdp;

  /// No description provided for @routeBonjour.
  ///
  /// In en, this message translates to:
  /// **'Bonjour (mDNS / DNS-SD)'**
  String get routeBonjour;

  /// No description provided for @routeUdp.
  ///
  /// In en, this message translates to:
  /// **'UDP beacon (Multicast)'**
  String get routeUdp;

  /// No description provided for @routeManual.
  ///
  /// In en, this message translates to:
  /// **'Manual address / Stored'**
  String get routeManual;

  /// No description provided for @licensesButton.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licensesButton;

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

  /// No description provided for @noTransfersYet.
  ///
  /// In en, this message translates to:
  /// **'No transfers yet'**
  String get noTransfersYet;

  /// No description provided for @transfersEmptyExplanation.
  ///
  /// In en, this message translates to:
  /// **'Anything you send or receive will stay visible here.'**
  String get transfersEmptyExplanation;

  /// No description provided for @pickerOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the picker: {error}'**
  String pickerOpenFailed(String error);

  /// No description provided for @imageOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'This image could not be opened.'**
  String get imageOpenFailed;

  /// No description provided for @connectedDeviceFallback.
  ///
  /// In en, this message translates to:
  /// **'Connected device'**
  String get connectedDeviceFallback;

  /// No description provided for @defaultAndroidPhoneName.
  ///
  /// In en, this message translates to:
  /// **'Android Phone'**
  String get defaultAndroidPhoneName;

  /// No description provided for @defaultPhoneName.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get defaultPhoneName;

  /// No description provided for @notificationConnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name}'**
  String notificationConnectedTitle(String name);

  /// No description provided for @notificationConnectedBody.
  ///
  /// In en, this message translates to:
  /// **'Remote Link is holding the connection open.'**
  String get notificationConnectedBody;

  /// No description provided for @notificationWaitingTitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {name}'**
  String notificationWaitingTitle(String name);

  /// No description provided for @notificationWaitingBody.
  ///
  /// In en, this message translates to:
  /// **'Allow the connection on {name} to carry on.'**
  String notificationWaitingBody(String name);

  /// No description provided for @notificationReconnectingBody.
  ///
  /// In en, this message translates to:
  /// **'Remote Link lost the connection and is trying again.'**
  String get notificationReconnectingBody;

  /// No description provided for @notificationStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get notificationStop;

  /// No description provided for @shareRefused.
  ///
  /// In en, this message translates to:
  /// **'The computer would not take it.'**
  String get shareRefused;

  /// No description provided for @shareUnexpectedFailure.
  ///
  /// In en, this message translates to:
  /// **'The share could not be sent.'**
  String get shareUnexpectedFailure;

  /// No description provided for @exportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Not saved — you closed the share sheet.'**
  String get exportCancelled;

  /// No description provided for @exportPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Remote Link cannot add to your photo library. Allow it under Settings › Remote Link › Photos, then send it again.'**
  String get exportPermissionDenied;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save this file to your phone.'**
  String get exportFailed;

  /// No description provided for @startingService.
  ///
  /// In en, this message translates to:
  /// **'Starting the service…'**
  String get startingService;

  /// No description provided for @keyBackspace.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get keyBackspace;

  /// No description provided for @keySwitchToThePhoneKeyboard.
  ///
  /// In en, this message translates to:
  /// **'Switch to the phone keyboard'**
  String get keySwitchToThePhoneKeyboard;

  /// No description provided for @keyLeftArrow.
  ///
  /// In en, this message translates to:
  /// **'Left arrow'**
  String get keyLeftArrow;

  /// No description provided for @keyUpArrow.
  ///
  /// In en, this message translates to:
  /// **'Up arrow'**
  String get keyUpArrow;

  /// No description provided for @keyDownArrow.
  ///
  /// In en, this message translates to:
  /// **'Down arrow'**
  String get keyDownArrow;

  /// No description provided for @keyRightArrow.
  ///
  /// In en, this message translates to:
  /// **'Right arrow'**
  String get keyRightArrow;

  /// No description provided for @keyCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get keyCommand;

  /// No description provided for @keyOption.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get keyOption;

  /// No description provided for @keyControl.
  ///
  /// In en, this message translates to:
  /// **'Control'**
  String get keyControl;

  /// No description provided for @keySpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get keySpace;

  /// No description provided for @keyEscape.
  ///
  /// In en, this message translates to:
  /// **'Escape'**
  String get keyEscape;

  /// No description provided for @keyDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get keyDelete;

  /// No description provided for @keyTab.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get keyTab;

  /// No description provided for @keyCapsLock.
  ///
  /// In en, this message translates to:
  /// **'Caps lock'**
  String get keyCapsLock;

  /// No description provided for @keyReturn.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get keyReturn;

  /// No description provided for @keyShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get keyShift;

  /// No description provided for @keyAlt.
  ///
  /// In en, this message translates to:
  /// **'Alt'**
  String get keyAlt;

  /// No description provided for @keyAltGr.
  ///
  /// In en, this message translates to:
  /// **'Alt Gr'**
  String get keyAltGr;

  /// No description provided for @keyWindows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get keyWindows;

  /// No description provided for @keyMeta.
  ///
  /// In en, this message translates to:
  /// **'Meta'**
  String get keyMeta;

  /// No description provided for @keyBacktick.
  ///
  /// In en, this message translates to:
  /// **'Backtick'**
  String get keyBacktick;

  /// No description provided for @keyMinus.
  ///
  /// In en, this message translates to:
  /// **'Minus'**
  String get keyMinus;

  /// No description provided for @keyEquals.
  ///
  /// In en, this message translates to:
  /// **'Equals'**
  String get keyEquals;

  /// No description provided for @keyLeftBracket.
  ///
  /// In en, this message translates to:
  /// **'Left bracket'**
  String get keyLeftBracket;

  /// No description provided for @keyRightBracket.
  ///
  /// In en, this message translates to:
  /// **'Right bracket'**
  String get keyRightBracket;

  /// No description provided for @keyBackslash.
  ///
  /// In en, this message translates to:
  /// **'Backslash'**
  String get keyBackslash;

  /// No description provided for @keySemicolon.
  ///
  /// In en, this message translates to:
  /// **'Semicolon'**
  String get keySemicolon;

  /// No description provided for @keyApostrophe.
  ///
  /// In en, this message translates to:
  /// **'Apostrophe'**
  String get keyApostrophe;

  /// No description provided for @keyComma.
  ///
  /// In en, this message translates to:
  /// **'Comma'**
  String get keyComma;

  /// No description provided for @keyFullStop.
  ///
  /// In en, this message translates to:
  /// **'Full stop'**
  String get keyFullStop;

  /// No description provided for @keySlash.
  ///
  /// In en, this message translates to:
  /// **'Slash'**
  String get keySlash;

  /// No description provided for @keyHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get keyHome;

  /// No description provided for @keyEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get keyEnd;

  /// No description provided for @keyPageUp.
  ///
  /// In en, this message translates to:
  /// **'Page up'**
  String get keyPageUp;

  /// No description provided for @keyPageDown.
  ///
  /// In en, this message translates to:
  /// **'Page down'**
  String get keyPageDown;

  /// No description provided for @keyEnter.
  ///
  /// In en, this message translates to:
  /// **'Enter'**
  String get keyEnter;

  /// No description provided for @transfersTitle.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfersTitle;

  /// No description provided for @shareTextDescription.
  ///
  /// In en, this message translates to:
  /// **'the text you shared'**
  String get shareTextDescription;

  /// No description provided for @shareFilesDescription.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no files} =1{one file} other{{count} files}}'**
  String shareFilesDescription(int count);
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
