import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  AppSettings settings = AppSettings(businessName: 'ElectroPowerInt');
  List<Invoice> invoices = [];
  List<Expense> expenses = [];
  List<Reminder> reminders = [];
  List<NoteItem> notes = [];
  List<Client> clients = [];

  String syncStatus = 'Checking...';
  bool isSyncing = false;

  final String firestoreProjectId = 'eppos-41139';

  DocumentReference<Map<String, dynamic>> get _snapDoc =>
      FirebaseFirestore.instance.collection('appdata').doc('snapshot');

  final String _restUrl =
      'https://firestore.googleapis.com/v1/projects/eppos-41139/databases/(default)/documents/appdata/snapshot';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await loadLocalData();
    _initialized = true;
    notifyListeners();

    // Pull from cloud immediately
    await pullFromCloud();

    // Setup real-time listener if Firestore is available
    _setupRealtimeListener();
  }

  void _setupRealtimeListener() {
    try {
      _snapDoc.snapshots().listen(
        (snap) {
          if (snap.exists && snap.data() != null) {
            _parseAndApply(snap.data()!);
          }
        },
        onError: (err) {
          if (kDebugMode) print('Realtime listener notice: $err');
        },
      );
    } catch (e) {
      if (kDebugMode) print('Firestore snapshots not supported on this platform: $e');
    }
  }

  Future<void> loadLocalData() async {
    final setStr = _prefs.getString('nv_settings');
    if (setStr != null) {
      try { settings = AppSettings.fromJson(jsonDecode(setStr)); } catch (_) {}
    }
    final invStr = _prefs.getString('nv_invoices');
    if (invStr != null) {
      try {
        final List list = jsonDecode(invStr);
        invoices = list.map((e) => Invoice.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }
    final expStr = _prefs.getString('nv_expenses');
    if (expStr != null) {
      try {
        final List list = jsonDecode(expStr);
        expenses = list.map((e) => Expense.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }
    final remStr = _prefs.getString('nv_reminders');
    if (remStr != null) {
      try {
        final List list = jsonDecode(remStr);
        reminders = list.map((e) => Reminder.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }
    final notStr = _prefs.getString('nv_notes');
    if (notStr != null) {
      try {
        final List list = jsonDecode(notStr);
        notes = list.map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }
    final cliStr = _prefs.getString('nv_clients');
    if (cliStr != null) {
      try {
        final List list = jsonDecode(cliStr);
        clients = list.map((e) => Client.fromJson(Map<String, dynamic>.from(e))).toList();
      } catch (_) {}
    }
  }

  int get localSavedAt => _prefs.getInt('nv_savedAt') ?? 0;

  Future<void> _markSaved() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _prefs.setInt('nv_savedAt', now);
    notifyListeners();
    _schedulePush();
  }

  void _schedulePush() {
    Future.delayed(const Duration(milliseconds: 1500), () => pushToCloud());
  }

  // ── Invoices & Data CRUD ──────────────────────────────────────────

  Future<void> saveSettings(AppSettings newSettings) async {
    settings = newSettings;
    await _prefs.setString('nv_settings', jsonEncode(settings.toJson()));
    await _markSaved();
  }

  Future<void> saveInvoices() async {
    await _prefs.setString('nv_invoices', jsonEncode(invoices.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  Future<void> addInvoice(Invoice inv) async {
    invoices.insert(0, inv);
    upsertClient(Client(
      name: inv.clientName,
      phone: inv.clientPhone,
      email: inv.clientEmail,
      address: inv.clientAddress,
    ));
    await saveInvoices();
  }

  Future<void> updateInvoice(Invoice inv) async {
    final idx = invoices.indexWhere((i) => i.id == inv.id);
    if (idx != -1) {
      invoices[idx] = inv;
      upsertClient(Client(
        name: inv.clientName,
        phone: inv.clientPhone,
        email: inv.clientEmail,
        address: inv.clientAddress,
      ));
      await saveInvoices();
    }
  }

  Future<void> deleteInvoice(String id) async {
    invoices.removeWhere((i) => i.id == id);
    await saveInvoices();
  }

  /// Adds to whatever was already received; the status flips itself once the total is covered.
  Future<void> applyPayment(String invoiceId, double amount) async {
    final idx = invoices.indexWhere((i) => i.id == invoiceId);
    if (idx == -1) return;
    final inv = invoices[idx];
    final now = DateTime.now().millisecondsSinceEpoch;
    inv.paidAmount = (inv.paidAmount + amount).clamp(0.0, inv.grandTotal);
    inv.status = inv.isFullyPaid ? 'paid' : (inv.isPartiallyPaid ? 'partial' : 'unpaid');
    inv.paidAt = inv.status == 'paid' ? now : null;
    inv.updatedAt = now;
    await saveInvoices();
  }

  /// 'paid' settles the whole invoice; anything else clears it back to full value due.
  Future<void> setInvoiceStatus(String invoiceId, String status) async {
    final idx = invoices.indexWhere((i) => i.id == invoiceId);
    if (idx == -1) return;
    final inv = invoices[idx];
    final now = DateTime.now().millisecondsSinceEpoch;
    final paid = status == 'paid';
    inv.paidAmount = paid ? inv.grandTotal : 0.0;
    inv.status = paid ? 'paid' : 'unpaid';
    inv.paidAt = paid ? now : null;
    inv.updatedAt = now;
    await saveInvoices();
  }

  // Duplicate invoice feature
  Future<void> duplicateInvoice(Invoice inv) async {
    final newNumber = nextInvoiceNumber();
    final dup = Invoice(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      number: newNumber,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      clientName: inv.clientName,
      clientPhone: inv.clientPhone,
      clientEmail: inv.clientEmail,
      clientAddress: inv.clientAddress,
      items: inv.items.map<InvoiceItem>((it) => InvoiceItem(
        name: it.name,
        qty: it.qty,
        price: it.price,
      )).toList(),
      notes: inv.notes,
      discount: inv.discount,
      status: 'unpaid',
    );
    await addInvoice(dup);
  }

  String nextInvoiceNumber() {
    final prefix = settings.prefix.isEmpty ? 'INV' : settings.prefix;
    final regex = RegExp('^${RegExp.escape(prefix)}-(\\d+)\$');
    int maxNum = 0;
    for (final inv in invoices) {
      final m = regex.firstMatch(inv.number);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '0') ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }
    return '$prefix-${(maxNum + 1).toString().padLeft(4, '0')}';
  }

  Future<void> addExpense(Expense exp) async {
    expenses.insert(0, exp);
    await _prefs.setString('nv_expenses', jsonEncode(expenses.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  Future<void> deleteExpense(String id) async {
    expenses.removeWhere((e) => e.id == id);
    await _prefs.setString('nv_expenses', jsonEncode(expenses.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  Future<void> addReminder(Reminder rem) async {
    reminders.insert(0, rem);
    await _prefs.setString('nv_reminders', jsonEncode(reminders.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  Future<void> toggleReminder(String id) async {
    final idx = reminders.indexWhere((r) => r.id == id);
    if (idx != -1) {
      reminders[idx].done = !reminders[idx].done;
      await _prefs.setString('nv_reminders', jsonEncode(reminders.map((e) => e.toJson()).toList()));
      await _markSaved();
    }
  }

  Future<void> deleteReminder(String id) async {
    reminders.removeWhere((r) => r.id == id);
    await _prefs.setString('nv_reminders', jsonEncode(reminders.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  Future<void> addNote(NoteItem note) async {
    notes.insert(0, note);
    await _prefs.setString('nv_notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  Future<void> updateNote(NoteItem note) async {
    final idx = notes.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      notes[idx] = note;
      await _prefs.setString('nv_notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
      await _markSaved();
    }
  }

  Future<void> deleteNote(String id) async {
    notes.removeWhere((n) => n.id == id);
    await _prefs.setString('nv_notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
    await _markSaved();
  }

  void upsertClient(Client c) {
    if (c.name.trim().isEmpty) return;
    final idx = clients.indexWhere((x) => x.name.toLowerCase() == c.name.toLowerCase());
    if (idx != -1) {
      clients[idx] = c;
    } else {
      clients.insert(0, c);
    }
    _prefs.setString('nv_clients', jsonEncode(clients.map((e) => e.toJson()).toList()));
  }

  // ── Cloud Sync Engine ─────────────────────────────────────────────

  /// Web-only keys (history log + whiteboard). The mobile app has no screens for
  /// them, so we carry the cloud's values straight back on every push instead of
  /// dropping them — this doc is replaced wholesale.
  dynamic _webHistory;
  dynamic _webBoard;
  bool _cloudSeen = false;

  Map<String, dynamic> allData() => {
    'settings': settings.toJson(),
    'invoices': invoices.map((e) => e.toJson()).toList(),
    'expenses': expenses.map((e) => e.toJson()).toList(),
    'reminders': reminders.map((e) => e.toJson()).toList(),
    'notes': notes.map((e) => e.toJson()).toList(),
    'history': _webHistory ?? [],
    'board': _webBoard,
    'clients': clients.map((e) => e.toJson()).toList(),
  };

  void _parseAndApply(Map<String, dynamic> d) {
    dynamic raw = d['data'] ?? d['dataRaw'];
    if (raw is String) {
      try { raw = jsonDecode(raw); } catch (_) {}
    }
    if (raw is Map) {
      applyData(Map<String, dynamic>.from(raw));
    }
  }

  void applyData(Map<String, dynamic> d) {
    _cloudSeen = true;
    if (d.containsKey('history')) _webHistory = d['history'];
    if (d.containsKey('board')) _webBoard = d['board'];
    if (d['settings'] != null) {
      final s = AppSettings.fromJson(Map<String, dynamic>.from(d['settings']));
      if (s.businessName.isEmpty) s.businessName = 'ElectroPowerInt';
      settings = s;
      _prefs.setString('nv_settings', jsonEncode(settings.toJson()));
    }
    if (d['invoices'] is List) {
      invoices = (d['invoices'] as List)
          .map((e) => Invoice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _prefs.setString('nv_invoices', jsonEncode(invoices.map((e) => e.toJson()).toList()));
    }
    if (d['expenses'] is List) {
      expenses = (d['expenses'] as List)
          .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _prefs.setString('nv_expenses', jsonEncode(expenses.map((e) => e.toJson()).toList()));
    }
    if (d['reminders'] is List) {
      reminders = (d['reminders'] as List)
          .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _prefs.setString('nv_reminders', jsonEncode(reminders.map((e) => e.toJson()).toList()));
    }
    if (d['notes'] is List) {
      notes = (d['notes'] as List)
          .map((e) => NoteItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _prefs.setString('nv_notes', jsonEncode(notes.map((e) => e.toJson()).toList()));
    }
    if (d['clients'] is List) {
      clients = (d['clients'] as List)
          .map((e) => Client.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _prefs.setString('nv_clients', jsonEncode(clients.map((e) => e.toJson()).toList()));
    }
    notifyListeners();
  }

  Future<bool> pullFromCloud() async {
    isSyncing = true;
    notifyListeners();

    // 1. Try Firestore SDK
    try {
      final snap = await _snapDoc.get();
      if (snap.exists && snap.data() != null) {
        _parseAndApply(snap.data()!);
        syncStatus = 'Synced ✓';
        isSyncing = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      if (kDebugMode) print('Firestore SDK get notice: $e');
    }

    // 2. Direct REST Fallback (100% platform-independent)
    try {
      final res = await http.get(Uri.parse(_restUrl)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final fields = body['fields'];
        if (fields != null) {
          if (fields['dataRaw']?['stringValue'] != null) {
            final raw = jsonDecode(fields['dataRaw']['stringValue']);
            if (raw is Map) {
              applyData(Map<String, dynamic>.from(raw));
              syncStatus = 'Synced ✓';
              isSyncing = false;
              notifyListeners();
              return true;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('REST sync notice: $e');
    }

    syncStatus = 'Offline';
    isSyncing = false;
    notifyListeners();
    return false;
  }

  Future<bool> pushToCloud() async {
    // A push replaces the whole doc, so the cloud's web-only keys must be known first.
    if (!_cloudSeen) {
      final pulled = await pullFromCloud();
      if (!pulled || !_cloudSeen) {
        syncStatus = 'Paused — offline, nothing pushed';
        notifyListeners();
        return false;
      }
    }
    isSyncing = true;
    notifyListeners();

    final all = allData();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Try Firestore SDK
    try {
      final payload = {
        'savedAt': now,
        'data': all,
        'dataRaw': jsonEncode(all),
      };
      await _snapDoc.set(payload);
      syncStatus = 'Synced ✓';
      isSyncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) print('Firestore SDK push notice: $e');
    }

    // 2. Direct REST Fallback
    try {
      final restPayload = {
        'fields': {
          'savedAt': {'integerValue': now.toString()},
          'dataRaw': {'stringValue': jsonEncode(all)},
        }
      };
      final res = await http.patch(
        Uri.parse(_restUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(restPayload),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        syncStatus = 'Synced ✓';
        isSyncing = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      if (kDebugMode) print('REST push notice: $e');
    }

    syncStatus = 'Offline';
    isSyncing = false;
    notifyListeners();
    return false;
  }
}
