import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import 'storage_service.dart';

class PdfService {
  static Future<Uint8List> generateInvoicePdf(Invoice inv) async {
    final pdf = pw.Document();
    final settings = StorageService().settings;
    final currency = settings.currency.trim().isEmpty ? 'Rs' : settings.currency.trim();
    final rowCount = settings.invoiceRows < 7 ? 7 : settings.invoiceRows;

    final dateStr = DateFormat('dd/MM/yyyy').format(
      DateTime.fromMillisecondsSinceEpoch(inv.createdAt),
    );

    // Font setup: serif for title, italic script, signature; sans-serif for content
    pw.Font fontSansNormal;
    pw.Font fontSansBold;
    pw.Font fontSerif;
    pw.Font fontSerifItalic;

    try {
      fontSansNormal = await PdfGoogleFonts.robotoRegular();
      fontSansBold = await PdfGoogleFonts.robotoBold();
      fontSerif = await PdfGoogleFonts.playfairDisplayRegular();
      fontSerifItalic = await PdfGoogleFonts.playfairDisplayItalic();
    } catch (_) {
      fontSansNormal = pw.Font.helvetica();
      fontSansBold = pw.Font.helveticaBold();
      fontSerif = pw.Font.times();
      fontSerifItalic = pw.Font.timesItalic();
    }

    // Palette identical to web app PDF (app.js buildInvoicePDF)
    final colorDark = PdfColor.fromHex('#141414');
    final colorBlack = PdfColor.fromHex('#181818');
    final colorMuted = PdfColor.fromHex('#3c3c3c');
    final colorDate = PdfColor.fromHex('#5a5a5a');
    final colorPayInfo = PdfColor.fromHex('#464646');
    final colorAddress = PdfColor.fromHex('#505050');
    final colorBorderLine = PdfColor.fromHex('#c8c8c8');
    final colorDash = PdfColor.fromHex('#a0a0a0');

    // Decode logo if present
    Uint8List? logoBytes;
    if (settings.logo.trim().isNotEmpty) {
      try {
        final logoStr = settings.logo.trim();
        final commaIdx = logoStr.indexOf(',');
        final base64Part = commaIdx != -1 ? logoStr.substring(commaIdx + 1) : logoStr;
        logoBytes = base64Decode(base64Part.trim());
      } catch (e) {
        if (kDebugMode) print('Logo decode error: $e');
      }
    }

    // Client lines: name, phone, address lines, email (exact web app order)
    final List<String> clLines = [];
    if (inv.clientName.trim().isNotEmpty) clLines.add(inv.clientName.trim());
    if (inv.clientPhone.trim().isNotEmpty) clLines.add(inv.clientPhone.trim());
    if (inv.clientAddress.trim().isNotEmpty) {
      for (final l in inv.clientAddress.split('\n')) {
        final t = l.trim();
        if (t.isNotEmpty) clLines.add(t);
      }
    }
    if (inv.clientEmail.trim().isNotEmpty) clLines.add(inv.clientEmail.trim());

    // Prepare table rows (real items + dashed placeholder rows)
    const dash = '------';
    final List<List<String>> tableData = [];
    final activeItems = inv.items.where((it) => it.name.trim().isNotEmpty).toList();

    for (final it in activeItems) {
      final qtyStr = it.qty.toStringAsFixed(it.qty.truncateToDouble() == it.qty ? 0 : 2);
      tableData.add([
        it.name.trim(),
        qtyStr,
        '$currency ${it.price.toStringAsFixed(0)}',
        '$currency ${it.total.toStringAsFixed(0)}',
      ]);
    }

    // Pad with placeholder dashed rows up to rowCount
    while (tableData.length < rowCount) {
      tableData.add([dash, dash, dash, dash]);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 42, vertical: 38),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // 1. TOP HEADER: Logo (Left) & "Invoice" Serif Title (Right)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Logo / Brand Emblem
                  if (logoBytes != null)
                    pw.Container(
                      width: 60,
                      height: 46,
                      alignment: pw.Alignment.topLeft,
                      child: pw.Image(
                        pw.MemoryImage(logoBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    )
                  else
                    pw.Container(
                      height: 46,
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        settings.businessName.isNotEmpty ? settings.businessName : 'Business',
                        style: pw.TextStyle(
                          font: fontSerif,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: colorDark,
                        ),
                      ),
                    ),

                  // "Invoice" Title
                  pw.Text(
                    'Invoice',
                    style: pw.TextStyle(
                      font: fontSerif,
                      fontSize: 34,
                      color: colorDark,
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 24),

              // 2. BILLED TO (Left) & INVOICE NO / DATE (Right)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Billed to details
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Billed to:',
                        style: pw.TextStyle(
                          font: fontSansBold,
                          fontSize: 9.5,
                          color: colorDark,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      ...clLines.asMap().entries.map((entry) {
                        final i = entry.key;
                        final line = entry.value;
                        if (i == 0) {
                          return pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2),
                            child: pw.Text(
                              line,
                              style: pw.TextStyle(
                                font: fontSansBold,
                                fontSize: 9,
                                color: colorBlack,
                              ),
                            ),
                          );
                        }
                        return pw.Padding(
                          padding: const pw.EdgeInsets.only(bottom: 1.5),
                          child: pw.Text(
                            line,
                            style: pw.TextStyle(
                              font: fontSansNormal,
                              fontSize: 8.5,
                              color: colorMuted,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),

                  // Right: Invoice No. & Date
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Invoice No. ${inv.number.isNotEmpty ? inv.number : '12345'}',
                        style: pw.TextStyle(
                          font: fontSansNormal,
                          fontSize: 9,
                          color: colorDark,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        dateStr,
                        style: pw.TextStyle(
                          font: fontSansNormal,
                          fontSize: 9,
                          color: colorDate,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              pw.SizedBox(height: 18),

              // 3. ITEMS TABLE
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder(
                  bottom: pw.BorderSide(color: colorBorderLine, width: 0.6),
                  horizontalInside: pw.BorderSide(color: colorBorderLine, width: 0.6),
                ),
                headerDecoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: colorBlack, width: 1.8),
                  ),
                ),
                headerStyle: pw.TextStyle(
                  font: fontSansBold,
                  fontSize: 9.5,
                  color: const PdfColor(0.06, 0.06, 0.06),
                ),
                cellStyle: pw.TextStyle(
                  font: fontSansNormal,
                  fontSize: 9,
                  color: const PdfColor(0.12, 0.12, 0.12),
                ),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 7.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(4.5),
                  1: const pw.FixedColumnWidth(70),
                  2: const pw.FixedColumnWidth(85),
                  3: const pw.FixedColumnWidth(85),
                },
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headers: ['Item', 'Quantity', 'Unit Price', 'Total'],
                data: tableData,
                cellFormat: (col, val) => val,
                // Color dashed placeholder cells with lighter color identical to web
                cellBuilder: (col, val, row) {
                  final isDash = val == dash;
                  pw.Alignment align = pw.Alignment.centerLeft;
                  if (col == 1) align = pw.Alignment.center;
                  if (col == 2 || col == 3) align = pw.Alignment.centerRight;

                  return pw.Container(
                    alignment: align,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 7.5),
                    child: pw.Text(
                      val,
                      style: pw.TextStyle(
                        font: fontSansNormal,
                        fontSize: 9,
                        color: isDash ? colorDash : const PdfColor(0.12, 0.12, 0.12),
                      ),
                    ),
                  );
                },
              ),

              pw.SizedBox(height: 16),

              // 4. SUBTOTAL & TOTAL SUMMARY BLOCK
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 215,
                    child: pw.Column(
                      children: [
                        // Subtotal
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'Subtotal',
                                style: pw.TextStyle(font: fontSansBold, fontSize: 9, color: colorBlack),
                              ),
                              pw.Text(
                                '$currency ${inv.subtotal.toStringAsFixed(0)}',
                                style: pw.TextStyle(font: fontSansBold, fontSize: 9, color: colorBlack),
                              ),
                            ],
                          ),
                        ),

                        // Discount (if any)
                        if (inv.calculatedDiscount > 0) ...[
                          pw.SizedBox(height: 3),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(
                                  'Discount',
                                  style: pw.TextStyle(font: fontSansBold, fontSize: 9, color: colorBlack),
                                ),
                                pw.Text(
                                  '- $currency ${inv.calculatedDiscount.toStringAsFixed(0)}',
                                  style: pw.TextStyle(font: fontSansBold, fontSize: 9, color: colorBlack),
                                ),
                              ],
                            ),
                          ),
                        ],

                        pw.SizedBox(height: 6),

                        // Dark Total Badge
                        pw.Container(
                          height: 25,
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10),
                          decoration: pw.BoxDecoration(
                            color: colorBlack,
                            borderRadius: pw.BorderRadius.circular(2),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                'Total',
                                style: pw.TextStyle(
                                  font: fontSansBold,
                                  fontSize: 11,
                                  color: PdfColors.white,
                                ),
                              ),
                              pw.Text(
                                '$currency ${inv.grandTotal.toStringAsFixed(0)}',
                                style: pw.TextStyle(
                                  font: fontSansBold,
                                  fontSize: 11,
                                  color: PdfColors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.Spacer(),

              // 5. BOTTOM AREA: "Thank You!" script + Payment Info + Business signature
              pw.Text(
                'Thank You!',
                style: pw.TextStyle(
                  font: fontSerifItalic,
                  fontSize: 26,
                  color: colorBlack,
                ),
              ),

              pw.SizedBox(height: 14),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left: Payment Information
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Payment Information',
                        style: pw.TextStyle(
                          font: fontSansBold,
                          fontSize: 9,
                          color: colorBlack,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      if (inv.notes.trim().isNotEmpty)
                        pw.Text(
                          inv.notes.trim(),
                          style: pw.TextStyle(
                            font: fontSansNormal,
                            fontSize: 8,
                            color: colorPayInfo,
                          ),
                        )
                      else ...[
                        pw.Text(
                          settings.businessName.isNotEmpty ? settings.businessName : 'Business',
                          style: pw.TextStyle(
                            font: fontSansNormal,
                            fontSize: 8,
                            color: colorPayInfo,
                          ),
                        ),
                        if (settings.phone.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 1),
                          pw.Text(
                            'Contact: ${settings.phone.trim()}',
                            style: pw.TextStyle(
                              font: fontSansNormal,
                              fontSize: 8,
                              color: colorPayInfo,
                            ),
                          ),
                        ],
                        if (settings.email.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 1),
                          pw.Text(
                            'Email: ${settings.email.trim()}',
                            style: pw.TextStyle(
                              font: fontSansNormal,
                              fontSize: 8,
                              color: colorPayInfo,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),

                   // Right: Signature Name (Serif) + "Proprietor" label
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        settings.signName.trim().isNotEmpty
                            ? settings.signName.trim()
                            : (settings.businessName.trim().isNotEmpty
                                ? settings.businessName.trim()
                                : 'Juliana Silva'),
                        style: pw.TextStyle(
                          font: fontSerif,
                          fontSize: 15,
                          color: colorDark,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'Proprietor',
                        style: pw.TextStyle(
                          font: fontSansNormal,
                          fontSize: 8,
                          color: colorAddress,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // Native PDF Share (sends ONLY the PDF file, no text message)
  static Future<void> sharePdfOnly(Invoice inv) async {
    final bytes = await generateInvoicePdf(inv);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${inv.number}.pdf',
    );
  }

  // Print or Preview
  static Future<void> printPdf(Invoice inv) async {
    final bytes = await generateInvoicePdf(inv);
    await Printing.layoutPdf(onLayout: (_) => bytes, name: '${inv.number}.pdf');
  }

  // ── Summary / P&L report (same content as the web app's reportPDF) ──────
  static Future<Uint8List> generateReportPdf(ReportSummary s) async {
    final settings = StorageService().settings;
    final currency = settings.currency.trim().isEmpty ? 'Rs' : settings.currency.trim();
    final biz = settings.businessName.trim().isEmpty ? 'ElectroPowerInt' : settings.businessName.trim();

    final brand = PdfColor.fromHex('#2563eb');
    final ink = PdfColor.fromHex('#0f172a');
    final muted = PdfColor.fromHex('#64748b');
    final bannerSub = PdfColor.fromHex('#dbeafe');
    final headBg = PdfColor.fromHex('#eff6ff');
    final headFg = PdfColor.fromHex('#1d4ed8');
    final lineCol = PdfColor.fromHex('#dbe4f0');

    String money(double v) => '$currency ${v.toStringAsFixed(0)}';

    final border = pw.TableBorder(
      horizontalInside: pw.BorderSide(color: lineCol, width: 0.5),
      bottom: pw.BorderSide(color: lineCol, width: 0.5),
    );

    // Same font strategy as the invoice PDF so symbols outside Latin-1 render.
    pw.Font sans;
    pw.Font sansBold;
    try {
      sans = await PdfGoogleFonts.robotoRegular();
      sansBold = await PdfGoogleFonts.robotoBold();
    } catch (_) {
      sans = pw.Font.helvetica();
      sansBold = pw.Font.helveticaBold();
    }
    final cellStyle = pw.TextStyle(font: sans, fontSize: 10, color: ink);
    final headStyle = pw.TextStyle(font: sansBold, fontSize: 9.5, color: headFg);

    pw.Widget heading(String text) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 22, bottom: 8),
      child: pw.Text(text, style: pw.TextStyle(font: sansBold, fontSize: 12, color: ink)),
    );

    pw.Widget emptyNote(String text) =>
        pw.Text(text, style: pw.TextStyle(font: sans, fontSize: 9.5, color: muted));

    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (_) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              color: brand,
              padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Summary Report',
                    style: pw.TextStyle(font: sansBold, fontSize: 19, color: PdfColor.fromHex('#ffffff')),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text('${s.periodLabel}  ·  $biz', style: pw.TextStyle(font: sans, fontSize: 10.5, color: bannerSub)),
                ],
              ),
            ),
            pw.SizedBox(height: 22),
            pw.TableHelper.fromTextArray(
              border: border,
              headerDecoration: pw.BoxDecoration(color: headBg),
              headerStyle: headStyle,
              cellStyle: cellStyle,
              cellAlignments: const {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.6)},
              headers: const ['Metric', 'Value'],
              data: <List<String>>[
                ['Revenue (amounts received)', money(s.revenue)],
                ['Total invoiced in period', money(s.invoiced)],
                ['Invoices in period', '${s.invCount}'],
                ['Fully paid invoices', '${s.paidCount}'],
                ['Unpaid / partial invoices', '${s.openCount}'],
                ['Outstanding (not yet received)', money(s.outstanding)],
                ['Total expenses', money(s.expenses)],
                ['Net profit (revenue - expenses)', money(s.profit)],
                ['Expenses recorded', '${s.expCount}'],
              ],
            ),
            heading('Top clients'),
            if (s.topClients.isEmpty)
              emptyNote('No payments received in this period.')
            else
              pw.TableHelper.fromTextArray(
                border: border,
                headerDecoration: pw.BoxDecoration(color: headBg),
                headerStyle: headStyle,
                cellStyle: cellStyle,
                cellAlignments: const {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
                columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1), 2: pw.FlexColumnWidth(1.6)},
                headers: const ['Client', 'Invoices', 'Received'],
                data: s.topClients.map((c) => <String>[c.name, '${c.count}', money(c.value)]).toList(),
              ),
            heading('Expenses by category'),
            if (s.expenseCats.isEmpty)
              emptyNote('No expense recorded in this period.')
            else
              pw.TableHelper.fromTextArray(
                border: border,
                headerDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#fffbeb')),
                headerStyle: pw.TextStyle(font: sansBold, fontSize: 9.5, color: PdfColor.fromHex('#b45309')),
                cellStyle: cellStyle,
                cellAlignments: const {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
                columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.6)},
                headers: const ['Category', 'Amount'],
                data: s.expenseCats.map((c) => <String>[c.name, money(c.value)]).toList(),
              ),
            pw.SizedBox(height: 26),
            emptyNote(
              'Generated with $biz · ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
            ),
          ],
        );
      },
    ));
    return doc.save();
  }

  static Future<void> openReportPdf(ReportSummary s) async {
    final bytes = await generateReportPdf(s);
    final name = 'report-${s.periodLabel.replaceAll(RegExp('[^A-Za-z0-9]+'), '-').replaceAll(RegExp('^-|-\$'), '')}.pdf';
    await Printing.layoutPdf(onLayout: (_) => bytes, name: name);
  }

  static Future<void> shareReportPdf(ReportSummary s) async {
    final bytes = await generateReportPdf(s);
    await Printing.sharePdf(bytes: bytes, filename: 'report.pdf');
  }
}

// ── Report payload handed to generateReportPdf ─────────────────────────────
class NamedValue {
  final String name;
  final double value;
  final int count;
  const NamedValue(this.name, this.value, [this.count = 0]);
}

class ReportSummary {
  final String periodLabel;
  final double revenue;
  final double invoiced;
  final int invCount;
  final double outstanding;
  final double expenses;
  final double profit;
  final int paidCount;
  final int openCount;
  final int expCount;
  final List<NamedValue> topClients;
  final List<NamedValue> expenseCats;

  const ReportSummary({
    required this.periodLabel,
    required this.revenue,
    required this.invoiced,
    required this.invCount,
    required this.outstanding,
    required this.expenses,
    required this.profit,
    required this.paidCount,
    required this.openCount,
    required this.expCount,
    required this.topClients,
    required this.expenseCats,
  });
}
