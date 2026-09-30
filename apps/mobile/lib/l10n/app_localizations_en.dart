// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Remote Link';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get undo => 'Undo';

  @override
  String get clear => 'Clear';

  @override
  String get clearAll => 'Clear all';

  @override
  String get settings => 'Settings';

  @override
  String get searchAgain => 'Search again';

  @override
  String get scanCode => 'Scan code';

  @override
  String get notConnected => 'Not connected';

  @override
  String get notConnectedPeriod => 'Not connected.';

  @override
  String get connected => 'Connected';

  @override
  String get reconnecting => 'Reconnecting';

  @override
  String get connecting => 'Connecting';

  @override
  String get pairing => 'Pairing';

  @override
  String get waitingToBeLetIn => 'Waiting to be let in';

  @override
  String get connectionFailed => 'Connection failed';

  @override
  String connectionStatusLabel(String status) {
    return 'Connection status: $status';
  }

  @override
  String shareSent(String description, String peerName) {
    return 'Sent $description to $peerName.';
  }

  @override
  String shareWaiting(String description) {
    return 'Holding $description until your computer is back.';
  }

  @override
  String shareFailed(String reason) {
    return 'Could not send that: $reason';
  }

  @override
  String get devicesTitle => 'Devices';

  @override
  String reconnectingTo(String name) {
    return 'Reconnecting to $name';
  }

  @override
  String get chooseDifferentComputer => 'Choose a different computer';

  @override
  String get deviceConnectedSubtitle => 'Connected';

  @override
  String get tapForControls => ' · tap for the controls';

  @override
  String get deviceAccessRevoked => 'This computer removed your access';

  @override
  String get pairedTapToScan => 'Paired · tap to scan its code';

  @override
  String pairedWithAddress(String host) {
    return 'Paired · $host';
  }

  @override
  String pairedNotSeen(String host) {
    return 'Paired · not seen right now · $host';
  }

  @override
  String tapToPair(String host) {
    return 'Tap to pair · $host';
  }

  @override
  String get pairAgain => 'Pair again';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get renameComputer => 'Rename computer';

  @override
  String get computerName => 'Computer name';

  @override
  String get invalidComputerName =>
      'Invalid name: 1–64 characters, no control codes or line breaks.';

  @override
  String get switchComputersTitle => 'Switch computers?';

  @override
  String switchComputersMessage(String name) {
    return 'This phone talks to one computer at a time, so connecting to $name will disconnect the one you are on. Anything still transferring will stop.';
  }

  @override
  String get stay => 'Stay';

  @override
  String switchToComputer(String name) {
    return 'Switch to $name';
  }

  @override
  String get deviceCantSearch => 'This device can’t search automatically';

  @override
  String get lookingForComputers => 'Looking for computers';

  @override
  String get noComputersFound => 'No computers found';

  @override
  String get deviceCantSearchExplanation =>
      'iPhones need a special Apple permission to search the local network, and some Wi-Fi networks block it entirely.\n\nScan the code your computer shows instead — it carries the address, so searching is not needed. Everything else works exactly the same.';

  @override
  String get lookingForComputersExplanation =>
      'Make sure Remote Link is running on your computer and both devices are on the same Wi-Fi network.';

  @override
  String get noComputersFoundExplanation =>
      'Check that Remote Link is running on your computer and that both devices are on the same Wi-Fi.\n\nSome networks — guest Wi-Fi in particular — block the traffic that finds computers automatically. If yours does, click “Pair a phone” on the computer and scan the code it shows. It is remembered afterwards.';

  @override
  String get platformMac => 'Mac';

  @override
  String get platformWindows => 'Windows PC';

  @override
  String get platformLinux => 'Linux computer';

  @override
  String get platformComputer => 'Computer';

  @override
  String get tabTouchpad => 'Touchpad';

  @override
  String get tabKeyboard => 'Keyboard';

  @override
  String get tabMedia => 'Media';

  @override
  String get tabClipboard => 'Clipboard';

  @override
  String get tabSend => 'Send';

  @override
  String get tooltipShowTabs => 'Show the tabs again';

  @override
  String get tooltipExpandGesture => 'Expand the gesture area';

  @override
  String get tooltipScreenStream => 'Screen Stream';

  @override
  String get clipboardSyncTitle => 'Clipboard sync';

  @override
  String get clipboardConnectedActive => 'Connected and active';

  @override
  String get clipboardSyncPaused => 'Sync is paused';

  @override
  String get clipboardReadyToSync => 'Ready to sync';

  @override
  String clipboardFromComputer(String name) {
    return 'From $name';
  }

  @override
  String get clipboardFromYourComputer => 'From your computer';

  @override
  String get clipboardFromThisPhone => 'From this phone';

  @override
  String get clipboardPlaceholder =>
      'Your latest clipboard item will appear here.';

  @override
  String get clipboardSendButton => 'Send';

  @override
  String get clipboardGetButton => 'Get';

  @override
  String get historyTitle => 'History';

  @override
  String get historySubtitle => 'Tap an item to copy it again';

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get remove => 'Remove';

  @override
  String get deletedFromHistory => 'Deleted from history';

  @override
  String get copied => 'Copied.';

  @override
  String get itemCantBeCopied => 'That item can’t be copied here.';

  @override
  String pinLimitReached(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You can pin up to $count items. Unpin one first.',
      one: 'You can pin up to 1 item. Unpin one first.',
    );
    return '$_temp0';
  }

  @override
  String systemBatteryCharging(int percent) {
    return 'Computer battery $percent percent, charging';
  }

  @override
  String systemBattery(int percent) {
    return 'Computer battery $percent percent';
  }

  @override
  String systemProcessor(String percent) {
    return 'Processor $percent percent';
  }

  @override
  String systemMemory(String percent) {
    return 'Memory $percent percent';
  }

  @override
  String systemUptime(String uptime) {
    return 'Up $uptime';
  }

  @override
  String get touchpadLabel => 'Touchpad';

  @override
  String get touchpadHint =>
      'Drag to move the pointer. Double tap to click. Swipe with three fingers to scroll. Directional controls are available below.';

  @override
  String get touchpadWatermarkHint =>
      'Drag to move · Tap to click\nTwo fingers to scroll or right-click\nHold to drag\n\nAdjust sensitivity anytime in Settings';

  @override
  String get sensitivityBannerTitle => 'Pointer Sensitivity';

  @override
  String get sensitivityBannerSubtitle =>
      'Tap for tutorial or adjust in Settings';

  @override
  String get adjust => 'Adjust';

  @override
  String get dismissHint => 'Dismiss hint';

  @override
  String get pointerControlsTitle => 'Pointer controls';

  @override
  String get hidePointerControls => 'Hide pointer controls';

  @override
  String get showPointerControls => 'Show pointer controls';

  @override
  String stepSizeAnnouncement(String stepName) {
    return 'Step size, currently $stepName';
  }

  @override
  String get stepFine => 'Fine';

  @override
  String get stepNormal => 'Normal';

  @override
  String get stepCoarse => 'Coarse';

  @override
  String stepTooltip(String stepName, int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: '$pixels pixels per press',
      one: '1 pixel per press',
    );
    return '$stepName — $_temp0';
  }

  @override
  String movePointerLeft(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'Move pointer left $pixels pixels',
      one: 'Move pointer left 1 pixel',
    );
    return '$_temp0';
  }

  @override
  String movePointerRight(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'Move pointer right $pixels pixels',
      one: 'Move pointer right 1 pixel',
    );
    return '$_temp0';
  }

  @override
  String movePointerUp(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'Move pointer up $pixels pixels',
      one: 'Move pointer up 1 pixel',
    );
    return '$_temp0';
  }

  @override
  String movePointerDown(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'Move pointer down $pixels pixels',
      one: 'Move pointer down 1 pixel',
    );
    return '$_temp0';
  }

  @override
  String get leftClick => 'Left click';

  @override
  String get rightClick => 'Right click';

  @override
  String get middleClick => 'Middle click';

  @override
  String get scrollUp => 'Scroll up';

  @override
  String get scrollDown => 'Scroll down';

  @override
  String get padButtonLeft => 'Left';

  @override
  String get padButtonMid => 'Mid';

  @override
  String get padButtonRight => 'Right';

  @override
  String get sensitivityTutorialTooltip => 'Pointer sensitivity tutorial';

  @override
  String get tutorialTitle => 'Pointer sensitivity';

  @override
  String get tutorialMessage =>
      'Moving the cursor feels natural when the sensitivity matches your screen resolution.\n\nAdjust it at any time in Settings › Touchpad to match your preference.';

  @override
  String get openSettingsButton => 'Open Settings';

  @override
  String get gotItButton => 'Got it';

  @override
  String get unmute => 'Unmute';

  @override
  String get mute => 'Mute';

  @override
  String get volume => 'Volume';

  @override
  String volumePercent(int percent) {
    return 'Volume $percent percent';
  }

  @override
  String get display => 'Display';

  @override
  String screenBrightnessPercent(int percent) {
    return 'Screen brightness $percent percent';
  }

  @override
  String get nothingPlaying => 'Nothing playing';

  @override
  String get mediaControls => 'Media controls';

  @override
  String get playSomethingHint =>
      'Play something and it will appear here. Controls work with any app, including browsers.';

  @override
  String get trackDetailsUnavailable =>
      'Track details are unavailable on this computer. Playback and volume controls still work.';

  @override
  String get previousTrack => 'Previous track';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get nextTrack => 'Next track';

  @override
  String get mediaControlUnavailable => 'Media control isn’t available';

  @override
  String get mediaControlUnavailableExplanation =>
      'This computer didn’t offer media control. It is implemented on macOS; Windows support is still to come.';

  @override
  String get sendToSubtitleNoDevice => 'No device connected';

  @override
  String sendToSubtitleSingle(String name) {
    return 'to $name';
  }

  @override
  String sendToSubtitleMultiple(String name, int total) {
    return 'to $name, of $total';
  }

  @override
  String get nowhereToSendYet => 'Nowhere to send yet';

  @override
  String get nowhereToSendExplanation =>
      'Connect to a computer, or open Remote Link on another phone on the same Wi-Fi and it will appear here.';

  @override
  String get addMedia => 'Add media';

  @override
  String get media => 'Media';

  @override
  String get addFiles => 'Add files';

  @override
  String get files => 'Files';

  @override
  String pickedFilesCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items · $size',
      one: '1 item · $size',
    );
    return '$_temp0';
  }

  @override
  String removeFileTooltip(String name) {
    return 'Remove $name';
  }

  @override
  String get deletedFromSelection => 'Deleted from selection';

  @override
  String get chooseSomethingToSend => 'Choose something to send first.';

  @override
  String filesNoLongerAvailable(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are no longer available. Choose them again.',
      one: '$name is no longer available. Choose it again.',
    );
    return '$_temp0';
  }

  @override
  String offeredItems(int count, String target) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Offered $count items to $target.',
      one: 'Offered 1 item to $target.',
    );
    return '$_temp0';
  }

  @override
  String couldNotRetry(String error) {
    return 'Could not retry: $error';
  }

  @override
  String get transferDeleted => 'Transfer deleted';

  @override
  String get connectToDeviceToSend => 'Connect to a device to send.';

  @override
  String get chooseMediaOrFilesAbove => 'Choose media or files above.';

  @override
  String previewFile(String name) {
    return 'Preview $name';
  }

  @override
  String transferFromPeer(String name) {
    return 'From $name';
  }

  @override
  String transferToPeer(String name) {
    return 'To $name';
  }

  @override
  String transferFileItemCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items · $size',
      one: '1 item · $size',
    );
    return '$_temp0';
  }

  @override
  String get deleteTransfer => 'Delete transfer';

  @override
  String get fileNoLongerStored =>
      'This file is no longer stored on your phone.';

  @override
  String openFile(String name) {
    return 'Open $name';
  }

  @override
  String shareFile(String name) {
    return 'Share $name';
  }

  @override
  String sendFailed(String error) {
    return 'Send failed: $error';
  }

  @override
  String get dismiss => 'Dismiss';

  @override
  String transferEta(String eta) {
    return 'ETA: $eta';
  }

  @override
  String get statusWaitingForYou => 'Waiting for you';

  @override
  String get statusAwaitingResponse => 'Awaiting response';

  @override
  String get statusOffered => 'Offered';

  @override
  String get statusTransferring => 'Transferring';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusDeclined => 'Declined';

  @override
  String get statusFailed => 'Failed';

  @override
  String get retry => 'Retry';

  @override
  String get keyboardModeText => 'Text';

  @override
  String get keyboardModeKeys => 'Keys';

  @override
  String modifierLockedOn(String name) {
    return '$name, locked on';
  }

  @override
  String get sentToComputer => 'Sent to your computer';

  @override
  String get clearTranscript => 'Clear the transcript';

  @override
  String get tapHereThenType => 'Tap here, then type.';

  @override
  String get sectionShortcuts => 'Shortcuts';

  @override
  String get sectionModifiers => 'Modifiers';

  @override
  String get sectionKeys => 'Keys';

  @override
  String get shortcutCopy => 'Copy';

  @override
  String get shortcutPaste => 'Paste';

  @override
  String get shortcutCut => 'Cut';

  @override
  String get shortcutUndo => 'Undo';

  @override
  String get shortcutRedo => 'Redo';

  @override
  String get shortcutSelectAll => 'Select all';

  @override
  String get shortcutSave => 'Save';

  @override
  String get shortcutFind => 'Find';

  @override
  String get shortcutSwitchApp => 'Switch app';

  @override
  String get shortcutCloseTab => 'Close tab';

  @override
  String get shortcutRefresh => 'Refresh';

  @override
  String get shortcutTaskManager => 'Task manager';

  @override
  String get scanCodeToPair => 'Scan code to pair';

  @override
  String get scanCodeInstructions =>
      'Point your camera at the code on your computer\'s screen.';

  @override
  String get verifyingSecurityCode => 'Verifying security code…';

  @override
  String pairingFailed(String reason) {
    return 'Pairing failed: $reason';
  }

  @override
  String securityCodeMatchesPrompt(String name) {
    return 'Compare the code below with the one shown on “$name”:';
  }

  @override
  String get securityCodeDoesNotMatch => 'Codes do not match';

  @override
  String get securityCodeMatches => 'Codes match';

  @override
  String waitingForApproval(String name) {
    return 'Waiting for “$name” to approve the connection…';
  }

  @override
  String incomingConnectionRequest(String name) {
    return '“$name” is asking to connect';
  }

  @override
  String get incomingConnectionExplanation =>
      'Allow this device to interact with your phone?';

  @override
  String get allowButton => 'Allow';

  @override
  String get declineButton => 'Decline';

  @override
  String incomingFilePrompt(String name, int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files ($size)',
      one: '1 file ($size)',
    );
    return '“$name” wants to send you $_temp0';
  }

  @override
  String connectionHoldWaiting(String name) {
    return 'Waiting for “$name” to respond…';
  }

  @override
  String connectionHoldDeclined(String name) {
    return '“$name” declined the connection.';
  }

  @override
  String connectionHoldApproved(String name) {
    return 'Connected to “$name”.';
  }

  @override
  String get sectionThisPhone => 'This Phone';

  @override
  String get deviceName => 'Device name';

  @override
  String get renameThisPhone => 'Rename this phone';

  @override
  String get renamePhoneDialogTitle => 'Rename this phone';

  @override
  String get deviceId => 'Device ID';

  @override
  String get publicKeyFingerprint => 'Public-key fingerprint';

  @override
  String get sectionAppearance => 'Appearance';

  @override
  String get themeModeLabel => 'Theme';

  @override
  String get themeModeSystem => 'System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get sectionTouchpad => 'Touchpad';

  @override
  String get pointerSpeed => 'Pointer speed';

  @override
  String get pointerAcceleration => 'Pointer acceleration';

  @override
  String get scrollSpeed => 'Scroll speed';

  @override
  String get naturalScrolling => 'Natural scrolling';

  @override
  String get naturalScrollingSubtitle =>
      'Content moves in the direction of your fingers';

  @override
  String get hapticFeedback => 'Haptic feedback';

  @override
  String get hapticFeedbackSubtitle => 'Vibrate on clicks and gestures';

  @override
  String get sectionReceiving => 'Receiving';

  @override
  String get allowFileTransfers => 'Allow incoming transfers';

  @override
  String get allowFileTransfersSubtitle =>
      'Prompt when nearby devices want to send files';

  @override
  String get sectionPairedComputers => 'Paired Computers';

  @override
  String get noPairedComputers => 'No paired computers yet';

  @override
  String get forgetDevice => 'Forget';

  @override
  String forgetDeviceConfirm(String name) {
    return 'Forget “$name”? You will need to pair again to connect.';
  }

  @override
  String get sectionClipboard => 'Clipboard';

  @override
  String get syncFromDesktop => 'Sync from computer';

  @override
  String get syncFromDesktopSubtitle =>
      'Automatically update phone clipboard when copying on computer';

  @override
  String get syncToDesktop => 'Sync to computer';

  @override
  String get syncToDesktopSubtitle => 'Send copied text to computer';

  @override
  String get sectionBackground => 'Background';

  @override
  String get keepConnectionAlive => 'Keep connection alive in background';

  @override
  String get keepConnectionAliveSubtitle =>
      'Maintain link when app is minimised';

  @override
  String get sectionDiagnostics => 'Diagnostics';

  @override
  String get exportLogs => 'Export Logs';

  @override
  String get exportLogsSubtitle => 'Share diagnostic logs for troubleshooting';

  @override
  String get logsExported => 'Logs exported.';

  @override
  String get sectionAbout => 'About';

  @override
  String version(String version) {
    return 'Version $version';
  }

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String connectionDeclined(String name) {
    return '$name did not allow the connection.';
  }

  @override
  String connectionTimedOut(String name) {
    return 'Nobody answered on $name, so the connection was not allowed.';
  }

  @override
  String get tryAgain => 'Try again';

  @override
  String get waitingToBeLetInTitle => 'Waiting to be let in';

  @override
  String waitingToBeLetInMessage(String name) {
    return '$name is asking whether to allow this connection.';
  }

  @override
  String get waitingToBeLetInInstructions =>
      'Go to it and tap Allow. Nothing is sent until someone does.';

  @override
  String get stopWaiting => 'Stop waiting';

  @override
  String get rememberConnectionTitle => 'Remember this connection?';

  @override
  String rememberConnectionMessage(String name) {
    return 'Remote Link can reconnect to $name by itself next time — no code to scan, and nobody asked to allow it.';
  }

  @override
  String rememberConnectionExplanation(String name) {
    return '$name is being asked the same thing. Both devices have to agree, and either one can change its mind later.';
  }

  @override
  String get notNow => 'Not now';

  @override
  String get remember => 'Remember';

  @override
  String get nothingCopiedYet => 'Nothing copied yet';

  @override
  String get nothingCopiedYetExplanation =>
      'Recent items appear here. Anything your password manager marks confidential is never recorded.';

  @override
  String securityCodeSpoken(String code) {
    return 'Security code: $code';
  }

  @override
  String pairWithDevice(String name) {
    return 'Pair with $name';
  }

  @override
  String get checkingTheCode => 'Checking the code…';

  @override
  String get connectingSecurely => 'Connecting securely…';

  @override
  String get checkDigitsPrompt =>
      'Check that your computer is showing these digits';

  @override
  String get numbersDifferentWarning =>
      'If the numbers are different, something is intercepting the connection. Cancel and try again on a network you trust.';

  @override
  String get theNumbersMatch => 'The numbers match';

  @override
  String get notTheComputerOnCode => 'This is not the computer on the code';

  @override
  String notTheComputerOnCodeExplanation(String name) {
    return 'Something answered at that address with a different identity than the code showed. Remote Link did not pair with it and did not send it anything.\n\nOn a network you trust this should never happen. Show the code again on $name and scan the new one.';
  }

  @override
  String get couldNotEstablishSecureConnection =>
      'Could not establish a secure connection';

  @override
  String get pairingFailedRefusedOrMismatched =>
      'The computer refused the connection, or its identity did not match what this phone had stored.';

  @override
  String get torchTooltip => 'Torch';

  @override
  String get scannerInstructions =>
      'On your computer, open Remote Link and click “Pair a phone”.';

  @override
  String get foreignCodeWarning => 'That code is not from Remote Link.';

  @override
  String get cameraPermissionDeniedTitle => 'Remote Link cannot use the camera';

  @override
  String get cameraPermissionDeniedDesc =>
      'Turn the camera on for Remote Link in your device’s Settings, under Apps.\n\nYou can pair without it: go back, and the computer appears in the list on its own as long as both are on the same Wi-Fi.';

  @override
  String get cameraUnsupportedTitle => 'This device has no camera to scan with';

  @override
  String get cameraUnsupportedDesc =>
      'Go back — the computer appears in the list on its own as long as both are on the same Wi-Fi.';

  @override
  String get cameraErrorTitle => 'The camera could not start';

  @override
  String get cameraErrorDesc =>
      'Something stopped the camera from starting. Try again, or go back and pick the computer from the list.';

  @override
  String get incomingDevicePrompt => 'A device wants to connect';

  @override
  String get pairingPromptHelp =>
      'Connect only if the other device is showing these same six digits. If they differ, something else is answering — decline and try again.';

  @override
  String get codesMatch => 'Codes match';

  @override
  String get allowDeviceToConnectTitle => 'Allow this device to connect?';

  @override
  String get allowDeviceToConnectHelp =>
      'You have paired with it before, so its identity is already checked. This is only about now — allow it if the device is in your hands, and turn it away if it is not.';

  @override
  String get allowDeviceToConnectRestartHelp =>
      'You will not be asked about it again until Remote Link restarts.';

  @override
  String rememberDevicePromptHelp(String name) {
    return 'Remote Link can let $name straight in next time — no code to scan, and nobody asked to allow it.';
  }

  @override
  String rememberDevicePromptBothAgree(String name) {
    return '$name is being asked the same thing. Both devices have to agree, and either one can change its mind later.';
  }

  @override
  String incomingFileTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Incoming files',
      many: 'Incoming files',
      few: 'Incoming files',
      two: 'Incoming files',
      one: 'Incoming file',
      zero: 'Incoming files',
    );
    return '$_temp0';
  }

  @override
  String incomingMoreFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more',
      many: 'and $count more',
      few: 'and $count more',
      two: 'and 2 more',
      one: 'and 1 more',
      zero: 'and none more',
    );
    return '$_temp0';
  }

  @override
  String get incomingDestinationExplanation =>
      'Photos and videos are saved to your Photos library. Anything else opens the share sheet so you can choose where it goes. Recent arrivals stay openable from this list.';

  @override
  String get accept => 'Accept';

  @override
  String get customiseCursorSpeed => 'Customise cursor speed';

  @override
  String get tutorialIntro =>
      'Cursor moving too fast or too slow? You can easily fine-tune pointer speed to suit your workflow:';

  @override
  String get tutorialStep1Title => 'Open Settings';

  @override
  String get tutorialStep1Desc =>
      'Tap the Settings gear icon in the top right corner of the app bar.';

  @override
  String get tutorialStep2Title => 'Pointer Sensitivity';

  @override
  String get tutorialStep2Desc =>
      'Under Touchpad, drag the sensitivity slider between 0.5x and 3.5x.';

  @override
  String get tutorialStep3Title => 'Gestures & Scrolling';

  @override
  String get tutorialStep3Desc =>
      'Toggle Natural Scrolling or Tap to Click to match your trackpad habits.';

  @override
  String get currentSensitivityLabel => 'Current sensitivity: ';

  @override
  String get screenStreamTitle => 'Screen Stream';

  @override
  String get startStream => 'Start Streaming';

  @override
  String get stopStream => 'Stop Streaming';

  @override
  String get stopSharing => 'Stop Sharing';

  @override
  String get waitingForScreenFrames => 'Waiting for screen frames...';

  @override
  String get screenSharingUnavailableTitle => 'Screen sharing isn’t available';

  @override
  String get screenSharingUnavailableDesc =>
      'This computer cannot share its screen. Screen capture is supported on macOS when Screen Recording permission is granted.';

  @override
  String couldNotLoadIdentity(String error) {
    return 'Could not load device identity: $error';
  }

  @override
  String get appleWatchTitle => 'Apple Watch';

  @override
  String get noWatchPaired => 'No Apple Watch paired';

  @override
  String get noWatchPairedDesc =>
      'Pair a watch with this iPhone and Remote Link appears on it.';

  @override
  String get watchNotInstalled => 'Not installed on your watch';

  @override
  String get watchNotInstalledDesc =>
      'Install Remote Link from the Watch app on this iPhone.';

  @override
  String get watchOutOfRange => 'Watch out of range';

  @override
  String get watchOutOfRangeDesc =>
      'The watch controls the pointer whenever it can reach this iPhone.';

  @override
  String get watchReady => 'Ready on your wrist';

  @override
  String get watchReadyDesc =>
      'Drag on the watch to move the pointer, tap to click, and turn the Digital Crown to scroll.';

  @override
  String get checkAgain => 'Check again';

  @override
  String get logsCopiedToClipboard => 'Logs copied to clipboard';

  @override
  String get logFilter => 'Log filter:';

  @override
  String get allLevels => 'All Levels';

  @override
  String logRecordsStored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log records stored in memory',
      many: '$count log records stored in memory',
      few: '$count log records stored in memory',
      two: '2 log records stored in memory',
      one: '1 log record stored in memory',
      zero: '0 log records stored in memory',
    );
    return '$_temp0';
  }

  @override
  String get connectionStateLabel => 'Connection state';

  @override
  String get roundTripTimeLabel => 'Round-trip time';

  @override
  String get discoveryRouteLabel => 'Discovery route';

  @override
  String get measuring => 'Measuring…';

  @override
  String get stateIdle => 'Idle (Not connected)';

  @override
  String get letNearbyDevicesSendTitle =>
      'Let nearby devices send to this phone';

  @override
  String get askBeforeConnectingTitle => 'Ask before a paired device connects';

  @override
  String get waitBeforeConnectingSubtitle =>
      'Wait for approval before connecting';

  @override
  String get connectAutomaticallySubtitle =>
      'Connect automatically without asking';

  @override
  String connectedNow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count connected now',
      many: '$count connected now',
      few: '$count connected now',
      two: '2 connected now',
      one: '1 connected now',
      zero: 'No devices connected now',
    );
    return '$_temp0';
  }

  @override
  String permissionsFor(String name) {
    return 'Permissions for $name';
  }

  @override
  String renameNamed(String name) {
    return 'Rename $name';
  }

  @override
  String forgetNamed(String name) {
    return 'Forget $name';
  }

  @override
  String forgetNamedQuestion(String name) {
    return 'Forget $name?';
  }

  @override
  String forgotNamed(String name) {
    return 'Forgot $name';
  }

  @override
  String get phoneName => 'Phone name';

  @override
  String lastSeen(String address) {
    return 'Last seen: $address';
  }

  @override
  String get noAddressRecorded => 'No address recorded';

  @override
  String get keepHistoryOnThisPhone => 'Keep history on this phone';

  @override
  String get secureStorageUnavailable =>
      'This phone’s secure storage is unavailable, so history stays in memory only.';

  @override
  String get whyPhoneOpenTitle => 'Why does my phone need to be open?';

  @override
  String get whyPhoneOpenSubtitle =>
      'OS security requires Remote Link to be open to read clipboard.';

  @override
  String get backgroundClipboardTitle => 'Copying while Remote Link is closed';

  @override
  String get batteryGuidanceTitle => 'If Remote Link keeps disconnecting';

  @override
  String get closeButton => 'Close';

  @override
  String get openBatterySettings => 'Open battery settings';

  @override
  String get turnItOn => 'Turn it on';

  @override
  String get themeModeFollowSystem => 'Follow the phone’s setting';

  @override
  String get themeModeAlwaysLight => 'Always light';

  @override
  String get themeModeAlwaysDark => 'Always dark';

  @override
  String receivingVisibleWifi(String name) {
    return 'Visible on this Wi-Fi as “$name”';
  }

  @override
  String get receivingStarting => 'Starting…';

  @override
  String get receivingHidden => 'This phone will not appear on other devices';

  @override
  String couldNotLoadPairedComputers(String error) {
    return 'Could not load paired computers: $error';
  }

  @override
  String get noPairedComputersExplanation =>
      'No paired computers yet. Pair with a computer on your Wi-Fi network to start.';

  @override
  String get pairedDevicesTitle => 'Paired Devices';

  @override
  String rememberAutoConnectTooltip(String name) {
    return '$name connects without being asked. Tap to start asking again.';
  }

  @override
  String rememberAskFirstTooltip(String name) {
    return 'Tap to let $name connect without being asked.';
  }

  @override
  String get forgetComputerConfirmation =>
      'This will remove this computer from your trusted list. You will need to pair again to reconnect.';

  @override
  String get renameComputerTitle => 'Rename computer';

  @override
  String get invalidDeviceName =>
      'Invalid name: 1–64 characters, no control codes or line breaks.';

  @override
  String permissionsNamed(String name) {
    return 'Permissions · $name';
  }

  @override
  String get currentPermissionTier => 'Current Permission Tier';

  @override
  String get requestHigherTier => 'Request Higher Tier';

  @override
  String whatTierAllows(String tier) {
    return 'What $tier allows:';
  }

  @override
  String get reasonJustificationOptional => 'Reason / Justification (optional)';

  @override
  String get reasonHint => 'e.g. Need to transfer files';

  @override
  String get requestElevation => 'Request Elevation';

  @override
  String get tierReadOnlyTitle => 'View Only';

  @override
  String get tierStandardTitle => 'Standard';

  @override
  String get tierExtendedTitle => 'Extended';

  @override
  String get tierAdminTitle => 'Admin';

  @override
  String get tierReadOnlyDesc =>
      'Allows viewing system status, media state, and screen stream.';

  @override
  String get tierStandardDesc =>
      'Allows sending keyboard and mouse input, synchronizing clipboard, controlling media, viewing this screen, and transferring files.';

  @override
  String get tierExtendedDesc =>
      'Allows launching applications and running pre-registered commands.';

  @override
  String get tierAdminDesc =>
      'Allows controlling power (shutdown, restart, sleep, lock) and managing paired devices.';

  @override
  String connectToRequestElevation(String name) {
    return 'Connect to $name to request permission elevation.';
  }

  @override
  String permissionRequestSent(String name) {
    return 'Permission request sent to $name.';
  }

  @override
  String get permissionRequestFailed => 'Failed to send permission request.';

  @override
  String get pointerSensitivity => 'Pointer sensitivity';

  @override
  String get naturalScrollingMatches =>
      'Content direction matches finger movement';

  @override
  String get tapToClick => 'Tap to click';

  @override
  String get tapToClickSubtitle =>
      'One finger left-clicks, two fingers right-click';

  @override
  String get hapticFeedbackDetail =>
      'Vibrate on gestures, keyboard taps, and buttons';

  @override
  String get syncFromDesktopDetail =>
      'Automatically receive clipboard copied on your computer';

  @override
  String get syncToDesktopDetail =>
      'Send phone clipboard when opening app or pressing Send';

  @override
  String get historyPersistentSubtitle =>
      'Encrypted and saved securely on this device.';

  @override
  String get historyMemoryOnlySubtitle =>
      'Off — the list is kept in memory and disappears when you close Remote Link.';

  @override
  String get stayConnectedBackground => 'Stay connected in the background';

  @override
  String get stayConnectedBackgroundSubtitle =>
      'Keeps transfers running when you switch apps. Shows a notification while connected.';

  @override
  String get keepsStoppingQuestion => 'Remote Link keeps stopping?';

  @override
  String get keepsStoppingSubtitle =>
      'Some phones close it anyway. Here is how to stop that.';

  @override
  String get copyInAnyApp => 'Copy in any app, paste on your computer';

  @override
  String get backgroundClipboardOn =>
      'On. What you copy anywhere goes to your computer.';

  @override
  String get backgroundClipboardOff =>
      'Off. Android only allows this through Accessibility settings.';

  @override
  String get couldNotOpenAccessibility =>
      'Could not open Accessibility settings.';

  @override
  String get openSettings => 'Open settings';

  @override
  String get accessibilityDialogPara1 =>
      'Android does not let an app read the clipboard unless it is the app you are looking at. That is why copying in Chrome does not reach your computer on its own.';

  @override
  String get accessibilityDialogPara2 =>
      'The one exception is an accessibility service, which you turn on yourself in Android settings. Remote Link uses it for the clipboard and nothing else: it cannot read your screen, and it does not see what you type.';

  @override
  String get accessibilityDialogPara3 =>
      'Settings › Accessibility › Remote Link › turn it on. Some phones refuse the read even then — if nothing arrives after enabling it, yours is one of them.';

  @override
  String get batteryGuidancePara1 =>
      'Android stops apps it thinks you are not using, and some phones are stricter than others. Remote Link asks to keep running, but only you can grant it.';

  @override
  String get batteryGuidanceAnyPhone => 'On any phone';

  @override
  String get batteryGuidanceAnyPhoneDesc =>
      'Allow unrestricted battery use for Remote Link.';

  @override
  String get batteryGuidanceXiaomi => 'Xiaomi, Redmi and POCO';

  @override
  String get batteryGuidanceXiaomiDesc =>
      'Settings › Apps › Remote Link: turn on Autostart, and set Battery saver to No restrictions. Then hold Remote Link in the recent-apps list and tap the lock.';

  @override
  String get batteryGuidanceOther => 'Huawei, Oppo, vivo and OnePlus';

  @override
  String get batteryGuidanceOtherDesc =>
      'Add Remote Link to the protected or auto-launch list in your battery settings.';

  @override
  String get noBatterySettingsScreen =>
      'This phone has no battery settings screen to open. Look under Settings › Apps › Remote Link.';

  @override
  String get stateConnected => 'Connected';

  @override
  String get stateConnecting => 'Connecting…';

  @override
  String get stateReconnecting => 'Reconnecting…';

  @override
  String get statePairing => 'Pairing…';

  @override
  String get stateAwaitingApproval => 'Waiting to be let in…';

  @override
  String get stateFailed => 'Connection failed';

  @override
  String get routeBonjourUdp => 'Bonjour & UDP beacon';

  @override
  String get routeBonjour => 'Bonjour (mDNS / DNS-SD)';

  @override
  String get routeUdp => 'UDP beacon (Multicast)';

  @override
  String get routeManual => 'Manual address / Stored';

  @override
  String get licensesButton => 'Licenses';

  @override
  String get transferFailureTimedOut => 'Transfer timed out';

  @override
  String get transferFailureHashMismatch => 'File integrity hash mismatch';

  @override
  String get transferFailureNoSpace => 'Not enough storage space';

  @override
  String get transferFailureNoSpaceOnPeer => 'Not enough storage space on peer';

  @override
  String get transferFailureChunkRefused => 'File chunk refused';

  @override
  String transferFailureCancelledByPeer(String peerName) {
    return 'Cancelled by $peerName';
  }

  @override
  String get transferFailureCancelledByYou => 'Cancelled by you';

  @override
  String transferFailureDeclinedByPeer(String peerName) {
    return 'Declined by $peerName';
  }

  @override
  String get transferFailureDeclinedByYou => 'Declined by you';

  @override
  String get transferFailureConnectionLost => 'Connection lost';

  @override
  String get transferFailureDeviceDisconnected => 'Device disconnected';

  @override
  String get transferFailureIoError => 'I/O error during transfer';

  @override
  String get transferFailureReceiverUnavailable => 'Receiver unavailable';

  @override
  String get transferFailureStorageUnavailable => 'Storage unavailable';

  @override
  String get transferFailureCouldNotComplete => 'File could not be completed';

  @override
  String get transferFailureCouldNotAccept => 'Could not accept transfer';

  @override
  String get transferFailureRetryFailed => 'Retry failed';

  @override
  String get noTransfersYet => 'No transfers yet';

  @override
  String get transfersEmptyExplanation =>
      'Anything you send or receive will stay visible here.';

  @override
  String pickerOpenFailed(String error) {
    return 'Could not open the picker: $error';
  }

  @override
  String get imageOpenFailed => 'This image could not be opened.';

  @override
  String get connectedDeviceFallback => 'Connected device';

  @override
  String get defaultAndroidPhoneName => 'Android Phone';

  @override
  String get defaultPhoneName => 'Phone';

  @override
  String notificationConnectedTitle(String name) {
    return 'Connected to $name';
  }

  @override
  String get notificationConnectedBody =>
      'Remote Link is holding the connection open.';

  @override
  String notificationWaitingTitle(String name) {
    return 'Waiting for $name';
  }

  @override
  String notificationWaitingBody(String name) {
    return 'Allow the connection on $name to carry on.';
  }

  @override
  String get notificationReconnectingBody =>
      'Remote Link lost the connection and is trying again.';

  @override
  String get notificationStop => 'Stop';

  @override
  String get shareRefused => 'The computer would not take it.';

  @override
  String get shareUnexpectedFailure => 'The share could not be sent.';

  @override
  String get exportCancelled => 'Not saved — you closed the share sheet.';

  @override
  String get exportPermissionDenied =>
      'Remote Link cannot add to your photo library. Allow it under Settings › Remote Link › Photos, then send it again.';

  @override
  String get exportFailed => 'Could not save this file to your phone.';

  @override
  String get startingService => 'Starting the service…';

  @override
  String get keyBackspace => 'Backspace';

  @override
  String get keySwitchToThePhoneKeyboard => 'Switch to the phone keyboard';

  @override
  String get keyLeftArrow => 'Left arrow';

  @override
  String get keyUpArrow => 'Up arrow';

  @override
  String get keyDownArrow => 'Down arrow';

  @override
  String get keyRightArrow => 'Right arrow';

  @override
  String get keyCommand => 'Command';

  @override
  String get keyOption => 'Option';

  @override
  String get keyControl => 'Control';

  @override
  String get keySpace => 'Space';

  @override
  String get keyEscape => 'Escape';

  @override
  String get keyDelete => 'Delete';

  @override
  String get keyTab => 'Tab';

  @override
  String get keyCapsLock => 'Caps lock';

  @override
  String get keyReturn => 'Return';

  @override
  String get keyShift => 'Shift';

  @override
  String get keyAlt => 'Alt';

  @override
  String get keyAltGr => 'Alt Gr';

  @override
  String get keyWindows => 'Windows';

  @override
  String get keyMeta => 'Meta';

  @override
  String get keyBacktick => 'Backtick';

  @override
  String get keyMinus => 'Minus';

  @override
  String get keyEquals => 'Equals';

  @override
  String get keyLeftBracket => 'Left bracket';

  @override
  String get keyRightBracket => 'Right bracket';

  @override
  String get keyBackslash => 'Backslash';

  @override
  String get keySemicolon => 'Semicolon';

  @override
  String get keyApostrophe => 'Apostrophe';

  @override
  String get keyComma => 'Comma';

  @override
  String get keyFullStop => 'Full stop';

  @override
  String get keySlash => 'Slash';

  @override
  String get keyHome => 'Home';

  @override
  String get keyEnd => 'End';

  @override
  String get keyPageUp => 'Page up';

  @override
  String get keyPageDown => 'Page down';

  @override
  String get keyEnter => 'Enter';

  @override
  String get transfersTitle => 'Transfers';

  @override
  String get shareTextDescription => 'the text you shared';

  @override
  String shareFilesDescription(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: 'one file',
      zero: 'no files',
    );
    return '$_temp0';
  }
}
