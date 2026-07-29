# Robokassa's vendored SDK serialises its parameter and receipt models with
# Gson, which maps JSON keys to *field names* by reflection. Only the enum
# constants carry @SerializedName; the model fields do not, so R8 renaming them
# in a release build silently changes the wire format.
#
# Two things break without this, in release builds only:
#
#   1. The fiscal receipt goes out as {"c":"...","d":1.0,"e":1} instead of
#      {"name":"...","sum":1.0,"quantity":1} (ParamsUtils.payPostParams). That
#      JSON is also concatenated into the SignatureValue pre-image, so the
#      receipt Robokassa fiscalises is garbage.
#   2. The whole PaymentParams graph is round-tripped through SharedPreferences
#      as JSON (RobokassaViewModel -> ParamsUtils.toParams) to resume a payment
#      after the customer returns from an external bank app (SBP, SberPay).
#      Renamed fields make that restore silently produce empty params.
#
# Upstream ships this file empty because its own demo app builds with
# isMinifyEnabled = false, so it never hits either case.
-keepclassmembers class com.robokassa.library.models.** { <fields>; }
-keepclassmembers class com.robokassa.library.params.** { <fields>; }

# Gson resolves enum constants through @SerializedName, which requires both the
# constants and the annotation to survive.
-keepclassmembers enum com.robokassa.library.** { *; }
-keepattributes *Annotation*

# Gson needs generic signatures to deserialise the parameterised fields
# (e.g. Receipt.items : List<ReceiptItem>).
-keepattributes Signature
