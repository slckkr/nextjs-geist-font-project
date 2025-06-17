import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fiş Tarayıcı',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        fontFamily: 'Roboto',
      ),
      home: ReceiptScanner(),
    );
  }
}

class ReceiptData {
  final String id;
  final String imagePath;
  final String firmaIsmi;
  final String tarih;
  final String fisNo;
  final String toplamKDV;
  final String kdvHaricTutar;
  final String genelToplam;
  final Map<String, String> vatRates; // VAT rate -> amount

  ReceiptData({
    required this.id,
    required this.imagePath,
    required this.firmaIsmi,
    required this.tarih,
    required this.fisNo,
    required this.toplamKDV,
    required this.kdvHaricTutar,
    required this.genelToplam,
    required this.vatRates,
  });

  Map<String, dynamic> toMap() {
    return {
      'imagePath': imagePath,
      'firmaIsmi': firmaIsmi,
      'tarih': tarih,
      'fisNo': fisNo,
      'toplamKDV': toplamKDV,
      'kdvHaricTutar': kdvHaricTutar,
      'genelToplam': genelToplam,
      'vatRates': vatRates,
    };
  }

  factory ReceiptData.fromMap(String id, Map<String, dynamic> map) {
    return ReceiptData(
      id: id,
      imagePath: map['imagePath'] ?? '',
      firmaIsmi: map['firmaIsmi'] ?? '',
      tarih: map['tarih'] ?? '',
      fisNo: map['fisNo'] ?? '',
      toplamKDV: map['toplamKDV'] ?? '',
      kdvHaricTutar: map['kdvHaricTutar'] ?? '',
      genelToplam: map['genelToplam'] ?? '',
      vatRates: Map<String, String>.from(map['vatRates'] ?? {}),
    );
  }
}

class ReceiptScanner extends StatefulWidget {
  @override
  _ReceiptScannerState createState() => _ReceiptScannerState();
}

class _ReceiptScannerState extends State<ReceiptScanner> {
  final ImagePicker _picker = ImagePicker();
  String _extractedText = '';
  List<ReceiptData> _receipts = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  Future<void> _loadReceipts() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('receipts').get();
    List<ReceiptData> loaded = snapshot.docs
        .map((doc) => ReceiptData.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList();
    setState(() {
      _receipts = loaded;
    });
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      await _processImage(image.path);
    }
  }

  Future<void> _takePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      await _processImage(image.path);
    }
  }

  Future<void> _processImage(String path) async {
    setState(() {
      _loading = true;
      _extractedText = '';
    });
    String text = await TesseractOcr.extractText(path, language: 'tur');
    setState(() {
      _extractedText = text;
    });
    Map<String, dynamic> data = _extractFields(text);
    data['imagePath'] = path;
    await _saveData(data);
    await _loadReceipts();
    setState(() {
      _loading = false;
    });
  }

  Map<String, dynamic> _extractFields(String text) {
    // Regex patterns for Turkish receipt fields
    String firmaIsmi = _extractFirmaIsmi(text);
    String tarih = _extractTarih(text);
    String fisNo = _extractFisNo(text);
    String toplamKDV = _extractToplamKDV(text);
    String kdvHaricTutar = _extractKdvHaricTutar(text);
    String genelToplam = _extractGenelToplam(text);
    Map<String, String> vatRates = _extractVatRates(text);

    return {
      'firmaIsmi': firmaIsmi,
      'tarih': tarih,
      'fisNo': fisNo,
      'toplamKDV': toplamKDV,
      'kdvHaricTutar': kdvHaricTutar,
      'genelToplam': genelToplam,
      'vatRates': vatRates,
    };
  }

  String _extractFirmaIsmi(String text) {
    RegExp reg = RegExp(r'Firma\s*İsmi\s*[:\-]?\s*(.+)', caseSensitive: false);
    var match = reg.firstMatch(text);
    if (match != null) return match.group(1)!.trim();
    // fallback: first line or other heuristics
    var lines = text.split('\n');
    if (lines.isNotEmpty) return lines[0].trim();
    return '';
  }

  String _extractTarih(String text) {
    RegExp reg = RegExp(r'Tarih\s*[:\-]?\s*(\d{2}[.\-]\d{2}[.\-]\d{4}|\d{4}[.\-]\d{2}[.\-]\d{2})', caseSensitive: false);
    var match = reg.firstMatch(text);
    if (match != null) return match.group(1)!.trim();
    return '';
  }

  String _extractFisNo(String text) {
    RegExp reg = RegExp(r'(FİŞ NO|Fiş No|Belge No)\s*[:\-]?\s*(\S+)', caseSensitive: false);
    var match = reg.firstMatch(text);
    if (match != null) return match.group(2)!.trim();
    return '';
  }

  String _extractToplamKDV(String text) {
    RegExp reg = RegExp(r'Toplam\s*KDV\s*[:\-]?\s*([\d.,]+)', caseSensitive: false);
    var match = reg.firstMatch(text);
    if (match != null) return match.group(1)!.trim();
    return '';
  }

  String _extractKdvHaricTutar(String text) {
    RegExp reg = RegExp(r'KDV\s*Hariç\s*Tutar\s*[:\-]?\s*([\d.,]+)', caseSensitive: false);
    var match = reg.firstMatch(text);
    if (match != null) return match.group(1)!.trim();
    return '';
  }

  String _extractGenelToplam(String text) {
    RegExp reg = RegExp(r'(Genel\s*Toplam|Toplam\s*Tutar)\s*[:\-]?\s*([\d.,]+)', caseSensitive: false);
    var match = reg.firstMatch(text);
    if (match != null) return match.group(2)!.trim();
    return '';
  }

  Map<String, String> _extractVatRates(String text) {
    Map<String, String> vatMap = {};
    List<String> rates = ['1%', '10%', '20%'];
    for (var rate in rates) {
      RegExp reg = RegExp(r'KDV\s*' + RegExp.escape(rate) + r'\s*[:\-]?\s*([\d.,]+)', caseSensitive: false);
      var match = reg.firstMatch(text);
      if (match != null) {
        vatMap[rate] = match.group(1)!.trim();
      }
    }
    return vatMap;
  }

  Future<void> _saveData(Map<String, dynamic> data) async {
    await FirebaseFirestore.instance.collection('receipts').add(data);
  }

  Future<void> _exportCSV() async {
    List<List<String>> rows = [
      [
        'Firma İsmi',
        'Tarih',
        'Fiş No',
        'Toplam KDV',
        'KDV Hariç Tutar',
        'Genel Toplam',
        'VAT 1%',
        'VAT 10%',
        'VAT 20%',
      ]
    ];
    for (var receipt in _receipts) {
      rows.add([
        receipt.firmaIsmi,
        receipt.tarih,
        receipt.fisNo,
        receipt.toplamKDV,
        receipt.kdvHaricTutar,
        receipt.genelToplam,
        receipt.vatRates['1%'] ?? '',
        receipt.vatRates['10%'] ?? '',
        receipt.vatRates['20%'] ?? '',
      ]);
    }
    String csvData = const ListToCsvConverter().convert(rows);
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/receipts_export.csv';
    final file = File(path);
    await file.writeAsString(csvData);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV exported to $path')));
  }

  void _editReceipt(ReceiptData receipt) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditReceiptScreen(receipt: receipt),
      ),
    ).then((value) {
      if (value == true) {
        _loadReceipts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fiş Tarayıcı'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download),
            onPressed: _exportCSV,
            tooltip: 'Export CSV',
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _pickImage,
                        child: Text('Galeriden Resim Yükle'),
                      ),
                      SizedBox(width: 20),
                      ElevatedButton(
                        onPressed: _takePhoto,
                        child: Text('Fotoğraf Çek'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: Text('Görsel')),
                        DataColumn(label: Text('Firma İsmi')),
                        DataColumn(label: Text('Tarih')),
                        DataColumn(label: Text('Fiş No')),
                        DataColumn(label: Text('Toplam KDV')),
                        DataColumn(label: Text('KDV Hariç Tutar')),
                        DataColumn(label: Text('Genel Toplam')),
                        DataColumn(label: Text('Düzenle')),
                      ],
                      rows: _receipts
                          .map(
                            (receipt) => DataRow(
                              cells: [
                                DataCell(
                                  Image.file(
                                    File(receipt.imagePath),
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                DataCell(Text(receipt.firmaIsmi)),
                                DataCell(Text(receipt.tarih)),
                                DataCell(Text(receipt.fisNo)),
                                DataCell(Text(receipt.toplamKDV)),
                                DataCell(Text(receipt.kdvHaricTutar)),
                                DataCell(Text(receipt.genelToplam)),
                                DataCell(
                                  IconButton(
                                    icon: Icon(Icons.edit),
                                    onPressed: () => _editReceipt(receipt),
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class EditReceiptScreen extends StatefulWidget {
  final ReceiptData receipt;

  EditReceiptScreen({required this.receipt});

  @override
  _EditReceiptScreenState createState() => _EditReceiptScreenState();
}

class _EditReceiptScreenState extends State<EditReceiptScreen> {
  late TextEditingController firmaController;
  late TextEditingController tarihController;
  late TextEditingController fisNoController;
  late TextEditingController toplamKDVController;
  late TextEditingController kdvHaricTutarController;
  late TextEditingController genelToplamController;

  @override
  void initState() {
    super.initState();
    firmaController = TextEditingController(text: widget.receipt.firmaIsmi);
    tarihController = TextEditingController(text: widget.receipt.tarih);
    fisNoController = TextEditingController(text: widget.receipt.fisNo);
    toplamKDVController = TextEditingController(text: widget.receipt.toplamKDV);
    kdvHaricTutarController = TextEditingController(text: widget.receipt.kdvHaricTutar);
    genelToplamController = TextEditingController(text: widget.receipt.genelToplam);
  }

  @override
  void dispose() {
    firmaController.dispose();
    tarihController.dispose();
    fisNoController.dispose();
    toplamKDVController.dispose();
    kdvHaricTutarController.dispose();
    genelToplamController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    await FirebaseFirestore.instance.collection('receipts').doc(widget.receipt.id).update({
      'firmaIsmi': firmaController.text,
      'tarih': tarihController.text,
      'fisNo': fisNoController.text,
      'toplamKDV': toplamKDVController.text,
      'kdvHaricTutar': kdvHaricTutarController.text,
      'genelToplam': genelToplamController.text,
    });
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fişi Düzenle'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: firmaController,
              decoration: InputDecoration(labelText: 'Firma İsmi'),
            ),
            TextField(
              controller: tarihController,
              decoration: InputDecoration(labelText: 'Tarih'),
            ),
            TextField(
              controller: fisNoController,
              decoration: InputDecoration(labelText: 'Fiş No'),
            ),
            TextField(
              controller: toplamKDVController,
              decoration: InputDecoration(labelText: 'Toplam KDV'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: kdvHaricTutarController,
              decoration: InputDecoration(labelText: 'KDV Hariç Tutar'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: genelToplamController,
              decoration: InputDecoration(labelText: 'Genel Toplam'),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveChanges,
              child: Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}
