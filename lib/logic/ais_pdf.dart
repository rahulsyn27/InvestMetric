import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/member.dart';
import 'ais_parser.dart';

enum AisPdfError { needsPassword, wrongPassword, unreadable }

class AisPdfException implements Exception {
  const AisPdfException(this.error, [this.detail]);

  final AisPdfError error;
  final Object? detail;

  String get message => switch (error) {
    AisPdfError.needsPassword => 'This PDF is password protected.',
    AisPdfError.wrongPassword =>
      'Wrong password. It is the PAN in small letters followed by the date '
          'of birth as DDMMYYYY, e.g. abcde1234f01011970.',
    AisPdfError.unreadable => 'Couldn\'t read this file. Is it the AIS PDF?',
  };

  @override
  String toString() => 'AisPdfException($error, $detail)';
}

/// The AIS PDF password the portal uses: PAN (lower case) + DOB (DDMMYYYY).
String? aisPasswordFor(Member m) {
  final dob = m.dateOfBirth;
  if (m.pan.isEmpty || dob == null) return null;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${m.pan.toLowerCase()}${two(dob.day)}${two(dob.month)}${dob.year}';
}

/// Opens the (password-protected) AIS PDF and reads its words with positions.
List<PdfWord> readPdfWords(Uint8List bytes, {String? password}) {
  final PdfDocument doc;
  try {
    doc = (password == null || password.isEmpty)
        ? PdfDocument(inputBytes: bytes)
        : PdfDocument(inputBytes: bytes, password: password);
  } on ArgumentError catch (e) {
    final msg = e.message.toString().toLowerCase();
    if (msg.contains('password')) {
      throw AisPdfException(
        (password == null || password.isEmpty)
            ? AisPdfError.needsPassword
            : AisPdfError.wrongPassword,
        e,
      );
    }
    throw AisPdfException(AisPdfError.unreadable, e);
  } catch (e) {
    throw AisPdfException(AisPdfError.unreadable, e);
  }
  try {
    final lines = PdfTextExtractor(doc).extractTextLines();
    final words = <PdfWord>[];
    for (final line in lines) {
      for (final w in line.wordCollection) {
        final t = w.text.trim();
        if (t.isEmpty) continue;
        words.add(
          PdfWord(
            t,
            w.bounds.left,
            w.bounds.top,
            width: w.bounds.width,
            height: w.bounds.height <= 0 ? 8 : w.bounds.height,
            page: line.pageIndex,
          ),
        );
      }
    }
    return words;
  } catch (e) {
    throw AisPdfException(AisPdfError.unreadable, e);
  } finally {
    doc.dispose();
  }
}

/// Opens and parses an AIS PDF.
AisParseResult readAisPdf(Uint8List bytes, {String? password}) =>
    parseAis(groupIntoLines(readPdfWords(bytes, password: password)));
