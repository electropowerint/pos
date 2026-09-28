class AppSettings {
  String businessName;
  String email;
  String phone;
  String address;
  String website;
  String currency;
  String prefix;
  String signName;
  String logo;
  int invoiceRows;

  AppSettings({
    this.businessName = 'ElectroPowerInt',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.website = '',
    this.currency = 'Rs',
    this.prefix = 'INV',
    this.signName = '',
    this.logo = '',
    this.invoiceRows = 7,
  });

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return AppSettings();
    return AppSettings(
      businessName: json['businessName']?.toString() ?? 'ElectroPowerInt',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      website: json['website']?.toString() ?? '',
      currency: json['currency']?.toString() ?? 'Rs',
      prefix: json['prefix']?.toString() ?? 'INV',
      signName: json['signName']?.toString() ?? '',
      logo: json['logo']?.toString() ?? '',
      invoiceRows: int.tryParse(json['invoiceRows']?.toString() ?? '7') ?? 7,
    );
  }

  Map<String, dynamic> toJson() => {
    'businessName': businessName,
    'email': email,
    'phone': phone,
    'address': address,
    'website': website,
    'currency': currency,
    'prefix': prefix,
    'signName': signName,
    'logo': logo,
    'invoiceRows': invoiceRows,
  };
}

class InvoiceItem {
  String name;
  double qty;
  double price;

  InvoiceItem({
    required this.name,
    required this.qty,
    required this.price,
  });

  double get total => qty * price;

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    _safeD(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    return InvoiceItem(
      name: json['name']?.toString() ?? '',
      qty: _safeD(json['qty']),
      price: _safeD(json['price']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'price': price,
  };
}

class Invoice {
  String id;
  String number;
  String clientName;
  String clientPhone;
  String clientEmail;
  String clientAddress;
  String dueDate;
  double discount;
  String discountType; // 'amount' or 'percent'
  String notes;
  List<InvoiceItem> items;
  int createdAt;
  int updatedAt;
  String status; // 'unpaid', 'partial', 'paid'
  double paidAmount;
  int? paidAt;

  Invoice({
    required this.id,
    required this.number,
    required this.clientName,
    this.clientPhone = '',
    this.clientEmail = '',
    this.clientAddress = '',
    this.dueDate = '',
    this.discount = 0.0,
    this.discountType = 'amount',
    this.notes = '',
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.status = 'unpaid',
    this.paidAmount = 0.0,
    this.paidAt,
  });

  double get subtotal => items.fold(0.0, (sum, it) => sum + it.total);

  double get calculatedDiscount {
    if (discountType == 'percent') {
      return (subtotal * discount) / 100.0;
    }
    return discount;
  }

  double get grandTotal {
    final t = subtotal - calculatedDiscount;
    return t > 0 ? t : 0.0;
  }

  bool get isFullyPaid =>
      (paidAmount >= (grandTotal - 0.01) && grandTotal > 0) || status == 'paid';

  bool get isPartiallyPaid => paidAmount > 0.001 && !isFullyPaid;

  double get remainingAmount {
    final rem = grandTotal - paidAmount;
    return rem > 0 ? rem : 0.0;
  }

  bool get isOverdueOneWeek =>
      !isFullyPaid &&
      (DateTime.now().millisecondsSinceEpoch - createdAt) >= (7 * 24 * 60 * 60 * 1000);

  /// Safely parses any JSON value (null, int, double, String) to double.
  static double _safeDouble(dynamic raw, {double fallback = 0.0}) {
    if (raw == null) return fallback;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? fallback;
  }

  factory Invoice.fromJson(Map<String, dynamic> json) {
    var rawItems = json['items'];
    List<InvoiceItem> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((i) => InvoiceItem.fromJson(Map<String, dynamic>.from(i)))
          .toList();
    }

    final invStatus = json['status']?.toString() ?? 'unpaid';
    final inv = Invoice(
      id: json['id']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      clientName: json['clientName']?.toString() ?? '',
      clientPhone: json['clientPhone']?.toString() ?? '',
      clientEmail: json['clientEmail']?.toString() ?? '',
      clientAddress: json['clientAddress']?.toString() ?? '',
      dueDate: json['dueDate']?.toString() ?? '',
      discount: _safeDouble(json['discount']),
      discountType: json['discountType']?.toString() ?? 'amount',
      notes: json['notes']?.toString() ?? '',
      items: itemList,
      createdAt: int.tryParse(json['createdAt']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
      status: invStatus,
      paidAmount: _safeDouble(json['paidAmount']),
      paidAt: json['paidAt'] != null ? int.tryParse(json['paidAt'].toString()) : null,
    );

    // If marked paid in older snapshot without explicit paidAmount, set paidAmount to grandTotal
    if (inv.status == 'paid' && inv.paidAmount <= 0.0) {
      inv.paidAmount = inv.grandTotal;
    }

    return inv;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'clientName': clientName,
    'clientPhone': clientPhone,
    'clientEmail': clientEmail,
    'clientAddress': clientAddress,
    'dueDate': dueDate,
    'discount': discount,
    'discountType': discountType,
    'notes': notes,
    'items': items.map((e) => e.toJson()).toList(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'status': isFullyPaid ? 'paid' : (isPartiallyPaid ? 'partial' : 'unpaid'),
    'paidAmount': paidAmount,
    'paidAt': paidAt,
  };
}

class Expense {
  String id;
  String title;
  String category;
  double amount;
  int date;

  Expense({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Other',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      date: int.tryParse(json['date']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'amount': amount,
    'date': date,
  };
}

class Reminder {
  String id;
  String title;
  String date;
  String time;
  bool done;

  Reminder({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    this.done = false,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      done: json['done'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'time': time,
    'done': done,
  };
}

class NoteItem {
  String id;
  String title;
  String body;
  int updatedAt;

  NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
  });

  factory NoteItem.fromJson(Map<String, dynamic> json) {
    return NoteItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '0') ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt,
  };
}

class Client {
  String name;
  String phone;
  String email;
  String address;

  Client({
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
  });

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      name: json['name']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
  };
}
