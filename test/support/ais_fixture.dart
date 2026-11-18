import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Password of the fixture: PAN "ABCDE1234F" + DOB 01/01/1960.
const fixturePassword = 'abcde1234f01011960';

/// Builds an encrypted PDF laid out like the AIS from the e-filing portal
/// (made-up data), to test the reader end to end.
Uint8List buildAisFixturePdf({String password = fixturePassword}) {
  final doc = PdfDocument();
  final page = doc.pages.add();
  final g = page.graphics;
  final f = PdfStandardFont(PdfFontFamily.helvetica, 7);
  final big = PdfStandardFont(PdfFontFamily.helvetica, 30);

  void row(double y, List<(double, String)> cells, [PdfFont? font]) {
    for (final (x, text) in cells) {
      g.drawString(text, font ?? f, bounds: Rect.fromLTWH(x, y, 300, 12));
    }
  }

  const infoHeader = [
    (0.0, 'SR. NO.'),
    (24.0, 'INFORMATION CODE'),
    (148.0, 'INFORMATION DESCRIPTION'),
    (279.0, 'INFORMATION SOURCE'),
    (440.0, 'COUNT'),
    (490.0, 'AMOUNT'),
  ];
  const detailHeader = [
    (0.0, 'SR. NO.'),
    (24.0, 'QUARTER'),
    (139.0, 'DATE OF PAYMENT/CREDIT'),
    (262.0, 'AMOUNT PAID/CREDITED'),
    (360.0, 'TDS DEDUCTED'),
    (420.0, 'TDS DEPOSITED'),
    (480.0, 'STATUS'),
  ];
  List<(double, String)> detail(
    String n,
    String q,
    String d,
    String a,
    String tds,
  ) => [
    (2, n),
    (24, q),
    (139, d),
    (300, a),
    (380, tds),
    (440, tds),
    (480, 'Active'),
  ];

  row(0, [
    (0, 'Annual Information Statement (AIS - Form 168)'),
    (400, 'Tax Year (T.Y.)'),
    (470, '2026-27'),
  ]);
  row(30, [(0, 'Part A - General Information')]);
  row(45, [(0, 'Name of Assessee'), (300, 'Date of Birth')]);
  row(55, [(0, 'TEST PERSON'), (300, '01/01/1960')]);
  row(80, [
    (0, 'Part B1-Information relating to tax deducted or collected at source'),
  ]);
  row(95, [(0, 'Salary')]);
  row(110, infoHeader);
  row(122, [
    (2, '1'),
    (24, 'TDS-392'),
    (148, 'Salary received (Section 392)'),
    (279, 'ACME STEEL LIMITED (MUMA12345B)'),
    (450, '2'),
    (490, '3,64,812'),
  ]);
  row(134, detailHeader);
  row(146, detail('1', 'Q2(Jul-Sep)', '30/09/2026', '1,79,900', '17,483'));
  row(158, detail('2', 'Q1(Apr-Jun)', '30/06/2026', '1,84,912', '16,803'));
  row(180, [(0, 'Interest from deposits')]);
  row(195, infoHeader);
  row(207, [
    (2, '1'),
    (24, 'TDS-393'),
    (148, 'Interest other than interest on'),
    (279, 'STATE BANK OF INDIA'),
    (450, '2'),
    (490, '17,750'),
  ]);
  row(217, [(148, 'securities (Section 393)'), (279, '(BLRS12345C)')]);
  row(229, detailHeader);
  row(241, detail('1', 'Q2(Jul-Sep)', '30/09/2026', '8,875', '888'));
  row(253, detail('2', 'Q1(Apr-Jun)', '30/06/2026', '8,875', '887'));
  // Watermark across the table, as on the real statement.
  row(236, [(120, 'INCOME TAX DEPARTMENT')], big);
  row(275, [
    (
      0,
      'Note - If there is variation between the TDS/TCS information as displayed in Form26AS',
    ),
  ]);
  row(300, [
    (
      0,
      'Part B2-Information relating to specified financial transaction (SFT)',
    ),
  ]);
  row(315, infoHeader);
  row(327, [
    (2, '1'),
    (24, 'SFT-016(SB)'),
    (148, 'Interest income'),
    (279, 'CANARA BANK (BLRC00001A)'),
    (450, '1'),
    (490, '2,340'),
  ]);
  row(350, [(0, 'Part B3-Information relating to payment of taxes')]);
  row(365, [
    (0, 'SR. NO.'),
    (24, 'FINANCIAL YEAR'),
    (80, 'MAJOR HEAD'),
    (120, 'MINOR HEAD'),
    (160, 'TAX (A)'),
  ]);
  row(377, [
    (2, '1'),
    (24, '2026-27'),
    (80, '0021'),
    (120, '100'),
    (160, '15,000'),
    (200, '0'),
    (230, '0'),
    (260, '0'),
    (290, '15,000'),
    (330, '0510308'),
    (380, '14/09/2026'),
    (430, '12345'),
  ]);
  row(400, [(0, 'Part B4-Information relating to demand and refund')]);
  row(412, [(0, 'Refund')]);
  row(424, [
    (0, 'SR. NO.'),
    (24, 'FINANCIAL YEAR'),
    (120, 'MODE'),
    (200, 'NATURE OF REFUND'),
    (340, 'REFUND AMOUNT'),
    (420, 'DATE OF PAYMENT'),
  ]);
  row(436, [
    (2, '1'),
    (24, '2025-26'),
    (120, 'ECS'),
    (200, 'ECS (direct credit to bank account)'),
    (360, '61,480'),
    (420, '30/10/2026'),
  ]);

  doc.security.userPassword = password;
  doc.security.algorithm = PdfEncryptionAlgorithm.aesx256Bit;
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}
