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
  String get desktopSubtitle => 'Desktop';

  @override
  String connectedStatusLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices connected',
      one: '1 device connected',
      zero: 'No devices connected',
    );
    return '$_temp0';
  }

  @override
  String get allowNewDevicesToPair => 'Allow new devices to pair';

  @override
  String openProduct(String productName) {
    return 'Open $productName';
  }

  @override
  String quitProduct(String productName) {
    return 'Quit $productName';
  }

  @override
  String startupError(String productName, String error) {
    return 'Failed to start $productName: $error';
  }

  @override
  String get retryButton => 'Retry';

  @override
  String get doneButton => 'Done';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get saveButton => 'Save';

  @override
  String get copyButton => 'Copy';

  @override
  String get copied => 'Copied.';

  @override
  String get clearAll => 'Clear all';

  @override
  String get clear => 'Clear';

  @override
  String get navOverview => 'Overview';

  @override
  String get navDevices => 'Devices';

  @override
  String get navSend => 'Send';

  @override
  String get navTransfers => 'Transfers';

  @override
  String get navClipboard => 'Clipboard';

  @override
  String get sidebarReady => 'Ready';

  @override
  String get sidebarRunning => 'Running';

  @override
  String get sidebarStopped => 'Stopped';

  @override
  String get tooltipDiagnostics => 'Diagnostics';

  @override
  String get tooltipSettings => 'Settings';

  @override
  String get workspaceTitle => 'Workspace';

  @override
  String get workspaceSubtitle =>
      'Manage connections, permissions, and transfers from one place.';

  @override
  String get overviewTitle => 'Overview';

  @override
  String get statConnected => 'Connected';

  @override
  String statConnectedDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count connected',
      one: '1 connected',
      zero: '0 connected',
    );
    return '$_temp0';
  }

  @override
  String get statTransfers => 'Transfers';

  @override
  String statRecentTransfers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recent',
      one: '1 recent',
      zero: '0 recent',
    );
    return '$_temp0';
  }

  @override
  String get statClipboardSync => 'Clipboard Sync';

  @override
  String get clipboardActive => 'Active';

  @override
  String get clipboardPaused => 'Paused';

  @override
  String get screenSharingActive => 'Sharing screen';

  @override
  String screenSharingDesc(String name) {
    return 'Screen streaming is currently active with $name.';
  }

  @override
  String get bannerInputBlockedTitle => 'Input simulation blocked';

  @override
  String get bannerInputBlockedDesc =>
      'Accessibility permissions are required on macOS to simulate mouse and keyboard input.';

  @override
  String get bannerOpenSystemSettings => 'Open System Settings';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get devicesSubtitle =>
      'Phones and tablets that can reach this computer';

  @override
  String get pairPhoneButton => 'Pair a phone';

  @override
  String get disconnectButton => 'Disconnect';

  @override
  String get noDevicesConnectedTitle => 'No devices connected';

  @override
  String get noDevicesConnectedMessage =>
      'Tap “Pair a phone” to connect your phone or tablet.';

  @override
  String get tierViewOnly => 'View-only';

  @override
  String get tierInteractive => 'Interactive';

  @override
  String get tierElevated => 'Elevated';

  @override
  String get rememberDevice => 'Remember this device';

  @override
  String get deviceAwaitingPairing => 'Awaiting pairing confirmation';

  @override
  String get deviceStreamingScreen => 'Streaming screen';

  @override
  String deviceLatency(String latency) {
    return '$latency ms';
  }

  @override
  String get sendCardTitle => 'Send files to phone';

  @override
  String get sendCardSubtitle => 'Drag and drop files here, or click to browse';

  @override
  String get browseFilesButton => 'Browse files';

  @override
  String get transfersTitle => 'Transfers';

  @override
  String get transfersSubtitle =>
      'Files sent and received with connected devices';

  @override
  String get noTransfersTitle => 'No transfers yet';

  @override
  String get noTransfersMessage =>
      'Files sent to or received from connected devices will appear here.';

  @override
  String get openFolder => 'Open folder';

  @override
  String get clearTransferHistory => 'Clear history';

  @override
  String get transferWaiting => 'Waiting for confirmation';

  @override
  String get transferTransferring => 'Transferring';

  @override
  String get transferCompleted => 'Completed';

  @override
  String get transferDeclined => 'Declined';

  @override
  String get transferCancelled => 'Cancelled';

  @override
  String get transferFailed => 'Failed';

  @override
  String transferFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/s';
  }

  @override
  String transferEta(String eta) {
    return 'ETA: $eta';
  }

  @override
  String missingFilesError(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are no longer available. Choose them again.',
      one: '1 file is no longer available. Choose it again.',
    );
    return '$_temp0';
  }

  @override
  String get clipboardHistoryTitle => 'Clipboard history';

  @override
  String get clipboardHistorySubtitle =>
      'Quickly reuse recent content from this computer';

  @override
  String get clipboardCleared => 'Clipboard history cleared.';

  @override
  String get persistenceEncrypted =>
      'Kept on this computer, encrypted. Content marked confidential by a password manager is never recorded.';

  @override
  String get persistenceMemoryOnly =>
      'Kept in memory only — this list is gone when Remote Link quits. Nothing is written to disk.';

  @override
  String get persistenceEnabledSnackBar =>
      'Clipboard history will be kept, encrypted, on this computer.';

  @override
  String get persistenceDisabledSnackBar =>
      'Stored clipboard history deleted. Keeping it in memory only.';

  @override
  String get nothingCopiedYetTitle => 'Nothing copied yet';

  @override
  String nothingCopiedYetMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The last $count items you copy will appear here.',
      one: 'The last item you copy will appear here.',
    );
    return '$_temp0';
  }

  @override
  String get unpin => 'Unpin';

  @override
  String get pin => 'Pin';

  @override
  String get removeFromHistory => 'Remove from history';

  @override
  String get clipboardUnavailable => 'The clipboard is unavailable.';

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
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h ago',
      one: '1 h ago',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count d ago',
      one: '1 d ago',
    );
    return '$_temp0';
  }

  @override
  String get pairingRequestTitle => 'Device Pairing Request';

  @override
  String pairingRequestMessage(String name) {
    return '“$name” wants to pair with this computer. Verify that the security code matches:';
  }

  @override
  String get incomingConnectionTitle => 'Incoming Connection';

  @override
  String incomingConnectionMessage(String name) {
    return '“$name” is asking to connect. Allow this connection?';
  }

  @override
  String get rememberDeviceTitle => 'Remember Device';

  @override
  String rememberDeviceMessage(String name) {
    return 'Do you want to remember “$name” so it connects automatically in the future?';
  }

  @override
  String get rememberAlways => 'Always allow';

  @override
  String get rememberThisSession => 'This session only';

  @override
  String get rememberDecline => 'Don\'t allow';

  @override
  String get incomingTransferTitle => 'Incoming File Transfer';

  @override
  String incomingTransferMessage(String name, int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files ($size)',
      one: '1 file ($size)',
    );
    return '“$name” wants to send $_temp0:';
  }

  @override
  String get acceptButton => 'Accept';

  @override
  String get declineButton => 'Decline';

  @override
  String get permissionRequestTitle => 'Permission Request';

  @override
  String permissionRequestMessage(String name, String tier) {
    return '“$name” is requesting $tier permission. Allow this tier?';
  }

  @override
  String securityCodeSpoken(String digits) {
    return 'Security code: $digits';
  }

  @override
  String get pairPhoneTitle => 'Pair a phone';

  @override
  String get pairPhoneInstruction =>
      'Open Remote Link on your phone and tap “Scan code”.';

  @override
  String get pairPhoneMultipleAddresses =>
      'This computer has more than one address. If the phone cannot reach it, try another.';

  @override
  String get addressLabel => 'Address';

  @override
  String get copyAddress => 'Copy address';

  @override
  String get settingsTitle => 'Settings';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get startupSectionTitle => 'Startup';

  @override
  String get startAtLoginTitle => 'Start when I log in';

  @override
  String get startAtLoginSubtitleOn =>
      'Starts hidden, so your phone can reach this computer without anyone opening a window first.';

  @override
  String get startAtLoginSubtitleOff =>
      'Your phone will not find this computer until you open Remote Link yourself.';

  @override
  String get connectionsSectionTitle => 'Connections';

  @override
  String get askBeforeConnectingTitle => 'Ask before a paired device connects';

  @override
  String get askBeforeConnectingSubtitleOn =>
      'A device you have paired with waits until you allow it. Asked once per device each time Remote Link starts, so a dropped Wi-Fi connection does not ask again.';

  @override
  String get askBeforeConnectingSubtitleOff =>
      'Any device you have paired with connects straight away, whoever is holding it.';

  @override
  String get windowSectionTitle => 'Closing the window';

  @override
  String get closingWindowKeepsServiceTitle =>
      'Closing this window keeps the service running';

  @override
  String closingWindowKeepsServiceSubtitle(String location) {
    return 'Your paired phones stay connected, and transfers in progress finish. Reopen or quit Remote Link from its icon in $location.';
  }

  @override
  String get menuBarLocationMac => 'the menu bar at the top of the screen';

  @override
  String get notificationAreaLocationOther =>
      'the notification area beside the clock';

  @override
  String get savingSectionTitle => 'Saving received files';

  @override
  String get folderLabel => 'Folder';

  @override
  String get saveFolderChecking => 'Checking…';

  @override
  String get saveFolderError => 'Could not work out where to save files.';

  @override
  String get useDownloadsButton => 'Use Downloads';

  @override
  String get changeFolderButton => 'Change…';

  @override
  String get saveFilesHerePrompt => 'Save files here';

  @override
  String get thisComputerSectionTitle => 'This computer';

  @override
  String get computerNameLabel => 'Name';

  @override
  String computerNameSubtitle(String name) {
    return '$name — this is what your phone shows in its list.';
  }

  @override
  String get renameButton => 'Rename';

  @override
  String get renameComputerDialogTitle => 'Rename this computer';

  @override
  String get supportSectionTitle => 'Support';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsSubtitle =>
      'Connection counters, permissions, and a log you can copy into a bug report.';

  @override
  String get diagnosticsScreenTitle => 'Diagnostics';

  @override
  String get systemHealthTitle => 'System health';

  @override
  String get systemHealthSubtitle =>
      'Network, permissions, connected devices, and live logs.';

  @override
  String get copyAllButton => 'Copy All';

  @override
  String get fullDiagnosticsCopied => 'Full diagnostics copied to clipboard';

  @override
  String get logsCopied => 'Logs copied to clipboard';

  @override
  String copiedLogRecords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Copied $count log records to clipboard',
      one: 'Copied 1 log record to clipboard',
      zero: 'Copied 0 log records to clipboard',
    );
    return '$_temp0';
  }

  @override
  String get serviceNetworkTitle => 'Service & Network';

  @override
  String get statusRunning => 'Running';

  @override
  String get statusStopped => 'Stopped';

  @override
  String get deviceNameLabel => 'Device Name';

  @override
  String get boundPortLabel => 'Bound Port';

  @override
  String boundPortValue(int port) {
    return 'Port $port';
  }

  @override
  String get deviceIdLabel => 'Device ID';

  @override
  String get lanAddressesTitle => 'LAN Addresses for Phone Connection:';

  @override
  String get noLanAddresses => 'No LAN addresses detected';

  @override
  String get discoveryBeaconTitle => 'Discovery Beacon';

  @override
  String get advertisingLabel => 'Advertising';

  @override
  String get activeLabel => 'Active';

  @override
  String get offLabel => 'Off';

  @override
  String get interfacesLabel => 'Advertising Interface(s):';

  @override
  String get noInterfacesDetected => 'No interfaces bound';

  @override
  String get lastErrorLabel => 'Last Discovery Error';

  @override
  String get dispatcherCountersTitle => 'Command Dispatcher';

  @override
  String get appliedLabel => 'Applied';

  @override
  String get deniedLabel => 'Denied';

  @override
  String get unsupportedLabel => 'Unsupported';

  @override
  String get backendsTitle => 'Backend Availability';

  @override
  String get availableLabel => 'Available';

  @override
  String get unavailableLabel => 'Unavailable';

  @override
  String reasonLabel(String reason) {
    return 'Reason: $reason';
  }

  @override
  String connectedDevicesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Connected Devices ($count)',
      one: 'Connected Devices (1)',
      zero: 'Connected Devices (0)',
    );
    return '$_temp0';
  }

  @override
  String get noDevicesConnectedDiagnostics => 'No devices connected';

  @override
  String get systemLogsTitle => 'System Logs';

  @override
  String get allLevelsLabel => 'All Levels';

  @override
  String get copyLogsButton => 'Copy Logs';

  @override
  String failedToLoadDiagnostics(String error) {
    return 'Failed to load diagnostics: $error';
  }

  @override
  String showingLogsCount(int filtered, int total) {
    return 'Showing $filtered of $total';
  }

  @override
  String get noLogsRecorded => 'No logs recorded yet';

  @override
  String get serviceOnline => 'Service online';

  @override
  String get serviceOffline => 'Service offline';

  @override
  String get navActivity => 'Activity';

  @override
  String alreadyRunningTitle(String productName) {
    return '$productName is already running';
  }

  @override
  String alreadyRunningSubtitle(String where) {
    return 'Your phone can already reach this computer. Open the copy that is running from its icon in $where — you don\'t need this second one.';
  }

  @override
  String get closeThisWindow => 'Close this window';

  @override
  String couldNotStartTitle(String productName) {
    return '$productName could not start';
  }

  @override
  String screenWatchingBanner(int count, String name, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count devices are watching this screen: $names',
      one: '$name is watching this screen',
    );
    return '$_temp0';
  }

  @override
  String get stopSharing => 'Stop sharing';

  @override
  String get screenRecordingPermissionReason =>
      'Remote Link needs Screen Recording permission before it can share this screen.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get statusDiscoverable => 'Discoverable on this network';

  @override
  String get statusNotRunning => 'Not running';

  @override
  String devicePortInfo(String name, int port) {
    return '$name · port $port';
  }

  @override
  String get readyToShareScreenPrompt =>
      'Ready to share this screen — start it from the phone, using the monitor button at the top of its remote screen.';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get sendToDeviceTitle => 'Send to device';

  @override
  String get sendToDeviceSubtitle =>
      'Share files, links, or notes with a connected phone';

  @override
  String get connectDeviceToSendPrompt =>
      'Connect a device to send files or text.';

  @override
  String get sendToLabel => 'Send to';

  @override
  String get transfersNotPermitted => ' · transfers not permitted';

  @override
  String get tabFileDragDrop => 'File / Drag & Drop';

  @override
  String get tabTextUrl => 'Text / URL';

  @override
  String get dragAndDropPrompt => 'Drag and drop files here to send';

  @override
  String get chooseFilesButton => 'Choose files';

  @override
  String get addMoreFilesButton => 'Add more files';

  @override
  String removeFileTooltip(String fileName) {
    return 'Remove $fileName';
  }

  @override
  String get textSnippetLabel => 'Text or URL snippet';

  @override
  String get textSnippetHint => 'Enter text to send directly to the phone…';

  @override
  String get fileNameOptionalLabel => 'File name (optional)';

  @override
  String get fileNameOptionalHint => 'snippet.txt';

  @override
  String get sendFileButton => 'Send File';

  @override
  String get sendTextButton => 'Send Text';

  @override
  String foldersNotSupportedError(String folders) {
    return 'Folders cannot be sent yet: $folders';
  }

  @override
  String openFileDialogError(String error) {
    return 'Could not open the file dialog: $error';
  }

  @override
  String get selectTargetDeviceError => 'Please select a target device';

  @override
  String get chooseAtLeastOneFileError => 'Choose at least one file to send';

  @override
  String filesNoLongerThere(int count, String fileName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files are no longer there.',
      one: '$fileName is no longer there.',
    );
    return '$_temp0';
  }

  @override
  String get enterTextToSendError => 'Please enter text to send';

  @override
  String sendFailedError(String error) {
    return 'Send failed: $error';
  }

  @override
  String get transfersActiveSubtitle =>
      'Completed and active transfers appear here';

  @override
  String transfersRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recent transfers',
      one: '1 recent transfer',
    );
    return '$_temp0';
  }

  @override
  String get noActiveOrRecentTransfers => 'No active or recent transfers.';

  @override
  String transferFromPeer(String name) {
    return 'From $name';
  }

  @override
  String transferToPeer(String name) {
    return 'To $name';
  }

  @override
  String get transferStatusWaitingForYou => 'Waiting for you';

  @override
  String get transferStatusAwaitingResponse => 'Awaiting response';

  @override
  String get transferStatusOffered => 'Offered';

  @override
  String get removeButton => 'Remove';

  @override
  String get fileMovedOrDeleted => 'File was moved or deleted';

  @override
  String showInFinder(String fileName) {
    return 'Show $fileName in Finder';
  }

  @override
  String showInFolder(String fileName) {
    return 'Show $fileName in folder';
  }

  @override
  String openFileTooltip(String fileName) {
    return 'Open $fileName';
  }

  @override
  String incomingTransferFromPeer(String name) {
    return 'Incoming transfer from $name';
  }

  @override
  String incomingTransferFilesCount(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$name wants to send $count files:',
      one: '$name wants to send 1 file:',
    );
    return '$_temp0';
  }

  @override
  String get totalSizeLabel => 'Total size:';

  @override
  String firstTransferNote(String path) {
    return 'First transfer from this device.\nFiles will be saved in: $path';
  }

  @override
  String get permissionElevationRequestTitle => 'Permission elevation request';

  @override
  String get peerIsRequesting => ' is requesting ';

  @override
  String get accessToThisComputer => ' access to this computer.';

  @override
  String get tierTitleViewOnly => 'View Only';

  @override
  String get tierTitleControl => 'Control';

  @override
  String get tierTitleControlAndApps => 'Control + Launch Apps';

  @override
  String get tierTitleAdmin => 'Administrator (Full Access)';

  @override
  String get tierExplViewOnly =>
      'Allows viewing system status, media state, and the display layout — but not the contents of the screen.';

  @override
  String get tierExplControl =>
      'Allows sending keyboard and mouse input, synchronizing clipboard, controlling media, viewing this screen, and transferring files — every transfer is still confirmed here before it starts.';

  @override
  String get tierExplExtended =>
      'Allows launching applications and running pre-registered commands without a further prompt.';

  @override
  String get tierExplAdmin =>
      'Allows controlling power (shutdown, restart, sleep, lock) and managing paired devices.';

  @override
  String get whatThisAllows => 'What this allows:';

  @override
  String get messageFromDevice => 'Message from device:';

  @override
  String get adminWarningMessage =>
      'Admin access allows restarting or shutting down your machine and discarding unsaved work.';

  @override
  String automaticallyDeniedInSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Automatically denied in $count seconds',
      one: 'Automatically denied in 1 second',
    );
    return '$_temp0';
  }

  @override
  String get temporary30Minutes => 'Temporary · 30 minutes';

  @override
  String get permanent => 'Permanent';

  @override
  String get denyButton => 'Deny';

  @override
  String get approveButton => 'Approve';

  @override
  String get waitingForPairingApproval => 'Waiting for pairing approval';

  @override
  String deviceConnectionStats(String address, String latency, int bars) {
    return '$address · $latency ms · $bars/4';
  }

  @override
  String get clipboardSyncEnabledTooltip => 'Clipboard sync enabled';

  @override
  String get clipboardSyncDisabledTooltip => 'Clipboard sync disabled';

  @override
  String get clipboardSyncNotPermittedTooltip =>
      'Clipboard sync not permitted at current tier';

  @override
  String get renameDeviceTooltip => 'Rename this device';

  @override
  String get rememberedDeviceTooltip =>
      'Remembered — connects without being asked. Click to start asking again.';

  @override
  String get notRememberedDeviceTooltip =>
      'Not remembered. Click to let it connect without asking.';

  @override
  String get forgetDeviceTooltip => 'Forget this device';

  @override
  String get tierLabelViewOnly => 'View only';

  @override
  String get tierLabelControl => 'Control';

  @override
  String get tierLabelControlAndApps => 'Control + apps';

  @override
  String get tierLabelFullAccess => 'Full access';

  @override
  String get renameDeviceDialogTitle => 'Rename device';

  @override
  String get invalidDeviceNameError =>
      'Invalid name: 1–64 characters, no control codes or line breaks.';

  @override
  String get pairingDialogTitle => 'Pair this device?';

  @override
  String pairingDialogMessage(String name) {
    return '$name wants to control this computer.';
  }

  @override
  String get pairingDialogInstructions =>
      'Approve only if your phone is showing exactly these six digits, or if you just scanned the code on this screen with it. Different numbers mean something is intercepting the connection.';

  @override
  String get theNumbersMatchButton => 'The numbers match';

  @override
  String get connectionRequestDialogTitle => 'Allow this device to connect?';

  @override
  String connectionRequestPeerMessage(String name) {
    return '$name is asking to connect to this computer.';
  }

  @override
  String get connectionRequestExplanation =>
      'You paired with it before, so its identity has already been checked. This is only about now: allow it if the device is in your hands, and turn it away if it is not.';

  @override
  String get connectionRequestSessionNote =>
      'Remote Link will not ask about this device again until you quit the app.';

  @override
  String get dontAllowButton => 'Don\'t allow';

  @override
  String get allowButton => 'Allow';

  @override
  String get rememberDeviceDialogTitle => 'Remember this device?';

  @override
  String rememberDeviceIntro(String name) {
    return '$name is connected. Remote Link can let it straight in next time, with nothing to scan and nobody to ask.';
  }

  @override
  String rememberDeviceExplanation(String name) {
    return '$name is being asked the same thing. Both devices have to agree, and either one can change its mind later in Devices.';
  }

  @override
  String get keepAskingButton => 'Keep asking';

  @override
  String get rememberButton => 'Remember';

  @override
  String rememberDeviceAgreedSnackBar(String name) {
    return '$name will be remembered once it agrees too.';
  }

  @override
  String couldNotRetryError(String error) {
    return 'Could not retry: $error';
  }

  @override
  String get invalidDeviceNameSnackBar =>
      'Invalid device name. Names must be 1–64 characters with no control characters.';

  @override
  String get waitingForDevicesMessage => 'Waiting for devices to connect…';

  @override
  String errorMessage(String error) {
    return 'Error: $error';
  }

  @override
  String get noDevicesConnectedPrompt =>
      'No devices connected. Open Remote Link on your phone — it should find this computer automatically, or you can show it a code to scan.';

  @override
  String get showPairingCodeButton => 'Show pairing code';

  @override
  String get connectedDevicesSectionTitle => 'Connected devices';

  @override
  String connectedDevicesCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count connected',
      one: '1 connected',
      zero: 'Phones connected to this computer appear here',
    );
    return '$_temp0';
  }

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
  String get startingService => 'Starting the service…';

  @override
  String get filterLevel => 'Filter Level:';

  @override
  String get phoneControlCapabilityMissing =>
      'Controlling a phone from this computer is not available. iPhones offer no way to allow it at all, Android needs a service this build does not include, and there is no viewer here yet.';

  @override
  String get phoneControlReadOnly =>
      'Raise this device above read-only to control it.';

  @override
  String get backendInputName => 'Input injection';

  @override
  String get backendClipboardName => 'Clipboard sync';

  @override
  String get backendMediaName => 'Media control';

  @override
  String backendClipboardUnsupported(String platform) {
    return 'Clipboard sync is not supported on $platform';
  }

  @override
  String get backendClipboardUnavailable => 'Clipboard backend unavailable';

  @override
  String backendMediaUnsupported(String platform) {
    return 'Media control is not supported on $platform';
  }

  @override
  String get backendMediaUnavailable => 'Media backend unavailable';

  @override
  String get inputAccessibilityPermission =>
      'Remote Link needs Accessibility permission. Enable it in System Settings › Privacy & Security › Accessibility, then quit and reopen Remote Link.';

  @override
  String backendInputUnsupported(String platform) {
    return 'Input control is not supported on $platform.';
  }

  @override
  String get backendInputLibrariesUnavailable =>
      'Input control could not start on this computer.';

  @override
  String get backendUnavailableGeneric =>
      'This control is unavailable right now.';

  @override
  String get thisPlatform => 'this platform';
}
