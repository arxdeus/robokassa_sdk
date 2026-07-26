/// Enumerations shared by the Robokassa payment and fiscal interfaces.
///
/// Wire values are the strings Robokassa expects in JSON / query parameters.
/// They are kept identical to the official Android SDK
/// (`com.robokassa.library.models`) and iOS SDK (`RobokassaSDK/Models`).
library;

/// Interface language of the Robokassa payment page (`Culture`).
enum Culture {
  /// Russian.
  ru('ru'),

  /// English.
  en('en');

  const Culture(this.wireValue);

  /// Value sent to Robokassa in the `Culture` parameter.
  final String wireValue;

  /// The `RobokassaSDK.Culture` case name used by the **iOS** native SDK.
  ///
  /// Upstream spells the English case `eng` rather than `en`, so the bridge
  /// has to translate. See `Robokassa/Models/Culture.swift`.
  String get iosCaseName => this == Culture.en ? 'eng' : 'ru';

  /// The `com.robokassa.library.models.Culture` name used by the **Android**
  /// native SDK.
  String get androidEnumName => this == Culture.en ? 'EN' : 'RU';

  /// Parses a `Culture` wire value, returning `null` when unrecognised.
  static Culture? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final culture in Culture.values) {
      if (culture.wireValue == normalized) return culture;
    }
    // Tolerate the iOS spelling and full names.
    if (normalized == 'eng' || normalized == 'english') return Culture.en;
    if (normalized == 'rus' || normalized == 'russian') return Culture.ru;
    return null;
  }
}

/// Currency a merchant may price an order in (`OutSumCurrency`).
///
/// When present, Robokassa converts the amount into Russian roubles itself.
enum Currency {
  /// US dollar.
  usd('USD'),

  /// Euro.
  eur('EUR'),

  /// Kazakhstani tenge.
  kzt('KZT'),

  /// Russian rouble.
  rub('RUB');

  const Currency(this.wireValue);

  /// Value sent to Robokassa in the `OutSumCurrency` parameter.
  final String wireValue;

  /// The `com.robokassa.library.models.Currency` name used by Android.
  String get androidEnumName => wireValue;

  /// The `RobokassaSDK.Currency` case name used by iOS (lower-cased).
  String get iosCaseName => wireValue.toLowerCase();

  /// Parses an `OutSumCurrency` value, returning `null` when unrecognised.
  static Currency? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toUpperCase();
    for (final currency in Currency.values) {
      if (currency.wireValue == normalized) return currency;
    }
    return null;
  }
}

/// Taxation system of the merchant (`sno` in the fiscal receipt).
///
/// Optional when the organisation has exactly one taxation system configured
/// in the Robokassa dashboard.
enum TaxSystem {
  /// Общая СН — general taxation system.
  osn('osn'),

  /// Упрощенная СН (доходы) — simplified, income.
  usnIncome('usn_income'),

  /// Упрощенная СН (доходы минус расходы) — simplified, income minus outcome.
  usnIncomeOutcome('usn_income_outcome'),

  /// Единый сельскохозяйственный налог — unified agricultural tax.
  esn('esn'),

  /// Патентная СН — patent taxation system.
  patent('patent');

  const TaxSystem(this.wireValue);

  /// Value serialised into the `sno` field of the receipt JSON.
  final String wireValue;

  /// The Kotlin enum constant name used by the Android SDK.
  String get androidEnumName => switch (this) {
    TaxSystem.osn => 'OSN',
    TaxSystem.usnIncome => 'USN_INCOME',
    TaxSystem.usnIncomeOutcome => 'USN_INCOME_OUTCOME',
    TaxSystem.esn => 'ESN',
    TaxSystem.patent => 'PATENT',
  };

  /// Parses an `sno` value, returning `null` when unrecognised.
  static TaxSystem? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final system in TaxSystem.values) {
      if (system.wireValue == normalized) return system;
    }
    return null;
  }
}

/// VAT rate applied to a receipt line (`tax`).
enum Tax {
  /// Без НДС — not subject to VAT.
  none('none'),

  /// НДС по ставке 0%.
  vat0('vat0'),

  /// НДС по ставке 5%.
  vat5('vat5'),

  /// НДС по ставке 7%.
  vat7('vat7'),

  /// НДС по ставке 10%.
  vat10('vat10'),

  /// НДС по ставке 20%.
  vat20('vat20'),

  /// НДС по ставке 22%.
  vat22('vat22'),

  /// НДС по расчётной ставке 5/105.
  vat105('vat105'),

  /// НДС по расчётной ставке 7/107.
  vat107('vat107'),

  /// НДС по расчётной ставке 10/110.
  vat110('vat110'),

  /// НДС по расчётной ставке 20/120.
  vat120('vat120'),

  /// НДС по расчётной ставке 22/122.
  vat122('vat122');

  const Tax(this.wireValue);

  /// Value serialised into the `tax` field of a receipt item.
  final String wireValue;

  /// The Kotlin enum constant name used by the Android SDK.
  String get androidEnumName =>
      this == Tax.none ? 'NONE' : 'VAT_${wireValue.substring(3)}';

  /// Parses a `tax` value, returning `null` when unrecognised.
  static Tax? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final tax in Tax.values) {
      if (tax.wireValue == normalized) return tax;
    }
    return null;
  }
}

/// Settlement method attribute (`payment_method`) — признак способа расчёта.
enum PaymentMethod {
  /// Предоплата 100%.
  fullPrepayment('full_prepayment'),

  /// Предоплата (частичная).
  prepayment('prepayment'),

  /// Аванс.
  advance('advance'),

  /// Полный расчёт.
  fullPayment('full_payment'),

  /// Частичный расчёт и кредит.
  partialPayment('partial_payment'),

  /// Передача в кредит.
  credit('credit'),

  /// Оплата кредита.
  creditPayment('credit_payment');

  const PaymentMethod(this.wireValue);

  /// Value serialised into the `payment_method` field of a receipt item.
  final String wireValue;

  /// The Kotlin enum constant name used by the Android SDK.
  String get androidEnumName => wireValue.toUpperCase();

  /// Parses a `payment_method` value, returning `null` when unrecognised.
  static PaymentMethod? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final method in PaymentMethod.values) {
      if (method.wireValue == normalized) return method;
    }
    return null;
  }
}

/// Settlement subject attribute (`payment_object`) — признак предмета расчёта.
enum PaymentObject {
  /// Товар.
  commodity('commodity', 'COMMODITY'),

  /// Подакцизный товар.
  excise('excise', 'EXCISE'),

  /// Работа.
  job('job', 'JOB'),

  /// Услуга.
  service('service', 'SERVICE'),

  /// Ставка азартной игры.
  gamblingBet('gambling_bet', 'GAMBLING_BET'),

  /// Выигрыш азартной игры.
  gamblingPrize('gambling_prize', 'GAMBLING_PRIZE'),

  /// Лотерейный билет.
  lottery('lottery', 'LOTTERY'),

  /// Выигрыш лотереи.
  lotteryPrize('lottery_prize', 'LOTTERY_PRIZE'),

  /// Предоставление результатов интеллектуальной деятельности.
  intellectualActivity('intellectual_activity', 'INTELLECTUAL_ACTIVITY'),

  /// Платёж (аванс, задаток, предоплата, кредит, пени, штраф, бонус…).
  payment('payment', 'PAYMENT'),

  /// Агентское вознаграждение.
  agentCommission('agent_commission', 'AGENT_COMMISSION'),

  /// Составной предмет расчёта.
  composite('composite', 'COMPOSITE'),

  /// Курортный сбор.
  resortFee('resort_fee', 'RESORT_FEE'),

  /// Иной предмет расчёта.
  another('another', 'ANOTHER'),

  /// Имущественное право.
  propertyRight('property_right', 'PROPERTY_RIGHT'),

  /// Внереализационный доход.
  ///
  /// The wire value is `operating_gain` while the Kotlin constant is
  /// `NON_OPERATING_GAIN`; both spellings come from upstream.
  nonOperatingGain('operating_gain', 'NON_OPERATING_GAIN'),

  /// Страховые взносы.
  insurancePremium('insurance_premium', 'INSURANCE_PREMIUM'),

  /// Торговый сбор.
  salesTax('sales_tax', 'SALES_TAX');

  const PaymentObject(this.wireValue, this.androidEnumName);

  /// Value serialised into the `payment_object` field of a receipt item.
  final String wireValue;

  /// The Kotlin enum constant name used by the Android SDK.
  final String androidEnumName;

  /// Parses a `payment_object` value, returning `null` when unrecognised.
  static PaymentObject? tryParse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    for (final object in PaymentObject.values) {
      if (object.wireValue == normalized) return object;
    }
    return null;
  }
}
