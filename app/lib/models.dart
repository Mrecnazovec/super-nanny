import 'package:latlong2/latlong.dart';

int? _int(dynamic v) => v == null ? null : (v as num).toInt();
double? _double(dynamic v) => v == null ? null : (v as num).toDouble();
List<Map<String, dynamic>> _list(dynamic v) =>
    v == null ? const [] : (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

class Company {
  Company({required this.id, required this.name});

  factory Company.fromJson(Map<String, dynamic> j) => Company(id: _int(j['id'])!, name: j['name'] as String);

  final int id;
  final String name;
}

class PayCard {
  PayCard({required this.id, required this.type, required this.mask, required this.expiry});

  factory PayCard.fromJson(Map<String, dynamic> j) =>
      PayCard(id: _int(j['id'])!, type: j['type'] as String, mask: j['mask'] as String, expiry: j['expiry'] as String);

  final int id;
  final String type;
  final String mask;
  final String expiry;

  String get typeLabel => type == 'humo' ? 'HUMO' : 'UZCARD';
}

class AppUser {
  AppUser({
    required this.id,
    required this.phone,
    this.name,
    this.role,
    this.company,
    this.cards = const [],
    this.nannyStatus,
    this.rejectReason,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: _int(j['id'])!,
        phone: j['phone'] as String,
        name: j['name'] as String?,
        role: j['role'] as String?,
        company: j['company'] == null ? null : Company.fromJson(Map<String, dynamic>.from(j['company'] as Map)),
        cards: _list(j['cards']).map(PayCard.fromJson).toList(),
        nannyStatus: j['nanny_status'] as String?,
        rejectReason: j['reject_reason'] as String?,
      );

  final int id;
  final String phone;
  final String? name;
  final String? role;
  final Company? company;
  final List<PayCard> cards;
  final String? nannyStatus;
  final String? rejectReason;

  bool get isParent => role == 'parent';
  bool get isNanny => role == 'nanny';
}

class Review {
  Review({required this.rating, this.text, required this.author, required this.createdAt});

  factory Review.fromJson(Map<String, dynamic> j) => Review(
        rating: _int(j['rating'])!,
        text: j['text'] as String?,
        author: (j['author'] as String?) ?? 'Родитель',
        createdAt: _int(j['created_at']) ?? 0,
      );

  final int rating;
  final String? text;
  final String author;
  final int createdAt;
}

class NannyCard {
  NannyCard({
    required this.id,
    required this.name,
    this.age,
    this.experience,
    required this.price,
    this.about,
    this.rating,
    this.reviewsCount = 0,
    this.photoId,
    this.medOk = false,
    this.policeOk = false,
    this.distanceM,
    this.isDemo = false,
  });

  factory NannyCard.fromJson(Map<String, dynamic> j) => NannyCard(
        id: _int(j['id'])!,
        name: (j['name'] as String?) ?? 'Няня',
        age: _int(j['age']),
        experience: _int(j['experience']),
        price: _int(j['price']) ?? 0,
        about: j['about'] as String?,
        rating: _double(j['rating']),
        reviewsCount: _int(j['reviews_count']) ?? 0,
        photoId: _int(j['photo_id']),
        medOk: j['med_ok'] == true,
        policeOk: j['police_ok'] == true,
        distanceM: _int(j['distance_m']),
        isDemo: j['is_demo'] == true,
      );

  final int id;
  final String name;
  final int? age;
  final int? experience;
  final int price;
  final String? about;
  final double? rating;
  final int reviewsCount;
  final int? photoId;
  final bool medOk;
  final bool policeOk;
  final int? distanceM;
  final bool isDemo;
}

class NannyDetail {
  NannyDetail({
    required this.card,
    this.schedule,
    this.ordersDone = 0,
    this.certificates = const [],
    this.reviews = const [],
    this.available = false,
  });

  factory NannyDetail.fromJson(Map<String, dynamic> j) => NannyDetail(
        card: NannyCard.fromJson(j),
        schedule: j['schedule'] as String?,
        ordersDone: _int(j['orders_done']) ?? 0,
        certificates: ((j['certificates'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        reviews: _list(j['reviews']).map(Review.fromJson).toList(),
        available: j['available'] == true,
      );

  final NannyCard card;
  final String? schedule;
  final int ordersDone;
  final List<int> certificates;
  final List<Review> reviews;
  final bool available;
}

class Party {
  Party({this.id, this.name, this.phone, this.photoId, this.rating, this.isDemo = false});

  factory Party.fromJson(Map<String, dynamic>? j) => j == null
      ? Party()
      : Party(
          id: _int(j['id']),
          name: j['name'] as String?,
          phone: j['phone'] as String?,
          photoId: _int(j['photo_id']),
          rating: _double(j['rating']),
          isDemo: j['is_demo'] == true,
        );

  final int? id;
  final String? name;
  final String? phone;
  final int? photoId;
  final double? rating;
  final bool isDemo;
}

class Order {
  Order({
    required this.id,
    required this.status,
    required this.type,
    this.scheduledAt,
    required this.childrenCount,
    this.childrenAges,
    this.notes,
    this.address,
    required this.lat,
    required this.lng,
    required this.corporate,
    required this.price,
    required this.holdAmount,
    required this.expectedEarning,
    required this.createdAt,
    this.acceptedAt,
    this.startedAt,
    this.finishedAt,
    this.minutes,
    this.total,
    this.commission,
    this.nannyEarning,
    this.cancelReason,
    this.cancelledBy,
    this.expiresAt,
    required this.parent,
    required this.nanny,
    this.unread = 0,
    this.nannyLocation,
    this.distanceM,
    this.track = const [],
    this.review,
    this.skewMs = 0,
  });

  factory Order.fromJson(Map<String, dynamic> j) {
    final loc = j['nanny_location'] as Map?;
    return Order(
      id: _int(j['id'])!,
      status: j['status'] as String,
      type: j['type'] as String,
      scheduledAt: _int(j['scheduled_at']),
      childrenCount: _int(j['children_count']) ?? 1,
      childrenAges: j['children_ages'] as String?,
      notes: j['notes'] as String?,
      address: j['address'] as String?,
      lat: _double(j['lat'])!,
      lng: _double(j['lng'])!,
      corporate: j['corporate'] == true,
      price: _int(j['price']) ?? 0,
      holdAmount: _int(j['hold_amount']) ?? 0,
      expectedEarning: _int(j['expected_earning']) ?? 0,
      createdAt: _int(j['created_at']) ?? 0,
      acceptedAt: _int(j['accepted_at']),
      startedAt: _int(j['started_at']),
      finishedAt: _int(j['finished_at']),
      minutes: _int(j['minutes']),
      total: _int(j['total']),
      commission: _int(j['commission']),
      nannyEarning: _int(j['nanny_earning']),
      cancelReason: j['cancel_reason'] as String?,
      cancelledBy: j['cancelled_by'] as String?,
      expiresAt: _int(j['expires_at']),
      parent: Party.fromJson(j['parent'] == null ? null : Map<String, dynamic>.from(j['parent'] as Map)),
      nanny: Party.fromJson(j['nanny'] == null ? null : Map<String, dynamic>.from(j['nanny'] as Map)),
      unread: _int(j['unread']) ?? 0,
      nannyLocation: loc == null ? null : LatLng(_double(loc['lat'])!, _double(loc['lng'])!),
      distanceM: _int(j['distance_m']),
      track: ((j['track'] as List?) ?? const [])
          .map((p) => LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
      review: j['review'] == null ? null : Review.fromJson(Map<String, dynamic>.from(j['review'] as Map)),
      skewMs: j['server_time'] == null ? 0 : _int(j['server_time'])! - DateTime.now().millisecondsSinceEpoch,
    );
  }

  final int id;
  final String status;
  final String type;
  final int? scheduledAt;
  final int childrenCount;
  final String? childrenAges;
  final String? notes;
  final String? address;
  final double lat;
  final double lng;
  final bool corporate;
  final int price;
  final int holdAmount;
  final int expectedEarning;
  final int createdAt;
  final int? acceptedAt;
  final int? startedAt;
  final int? finishedAt;
  final int? minutes;
  final int? total;
  final int? commission;
  final int? nannyEarning;
  final String? cancelReason;
  final String? cancelledBy;
  final int? expiresAt;
  final Party parent;
  final Party nanny;
  final int unread;
  final LatLng? nannyLocation;
  final int? distanceM;
  final List<LatLng> track;
  final Review? review;

  /// Расхождение часов сервера и телефона — таймеры считаем по серверному времени.
  final int skewMs;

  int get serverNow => DateTime.now().millisecondsSinceEpoch + skewMs;

  LatLng get destination => LatLng(lat, lng);
  bool get isActive => const {'pending', 'accepted', 'on_the_way', 'arrived', 'in_progress'}.contains(status);
  bool get canCancel => const {'pending', 'accepted', 'on_the_way', 'arrived'}.contains(status);
  bool get chatOpen => !const {'pending', 'declined', 'expired'}.contains(status);
}

class ChatItem {
  ChatItem({
    required this.orderId,
    required this.status,
    required this.title,
    this.photoId,
    this.unread = 0,
    this.lastText,
    this.lastMine = false,
    required this.updatedAt,
  });

  factory ChatItem.fromJson(Map<String, dynamic> j) {
    final last = j['last_message'] as Map?;
    return ChatItem(
      orderId: _int(j['order_id'])!,
      status: j['status'] as String,
      title: (j['title'] as String?) ?? '',
      photoId: _int(j['photo_id']),
      unread: _int(j['unread']) ?? 0,
      lastText: last?['text'] as String?,
      lastMine: last?['mine'] == true,
      updatedAt: _int(j['updated_at']) ?? 0,
    );
  }

  final int orderId;
  final String status;
  final String title;
  final int? photoId;
  final int unread;
  final String? lastText;
  final bool lastMine;
  final int updatedAt;
}

class ChatMessage {
  ChatMessage({required this.id, required this.text, required this.createdAt, required this.mine});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _int(j['id'])!,
        text: j['text'] as String,
        createdAt: _int(j['created_at']) ?? 0,
        mine: j['mine'] == true,
      );

  final int id;
  final String text;
  final int createdAt;
  final bool mine;
}

class Doc {
  Doc({required this.id, required this.kind, required this.mime});

  factory Doc.fromJson(Map<String, dynamic> j) =>
      Doc(id: _int(j['id'])!, kind: j['kind'] as String, mime: (j['mime'] as String?) ?? 'image/jpeg');

  final int id;
  final String kind;
  final String mime;
}

class NannyProfile {
  NannyProfile({
    this.fullName,
    this.age,
    this.experience,
    this.about,
    this.price,
    this.schedule,
    required this.status,
    this.rejectReason,
    this.medOk = false,
    this.policeOk = false,
    this.online = false,
    this.rating,
    this.reviewsCount = 0,
    this.balance = 0,
    this.docs = const [],
  });

  factory NannyProfile.fromJson(Map<String, dynamic> j) => NannyProfile(
        fullName: j['full_name'] as String?,
        age: _int(j['age']),
        experience: _int(j['experience']),
        about: j['about'] as String?,
        price: _int(j['price']),
        schedule: j['schedule'] as String?,
        status: (j['status'] as String?) ?? 'draft',
        rejectReason: j['reject_reason'] as String?,
        medOk: j['med_ok'] == true,
        policeOk: j['police_ok'] == true,
        online: j['online'] == true,
        rating: _double(j['rating']),
        reviewsCount: _int(j['reviews_count']) ?? 0,
        balance: _int(j['balance']) ?? 0,
        docs: _list(j['docs']).map(Doc.fromJson).toList(),
      );

  final String? fullName;
  final int? age;
  final int? experience;
  final String? about;
  final int? price;
  final String? schedule;
  final String status;
  final String? rejectReason;
  final bool medOk;
  final bool policeOk;
  final bool online;
  final double? rating;
  final int reviewsCount;
  final int balance;
  final List<Doc> docs;

  Doc? doc(String kind) {
    for (final d in docs.reversed) {
      if (d.kind == kind) return d;
    }
    return null;
  }
}

class WalletTx {
  WalletTx({required this.amount, required this.kind, this.orderId, required this.createdAt});

  factory WalletTx.fromJson(Map<String, dynamic> j) => WalletTx(
        amount: _int(j['amount']) ?? 0,
        kind: j['kind'] as String,
        orderId: _int(j['order_id']),
        createdAt: _int(j['created_at']) ?? 0,
      );

  final int amount;
  final String kind;
  final int? orderId;
  final int createdAt;
}

class Withdrawal {
  Withdrawal({required this.amount, required this.cardMask, required this.status, required this.createdAt});

  factory Withdrawal.fromJson(Map<String, dynamic> j) => Withdrawal(
        amount: _int(j['amount']) ?? 0,
        cardMask: j['card_mask'] as String,
        status: j['status'] as String,
        createdAt: _int(j['created_at']) ?? 0,
      );

  final int amount;
  final String cardMask;
  final String status;
  final int createdAt;
}

class Wallet {
  Wallet({
    required this.balance,
    required this.totalEarned,
    required this.commissionPercent,
    required this.minWithdraw,
    this.transactions = const [],
    this.withdrawals = const [],
  });

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        balance: _int(j['balance']) ?? 0,
        totalEarned: _int(j['total_earned']) ?? 0,
        commissionPercent: _int(j['commission_percent']) ?? 12,
        minWithdraw: _int(j['min_withdraw']) ?? 10000,
        transactions: _list(j['transactions']).map(WalletTx.fromJson).toList(),
        withdrawals: _list(j['withdrawals']).map(Withdrawal.fromJson).toList(),
      );

  final int balance;
  final int totalEarned;
  final int commissionPercent;
  final int minWithdraw;
  final List<WalletTx> transactions;
  final List<Withdrawal> withdrawals;
}
