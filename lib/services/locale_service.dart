import 'dart:ui' as ui;

/// Locale for dictionary selection.
enum DictionaryLocale { us, uk }

/// Service for detecting user's locale and selecting appropriate dictionary.
class LocaleService {
  const LocaleService();

  /// Determine which dictionary to use based on system locale.
  ///
  /// Returns [DictionaryLocale.uk] for British English locales
  /// (GB, UK, IE, AU, NZ), [DictionaryLocale.us] for everything else.
  DictionaryLocale detectDictionaryLocale() {
    final locale = ui.PlatformDispatcher.instance.locale;

    if (locale.languageCode == 'en') {
      final country = locale.countryCode?.toUpperCase();
      if (country == 'GB' ||
          country == 'UK' ||
          country == 'IE' || // Ireland
          country == 'AU' || // Australia
          country == 'NZ') {
        // New Zealand
        return DictionaryLocale.uk;
      }
    }

    // Default to US English
    return DictionaryLocale.us;
  }
}
