// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'Remote Link';

  @override
  String get desktopSubtitle => 'سطح المكتب';

  @override
  String connectedStatusLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جهاز متصل',
      many: '$count جهازًا متصلًا',
      few: '$count أجهزة متصلة',
      two: 'جهازان متصلان',
      one: 'جهاز واحد متصل',
      zero: 'لا توجد أجهزة متصلة',
    );
    return '$_temp0';
  }

  @override
  String get allowNewDevicesToPair => 'السماح بإقران أجهزة جديدة';

  @override
  String openProduct(String productName) {
    return 'فتح $productName';
  }

  @override
  String quitProduct(String productName) {
    return 'إنهاء $productName';
  }

  @override
  String startupError(String productName, String error) {
    return 'فشل بدء $productName: $error';
  }

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get doneButton => 'تم';

  @override
  String get cancelButton => 'إلغاء';

  @override
  String get saveButton => 'حفظ';

  @override
  String get copyButton => 'نسخ';

  @override
  String get copied => 'تم النسخ.';

  @override
  String get clearAll => 'مسح الكل';

  @override
  String get clear => 'مسح';

  @override
  String get navOverview => 'نظرة عامة';

  @override
  String get navDevices => 'الأجهزة';

  @override
  String get navSend => 'إرسال';

  @override
  String get navTransfers => 'التحويلات';

  @override
  String get navClipboard => 'الحافظة';

  @override
  String get sidebarReady => 'جاهز';

  @override
  String get sidebarRunning => 'قيد التشغيل';

  @override
  String get sidebarStopped => 'متوقف';

  @override
  String get tooltipDiagnostics => 'التشخيصات';

  @override
  String get tooltipSettings => 'الإعدادات';

  @override
  String get workspaceTitle => 'مساحة العمل';

  @override
  String get workspaceSubtitle =>
      'إدارة الاتصالات والأذونات ونقل الملفات من مكان واحد.';

  @override
  String get overviewTitle => 'نظرة عامة';

  @override
  String get statConnected => 'متصل';

  @override
  String statConnectedDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count متصل',
      many: '$count متصلًا',
      few: '$count متصلة',
      two: '2 متصلان',
      one: '1 متصل',
      zero: '0 متصل',
    );
    return '$_temp0';
  }

  @override
  String get statTransfers => 'التحويلات';

  @override
  String statRecentTransfers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count حديث',
      many: '$count حديثًا',
      few: '$count حديثة',
      two: '2 حديثان',
      one: '1 حديث',
      zero: '0 حديثة',
    );
    return '$_temp0';
  }

  @override
  String get statClipboardSync => 'مزامنة الحافظة';

  @override
  String get clipboardActive => 'نشطة';

  @override
  String get clipboardPaused => 'متوقفة مؤقتًا';

  @override
  String get screenSharingActive => 'مشاركة الشاشة';

  @override
  String screenSharingDesc(String name) {
    return 'بث الشاشة نشط حاليًا مع $name.';
  }

  @override
  String get bannerInputBlockedTitle => 'محاكاة الإدخال محظورة';

  @override
  String get bannerInputBlockedDesc =>
      'أذونات تسهيلات الاستخدام مطلوبة على macOS لمحاكاة إدخال الماوس ولوحة المفاتيح.';

  @override
  String get bannerOpenSystemSettings => 'فتح إعدادات النظام';

  @override
  String get devicesTitle => 'الأجهزة';

  @override
  String get devicesSubtitle =>
      'الهواتف والأجهزة اللوحية التي يمكنها الوصول إلى هذا الكمبيوتر';

  @override
  String get pairPhoneButton => 'إقران هاتف';

  @override
  String get disconnectButton => 'قطع الاتصال';

  @override
  String get noDevicesConnectedTitle => 'لا توجد أجهزة متصلة';

  @override
  String get noDevicesConnectedMessage =>
      'اضغط على «إقران هاتف» لتوصيل هاتفك أو جهازك اللوحي.';

  @override
  String get tierViewOnly => 'عرض فقط';

  @override
  String get tierInteractive => 'تفاعلي';

  @override
  String get tierElevated => 'مرتفع الصلاحيات';

  @override
  String get rememberDevice => 'تذكر هذا الجهاز';

  @override
  String get deviceAwaitingPairing => 'في انتظار تأكيد الإقران';

  @override
  String get deviceStreamingScreen => 'بث الشاشة';

  @override
  String deviceLatency(String latency) {
    return '$latency ملّي ثانية';
  }

  @override
  String get sendCardTitle => 'إرسال ملفات إلى الهاتف';

  @override
  String get sendCardSubtitle => 'اسحب الملفات وأفلتها هنا، أو انقر للاستعراض';

  @override
  String get browseFilesButton => 'استعراض الملفات';

  @override
  String get transfersTitle => 'التحويلات';

  @override
  String get transfersSubtitle =>
      'الملفات المرسلة والمستلمة مع الأجهزة المتصلة';

  @override
  String get noTransfersTitle => 'لا توجد تحويلات بعد';

  @override
  String get noTransfersMessage =>
      'ستظهر هنا الملفات المرسلة إلى الأجهزة المتصلة أو المستلمة منها.';

  @override
  String get openFolder => 'فتح المجلد';

  @override
  String get clearTransferHistory => 'مسح السجل';

  @override
  String get transferWaiting => 'في انتظار التأكيد';

  @override
  String get transferTransferring => 'جارٍ النقل';

  @override
  String get transferCompleted => 'اكتمل';

  @override
  String get transferDeclined => 'مرفوض';

  @override
  String get transferCancelled => 'ملغى';

  @override
  String get transferFailed => 'فشل';

  @override
  String transferFilesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف',
      many: '$count ملفًا',
      few: '$count ملفات',
      two: 'ملفان',
      one: 'ملف واحد',
      zero: 'ولا ملف',
    );
    return '$_temp0';
  }

  @override
  String transferSpeed(String speed) {
    return '$speed/ثانية';
  }

  @override
  String transferEta(String eta) {
    return 'الوقت المتبقي: $eta';
  }

  @override
  String missingFilesError(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف لم تعد متوفرة. يرجى اختيارها مرة أخرى.',
      many: '$count ملفًا لم تعد متوفرة. يرجى اختيارها مرة أخرى.',
      few: '$count ملفات لم تعد متوفرة. يرجى اختيارها مرة أخرى.',
      two: 'الملفان لم يعودا متوفرين. يرجى اختيارهما مرة أخرى.',
      one: 'الملف لم يعد متوفرًا. يرجى اختياره مرة أخرى.',
      zero: 'لم تعد الملفات متوفرة.',
    );
    return '$_temp0';
  }

  @override
  String get clipboardHistoryTitle => 'سجل الحافظة';

  @override
  String get clipboardHistorySubtitle =>
      'إعادة استخدام المحتوى الأخير بسرعة من هذا الكمبيوتر';

  @override
  String get clipboardCleared => 'تم مسح سجل الحافظة.';

  @override
  String get persistenceEncrypted =>
      'محفوظة على هذا الكمبيوتر ومشفرة. لا يتم أبدًا تسجيل المحتوى المصنف سريًا بواسطة مدير كلمات المرور.';

  @override
  String get persistenceMemoryOnly =>
      'محفوظة في الذاكرة فقط — ستختفي هذه القائمة عند إنهاء Remote Link. لا يُكتب أي شيء على القرص.';

  @override
  String get persistenceEnabledSnackBar =>
      'سيتم الاحتفاظ بسجل الحافظة مشفرًا على هذا الكمبيوتر.';

  @override
  String get persistenceDisabledSnackBar =>
      'تم حذف سجل الحافظة المحفوظ. يتم الاحتفاظ به في الذاكرة فقط.';

  @override
  String get nothingCopiedYetTitle => 'لم يتم نسخ أي شيء بعد';

  @override
  String nothingCopiedYetMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ستظهر هنا آخر $count عنصر تنسخها.',
      many: 'ستظهر هنا آخر $count عنصرًا تنسخها.',
      few: 'ستظهر هنا آخر $count عناصر تنسخها.',
      two: 'سيظهر هنا آخر عنصرين تنسخهما.',
      one: 'سيظهر هنا آخر عنصر تنسخه.',
      zero: 'ستظهر العناصر المنسوخة هنا.',
    );
    return '$_temp0';
  }

  @override
  String get unpin => 'إلغاء التثبيت';

  @override
  String get pin => 'تثبيت';

  @override
  String get removeFromHistory => 'إزالة من السجل';

  @override
  String get clipboardUnavailable => 'الحافظة غير متوفرة.';

  @override
  String pinLimitReached(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يمكنك تثبيت ما يصل إلى $count عنصر. ألغِ تثبيت عنصر أولاً.',
      many: 'يمكنك تثبيت ما يصل إلى $count عنصرًا. ألغِ تثبيت عنصر أولاً.',
      few: 'يمكنك تثبيت ما يصل إلى $count عناصر. ألغِ تثبيت عنصر أولاً.',
      two: 'يمكنك تثبيت عنصرين كحد أقصى. ألغِ تثبيت عنصر أولاً.',
      one: 'يمكنك تثبيت عنصر واحد فقط. ألغِ تثبيت عنصر أولاً.',
      zero: 'لا يمكنك تثبيت المزيد.',
    );
    return '$_temp0';
  }

  @override
  String get timeJustNow => 'الآن';

  @override
  String timeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'منذ $count دقيقة',
      many: 'منذ $count دقيقة',
      few: 'منذ $count دقائق',
      two: 'منذ دقيقتين',
      one: 'منذ دقيقة واحدة',
      zero: 'الآن',
    );
    return '$_temp0';
  }

  @override
  String timeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'منذ $count ساعة',
      many: 'منذ $count ساعة',
      few: 'منذ $count ساعات',
      two: 'منذ ساعتين',
      one: 'منذ ساعة واحدة',
      zero: 'الآن',
    );
    return '$_temp0';
  }

  @override
  String timeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'منذ $count يوم',
      many: 'منذ $count يومًا',
      few: 'منذ $count أيام',
      two: 'منذ يومين',
      one: 'منذ يوم واحد',
      zero: 'اليوم',
    );
    return '$_temp0';
  }

  @override
  String get pairingRequestTitle => 'طلب إقران جهاز';

  @override
  String pairingRequestMessage(String name) {
    return 'يريد «$name» الإقران بهذا الكمبيوتر. يرجى التحقق من تطابق رمز الأمان:';
  }

  @override
  String get incomingConnectionTitle => 'اتصال وارد';

  @override
  String incomingConnectionMessage(String name) {
    return 'يطلب «$name» الاتصال. هل تسمح بهذا الاتصال؟';
  }

  @override
  String get rememberDeviceTitle => 'تذكر الجهاز';

  @override
  String rememberDeviceMessage(String name) {
    return 'هل تريد تذكر «$name» حتى يتصل تلقائيًا في المستقبل؟';
  }

  @override
  String get rememberAlways => 'السماح دائمًا';

  @override
  String get rememberThisSession => 'لهذه الجلسة فقط';

  @override
  String get rememberDecline => 'عدم السماح';

  @override
  String get incomingTransferTitle => 'تحويل ملف وارد';

  @override
  String incomingTransferMessage(String name, int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف ($size)',
      many: '$count ملفًا ($size)',
      few: '$count ملفات ($size)',
      two: 'ملفين ($size)',
      one: 'ملف واحد ($size)',
      zero: 'ملفات ($size)',
    );
    return 'يريد «$name» إرسال $_temp0:';
  }

  @override
  String get acceptButton => 'قبول';

  @override
  String get declineButton => 'رفض';

  @override
  String get permissionRequestTitle => 'طلب إذن';

  @override
  String permissionRequestMessage(String name, String tier) {
    return 'يطلب «$name» إذن مستوى $tier. هل تسمح بهذا المستوى؟';
  }

  @override
  String securityCodeSpoken(String digits) {
    return 'رمز الأمان: $digits';
  }

  @override
  String get pairPhoneTitle => 'إقران هاتف';

  @override
  String get pairPhoneInstruction =>
      'افتح Remote Link على هاتفك واضغط على «مسح الرمز».';

  @override
  String get pairPhoneMultipleAddresses =>
      'يحتوي هذا الكمبيوتر على أكثر من عنوان. إذا تعذر على الهاتف الوصول إليه، فجرّب عنوانًا آخر.';

  @override
  String get addressLabel => 'العنوان';

  @override
  String get copyAddress => 'نسخ العنوان';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String versionLabel(String version) {
    return 'الإصدار $version';
  }

  @override
  String get startupSectionTitle => 'بدء التشغيل';

  @override
  String get startAtLoginTitle => 'البدء عند تسجيل الدخول';

  @override
  String get startAtLoginSubtitleOn =>
      'يبدأ التطبيق مخفيًا، حتى يتمكن هاتفك من الوصول إلى هذا الكمبيوتر دون الحاجة لفتح نافذة أولاً.';

  @override
  String get startAtLoginSubtitleOff =>
      'لن يجد هاتفك هذا الكمبيوتر حتى تفتح Remote Link بنفسك.';

  @override
  String get connectionsSectionTitle => 'الاتصالات';

  @override
  String get askBeforeConnectingTitle => 'السؤال قبل اتصال جهاز مقترن';

  @override
  String get askBeforeConnectingSubtitleOn =>
      'ينتظر الجهاز المقترن حتى تسمح له بالاتصال. يُسأل مرة واحدة لكل جهاز عند تشغيل Remote Link، حتى لا يكرر السؤال عند انقطاع Wi-Fi.';

  @override
  String get askBeforeConnectingSubtitleOff =>
      'يتصل أي جهاز مقترن على الفور دون طلب إذن.';

  @override
  String get windowSectionTitle => 'إغلاق النافذة';

  @override
  String get closingWindowKeepsServiceTitle =>
      'إغلاق هذه النافذة يُبقي الخدمة قيد التشغيل';

  @override
  String closingWindowKeepsServiceSubtitle(String location) {
    return 'تظل هواتفك المقترنة متصلة، وتكتمل عمليات النقل الجارية. يمكنك إعادة فتح Remote Link أو إنهاؤه من أيقونته في $location.';
  }

  @override
  String get menuBarLocationMac => 'شريط القوائم في أعلى الشاشة';

  @override
  String get notificationAreaLocationOther => 'منطقة الإشعارات بجانب الساعة';

  @override
  String get savingSectionTitle => 'حفظ الملفات المستلمة';

  @override
  String get folderLabel => 'المجلد';

  @override
  String get saveFolderChecking => 'جارٍ التحقق…';

  @override
  String get saveFolderError => 'تعذر تحديد مكان حفظ الملفات.';

  @override
  String get useDownloadsButton => 'استخدام التنزيلات';

  @override
  String get changeFolderButton => 'تغيير…';

  @override
  String get saveFilesHerePrompt => 'حفظ الملفات هنا';

  @override
  String get thisComputerSectionTitle => 'هذا الكمبيوتر';

  @override
  String get computerNameLabel => 'الاسم';

  @override
  String computerNameSubtitle(String name) {
    return '$name — هذا هو الاسم الذي يظهر في قائمة هاتفك.';
  }

  @override
  String get renameButton => 'إعادة التسمية';

  @override
  String get renameComputerDialogTitle => 'إعادة تسمية هذا الكمبيوتر';

  @override
  String get supportSectionTitle => 'الدعم';

  @override
  String get diagnosticsTitle => 'التشخيصات';

  @override
  String get diagnosticsSubtitle =>
      'عدادات الاتصال، والأذونات، وسجل يمكنك نسخه في تقرير خطأ.';

  @override
  String get diagnosticsScreenTitle => 'التشخيصات';

  @override
  String get systemHealthTitle => 'صحة النظام';

  @override
  String get systemHealthSubtitle =>
      'الشبكة، والأذونات، والأجهزة المتصلة، والسجلات الحية.';

  @override
  String get copyAllButton => 'نسخ الكل';

  @override
  String get fullDiagnosticsCopied => 'تم نسخ كامل التشخيصات إلى الحافظة';

  @override
  String get logsCopied => 'تم نسخ السجلات إلى الحافظة';

  @override
  String copiedLogRecords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم نسخ $count سجل إلى الحافظة',
      many: 'تم نسخ $count سجلًا إلى الحافظة',
      few: 'تم نسخ $count سجلات إلى الحافظة',
      two: 'تم نسخ سجلين إلى الحافظة',
      one: 'تم نسخ سجل واحد إلى الحافظة',
      zero: 'تم نسخ 0 سجل إلى الحافظة',
    );
    return '$_temp0';
  }

  @override
  String get serviceNetworkTitle => 'الخدمة والشبكة';

  @override
  String get statusRunning => 'قيد التشغيل';

  @override
  String get statusStopped => 'متوقف';

  @override
  String get deviceNameLabel => 'اسم الجهاز';

  @override
  String get boundPortLabel => 'المنفذ المرتبط';

  @override
  String boundPortValue(int port) {
    return 'المنفذ $port';
  }

  @override
  String get deviceIdLabel => 'معرّف الجهاز';

  @override
  String get lanAddressesTitle => 'عناوين LAN لاتصال الهاتف:';

  @override
  String get noLanAddresses => 'لم يتم اكتشاف عناوين LAN';

  @override
  String get discoveryBeaconTitle => 'منارة الاكتشاف';

  @override
  String get advertisingLabel => 'الإعلان';

  @override
  String get activeLabel => 'نشط';

  @override
  String get offLabel => 'متوقف';

  @override
  String get interfacesLabel => 'واجهة (واجهات) الإعلان:';

  @override
  String get noInterfacesDetected => 'لا توجد واجهات مقترنة';

  @override
  String get lastErrorLabel => 'آخر خطأ استكشاف';

  @override
  String get dispatcherCountersTitle => 'موجّه الأوامر';

  @override
  String get appliedLabel => 'تم التطبيق';

  @override
  String get deniedLabel => 'مرفوض';

  @override
  String get unsupportedLabel => 'غير مدعوم';

  @override
  String get backendsTitle => 'توفر الواجهات الخلفية';

  @override
  String get availableLabel => 'متوفر';

  @override
  String get unavailableLabel => 'غير متوفر';

  @override
  String reasonLabel(String reason) {
    return 'السبب: $reason';
  }

  @override
  String connectedDevicesTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'الأجهزة المتصلة ($count)',
      many: 'الأجهزة المتصلة ($count)',
      few: 'الأجهزة المتصلة ($count)',
      two: 'الأجهزة المتصلة (2)',
      one: 'الأجهزة المتصلة (1)',
      zero: 'الأجهزة المتصلة (0)',
    );
    return '$_temp0';
  }

  @override
  String get noDevicesConnectedDiagnostics => 'لا توجد أجهزة متصلة';

  @override
  String get systemLogsTitle => 'سجلات النظام';

  @override
  String get allLevelsLabel => 'جميع المستويات';

  @override
  String get copyLogsButton => 'نسخ السجلات';

  @override
  String failedToLoadDiagnostics(String error) {
    return 'فشل تحميل التشخيصات: $error';
  }

  @override
  String showingLogsCount(int filtered, int total) {
    return 'عرض $filtered من $total';
  }

  @override
  String get noLogsRecorded => 'لم يتم تسجيل أي سجلات بعد';

  @override
  String get serviceOnline => 'الخدمة متصلة';

  @override
  String get serviceOffline => 'الخدمة غير متصلة';

  @override
  String get navActivity => 'النشاط';

  @override
  String alreadyRunningTitle(String productName) {
    return '$productName قيد التشغيل بالفعل';
  }

  @override
  String alreadyRunningSubtitle(String where) {
    return 'يمكن لهاتفك الوصول إلى هذا الكمبيوتر بالفعل. افتح النسخة التي تعمل من أيقونتها في $where — لا تحتاج إلى فتح نسخة ثانية.';
  }

  @override
  String get closeThisWindow => 'إغلاق هذه النافذة';

  @override
  String couldNotStartTitle(String productName) {
    return 'تعذر بدء $productName';
  }

  @override
  String screenWatchingBanner(int count, String name, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جهاز يشاهد هذه الشاشة: $names',
      many: '$count جهازًا يشاهد هذه الشاشة: $names',
      few: '$count أجهزة تشاهد هذه الشاشة: $names',
      two: 'جهازان يشاهدان هذه الشاشة: $names',
      one: '$name يشاهد هذه الشاشة',
      zero: 'لا توجد أجهزة تشاهد هذه الشاشة',
    );
    return '$_temp0';
  }

  @override
  String get stopSharing => 'إيقاف المشاركة';

  @override
  String get screenRecordingPermissionReason =>
      'يحتاج Remote Link إلى إذن تسجيل الشاشة قبل أن يتمكن من مشاركة هذه الشاشة.';

  @override
  String get openSettings => 'فتح الإعدادات';

  @override
  String get statusDiscoverable => 'قابل للاكتشاف على هذه الشبكة';

  @override
  String get statusNotRunning => 'غير قيد التشغيل';

  @override
  String devicePortInfo(String name, int port) {
    return '$name · المنفذ $port';
  }

  @override
  String get readyToShareScreenPrompt =>
      'جاهز لمشاركة هذه الشاشة — ابدأ ذلك من الهاتف باستخدام زر الشاشة في أعلى شاشته عن بعد.';

  @override
  String get statusOnline => 'متصل';

  @override
  String get statusOffline => 'غير متصل';

  @override
  String get sendToDeviceTitle => 'إرسال إلى الجهاز';

  @override
  String get sendToDeviceSubtitle =>
      'مشاركة الملفات أو الروابط أو الملاحظات مع هاتف متصل';

  @override
  String get connectDeviceToSendPrompt =>
      'قم بتوصيل جهاز لإرسال الملفات أو النصوص.';

  @override
  String get sendToLabel => 'إرسال إلى';

  @override
  String get transfersNotPermitted => ' · عمليات النقل غير مسموح بها';

  @override
  String get tabFileDragDrop => 'ملف / سحب وإفلات';

  @override
  String get tabTextUrl => 'نص / رابط';

  @override
  String get dragAndDropPrompt => 'اسحب الملفات وأفلتها هنا للإرسال';

  @override
  String get chooseFilesButton => 'اختيار ملفات';

  @override
  String get addMoreFilesButton => 'إضافة المزيد من الملفات';

  @override
  String removeFileTooltip(String fileName) {
    return 'إزالة $fileName';
  }

  @override
  String get textSnippetLabel => 'مقتطف نص أو رابط';

  @override
  String get textSnippetHint => 'أدخل نصًا لإرساله مباشرة إلى الهاتف…';

  @override
  String get fileNameOptionalLabel => 'اسم الملف (اختياري)';

  @override
  String get fileNameOptionalHint => 'snippet.txt';

  @override
  String get sendFileButton => 'إرسال ملف';

  @override
  String get sendTextButton => 'إرسال نص';

  @override
  String foldersNotSupportedError(String folders) {
    return 'لا يمكن إرسال المجلدات بعد: $folders';
  }

  @override
  String openFileDialogError(String error) {
    return 'تعذر فتح نافذة اختيار الملفات: $error';
  }

  @override
  String get selectTargetDeviceError => 'يرجى تحديد جهاز مستهدف';

  @override
  String get chooseAtLeastOneFileError => 'اختر ملفًا واحدًا على الأقل للإرسال';

  @override
  String filesNoLongerThere(int count, String fileName) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف لم تعد موجودة هناك.',
      many: '$count ملفًا لم تعد موجودة هناك.',
      few: '$count ملفات لم تعد موجودة هناك.',
      two: 'الملفان لم يعودا موجودين هناك.',
      one: '$fileName لم يعد موجودًا هناك.',
      zero: 'الملفات لم تعد موجودة.',
    );
    return '$_temp0';
  }

  @override
  String get enterTextToSendError => 'يرجى إدخال نص للإرسال';

  @override
  String sendFailedError(String error) {
    return 'فشل الإرسال: $error';
  }

  @override
  String get transfersActiveSubtitle => 'تظهر هنا التحويلات المكتملة والنشطة';

  @override
  String transfersRecentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تحويل حديث',
      many: '$count تحويلًا حديثًا',
      few: '$count تحويلات حديثة',
      two: 'تحويلان حديثان',
      one: 'تحويل حديث واحد',
      zero: 'لا توجد تحويلات حديثة',
    );
    return '$_temp0';
  }

  @override
  String get noActiveOrRecentTransfers => 'لا توجد تحويلات نشطة أو حديثة.';

  @override
  String transferFromPeer(String name) {
    return 'من $name';
  }

  @override
  String transferToPeer(String name) {
    return 'إلى $name';
  }

  @override
  String get transferStatusWaitingForYou => 'في انتظارك';

  @override
  String get transferStatusAwaitingResponse => 'في انتظار الرد';

  @override
  String get transferStatusOffered => 'معروض';

  @override
  String get removeButton => 'إزالة';

  @override
  String get fileMovedOrDeleted => 'تم نقل الملف أو حذفه';

  @override
  String showInFinder(String fileName) {
    return 'إظهار $fileName في Finder';
  }

  @override
  String showInFolder(String fileName) {
    return 'إظهار $fileName في المجلد';
  }

  @override
  String openFileTooltip(String fileName) {
    return 'فتح $fileName';
  }

  @override
  String incomingTransferFromPeer(String name) {
    return 'تحويل وارد من $name';
  }

  @override
  String incomingTransferFilesCount(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يريد $name إرسال $count ملف:',
      many: 'يريد $name إرسال $count ملفًا:',
      few: 'يريد $name إرسال $count ملفات:',
      two: 'يريد $name إرسال ملفين:',
      one: 'يريد $name إرسال ملف واحد:',
      zero: 'يريد $name إرسال 0 ملف:',
    );
    return '$_temp0';
  }

  @override
  String get totalSizeLabel => 'الحجم الإجمالي:';

  @override
  String firstTransferNote(String path) {
    return 'أول تحويل من هذا الجهاز.\nسيتم حفظ الملفات في: $path';
  }

  @override
  String get permissionElevationRequestTitle => 'طلب رفع مستوى الإذن';

  @override
  String get peerIsRequesting => ' يطلب إذن ';

  @override
  String get accessToThisComputer => ' للوصول إلى هذا الكمبيوتر.';

  @override
  String get tierTitleViewOnly => 'عرض فقط';

  @override
  String get tierTitleControl => 'تحكم';

  @override
  String get tierTitleControlAndApps => 'تحكم + تشغيل التطبيقات';

  @override
  String get tierTitleAdmin => 'مسؤول (وصول كامل)';

  @override
  String get tierExplViewOnly =>
      'يسمح بعرض حالة النظام وحالة الوسائط وتخطيط الشاشة — دون محتويات الشاشة.';

  @override
  String get tierExplControl =>
      'يسمح بإرسال إدخال لوحة المفاتيح والماوس، ومزامنة الحافظة، والتحكم في الوسائط، وعرض هذه الشاشة، ونقل الملفات — مع تأكيد كل عملية نقل قبل بدئها.';

  @override
  String get tierExplExtended =>
      'يسمح بتشغيل التطبيقات وتنفيذ الأوامر المسجلة مسبقًا دون طلب تأكيد إضافي.';

  @override
  String get tierExplAdmin =>
      'يسمح بالتحكم في الطاقة (إيقاف التشغيل، إعادة التشغيل، وضع السكون، القفل) وإدارة الأجهزة المقترنة.';

  @override
  String get whatThisAllows => 'ما يتيحه هذا الإذن:';

  @override
  String get messageFromDevice => 'رسالة من الجهاز:';

  @override
  String get adminWarningMessage =>
      'يتيح وصول المسؤول إعادة تشغيل جهازك أو إيقاف تشغيله والتراجع عن الأعمال غير المحفوظة.';

  @override
  String automaticallyDeniedInSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'يتم الرفض تلقائيًا خلال $count ثانية',
      many: 'يتم الرفض تلقائيًا خلال $count ثانية',
      few: 'يتم الرفض تلقائيًا خلال $count ثوانٍ',
      two: 'يتم الرفض تلقائيًا خلال ثانيتين',
      one: 'يتم الرفض تلقائيًا خلال ثانية واحدة',
      zero: 'يتم الرفض تلقائيًا خلال 0 ثانية',
    );
    return '$_temp0';
  }

  @override
  String get temporary30Minutes => 'مؤقت · 30 دقيقة';

  @override
  String get permanent => 'دائم';

  @override
  String get denyButton => 'رفض';

  @override
  String get approveButton => 'موافقة';

  @override
  String get waitingForPairingApproval => 'في انتظار الموافقة على الإقران';

  @override
  String deviceConnectionStats(String address, String latency, int bars) {
    return '$address · $latency ملّي ثانية · $bars/4';
  }

  @override
  String get clipboardSyncEnabledTooltip => 'تم تفعيل مزامنة الحافظة';

  @override
  String get clipboardSyncDisabledTooltip => 'تم تعطيل مزامنة الحافظة';

  @override
  String get clipboardSyncNotPermittedTooltip =>
      'مزامنة الحافظة غير مسموح بها في هذا المستوى من الإذن';

  @override
  String get renameDeviceTooltip => 'إعادة تسمية هذا الجهاز';

  @override
  String get rememberedDeviceTooltip =>
      'متذكر — يتصل دون طلب إذن. اضغط لبدء السؤال مجددًا.';

  @override
  String get notRememberedDeviceTooltip =>
      'غير متذكر. اضغط للسماح له بالاتصال دون سؤال.';

  @override
  String get forgetDeviceTooltip => 'نسيان هذا الجهاز';

  @override
  String get tierLabelViewOnly => 'عرض فقط';

  @override
  String get tierLabelControl => 'تحكم';

  @override
  String get tierLabelControlAndApps => 'تحكم + تطبيقات';

  @override
  String get tierLabelFullAccess => 'وصول كامل';

  @override
  String get renameDeviceDialogTitle => 'إعادة تسمية الجهاز';

  @override
  String get invalidDeviceNameError =>
      'اسم غير صالح: من 1 إلى 64 حرفًا، وبدون رموز تحكم أو فواصل أسطر.';

  @override
  String get pairingDialogTitle => 'هل تريد إقران هذا الجهاز؟';

  @override
  String pairingDialogMessage(String name) {
    return 'يريد $name التحكم في هذا الكمبيوتر.';
  }

  @override
  String get pairingDialogInstructions =>
      'وافق فقط إذا كان هاتفك يعرض هذه الأرقام الستة بالضبط، أو إذا قمت بمسح الرمز على هذه الشاشة باستخدامه للتو. تعني الأرقام المختلفة وجود طرف يعترض الاتصال.';

  @override
  String get theNumbersMatchButton => 'الأرقام متطابقة';

  @override
  String get connectionRequestDialogTitle => 'هل تسمح لهذا الجهاز بالاتصال؟';

  @override
  String connectionRequestPeerMessage(String name) {
    return 'يطلب $name الاتصال بهذا الكمبيوتر.';
  }

  @override
  String get connectionRequestExplanation =>
      'لقد قمت بإقرانه من قبل، لذا تم التحقق من هويته مسبقًا. يتعلق هذا بالوقت الحالي فقط: اسمح به إذا كان الجهاز معك، وارفضه إذا لم يكن معك.';

  @override
  String get connectionRequestSessionNote =>
      'لن يطلب Remote Link الإذن لهذا الجهاز مرة أخرى حتى تغلق التطبيق.';

  @override
  String get dontAllowButton => 'عدم السماح';

  @override
  String get allowButton => 'سماح';

  @override
  String get rememberDeviceDialogTitle => 'هل تريد تذكر هذا الجهاز؟';

  @override
  String rememberDeviceIntro(String name) {
    return '$name متصل حاليًا. يمكن لـ Remote Link السماح له بالدخول مباشرة في المرة القادمة، دون الحاجة للمسح أو طلب الإذن.';
  }

  @override
  String rememberDeviceExplanation(String name) {
    return 'يُطلب من $name نفس الأمر. يجب أن يوافق كلا الجهازين، ويمكن لأي منهما تغيير رأيه لاحقًا في قسم الأجهزة.';
  }

  @override
  String get keepAskingButton => 'الاستمرار في السؤال';

  @override
  String get rememberButton => 'تذكر';

  @override
  String rememberDeviceAgreedSnackBar(String name) {
    return 'سيتم تذكر $name بمجرد موافقته أيضًا.';
  }

  @override
  String couldNotRetryError(String error) {
    return 'تعذرت إعادة المحاولة: $error';
  }

  @override
  String get invalidDeviceNameSnackBar =>
      'اسم الجهاز غير صالح. يجب أن يتكون الاسم من 1 إلى 64 حرفًا دون رموز تحكم.';

  @override
  String get waitingForDevicesMessage => 'في انتظار اتصال الأجهزة…';

  @override
  String errorMessage(String error) {
    return 'خطأ: $error';
  }

  @override
  String get noDevicesConnectedPrompt =>
      'لا توجد أجهزة متصلة. افتح Remote Link على هاتفك — يُفترض أن يجد هذا الكمبيوتر تلقائيًا، أو يمكنك إظهار رمز لمسحه.';

  @override
  String get showPairingCodeButton => 'إظهار رمز الإقران';

  @override
  String get connectedDevicesSectionTitle => 'الأجهزة المتصلة';

  @override
  String connectedDevicesCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جهاز متصل',
      many: '$count جهازًا متصلًا',
      few: '$count أجهزة متصلة',
      two: 'جهازان متصلان',
      one: 'جهاز واحد متصل',
      zero: 'ستظهر الهواتف المتصلة بهذا الكمبيوتر هنا',
    );
    return '$_temp0';
  }

  @override
  String get transferFailureTimedOut => 'انتهت مهلة نقل الملف';

  @override
  String get transferFailureHashMismatch => 'بصمة سلامة الملف غير متطابقة';

  @override
  String get transferFailureNoSpace => 'لا توجد مساحة تخزين كافية';

  @override
  String get transferFailureNoSpaceOnPeer =>
      'لا توجد مساحة تخزين كافية على الجهاز الآخر';

  @override
  String get transferFailureChunkRefused => 'رُفض جزء من الملف';

  @override
  String transferFailureCancelledByPeer(String peerName) {
    return 'ألغى $peerName النقل';
  }

  @override
  String get transferFailureCancelledByYou => 'ألغيت النقل';

  @override
  String transferFailureDeclinedByPeer(String peerName) {
    return 'رفض $peerName النقل';
  }

  @override
  String get transferFailureDeclinedByYou => 'رفضت النقل';

  @override
  String get transferFailureConnectionLost => 'انقطع الاتصال';

  @override
  String get transferFailureDeviceDisconnected => 'انقطع اتصال الجهاز';

  @override
  String get transferFailureIoError => 'حدث خطأ إدخال أو إخراج أثناء النقل';

  @override
  String get transferFailureReceiverUnavailable => 'جهاز الاستقبال غير متاح';

  @override
  String get transferFailureStorageUnavailable => 'مساحة التخزين غير متاحة';

  @override
  String get transferFailureCouldNotComplete => 'تعذر إكمال الملف';

  @override
  String get transferFailureCouldNotAccept => 'تعذر قبول النقل';

  @override
  String get transferFailureRetryFailed => 'فشلت إعادة المحاولة';

  @override
  String get startingService => 'جارٍ تشغيل الخدمة…';

  @override
  String get filterLevel => 'مستوى التصفية:';

  @override
  String get phoneControlCapabilityMissing =>
      'التحكم بالهاتف من هذا الكمبيوتر غير متاح. لا تتيح أجهزة iPhone ذلك، وتحتاج أجهزة Android إلى خدمة غير متضمنة في هذا الإصدار، ولا يوجد عارض هنا بعد.';

  @override
  String get phoneControlReadOnly =>
      'ارفع صلاحية هذا الجهاز فوق وضع القراءة فقط للتحكم به.';

  @override
  String get backendInputName => 'إدخال الأوامر';

  @override
  String get backendClipboardName => 'مزامنة الحافظة';

  @override
  String get backendMediaName => 'التحكم بالوسائط';

  @override
  String backendClipboardUnsupported(String platform) {
    return 'مزامنة الحافظة غير مدعومة على $platform';
  }

  @override
  String get backendClipboardUnavailable => 'خدمة الحافظة غير متاحة';

  @override
  String backendMediaUnsupported(String platform) {
    return 'التحكم بالوسائط غير مدعوم على $platform';
  }

  @override
  String get backendMediaUnavailable => 'خدمة الوسائط غير متاحة';

  @override
  String get inputAccessibilityPermission =>
      'يحتاج Remote Link إلى إذن تسهيلات الاستخدام. فعّله من إعدادات النظام › الخصوصية والأمان › تسهيلات الاستخدام، ثم أغلق Remote Link وأعد فتحه.';

  @override
  String backendInputUnsupported(String platform) {
    return 'التحكم في الإدخال غير مدعوم على $platform.';
  }

  @override
  String get backendInputLibrariesUnavailable =>
      'تعذر تشغيل التحكم في الإدخال على هذا الكمبيوتر.';

  @override
  String get backendUnavailableGeneric => 'عنصر التحكم هذا غير متاح حاليًا.';

  @override
  String get thisPlatform => 'هذه المنصة';
}
