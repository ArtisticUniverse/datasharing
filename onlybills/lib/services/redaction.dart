/// Client-side redaction of personal identifiers. The server re-applies the same
/// patterns (functions/rules.js redact) so a modified client cannot skip it.
class Redactor {
  static final _rules = <(RegExp, String)>[
    (RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b'), '[AADHAAR]'),
    (RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b'), '[PAN]'),
    (RegExp(r'\b(?:\d[ -]?){13,19}\b'), '[CARD/ACCOUNT]'),
    (RegExp(r'\b(?:\+91[\s-]?)?[6-9]\d{9}\b'), '[PHONE]'),
    (RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), '[EMAIL]'),
    (RegExp(r'\b(?:UHID|MRN|IP\s?No|Patient\s?ID|Reg\.?\s?No)[:#.\s]*[\w/-]+', caseSensitive: false), '[PATIENT-ID]'),
    (RegExp(r'\b(?:A/?C|Account)\s*(?:No\.?)?[:#\s]*\d+', caseSensitive: false), '[ACCOUNT]'),
    (RegExp(r'\b\d{6}\b(?=\s*$|\s*[,\n])', multiLine: true), '[PIN]'),
  ];

  static String redact(String text) =>
      _rules.fold(text, (t, r) => t.replaceAll(r.$1, r.$2));
}
