// Plain data classes mirroring the Supabase schema.
// Each knows how to read itself from a PostgREST row.

DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v as String);
DateTime _dtReq(dynamic v) => DateTime.parse(v as String);
List<String> _strList(dynamic v) => v == null ? const [] : List<String>.from(v as List);
Map<String, dynamic> _map(dynamic v) => v == null ? <String, dynamic>{} : Map<String, dynamic>.from(v as Map);

class Profile {
  Profile({
    required this.id,
    required this.displayName,
    this.avatarPath,
    this.bio,
    this.countryCode,
    this.currencyCode,
    required this.dateOfBirth,
    required this.notificationPrefs,
    required this.privacyPrefs,
  });

  final String id;
  final String displayName;
  final String? avatarPath;
  final String? bio;
  final String? countryCode;
  final String? currencyCode;
  final DateTime dateOfBirth;
  final Map<String, dynamic> notificationPrefs;
  final Map<String, dynamic> privacyPrefs;

  bool get showOnline => privacyPrefs['show_online'] != false;
  bool get readReceipts => privacyPrefs['read_receipts'] != false;
  bool notifies(String kind) => notificationPrefs[kind] != false;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        displayName: j['display_name'] as String,
        avatarPath: j['avatar_path'] as String?,
        bio: j['bio'] as String?,
        countryCode: (j['country_code'] as String?)?.trim(),
        currencyCode: (j['currency_code'] as String?)?.trim(),
        dateOfBirth: _dtReq(j['date_of_birth']),
        notificationPrefs: _map(j['notification_prefs']),
        privacyPrefs: _map(j['privacy_prefs']),
      );
}

class Circle {
  Circle({
    required this.id,
    required this.status,
    required this.createdBy,
    this.coupleName,
    this.relationshipStart,
    required this.theme,
    required this.createdAt,
    this.activatedAt,
    this.endedAt,
    this.purgeAfter,
  });

  final String id;
  final String status; // pending | active | ended
  final String createdBy;
  final String? coupleName;
  final DateTime? relationshipStart;
  final String theme;
  final DateTime createdAt;
  final DateTime? activatedAt;
  final DateTime? endedAt;
  final DateTime? purgeAfter;

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';

  /// Days together: relationship start if set, else since they connected on Lovebird.
  int get daysTogether {
    final start = relationshipStart ?? activatedAt ?? createdAt;
    return DateTime.now().difference(start).inDays;
  }

  factory Circle.fromJson(Map<String, dynamic> j) => Circle(
        id: j['id'] as String,
        status: j['status'] as String,
        createdBy: j['created_by'] as String,
        coupleName: j['couple_name'] as String?,
        relationshipStart: _dt(j['relationship_start']),
        theme: (j['theme'] as String?) ?? 'blush',
        createdAt: _dtReq(j['created_at']),
        activatedAt: _dt(j['activated_at']),
        endedAt: _dt(j['ended_at']),
        purgeAfter: _dt(j['purge_after']),
      );
}

class Message {
  Message({
    required this.id,
    required this.circleId,
    required this.senderId,
    required this.clientId,
    required this.kind,
    this.body,
    this.mediaPath,
    required this.meta,
    this.replyTo,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.deletedAt,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String circleId;
  final String senderId;
  final String clientId;
  final String kind; // text | image | voice | gif | system
  final String? body;
  final String? mediaPath;
  final Map<String, dynamic> meta;
  final String? replyTo;
  final DateTime createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? deletedAt;

  /// Local-only states for optimistic sending.
  final bool pending;
  final bool failed;

  bool get isDeleted => deletedAt != null;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        senderId: j['sender_id'] as String,
        clientId: j['client_id'] as String,
        kind: j['kind'] as String,
        body: j['body'] as String?,
        mediaPath: j['media_path'] as String?,
        meta: _map(j['meta']),
        replyTo: j['reply_to'] as String?,
        createdAt: _dtReq(j['created_at']),
        deliveredAt: _dt(j['delivered_at']),
        readAt: _dt(j['read_at']),
        deletedAt: _dt(j['deleted_at']),
      );

  Message copyWith({bool? pending, bool? failed}) => Message(
        id: id,
        circleId: circleId,
        senderId: senderId,
        clientId: clientId,
        kind: kind,
        body: body,
        mediaPath: mediaPath,
        meta: meta,
        replyTo: replyTo,
        createdAt: createdAt,
        deliveredAt: deliveredAt,
        readAt: readAt,
        deletedAt: deletedAt,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );
}

class Reaction {
  Reaction({required this.messageId, required this.userId, required this.emoji});
  final String messageId;
  final String userId;
  final String emoji;
  factory Reaction.fromJson(Map<String, dynamic> j) =>
      Reaction(messageId: j['message_id'] as String, userId: j['user_id'] as String, emoji: j['emoji'] as String);
}

class Memory {
  Memory({
    required this.id,
    required this.circleId,
    this.authorId,
    required this.title,
    this.description,
    required this.happenedOn,
    required this.category,
    required this.photoPaths,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String circleId;
  final String? authorId;
  final String title;
  final String? description;
  final DateTime happenedOn;
  final String category;
  final List<String> photoPaths;
  final String source;
  final DateTime createdAt;

  factory Memory.fromJson(Map<String, dynamic> j) => Memory(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        authorId: j['author_id'] as String?,
        title: j['title'] as String,
        description: j['description'] as String?,
        happenedOn: _dtReq(j['happened_on']),
        category: j['category'] as String,
        photoPaths: _strList(j['photo_paths']),
        source: j['source'] as String,
        createdAt: _dtReq(j['created_at']),
      );
}

class DiaryEntry {
  DiaryEntry({
    required this.id,
    required this.circleId,
    this.authorId,
    required this.origin,
    required this.entryType,
    this.title,
    this.body,
    required this.photoPaths,
    required this.payload,
    this.mood,
    required this.entryDate,
    required this.createdAt,
  });

  final String id;
  final String circleId;
  final String? authorId;
  final String origin; // partner | together | suggested
  final String entryType;
  final String? title;
  final String? body;
  final List<String> photoPaths;
  final Map<String, dynamic> payload;
  final String? mood;
  final DateTime entryDate;
  final DateTime createdAt;

  factory DiaryEntry.fromJson(Map<String, dynamic> j) => DiaryEntry(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        authorId: j['author_id'] as String?,
        origin: j['origin'] as String,
        entryType: j['entry_type'] as String,
        title: j['title'] as String?,
        body: j['body'] as String?,
        photoPaths: _strList(j['photo_paths']),
        payload: _map(j['payload']),
        mood: j['mood'] as String?,
        entryDate: _dtReq(j['entry_date']),
        createdAt: _dtReq(j['created_at']),
      );
}

class Plan {
  Plan({required this.id, required this.circleId, required this.title, required this.category, this.emoji, this.createdBy});
  final String id;
  final String circleId;
  final String title;
  final String category;
  final String? emoji;
  final String? createdBy;
  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        title: j['title'] as String,
        category: j['category'] as String,
        emoji: j['emoji'] as String?,
        createdBy: j['created_by'] as String?,
      );
}

class PlanItem {
  PlanItem({
    required this.id,
    required this.planId,
    required this.text,
    this.notes,
    this.dueAt,
    this.privateTo,
    this.doneAt,
    this.doneBy,
    this.createdBy,
    required this.position,
  });
  final String id;
  final String planId;
  final String text;
  final String? notes;
  final DateTime? dueAt;
  final String? privateTo;
  final DateTime? doneAt;
  final String? doneBy;
  final String? createdBy;
  final double position;
  bool get done => doneAt != null;
  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
        id: j['id'] as String,
        planId: j['plan_id'] as String,
        text: j['text'] as String,
        notes: j['notes'] as String?,
        dueAt: _dt(j['due_at']),
        privateTo: j['private_to'] as String?,
        doneAt: _dt(j['done_at']),
        doneBy: j['done_by'] as String?,
        createdBy: j['created_by'] as String?,
        position: (j['position'] as num).toDouble(),
      );
}

class SpecialDate {
  SpecialDate({
    required this.id,
    required this.kind,
    required this.title,
    required this.date,
    required this.recursYearly,
    required this.remind,
    this.personId,
  });
  final String id;
  final String kind;
  final String title;
  final DateTime date;
  final bool recursYearly;
  final bool remind;
  final String? personId;

  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!recursYearly) return DateTime(date.year, date.month, date.day).difference(today).inDays;
    DateTime at(int y) {
      final last = DateTime(y, date.month + 1, 0).day;
      return DateTime(y, date.month, date.day > last ? last : date.day);
    }

    var next = at(today.year);
    if (next.isBefore(today)) next = at(today.year + 1);
    return next.difference(today).inDays;
  }

  /// For anniversaries: which one is coming up (e.g. 3rd).
  int get upcomingYears {
    final next = DateTime.now().add(Duration(days: daysUntil));
    return next.year - date.year;
  }

  factory SpecialDate.fromJson(Map<String, dynamic> j) => SpecialDate(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        date: _dtReq(j['date']),
        recursYearly: j['recurs_yearly'] as bool,
        remind: j['remind'] as bool,
        personId: j['person_id'] as String?,
      );
}

class TogetherSession {
  TogetherSession({
    required this.id,
    required this.circleId,
    required this.activity,
    this.refType,
    this.refId,
    this.title,
    this.startedBy,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final String circleId;
  final String activity;
  final String? refType;
  final String? refId;
  final String? title;
  final String? startedBy;
  final String status;
  final DateTime createdAt;
  bool get live => status != 'ended';
  factory TogetherSession.fromJson(Map<String, dynamic> j) => TogetherSession(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        activity: j['activity'] as String,
        refType: j['ref_type'] as String?,
        refId: j['ref_id'] as String?,
        title: j['title'] as String?,
        startedBy: j['started_by'] as String?,
        status: j['status'] as String,
        createdAt: _dtReq(j['created_at']),
      );
}

class GameSession {
  GameSession({
    required this.id,
    required this.circleId,
    required this.gameKey,
    required this.status,
    required this.round,
    required this.totalRounds,
    required this.deck,
    this.turnUserId,
    required this.state,
    required this.scores,
    this.startedBy,
    required this.createdAt,
  });
  final String id;
  final String circleId;
  final String gameKey;
  final String status;
  final int round;
  final int totalRounds;
  final List<dynamic> deck;
  final String? turnUserId;
  final Map<String, dynamic> state;
  final Map<String, dynamic> scores;
  final String? startedBy;
  final DateTime createdAt;
  bool get active => status == 'active';
  factory GameSession.fromJson(Map<String, dynamic> j) => GameSession(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        gameKey: j['game_key'] as String,
        status: j['status'] as String,
        round: j['round'] as int,
        totalRounds: j['total_rounds'] as int,
        deck: List<dynamic>.from((j['deck'] as List?) ?? const []),
        turnUserId: j['turn_user_id'] as String?,
        state: _map(j['state']),
        scores: _map(j['scores']),
        startedBy: j['started_by'] as String?,
        createdAt: _dtReq(j['created_at']),
      );
}

class GameResponse {
  GameResponse({required this.id, required this.round, required this.userId, required this.answer});
  final String id;
  final int round;
  final String userId;
  final dynamic answer;
  factory GameResponse.fromJson(Map<String, dynamic> j) => GameResponse(
        id: j['id'] as String,
        round: j['round'] as int,
        userId: j['user_id'] as String,
        answer: j['answer'],
      );
}

class MovieSession {
  MovieSession({
    required this.id,
    required this.circleId,
    required this.title,
    required this.sourceUrl,
    required this.sourceKind,
    this.catalogId,
    required this.playbackState,
    required this.positionMs,
    required this.stateUpdatedAt,
    this.updatedBy,
    required this.createdAt,
    this.endedAt,
  });
  final String id;
  final String circleId;
  final String title;
  final String sourceUrl;
  final String sourceKind;
  final String? catalogId;
  final String playbackState;
  final int positionMs;
  final DateTime stateUpdatedAt;
  final String? updatedBy;
  final DateTime createdAt;
  final DateTime? endedAt;
  factory MovieSession.fromJson(Map<String, dynamic> j) => MovieSession(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        title: j['title'] as String,
        sourceUrl: j['source_url'] as String,
        sourceKind: j['source_kind'] as String,
        catalogId: j['catalog_id'] as String?,
        playbackState: j['playback_state'] as String,
        positionMs: (j['position_ms'] as num).toInt(),
        stateUpdatedAt: _dtReq(j['state_updated_at']),
        updatedBy: j['updated_by'] as String?,
        createdAt: _dtReq(j['created_at']),
        endedAt: _dt(j['ended_at']),
      );
}

class Book {
  Book({
    required this.id,
    this.circleId,
    required this.title,
    required this.author,
    this.description,
    required this.coverColor,
    required this.category,
    required this.license,
    required this.tags,
    required this.published,
    this.chapterCount,
  });
  final String id;
  final String? circleId;
  final String title;
  final String author;
  final String? description;
  final String coverColor;
  final String category;
  final String license;
  final List<String> tags;
  final bool published;
  final int? chapterCount;
  bool get isPrivate => circleId != null;
  String get licenseLabel => switch (license) {
        'public_domain' => 'Public domain',
        'original' => 'Lovebird Original',
        'licensed' => 'Licensed',
        _ => 'Your upload',
      };
  factory Book.fromJson(Map<String, dynamic> j) {
    final chapters = j['book_chapters'];
    return Book(
      id: j['id'] as String,
      circleId: j['circle_id'] as String?,
      title: j['title'] as String,
      author: j['author'] as String,
      description: j['description'] as String?,
      coverColor: j['cover_color'] as String,
      category: j['category'] as String,
      license: j['license'] as String,
      tags: _strList(j['tags']),
      published: j['published'] as bool,
      chapterCount: chapters is List && chapters.isNotEmpty ? (chapters.first['count'] as num?)?.toInt() : null,
    );
  }
}

class Chapter {
  Chapter({required this.id, required this.bookId, required this.number, required this.title, required this.body});
  final String id;
  final String bookId;
  final int number;
  final String title;
  final String body;
  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        id: j['id'] as String,
        bookId: j['book_id'] as String,
        number: j['number'] as int,
        title: j['title'] as String,
        body: (j['body'] as String?) ?? '',
      );
}

class CircleBook {
  CircleBook({
    required this.id,
    required this.circleId,
    required this.bookId,
    required this.status,
    required this.isClub,
    this.goal,
    required this.schedule,
    this.nextSessionAt,
    this.startedAt,
    this.finishedAt,
    this.book,
  });
  final String id;
  final String circleId;
  final String bookId;
  final String status;
  final bool isClub;
  final String? goal;
  final Map<String, dynamic> schedule;
  final DateTime? nextSessionAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final Book? book;
  factory CircleBook.fromJson(Map<String, dynamic> j) => CircleBook(
        id: j['id'] as String,
        circleId: j['circle_id'] as String,
        bookId: j['book_id'] as String,
        status: j['status'] as String,
        isClub: j['is_club'] as bool,
        goal: j['goal'] as String?,
        schedule: _map(j['schedule']),
        nextSessionAt: _dt(j['next_session_at']),
        startedAt: _dt(j['started_at']),
        finishedAt: _dt(j['finished_at']),
        book: j['books'] is Map ? Book.fromJson(Map<String, dynamic>.from(j['books'] as Map)) : null,
      );
}

class ReadingProgress {
  ReadingProgress({
    required this.userId,
    required this.chapter,
    required this.scroll,
    required this.chaptersDone,
    required this.streakDays,
    required this.lastReadOn,
  });
  final String userId;
  final int chapter;
  final double scroll;
  final List<int> chaptersDone;
  final int streakDays;
  final DateTime lastReadOn;
  factory ReadingProgress.fromJson(Map<String, dynamic> j) => ReadingProgress(
        userId: j['user_id'] as String,
        chapter: j['chapter'] as int,
        scroll: (j['scroll'] as num).toDouble(),
        chaptersDone: List<int>.from((j['chapters_done'] as List?) ?? const []),
        streakDays: j['streak_days'] as int,
        lastReadOn: _dtReq(j['last_read_on']),
      );
}

class Highlight {
  Highlight({
    required this.id,
    required this.userId,
    required this.chapter,
    required this.quote,
    this.note,
    required this.createdAt,
    this.replies = const [],
  });
  final String id;
  final String userId;
  final int chapter;
  final String quote;
  final String? note;
  final DateTime createdAt;
  final List<HighlightReply> replies;
  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        chapter: j['chapter'] as int,
        quote: j['quote'] as String,
        note: j['note'] as String?,
        createdAt: _dtReq(j['created_at']),
        replies: ((j['highlight_replies'] as List?) ?? const [])
            .map((r) => HighlightReply.fromJson(Map<String, dynamic>.from(r as Map)))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      );
}

class HighlightReply {
  HighlightReply({required this.id, required this.userId, required this.body, required this.createdAt});
  final String id;
  final String userId;
  final String body;
  final DateTime createdAt;
  factory HighlightReply.fromJson(Map<String, dynamic> j) => HighlightReply(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        body: j['body'] as String,
        createdAt: _dtReq(j['created_at']),
      );
}

class Reflection {
  Reflection({required this.userId, required this.chapter, required this.body, this.rating});
  final String userId;
  final int chapter;
  final String body;
  final int? rating;
  factory Reflection.fromJson(Map<String, dynamic> j) => Reflection(
        userId: j['user_id'] as String,
        chapter: j['chapter'] as int,
        body: j['body'] as String,
        rating: j['rating'] as int?,
      );
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    required this.data,
    this.readAt,
    required this.createdAt,
  });
  final String id;
  final String kind;
  final String title;
  final String? body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;
  bool get unread => readAt == null;
  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: j['body'] as String?,
        data: _map(j['data']),
        readAt: _dt(j['read_at']),
        createdAt: _dtReq(j['created_at']),
      );
}

class Announcement {
  Announcement({required this.id, required this.title, required this.body});
  final String id;
  final String title;
  final String body;
  factory Announcement.fromJson(Map<String, dynamic> j) =>
      Announcement(id: j['id'] as String, title: j['title'] as String, body: j['body'] as String);
}

class Competition {
  Competition({
    required this.id,
    required this.year,
    required this.title,
    required this.description,
    required this.status,
    this.registrationOpens,
    this.registrationCloses,
    this.votingOpens,
    this.votingCloses,
    this.winnerAnnounceAt,
    this.celebrationEndsAt,
    required this.selectionMethod,
    required this.judgeWeight,
    required this.criteria,
    required this.termsMd,
    required this.numberOfWinners,
    required this.allowedCountries,
    required this.minAge,
    required this.freeEntryAvailable,
    this.fees = const [],
    this.prizes = const [],
  });
  final String id;
  final int year;
  final String title;
  final String description;
  final String status;
  final DateTime? registrationOpens;
  final DateTime? registrationCloses;
  final DateTime? votingOpens;
  final DateTime? votingCloses;
  final DateTime? winnerAnnounceAt;
  final DateTime? celebrationEndsAt;
  final String selectionMethod;
  final double judgeWeight;
  final List<Map<String, dynamic>> criteria;
  final String termsMd;
  final int numberOfWinners;
  final List<String> allowedCountries;
  final int minAge;
  final bool freeEntryAvailable;
  final List<CompetitionFee> fees;
  final List<CompetitionPrize> prizes;

  bool get registrationOpen {
    final now = DateTime.now();
    return status == 'registration' &&
        (registrationOpens == null || now.isAfter(registrationOpens!)) &&
        (registrationCloses == null || now.isBefore(registrationCloses!));
  }

  bool get votingOpen {
    final now = DateTime.now();
    return status == 'voting' &&
        selectionMethod != 'judges' &&
        votingOpens != null &&
        votingCloses != null &&
        now.isAfter(votingOpens!) &&
        now.isBefore(votingCloses!);
  }

  String get methodLabel => switch (selectionMethod) {
        'community' => 'Community voting',
        'judges' => 'Judging panel',
        _ => 'Judges (${(judgeWeight * 100).round()}%) + community votes (${((1 - judgeWeight) * 100).round()}%)',
      };

  CompetitionFee? feeFor(String? currency) {
    for (final f in fees) {
      if (f.currency == currency) return f;
    }
    for (final f in fees) {
      if (f.currency == 'USD') return f;
    }
    return fees.isEmpty ? null : fees.first;
  }

  factory Competition.fromJson(Map<String, dynamic> j) => Competition(
        id: j['id'] as String,
        year: j['year'] as int,
        title: j['title'] as String,
        description: j['description'] as String,
        status: j['status'] as String,
        registrationOpens: _dt(j['registration_opens']),
        registrationCloses: _dt(j['registration_closes']),
        votingOpens: _dt(j['voting_opens']),
        votingCloses: _dt(j['voting_closes']),
        winnerAnnounceAt: _dt(j['winner_announce_at']),
        celebrationEndsAt: _dt(j['celebration_ends_at']),
        selectionMethod: j['selection_method'] as String,
        judgeWeight: (j['judge_weight'] as num).toDouble(),
        criteria: ((j['criteria'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        termsMd: j['terms_md'] as String,
        numberOfWinners: j['number_of_winners'] as int,
        allowedCountries: _strList(j['allowed_countries']),
        minAge: j['min_age'] as int,
        freeEntryAvailable: j['free_entry_available'] as bool,
        fees: ((j['competition_fees'] as List?) ?? const [])
            .map((e) => CompetitionFee.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        prizes: ((j['competition_prizes'] as List?) ?? const [])
            .map((e) => CompetitionPrize.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList()
          ..sort((a, b) => a.rank.compareTo(b.rank)),
      );
}

class CompetitionFee {
  CompetitionFee({required this.currency, required this.amountMinor});
  final String currency;
  final int amountMinor;
  factory CompetitionFee.fromJson(Map<String, dynamic> j) =>
      CompetitionFee(currency: (j['currency'] as String).trim(), amountMinor: (j['amount_minor'] as num).toInt());
}

class CompetitionPrize {
  CompetitionPrize({
    required this.id,
    required this.rank,
    required this.title,
    required this.description,
    this.cashAmountMinor,
    this.cashCurrency,
  });
  final String id;
  final int rank;
  final String title;
  final String description;
  final int? cashAmountMinor;
  final String? cashCurrency;
  factory CompetitionPrize.fromJson(Map<String, dynamic> j) => CompetitionPrize(
        id: j['id'] as String,
        rank: j['rank'] as int,
        title: j['title'] as String,
        description: j['description'] as String,
        cashAmountMinor: (j['cash_amount_minor'] as num?)?.toInt(),
        cashCurrency: (j['cash_currency'] as String?)?.trim(),
      );
}

class CompetitionEntry {
  CompetitionEntry({
    required this.id,
    required this.competitionId,
    required this.circleId,
    required this.coupleName,
    required this.story,
    required this.howWeMet,
    required this.favoriteActivity,
    required this.favoriteMemory,
    required this.whyLovebird,
    required this.photoPaths,
    required this.status,
    required this.paymentStatus,
    this.feeCurrency,
    this.feeAmountMinor,
    this.finalScore,
    this.consents = const [],
  });
  final String id;
  final String competitionId;
  final String circleId;
  final String coupleName;
  final String story;
  final String howWeMet;
  final String favoriteActivity;
  final String favoriteMemory;
  final String whyLovebird;
  final List<String> photoPaths;
  final String status;
  final String paymentStatus;
  final String? feeCurrency;
  final int? feeAmountMinor;
  final double? finalScore;
  final List<Map<String, dynamic>> consents;

  bool consentedBy(String uid) => consents.any((c) => c['user_id'] == uid);

  factory CompetitionEntry.fromJson(Map<String, dynamic> j) => CompetitionEntry(
        id: j['id'] as String,
        competitionId: j['competition_id'] as String,
        circleId: j['circle_id'] as String,
        coupleName: j['couple_name'] as String,
        story: j['story'] as String,
        howWeMet: j['how_we_met'] as String,
        favoriteActivity: j['favorite_activity'] as String,
        favoriteMemory: j['favorite_memory'] as String,
        whyLovebird: j['why_lovebird'] as String,
        photoPaths: _strList(j['photo_paths']),
        status: j['status'] as String,
        paymentStatus: j['payment_status'] as String,
        feeCurrency: (j['fee_currency'] as String?)?.trim(),
        feeAmountMinor: (j['fee_amount_minor'] as num?)?.toInt(),
        finalScore: (j['final_score'] as num?)?.toDouble(),
        consents: ((j['competition_consents'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}

class Finalist {
  Finalist({
    required this.entryId,
    required this.coupleName,
    required this.story,
    required this.howWeMet,
    required this.favoriteActivity,
    required this.favoriteMemory,
    required this.photoPaths,
    required this.status,
    this.votes,
  });
  final String entryId;
  final String coupleName;
  final String story;
  final String howWeMet;
  final String favoriteActivity;
  final String favoriteMemory;
  final List<String> photoPaths;
  final String status;
  final int? votes;
  factory Finalist.fromJson(Map<String, dynamic> j) => Finalist(
        entryId: j['entry_id'] as String,
        coupleName: j['couple_name'] as String,
        story: j['story'] as String,
        howWeMet: j['how_we_met'] as String,
        favoriteActivity: j['favorite_activity'] as String,
        favoriteMemory: j['favorite_memory'] as String,
        photoPaths: _strList(j['photo_paths']),
        status: j['status'] as String,
        votes: (j['votes'] as num?)?.toInt(),
      );
}

class Report {
  Report({
    required this.id,
    required this.reporterId,
    this.circleId,
    required this.category,
    required this.description,
    required this.snapshot,
    required this.status,
    this.adminNotes,
    required this.createdAt,
  });
  final String id;
  final String reporterId;
  final String? circleId;
  final String category;
  final String description;
  final Map<String, dynamic> snapshot;
  final String status;
  final String? adminNotes;
  final DateTime createdAt;
  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'] as String,
        reporterId: j['reporter_id'] as String,
        circleId: j['circle_id'] as String?,
        category: j['category'] as String,
        description: j['description'] as String,
        snapshot: _map(j['snapshot']),
        status: j['status'] as String,
        adminNotes: j['admin_notes'] as String?,
        createdAt: _dtReq(j['created_at']),
      );
}
