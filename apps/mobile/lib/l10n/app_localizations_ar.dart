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
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get done => 'تم';

  @override
  String get undo => 'تراجع';

  @override
  String get clear => 'مسح';

  @override
  String get clearAll => 'مسح الكل';

  @override
  String get settings => 'الإعدادات';

  @override
  String get searchAgain => 'البحث مجددًا';

  @override
  String get scanCode => 'مسح الرمز';

  @override
  String get notConnected => 'غير متصل';

  @override
  String get notConnectedPeriod => 'غير متصل.';

  @override
  String get connected => 'متصل';

  @override
  String get reconnecting => 'جارٍ إعادة الاتصال';

  @override
  String get connecting => 'جارٍ الاتصال';

  @override
  String get pairing => 'جارٍ الإقران';

  @override
  String get waitingToBeLetIn => 'في انتظار السماح بالدخول';

  @override
  String get connectionFailed => 'فشل الاتصال';

  @override
  String connectionStatusLabel(String status) {
    return 'حالة الاتصال: $status';
  }

  @override
  String shareSent(String description, String peerName) {
    return 'تم إرسال $description إلى $peerName.';
  }

  @override
  String shareWaiting(String description) {
    return 'جارٍ الاحتفاظ بـ $description حتى يعود الكمبيوتر.';
  }

  @override
  String shareFailed(String reason) {
    return 'تعذر إرسال ذلك: $reason';
  }

  @override
  String get devicesTitle => 'الأجهزة';

  @override
  String reconnectingTo(String name) {
    return 'جارٍ إعادة الاتصال بـ $name';
  }

  @override
  String get chooseDifferentComputer => 'اختيار كمبيوتر آخر';

  @override
  String get deviceConnectedSubtitle => 'متصل';

  @override
  String get tapForControls => ' · اضغط للتحكم';

  @override
  String get deviceAccessRevoked => 'قام هذا الكمبيوتر بإلغاء وصولك';

  @override
  String get pairedTapToScan => 'مقترن · اضغط لمسح رمزه';

  @override
  String pairedWithAddress(String host) {
    return 'مقترن · $host';
  }

  @override
  String pairedNotSeen(String host) {
    return 'مقترن · غير مرئي حاليًا · $host';
  }

  @override
  String tapToPair(String host) {
    return 'اضغط للإقران · $host';
  }

  @override
  String get pairAgain => 'إقران مجددًا';

  @override
  String get disconnect => 'قطع الاتصال';

  @override
  String get renameComputer => 'إعادة تسمية الكمبيوتر';

  @override
  String get computerName => 'اسم الحاسوب';

  @override
  String get invalidComputerName =>
      'اسم غير صالح: من 1 إلى 64 حرفًا، بدون رموز تحكم أو فواصل أسطر.';

  @override
  String get switchComputersTitle => 'تبديل الكمبيوتر؟';

  @override
  String switchComputersMessage(String name) {
    return 'يتصل هذا الهاتف بكمبيوتر واحد في كل مرة، لذا سيؤدي الاتصال بـ $name إلى قطع الاتصال بالكمبيوتر الحالي. سيتوقف أي نقل قيد التشغيل.';
  }

  @override
  String get stay => 'البقاء';

  @override
  String switchToComputer(String name) {
    return 'التبديل إلى $name';
  }

  @override
  String get deviceCantSearch => 'لا يمكن لهذا الجهاز البحث تلقائيًا';

  @override
  String get lookingForComputers => 'جارٍ البحث عن أجهزة كمبيوتر';

  @override
  String get noComputersFound => 'لم يتم العثور على أجهزة كمبيوتر';

  @override
  String get deviceCantSearchExplanation =>
      'تحتاج هواتف iPhone إلى إذن خاص من Apple للبحث في الشبكة المحلية، وبعض شبكات Wi-Fi تحظر ذلك تمامًا.\n\nامسح الرمز الذي يظهره الكمبيوتر بدلاً من ذلك — فهو يحتوي على العنوان، وبالتالي لا يلزم البحث. يعمل كل شيء آخر تمامًا بالطريقة نفسها.';

  @override
  String get lookingForComputersExplanation =>
      'تأكد من تشغيل Remote Link على الكمبيوتر ومن وجود كلا الجهازين على شبكة Wi-Fi نفسها.';

  @override
  String get noComputersFoundExplanation =>
      'تحقق من تشغيل Remote Link على جهاز الكمبيوتر ومن وجود كلا الجهازين على نفس شبكة Wi-Fi.\n\nتحظر بعض الشبكات — وخاصة شبكات Wi-Fi للضيوف — حركة المرور التي تكتشف أجهزة الكمبيوتر تلقائيًا. إذا كانت شبكتك كذلك، فانقر على «إقران هاتف» على الكمبيوتر وامسح الرمز الذي يظهره. سيتم تذكره لاحقًا.';

  @override
  String get platformMac => 'Mac';

  @override
  String get platformWindows => 'كمبيوتر Windows';

  @override
  String get platformLinux => 'كمبيوتر Linux';

  @override
  String get platformComputer => 'كمبيوتر';

  @override
  String get tabTouchpad => 'لوحة اللمس';

  @override
  String get tabKeyboard => 'لوحة المفاتيح';

  @override
  String get tabMedia => 'الوسائط';

  @override
  String get tabClipboard => 'الحافظة';

  @override
  String get tabSend => 'إرسال';

  @override
  String get tooltipShowTabs => 'إظهار علامات التبويب مجددًا';

  @override
  String get tooltipExpandGesture => 'توسيع مساحة الإيماءات';

  @override
  String get tooltipScreenStream => 'بث الشاشة';

  @override
  String get clipboardSyncTitle => 'مزامنة الحافظة';

  @override
  String get clipboardConnectedActive => 'متصل ونشط';

  @override
  String get clipboardSyncPaused => 'المزامنة متوقفة مؤقتًا';

  @override
  String get clipboardReadyToSync => 'جاهز للمزامنة';

  @override
  String clipboardFromComputer(String name) {
    return 'من $name';
  }

  @override
  String get clipboardFromYourComputer => 'من جهاز الكمبيوتر الخاص بك';

  @override
  String get clipboardFromThisPhone => 'من هذا الهاتف';

  @override
  String get clipboardPlaceholder => 'سيظهر أحدث عنصر في الحافظة هنا.';

  @override
  String get clipboardSendButton => 'إرسال';

  @override
  String get clipboardGetButton => 'جلب';

  @override
  String get historyTitle => 'السجل';

  @override
  String get historySubtitle => 'اضغط على عنصر لنسخه مجددًا';

  @override
  String get unpin => 'إلغاء التثبيت';

  @override
  String get pin => 'تثبيت';

  @override
  String get remove => 'إزالة';

  @override
  String get deletedFromHistory => 'تم الحذف من السجل';

  @override
  String get copied => 'تم النسخ.';

  @override
  String get itemCantBeCopied => 'لا يمكن نسخ هذا العنصر هنا.';

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
  String systemBatteryCharging(int percent) {
    return 'بطارية الكمبيوتر $percent بالمائة، جارٍ الشحن';
  }

  @override
  String systemBattery(int percent) {
    return 'بطارية الكمبيوتر $percent بالمائة';
  }

  @override
  String systemProcessor(String percent) {
    return 'المعالج $percent بالمائة';
  }

  @override
  String systemMemory(String percent) {
    return 'الذاكرة $percent بالمائة';
  }

  @override
  String systemUptime(String uptime) {
    return 'قيد التشغيل منذ $uptime';
  }

  @override
  String get touchpadLabel => 'لوحة اللمس';

  @override
  String get touchpadHint =>
      'اسحب لتحريك المؤشر. انقر مرتين للنقر. اسحب بثلاثة أصابع للتمرير. أزرار الاتجاهات متوفرة بالأسفل.';

  @override
  String get touchpadWatermarkHint =>
      'اسحب للتحريك · انقر للضغط\nإصبعان للتمرير أو النقر الأيمن\nاضغط مع الاستمرار للسحب\n\nاضبط الحساسية في أي وقت من الإعدادات';

  @override
  String get sensitivityBannerTitle => 'حساسية المؤشر';

  @override
  String get sensitivityBannerSubtitle =>
      'اضغط للشرح التعليمي أو اضبطها في الإعدادات';

  @override
  String get adjust => 'ضبط';

  @override
  String get dismissHint => 'تجاهل التلميح';

  @override
  String get pointerControlsTitle => 'عناصر التحكم بالمؤشر';

  @override
  String get hidePointerControls => 'إخفاء عناصر التحكم بالمؤشر';

  @override
  String get showPointerControls => 'إظهار عناصر التحكم بالمؤشر';

  @override
  String stepSizeAnnouncement(String stepName) {
    return 'حجم الخطوة، حاليًا $stepName';
  }

  @override
  String get stepFine => 'دقيق';

  @override
  String get stepNormal => 'عادي';

  @override
  String get stepCoarse => 'عريض';

  @override
  String stepTooltip(String stepName, int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: '$pixels بكسل لكل ضغطة',
      many: '$pixels بكسلًا لكل ضغطة',
      few: '$pixels بكسلات لكل ضغطة',
      two: 'بكسلان لكل ضغطة',
      one: 'بكسل واحد لكل ضغطة',
      zero: 'ولا بكسل لكل ضغطة',
    );
    return '$stepName — $_temp0';
  }

  @override
  String movePointerLeft(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'تحريك المؤشر يسارًا $pixels بكسل',
      many: 'تحريك المؤشر يسارًا $pixels بكسلًا',
      few: 'تحريك المؤشر يسارًا $pixels بكسلات',
      two: 'تحريك المؤشر يسارًا بكسلين',
      one: 'تحريك المؤشر يسارًا بكسلًا واحدًا',
      zero: 'تحريك المؤشر يسارًا',
    );
    return '$_temp0';
  }

  @override
  String movePointerRight(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'تحريك المؤشر يمينًا $pixels بكسل',
      many: 'تحريك المؤشر يمينًا $pixels بكسلًا',
      few: 'تحريك المؤشر يمينًا $pixels بكسلات',
      two: 'تحريك المؤشر يمينًا بكسلين',
      one: 'تحريك المؤشر يمينًا بكسلًا واحدًا',
      zero: 'تحريك المؤشر يمينًا',
    );
    return '$_temp0';
  }

  @override
  String movePointerUp(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'تحريك المؤشر لأعلى $pixels بكسل',
      many: 'تحريك المؤشر لأعلى $pixels بكسلًا',
      few: 'تحريك المؤشر لأعلى $pixels بكسلات',
      two: 'تحريك المؤشر لأعلى بكسلين',
      one: 'تحريك المؤشر لأعلى بكسلًا واحدًا',
      zero: 'تحريك المؤشر لأعلى',
    );
    return '$_temp0';
  }

  @override
  String movePointerDown(int pixels) {
    String _temp0 = intl.Intl.pluralLogic(
      pixels,
      locale: localeName,
      other: 'تحريك المؤشر لأسفل $pixels بكسل',
      many: 'تحريك المؤشر لأسفل $pixels بكسلًا',
      few: 'تحريك المؤشر لأسفل $pixels بكسلات',
      two: 'تحريك المؤشر لأسفل بكسلين',
      one: 'تحريك المؤشر لأسفل بكسلًا واحدًا',
      zero: 'تحريك المؤشر لأسفل',
    );
    return '$_temp0';
  }

  @override
  String get leftClick => 'نقر أيسر';

  @override
  String get rightClick => 'نقر أيمن';

  @override
  String get middleClick => 'نقر أوسط';

  @override
  String get scrollUp => 'تمرير لأعلى';

  @override
  String get scrollDown => 'تمرير لأسفل';

  @override
  String get padButtonLeft => 'يسار';

  @override
  String get padButtonMid => 'وسط';

  @override
  String get padButtonRight => 'يمين';

  @override
  String get sensitivityTutorialTooltip => 'دليل حساسية المؤشر التعليمي';

  @override
  String get tutorialTitle => 'حساسية المؤشر';

  @override
  String get tutorialMessage =>
      'تبدو حركة المؤشر طبيعية عندما تتطابق الحساسية مع دقة شاشتك.\n\nاضبطها في أي وقت من الإعدادات › لوحة اللمس بما يناسب تفضيلك.';

  @override
  String get openSettingsButton => 'فتح الإعدادات';

  @override
  String get gotItButton => 'فهمت';

  @override
  String get unmute => 'إلغاء كتم الصوت';

  @override
  String get mute => 'كتم الصوت';

  @override
  String get volume => 'مستوى الصوت';

  @override
  String volumePercent(int percent) {
    return 'مستوى الصوت $percent بالمائة';
  }

  @override
  String get display => 'الشاشة';

  @override
  String screenBrightnessPercent(int percent) {
    return 'سطوع الشاشة $percent بالمائة';
  }

  @override
  String get nothingPlaying => 'لا شيء قيد التشغيل';

  @override
  String get mediaControls => 'عناصر التحكم بالوسائط';

  @override
  String get playSomethingHint =>
      'شغّل شيئًا وسيظهر هنا. تعمل عناصر التحكم مع أي تطبيق بما في ذلك المتصفحات.';

  @override
  String get trackDetailsUnavailable =>
      'تفاصيل المسار غير متوفرة على هذا الكمبيوتر. لا تزال عناصر التحكم بالتشغيل ومستوى الصوت تعمل.';

  @override
  String get previousTrack => 'المسار السابق';

  @override
  String get play => 'تشغيل';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get nextTrack => 'المسار التالي';

  @override
  String get mediaControlUnavailable => 'التحكم بالوسائط غير متوفر';

  @override
  String get mediaControlUnavailableExplanation =>
      'لم يوفّر هذا الكمبيوتر إمكانية التحكم بالوسائط. تم تنفيذها على macOS ودعم Windows قادم قريبًا.';

  @override
  String get sendToSubtitleNoDevice => 'لا يوجد جهاز متصل';

  @override
  String sendToSubtitleSingle(String name) {
    return 'إلى $name';
  }

  @override
  String sendToSubtitleMultiple(String name, int total) {
    return 'إلى $name، من أصل $total';
  }

  @override
  String get nowhereToSendYet => 'لا توجد وجهة للإرسال بعد';

  @override
  String get nowhereToSendExplanation =>
      'اتصل بجهاز كمبيوتر، أو افتح Remote Link على هاتف آخر على شبكة Wi-Fi نفسها وسيظهر هنا.';

  @override
  String get addMedia => 'إضافة وسائط';

  @override
  String get media => 'وسائط';

  @override
  String get addFiles => 'إضافة ملفات';

  @override
  String get files => 'ملفات';

  @override
  String pickedFilesCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر · $size',
      many: '$count عنصرًا · $size',
      few: '$count عناصر · $size',
      two: 'عنصران · $size',
      one: 'عنصر واحد · $size',
      zero: 'ولا عنصر · $size',
    );
    return '$_temp0';
  }

  @override
  String removeFileTooltip(String name) {
    return 'إزالة $name';
  }

  @override
  String get deletedFromSelection => 'تم الحذف من التحديد';

  @override
  String get chooseSomethingToSend => 'اختر شيئًا لإرساله أولاً.';

  @override
  String filesNoLongerAvailable(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف لم تعد متوفرة. يرجى اختيارها مجددًا.',
      many: '$count ملفًا لم تعد متوفرة. يرجى اختيارها مجددًا.',
      few: '$count ملفات لم تعد متوفرة. يرجى اختيارها مجددًا.',
      two: 'الملفان لم يعودا متوفرين. يرجى اختيارهما مجددًا.',
      one: 'الملف $name لم يعد متوفرًا. يرجى اختياره مجددًا.',
      zero: 'لم تعد الملفات متوفرة.',
    );
    return '$_temp0';
  }

  @override
  String offeredItems(int count, String target) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم عرض $count عنصر على $target.',
      many: 'تم عرض $count عنصرًا على $target.',
      few: 'تم عرض $count عناصر على $target.',
      two: 'تم عرض عنصرين على $target.',
      one: 'تم عرض عنصر واحد على $target.',
      zero: 'تم عرض 0 عنصر على $target.',
    );
    return '$_temp0';
  }

  @override
  String couldNotRetry(String error) {
    return 'تعذرت إعادة المحاولة: $error';
  }

  @override
  String get transferDeleted => 'تم حذف التحويل';

  @override
  String get connectToDeviceToSend => 'اتصل بجهاز للإرسال.';

  @override
  String get chooseMediaOrFilesAbove => 'اختر وسائط أو ملفات من الأعلى.';

  @override
  String previewFile(String name) {
    return 'معاينة $name';
  }

  @override
  String transferFromPeer(String name) {
    return 'من $name';
  }

  @override
  String transferToPeer(String name) {
    return 'إلى $name';
  }

  @override
  String transferFileItemCount(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر · $size',
      many: '$count عنصرًا · $size',
      few: '$count عناصر · $size',
      two: 'عنصران · $size',
      one: 'عنصر واحد · $size',
      zero: 'ولا عنصر · $size',
    );
    return '$_temp0';
  }

  @override
  String get deleteTransfer => 'حذف التحويل';

  @override
  String get fileNoLongerStored => 'لم يعد هذا الملف مخزنًا على هاتفك.';

  @override
  String openFile(String name) {
    return 'فتح $name';
  }

  @override
  String shareFile(String name) {
    return 'مشاركة $name';
  }

  @override
  String sendFailed(String error) {
    return 'فشل الإرسال: $error';
  }

  @override
  String get dismiss => 'تجاهل';

  @override
  String transferEta(String eta) {
    return 'الوقت المتبقي: $eta';
  }

  @override
  String get statusWaitingForYou => 'في انتظارك';

  @override
  String get statusAwaitingResponse => 'في انتظار الرد';

  @override
  String get statusOffered => 'معروض';

  @override
  String get statusTransferring => 'جارٍ النقل';

  @override
  String get statusCompleted => 'اكتمل';

  @override
  String get statusCancelled => 'ملغى';

  @override
  String get statusDeclined => 'مرفوض';

  @override
  String get statusFailed => 'فشل';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get keyboardModeText => 'نص';

  @override
  String get keyboardModeKeys => 'مفاتيح';

  @override
  String modifierLockedOn(String name) {
    return '$name، مفعّل دائمًا';
  }

  @override
  String get sentToComputer => 'تم الإرسال إلى جهاز الكمبيوتر الخاص بك';

  @override
  String get clearTranscript => 'مسح النص المرسل';

  @override
  String get tapHereThenType => 'اضغط هنا، ثم اكتب.';

  @override
  String get sectionShortcuts => 'الاختصارات';

  @override
  String get sectionModifiers => 'مفاتيح التعديل';

  @override
  String get sectionKeys => 'المفاتيح';

  @override
  String get shortcutCopy => 'نسخ';

  @override
  String get shortcutPaste => 'لصق';

  @override
  String get shortcutCut => 'قص';

  @override
  String get shortcutUndo => 'تراجع';

  @override
  String get shortcutRedo => 'إعادة';

  @override
  String get shortcutSelectAll => 'تحديد الكل';

  @override
  String get shortcutSave => 'حفظ';

  @override
  String get shortcutFind => 'بحث';

  @override
  String get shortcutSwitchApp => 'تبديل التطبيق';

  @override
  String get shortcutCloseTab => 'إغلاق التبويب';

  @override
  String get shortcutRefresh => 'تحديث';

  @override
  String get shortcutTaskManager => 'مدير المهام';

  @override
  String get scanCodeToPair => 'مسح الرمز للإقران';

  @override
  String get scanCodeInstructions =>
      'وجّه الكاميرا نحو الرمز الظاهر على شاشة الكمبيوتر.';

  @override
  String get verifyingSecurityCode => 'جارٍ التحقق من رمز الأمان…';

  @override
  String pairingFailed(String reason) {
    return 'فشل الإقران: $reason';
  }

  @override
  String securityCodeMatchesPrompt(String name) {
    return 'قارن الرمز أدناه بالرمز الظاهر على «$name»:';
  }

  @override
  String get securityCodeDoesNotMatch => 'الرمزان غير متطابقين';

  @override
  String get securityCodeMatches => 'الرمزان متطابقان';

  @override
  String waitingForApproval(String name) {
    return 'في انتظار موافقة «$name» على الاتصال…';
  }

  @override
  String incomingConnectionRequest(String name) {
    return 'يطلب «$name» الاتصال';
  }

  @override
  String get incomingConnectionExplanation =>
      'هل تسمح لهذا الجهاز بالتفاعل مع هاتفك؟';

  @override
  String get allowButton => 'السماح';

  @override
  String get declineButton => 'رفض';

  @override
  String incomingFilePrompt(String name, int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف ($size)',
      many: '$count ملفًا ($size)',
      few: '$count ملفات ($size)',
      two: 'ملفين ($size)',
      one: 'ملفًا واحدًا ($size)',
      zero: 'ملفات ($size)',
    );
    return 'يريد «$name» أن يرسل لك $_temp0';
  }

  @override
  String connectionHoldWaiting(String name) {
    return 'في انتظار رد «$name»…';
  }

  @override
  String connectionHoldDeclined(String name) {
    return 'رفض «$name» الاتصال.';
  }

  @override
  String connectionHoldApproved(String name) {
    return 'تم الاتصال بـ «$name».';
  }

  @override
  String get sectionThisPhone => 'هذا الهاتف';

  @override
  String get deviceName => 'اسم الجهاز';

  @override
  String get renameThisPhone => 'إعادة تسمية هذا الهاتف';

  @override
  String get renamePhoneDialogTitle => 'إعادة تسمية هذا الهاتف';

  @override
  String get deviceId => 'معرّف الجهاز';

  @override
  String get publicKeyFingerprint => 'بصمة المفتاح العام';

  @override
  String get sectionAppearance => 'المظهر';

  @override
  String get themeModeLabel => 'السمة';

  @override
  String get themeModeSystem => 'تلقائي حسب النظام';

  @override
  String get themeModeLight => 'فاتح';

  @override
  String get themeModeDark => 'داكن';

  @override
  String get sectionTouchpad => 'لوحة اللمس';

  @override
  String get pointerSpeed => 'سرعة المؤشر';

  @override
  String get pointerAcceleration => 'تسارع المؤشر';

  @override
  String get scrollSpeed => 'سرعة التمرير';

  @override
  String get naturalScrolling => 'تمرير طبيعي';

  @override
  String get naturalScrollingSubtitle => 'يتحرك المحتوى في نفس اتجاه أصابعك';

  @override
  String get hapticFeedback => 'الاستجابة اللمسية';

  @override
  String get hapticFeedbackSubtitle => 'اهتزاز خفيف عند النقرات والإيماءات';

  @override
  String get sectionReceiving => 'الاستلام';

  @override
  String get allowFileTransfers => 'السماح بالنقل الوارد';

  @override
  String get allowFileTransfersSubtitle =>
      'السؤال عندما تريد أجهزة قريبة إرسال ملفات';

  @override
  String get sectionPairedComputers => 'أجهزة الكمبيوتر المقترنة';

  @override
  String get noPairedComputers => 'لا توجد أجهزة كمبيوتر مقترنة بعد';

  @override
  String get forgetDevice => 'نسيان';

  @override
  String forgetDeviceConfirm(String name) {
    return 'هل تريد نسيان «$name»؟ ستحتاج إلى الإقران مجددًا للاتصال.';
  }

  @override
  String get sectionClipboard => 'الحافظة';

  @override
  String get syncFromDesktop => 'مزامنة من الكمبيوتر';

  @override
  String get syncFromDesktopSubtitle =>
      'تحديث حافظة الهاتف تلقائيًا عند النسخ على الكمبيوتر';

  @override
  String get syncToDesktop => 'مزامنة إلى الكمبيوتر';

  @override
  String get syncToDesktopSubtitle => 'إرسال النص المنسوخ إلى الكمبيوتر';

  @override
  String get sectionBackground => 'الخلفية';

  @override
  String get keepConnectionAlive => 'إبقاء الاتصال نشطًا في الخلفية';

  @override
  String get keepConnectionAliveSubtitle =>
      'الحفاظ على الرابط عند تصغير التطبيق';

  @override
  String get sectionDiagnostics => 'التشخيصات';

  @override
  String get exportLogs => 'تصدير السجلات';

  @override
  String get exportLogsSubtitle => 'مشاركة سجلات التشخيص لاستكشاف الأخطاء';

  @override
  String get logsExported => 'تم تصدير السجلات.';

  @override
  String get sectionAbout => 'حول التطبيق';

  @override
  String version(String version) {
    return 'الإصدار $version';
  }

  @override
  String get openSourceLicenses => 'تراخيص البرمجيات مفتوحة المصدر';

  @override
  String connectionDeclined(String name) {
    return 'لم يسمح «$name» بالاتصال.';
  }

  @override
  String connectionTimedOut(String name) {
    return 'لم يجب أحد على «$name»، لذا لم يُسمح بالاتصال.';
  }

  @override
  String get tryAgain => 'إعادة المحاولة';

  @override
  String get waitingToBeLetInTitle => 'في انتظار السماح بالدخول';

  @override
  String waitingToBeLetInMessage(String name) {
    return 'يسأل «$name» عما إذا كان سيسمح بهذا الاتصال.';
  }

  @override
  String get waitingToBeLetInInstructions =>
      'انتقل إلى الجهاز واضغط على «السماح». لن يتم إرسال أي شيء حتى يتم ذلك.';

  @override
  String get stopWaiting => 'إيقاف الانتظار';

  @override
  String get rememberConnectionTitle => 'تذكر هذا الاتصال؟';

  @override
  String rememberConnectionMessage(String name) {
    return 'يمكن لـ Remote Link إعادة الاتصال بـ «$name» تلقائيًا في المرة القادمة — دون مسح رمز أو طلب إذن.';
  }

  @override
  String rememberConnectionExplanation(String name) {
    return 'يتم سؤال «$name» عن الشيء نفسه. يجب أن يوافق كلا الجهازين، ويمكن لأي منهما تغيير رأيه لاحقًا.';
  }

  @override
  String get notNow => 'ليس الآن';

  @override
  String get remember => 'تذكّر';

  @override
  String get nothingCopiedYet => 'لم يتم نسخ أي شيء بعد';

  @override
  String get nothingCopiedYetExplanation =>
      'تظهر العناصر الأخيرة هنا. لا يتم تسجيل أي شيء يحدده مدير كلمات المرور كسري.';

  @override
  String securityCodeSpoken(String code) {
    return 'رمز الأمان: $code';
  }

  @override
  String pairWithDevice(String name) {
    return 'إقران مع «$name»';
  }

  @override
  String get checkingTheCode => 'جارٍ التحقق من الرمز…';

  @override
  String get connectingSecurely => 'جارٍ الاتصال بأمان…';

  @override
  String get checkDigitsPrompt => 'تأكد من أن جهاز الكمبيوتر يعرض هذه الأرقام';

  @override
  String get numbersDifferentWarning =>
      'إذا كانت الأرقام مختلفة، فهناك جهة تعترض الاتصال. قم بالإلغاء وحاول مرة أخرى على شبكة تثق بها.';

  @override
  String get theNumbersMatch => 'الأرقام متطابقة';

  @override
  String get notTheComputerOnCode => 'هذا ليس الكمبيوتر الموجود على الرمز';

  @override
  String notTheComputerOnCodeExplanation(String name) {
    return 'استجاب شيء ما على ذلك العنوان بهوية مختلفة عن الرمز. لم يقترن به Remote Link ولم يرسل إليه شيئًا.\n\nعلى شبكة تثق بها لا ينبغي أن يحدث هذا أبدًا. اعرض الرمز مرة أخرى على «$name» وامسح الرمز الجديد.';
  }

  @override
  String get couldNotEstablishSecureConnection => 'تعذر إنشاء اتصال آمن';

  @override
  String get pairingFailedRefusedOrMismatched =>
      'رفض الكمبيوتر الاتصال، أو لم تتطابق هويته مع ما تم حفظه على هذا الهاتف.';

  @override
  String get torchTooltip => 'الفلاش';

  @override
  String get scannerInstructions =>
      'على جهاز الكمبيوتر، افتح Remote Link واضغط على «إقران هاتف».';

  @override
  String get foreignCodeWarning => 'هذا الرمز ليس من Remote Link.';

  @override
  String get cameraPermissionDeniedTitle =>
      'لا يمكن لـ Remote Link استخدام الكاميرا';

  @override
  String get cameraPermissionDeniedDesc =>
      'قم بتفعيل الكاميرا لـ Remote Link في إعدادات جهازك، ضمن التطبيقات.\n\nيمكنك الإقران بدونها: ارجع وسيظهر الكمبيوتر في القائمة إذا كان كلاهما على نفس شبكة Wi-Fi.';

  @override
  String get cameraUnsupportedTitle => 'هذا الجهاز لا يحتوي على كاميرا للمسح';

  @override
  String get cameraUnsupportedDesc =>
      'ارجع — وسيظهر الكمبيوتر في القائمة بمفرده طالما أن كلا الجهازين على نفس شبكة Wi-Fi.';

  @override
  String get cameraErrorTitle => 'تعذر تشغيل الكاميرا';

  @override
  String get cameraErrorDesc =>
      'منع أمر ما الكاميرا من البدء. حاول مجددًا أو ارجع واختر الكمبيوتر من القائمة.';

  @override
  String get incomingDevicePrompt => 'يريد جهاز الاتصال';

  @override
  String get pairingPromptHelp =>
      'اتصل فقط إذا كان الجهاز الآخر يعرض نفس الأرقام الستة. إذا كانت مختلفة، فهناك جهة أخرى تستجيب — ارفض وحاول مجددًا.';

  @override
  String get codesMatch => 'الرمزان متطابقان';

  @override
  String get allowDeviceToConnectTitle => 'السماح لهذا الجهاز بالاتصال؟';

  @override
  String get allowDeviceToConnectHelp =>
      'لقد قمت بالإقران به من قبل، لذا تم التحقق من هويته مسبقًا. هذا مخصص للوقت الحالي فقط — اسمح به إذا كان الجهاز بيدك، وارفضه إذا لم يكن كذلك.';

  @override
  String get allowDeviceToConnectRestartHelp =>
      'لن تُسأل عنه مجددًا حتى تتم إعادة تشغيل Remote Link.';

  @override
  String rememberDevicePromptHelp(String name) {
    return 'يمكن لـ Remote Link السماح لـ «$name» بالدخول مباشرة في المرة القادمة — دون مسح رمز أو طلب إذن.';
  }

  @override
  String rememberDevicePromptBothAgree(String name) {
    return 'يتم سؤال «$name» عن الشيء نفسه. يجب أن يوافق كلا الجهازين، ويمكن لأي منهما تغيير رأيه لاحقًا.';
  }

  @override
  String incomingFileTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ملفات واردة',
      many: 'ملفات واردة',
      few: 'ملفات واردة',
      two: 'ملفان واردان',
      one: 'ملف وارد',
      zero: 'ملفات واردة',
    );
    return '$_temp0';
  }

  @override
  String incomingMoreFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'و$count آخر',
      many: 'و$count آخر',
      few: 'و$count أخرى',
      two: 'و2 آخرين',
      one: 'و1 آخر',
      zero: 'و0 أخرى',
    );
    return '$_temp0';
  }

  @override
  String get incomingDestinationExplanation =>
      'يتم حفظ الصور ومقاطع الفيديو في مكتبة الصور الخاصة بك. تفتح الملفات الأخرى ورقة المشاركة لتختار وجهتها. تظل العناصر المستلمة حديثًا قابلة للفتح من هذه القائمة.';

  @override
  String get accept => 'قبول';

  @override
  String get customiseCursorSpeed => 'تخصيص سرعة المؤشر';

  @override
  String get tutorialIntro =>
      'المؤشر يتحرك بسرعة كبيرة أو ببطء شديد؟ يمكنك ضبط سرعة المؤشر بسهولة لتناسب استخدامك:';

  @override
  String get tutorialStep1Title => 'افتح الإعدادات';

  @override
  String get tutorialStep1Desc =>
      'اضغط على أيقونة الإعدادات في الزاوية العلوية لشريط التطبيق.';

  @override
  String get tutorialStep2Title => 'حساسية المؤشر';

  @override
  String get tutorialStep2Desc =>
      'ضمن لوحة اللمس، اسحب شريط الحساسية بين 0.5x و 3.5x.';

  @override
  String get tutorialStep3Title => 'الإيماءات والتمرير';

  @override
  String get tutorialStep3Desc =>
      'قم بتبديل التمرير الطبيعي أو النقر للضغط ليتناسب مع عادات لوحة التتبع لديك.';

  @override
  String get currentSensitivityLabel => 'الحساسية الحالية: ';

  @override
  String get screenStreamTitle => 'بث الشاشة';

  @override
  String get startStream => 'بدء البث';

  @override
  String get stopStream => 'إيقاف البث';

  @override
  String get stopSharing => 'إيقاف المشاركة';

  @override
  String get waitingForScreenFrames => 'في انتظار إطارات الشاشة…';

  @override
  String get screenSharingUnavailableTitle => 'مشاركة الشاشة غير متوفرة';

  @override
  String get screenSharingUnavailableDesc =>
      'لا يمكن لهذا الكمبيوتر مشاركة شاشته. تسجيل الشاشة مدعوم على macOS عند منح إذن تسجيل الشاشة.';

  @override
  String couldNotLoadIdentity(String error) {
    return 'تعذر تحميل هوية الجهاز: $error';
  }

  @override
  String get appleWatchTitle => 'Apple Watch';

  @override
  String get noWatchPaired => 'لا توجد Apple Watch مقترنة';

  @override
  String get noWatchPairedDesc =>
      'قم بإقران ساعة مع هذا الـ iPhone وسيظهر Remote Link عليها.';

  @override
  String get watchNotInstalled => 'غير مثبت على ساعتك';

  @override
  String get watchNotInstalledDesc =>
      'قم بتثبيت Remote Link من تطبيق Watch على هذا الـ iPhone.';

  @override
  String get watchOutOfRange => 'الساعة خارج النطاق';

  @override
  String get watchOutOfRangeDesc =>
      'تتحكم الساعة في المؤشر متى استطاعت الوصول إلى هذا الـ iPhone.';

  @override
  String get watchReady => 'جاهز على معصمك';

  @override
  String get watchReadyDesc =>
      'اسحب على الساعة لتحريك المؤشر، وانقر للضغط، وأدر التاج الرقمي للتمرير.';

  @override
  String get checkAgain => 'تحقق مجددًا';

  @override
  String get logsCopiedToClipboard => 'تم نسخ السجلات إلى الحافظة';

  @override
  String get logFilter => 'تصفية السجلات:';

  @override
  String get allLevels => 'جميع المستويات';

  @override
  String logRecordsStored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سجل محفوظ في الذاكرة',
      many: '$count سجلًا محفوظًا في الذاكرة',
      few: '$count سجلات محفوظة في الذاكرة',
      two: 'سجلان محفوظان في الذاكرة',
      one: 'سجل واحد محفوظ في الذاكرة',
      zero: '0 سجل محفوظ في الذاكرة',
    );
    return '$_temp0';
  }

  @override
  String get connectionStateLabel => 'حالة الاتصال';

  @override
  String get roundTripTimeLabel => 'زمن الذهاب والإياب';

  @override
  String get discoveryRouteLabel => 'مسار الاكتشاف';

  @override
  String get measuring => 'جارٍ القياس…';

  @override
  String get stateIdle => 'خامل (غير متصل)';

  @override
  String get letNearbyDevicesSendTitle =>
      'السماح للأجهزة القريبة بالإرسال إلى هذا الهاتف';

  @override
  String get askBeforeConnectingTitle => 'السؤال قبل اتصال جهاز مقترن';

  @override
  String get waitBeforeConnectingSubtitle => 'الانتظار للموافقة قبل الاتصال';

  @override
  String get connectAutomaticallySubtitle => 'الاتصال تلقائيًا دون سؤال';

  @override
  String connectedNow(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count جهاز متصل الآن',
      many: '$count جهازًا متصلًا الآن',
      few: '$count أجهزة متصلة الآن',
      two: 'جهازان متصلان الآن',
      one: 'جهاز واحد متصل الآن',
      zero: 'لا توجد أجهزة متصلة الآن',
    );
    return '$_temp0';
  }

  @override
  String permissionsFor(String name) {
    return 'أذونات «$name»';
  }

  @override
  String renameNamed(String name) {
    return 'إعادة تسمية «$name»';
  }

  @override
  String forgetNamed(String name) {
    return 'نسيان «$name»';
  }

  @override
  String forgetNamedQuestion(String name) {
    return 'نسيان «$name»؟';
  }

  @override
  String forgotNamed(String name) {
    return 'تم نسيان «$name»';
  }

  @override
  String get phoneName => 'اسم الهاتف';

  @override
  String lastSeen(String address) {
    return 'آخر ظهور: $address';
  }

  @override
  String get noAddressRecorded => 'لا يوجد عنوان مسجل';

  @override
  String get keepHistoryOnThisPhone => 'الاحتفاظ بالسجل على هذا الهاتف';

  @override
  String get secureStorageUnavailable =>
      'التخزين الآمن لهذا الهاتف غير متوفر، لذا يظل السجل في الذاكرة فقط.';

  @override
  String get whyPhoneOpenTitle => 'لماذا يجب أن يظل هاتفي مفتوحًا؟';

  @override
  String get whyPhoneOpenSubtitle =>
      'يتطلب أمان نظام التشغيل أن يكون Remote Link مفتوحًا لقراءة الحافظة.';

  @override
  String get backgroundClipboardTitle => 'النسخ أثناء إغلاق Remote Link';

  @override
  String get batteryGuidanceTitle => 'إذا استمر انقطاع اتصال Remote Link';

  @override
  String get closeButton => 'إغلاق';

  @override
  String get openBatterySettings => 'فتح إعدادات البطارية';

  @override
  String get turnItOn => 'تفعيله';

  @override
  String get themeModeFollowSystem => 'متابعة إعدادات الهاتف';

  @override
  String get themeModeAlwaysLight => 'فاتح دائمًا';

  @override
  String get themeModeAlwaysDark => 'داكن دائمًا';

  @override
  String receivingVisibleWifi(String name) {
    return 'مرئي على هذه الشبكة باسم «$name»';
  }

  @override
  String get receivingStarting => 'جارٍ البدء…';

  @override
  String get receivingHidden => 'لن يظهر هذا الهاتف على الأجهزة الأخرى';

  @override
  String couldNotLoadPairedComputers(String error) {
    return 'تعذر تحميل الحواسيب المقترنة: $error';
  }

  @override
  String get noPairedComputersExplanation =>
      'لا توجد حواسيب مقترنة بعد. قم بالاقتران بحاسوب على شبكة Wi-Fi للبدء.';

  @override
  String get pairedDevicesTitle => 'الأجهزة المقترنة';

  @override
  String rememberAutoConnectTooltip(String name) {
    return 'يتصل «$name» دون طلب إذن. المس لإعادة طلب الإذن.';
  }

  @override
  String rememberAskFirstTooltip(String name) {
    return 'المس للسماح لـ «$name» بالاتصال دون طلب إذن.';
  }

  @override
  String get forgetComputerConfirmation =>
      'سيؤدي هذا إلى إزالة هذا الحاسوب من قائمة الأجهزة الموثوقة. ستحتاج إلى الاقتران مرة أخرى لإعادة الاتصال.';

  @override
  String get renameComputerTitle => 'إعادة تسمية الحاسوب';

  @override
  String get invalidDeviceName =>
      'اسم غير صالح: من 1 إلى 64 حرفًا، وبدون رموز تحكم أو فواصل أسطر.';

  @override
  String permissionsNamed(String name) {
    return 'الأذونات · $name';
  }

  @override
  String get currentPermissionTier => 'مستوى الأذونات الحالي';

  @override
  String get requestHigherTier => 'طلب مستوى أعلى';

  @override
  String whatTierAllows(String tier) {
    return 'ما يتيحه مستوى $tier:';
  }

  @override
  String get reasonJustificationOptional => 'السبب / المبرر (اختياري)';

  @override
  String get reasonHint => 'مثال: الحاجة إلى نقل الملفات';

  @override
  String get requestElevation => 'طلب ترقية الأذونات';

  @override
  String get tierReadOnlyTitle => 'عرض فقط';

  @override
  String get tierStandardTitle => 'قياسي';

  @override
  String get tierExtendedTitle => 'موسع';

  @override
  String get tierAdminTitle => 'مسؤول';

  @override
  String get tierReadOnlyDesc =>
      'يتيح عرض حالة النظام، وحالة الوسائط، وبث الشاشة.';

  @override
  String get tierStandardDesc =>
      'يتيح إرسال إدخالات لوحة المفاتيح والفأرة، ومزامنة الحافظة، والتحكم بالوسائط، وعرض هذه الشاشة، ونقل الملفات.';

  @override
  String get tierExtendedDesc =>
      'يتيح تشغيل التطبيقات وتنفيذ الأوامر المسجلة مسبقًا.';

  @override
  String get tierAdminDesc =>
      'يتيح التحكم في الطاقة (إيقاف التشغيل، إعادة التشغيل، وضع السكون، القفل) وإدارة الأجهزة المقترنة.';

  @override
  String connectToRequestElevation(String name) {
    return 'اتصل بـ «$name» لطلب ترقية الأذونات.';
  }

  @override
  String permissionRequestSent(String name) {
    return 'تم إرسال طلب الأذونات إلى «$name».';
  }

  @override
  String get permissionRequestFailed => 'فشل إرسال طلب الأذونات.';

  @override
  String get pointerSensitivity => 'حساسية المؤشر';

  @override
  String get naturalScrollingMatches => 'اتجاه المحتوى يطابق حركة الأصابع';

  @override
  String get tapToClick => 'المس للنقر';

  @override
  String get tapToClickSubtitle =>
      'إصبع واحد للنقر الأيسر، وإصبعان للنقر الأيمن';

  @override
  String get hapticFeedbackDetail =>
      'الاهتزاز عند الإيماءات، ونقرات لوحة المفاتيح، والأزرار';

  @override
  String get syncFromDesktopDetail => 'تلقي ما يتم نسخه على حاسوبك تلقائيًا';

  @override
  String get syncToDesktopDetail =>
      'إرسال حافظة الهاتف عند فتح التطبيق أو الضغط على إرسال';

  @override
  String get historyPersistentSubtitle => 'مشفر ومحفوظ بأمان على هذا الجهاز.';

  @override
  String get historyMemoryOnlySubtitle =>
      'معطل — تظل القائمة في الذاكرة وتختفي عند إغلاق Remote Link.';

  @override
  String get stayConnectedBackground => 'البقاء متصلاً في الخلفية';

  @override
  String get stayConnectedBackgroundSubtitle =>
      'يحافظ على استمرار عمليات النقل عند التبديل بين التطبيقات. يعرض إشعارًا أثناء الاتصال.';

  @override
  String get keepsStoppingQuestion => 'هل يتوقف Remote Link بشكل متكرر؟';

  @override
  String get keepsStoppingSubtitle =>
      'تقوم بعض الهواتف بإغلاقه على أي حال. إليك كيفية إيقاف ذلك.';

  @override
  String get copyInAnyApp => 'انسخ في أي تطبيق، والصق على حاسوبك';

  @override
  String get backgroundClipboardOn =>
      'مفعل. ما تنسخه في أي مكان ينتقل إلى حاسوبك.';

  @override
  String get backgroundClipboardOff =>
      'معطل. يسمح Android بذلك فقط عبر إعدادات إمكانية الوصول.';

  @override
  String get couldNotOpenAccessibility => 'تعذر فتح إعدادات إمكانية الوصول.';

  @override
  String get openSettings => 'فتح الإعدادات';

  @override
  String get accessibilityDialogPara1 =>
      'لا يسمح Android للتطبيق بقراءة الحافظة ما لم يكن هو التطبيق الذي تشاهده حاليًا. لهذا السبب لا يصل النسخ في Chrome إلى حاسوبك تلقائيًا.';

  @override
  String get accessibilityDialogPara2 =>
      'الاستثناء الوحيد هو خدمة إمكانية الوصول، والتي تقوم بتفعيلها بنفسك في إعدادات Android. يستخدمها Remote Link للحافظة فقط: لا يمكنها قراءة شاشتك، ولا ترى ما تكتبه.';

  @override
  String get accessibilityDialogPara3 =>
      'الإعدادات › إمكانية الوصول › Remote Link › تفعيله. ترفض بعض الهواتف القراءة حتى بعد ذلك — إذا لم يصل شيء بعد تفعيله، فهاتفك أحدها.';

  @override
  String get batteryGuidancePara1 =>
      'يوقف Android التطبيقات التي يعتقد أنك لا تستخدمها، وبعض الهواتف أكثر صرامة من غيرها. يطلب Remote Link الاستمرار في العمل، ولكن يمكنك أنت فقط منح هذا الإذن.';

  @override
  String get batteryGuidanceAnyPhone => 'على أي هاتف';

  @override
  String get batteryGuidanceAnyPhoneDesc =>
      'السماح باستخدام البطارية بدون قيود لـ Remote Link.';

  @override
  String get batteryGuidanceXiaomi => 'Xiaomi وRedmi وPOCO';

  @override
  String get batteryGuidanceXiaomiDesc =>
      'الإعدادات › التطبيقات › Remote Link: قم بتشغيل التشغيل التلقائي، واضبط موفر البطارية على بلا قيود. ثم اضغط مطولاً على Remote Link في قائمة التطبيقات الحديثة والمس رمز القفل.';

  @override
  String get batteryGuidanceOther => 'Huawei وOppo وvivo وOnePlus';

  @override
  String get batteryGuidanceOtherDesc =>
      'أضف Remote Link إلى قائمة التطبيقات المحمية أو التشغيل التلقائي في إعدادات البطارية.';

  @override
  String get noBatterySettingsScreen =>
      'لا يحتوي هذا الهاتف على شاشة لإعدادات البطارية لفتحها. ابحث تحت الإعدادات › التطبيقات › Remote Link.';

  @override
  String get stateConnected => 'متصل';

  @override
  String get stateConnecting => 'جارٍ الاتصال…';

  @override
  String get stateReconnecting => 'جارٍ إعادة الاتصال…';

  @override
  String get statePairing => 'جارٍ الاقتران…';

  @override
  String get stateAwaitingApproval => 'بانتظار السماح بالدخول…';

  @override
  String get stateFailed => 'فشل الاتصال';

  @override
  String get routeBonjourUdp => 'Bonjour وإشارة UDP';

  @override
  String get routeBonjour => 'Bonjour (mDNS / DNS-SD)';

  @override
  String get routeUdp => 'إشارة UDP (Multicast)';

  @override
  String get routeManual => 'عنوان يدوي / مخزن';

  @override
  String get licensesButton => 'التراخيص';

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
  String get noTransfersYet => 'لا توجد عمليات نقل بعد';

  @override
  String get transfersEmptyExplanation => 'سيظهر هنا كل ما ترسله أو تستقبله.';

  @override
  String pickerOpenFailed(String error) {
    return 'تعذر فتح منتقي الملفات: $error';
  }

  @override
  String get imageOpenFailed => 'تعذر فتح هذه الصورة.';

  @override
  String get connectedDeviceFallback => 'جهاز متصل';

  @override
  String get defaultAndroidPhoneName => 'هاتف Android';

  @override
  String get defaultPhoneName => 'هاتف';

  @override
  String notificationConnectedTitle(String name) {
    return 'متصل بـ $name';
  }

  @override
  String get notificationConnectedBody =>
      'يحافظ Remote Link على الاتصال مفتوحًا.';

  @override
  String notificationWaitingTitle(String name) {
    return 'في انتظار $name';
  }

  @override
  String notificationWaitingBody(String name) {
    return 'اسمح باستمرار الاتصال على $name.';
  }

  @override
  String get notificationReconnectingBody =>
      'انقطع اتصال Remote Link ويعيد المحاولة.';

  @override
  String get notificationStop => 'إيقاف';

  @override
  String get shareRefused => 'رفض الكمبيوتر استلامه.';

  @override
  String get shareUnexpectedFailure => 'تعذر إرسال المشاركة.';

  @override
  String get exportCancelled => 'لم يُحفظ الملف — أغلقت نافذة المشاركة.';

  @override
  String get exportPermissionDenied =>
      'لا يستطيع Remote Link الإضافة إلى مكتبة الصور. اسمح له بذلك من الإعدادات › Remote Link › الصور، ثم أرسله مجددًا.';

  @override
  String get exportFailed => 'تعذر حفظ الملف على هاتفك.';

  @override
  String get startingService => 'جارٍ تشغيل الخدمة…';

  @override
  String get keyBackspace => 'مسافة للخلف';

  @override
  String get keySwitchToThePhoneKeyboard => 'التبديل إلى لوحة مفاتيح الهاتف';

  @override
  String get keyLeftArrow => 'سهم لليسار';

  @override
  String get keyUpArrow => 'سهم للأعلى';

  @override
  String get keyDownArrow => 'سهم للأسفل';

  @override
  String get keyRightArrow => 'سهم لليمين';

  @override
  String get keyCommand => 'الأمر';

  @override
  String get keyOption => 'الخيار';

  @override
  String get keyControl => 'التحكم';

  @override
  String get keySpace => 'مسافة';

  @override
  String get keyEscape => 'هروب';

  @override
  String get keyDelete => 'حذف';

  @override
  String get keyTab => 'جدولة';

  @override
  String get keyCapsLock => 'قفل الأحرف الكبيرة';

  @override
  String get keyReturn => 'إدخال';

  @override
  String get keyShift => 'تبديل';

  @override
  String get keyAlt => 'بديل';

  @override
  String get keyAltGr => 'بديل رسومي';

  @override
  String get keyWindows => 'ويندوز';

  @override
  String get keyMeta => 'ميتا';

  @override
  String get keyBacktick => 'علامة الاقتباس الخلفية';

  @override
  String get keyMinus => 'ناقص';

  @override
  String get keyEquals => 'يساوي';

  @override
  String get keyLeftBracket => 'قوس مربع أيسر';

  @override
  String get keyRightBracket => 'قوس مربع أيمن';

  @override
  String get keyBackslash => 'شرطة مائلة عكسية';

  @override
  String get keySemicolon => 'فاصلة منقوطة';

  @override
  String get keyApostrophe => 'فاصلة علوية';

  @override
  String get keyComma => 'فاصلة';

  @override
  String get keyFullStop => 'نقطة';

  @override
  String get keySlash => 'شرطة مائلة';

  @override
  String get keyHome => 'بداية';

  @override
  String get keyEnd => 'نهاية';

  @override
  String get keyPageUp => 'صفحة للأعلى';

  @override
  String get keyPageDown => 'صفحة للأسفل';

  @override
  String get keyEnter => 'إدخال';

  @override
  String get transfersTitle => 'عمليات النقل';

  @override
  String get shareTextDescription => 'النص الذي شاركته';

  @override
  String shareFilesDescription(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف',
      many: '$count ملفًا',
      few: '$count ملفات',
      two: 'ملفان',
      one: 'ملف واحد',
      zero: 'لا ملفات',
    );
    return '$_temp0';
  }
}
