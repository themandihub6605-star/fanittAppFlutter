import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/utils/json.dart';

enum CommunityRole {
  member,
  moderator,
  owner;

  static CommunityRole from(String? v) => switch (v) {
    'admin' => CommunityRole.owner,
    'moderator' => CommunityRole.moderator,
    _ => CommunityRole.member,
  };

  String get label => switch (this) {
    CommunityRole.owner => 'Owner',
    CommunityRole.moderator => 'Moderator',
    CommunityRole.member => 'Member',
  };
}

enum MembershipStatus {
  active,
  pending,
  banned,
  expired;

  static MembershipStatus? from(String? v) => switch (v) {
    'active' => MembershipStatus.active,
    'pending' => MembershipStatus.pending,
    'banned' => MembershipStatus.banned,
    'expired' => MembershipStatus.expired,
    _ => null,
  };
}

/// How a paid community can be bought.
enum CommunityPlanKey {
  monthly('monthly', 'Monthly', '/month'),
  yearly('yearly', 'Yearly', '/year'),
  lifetime('lifetime', 'One-time', ' once');

  const CommunityPlanKey(this.value, this.label, this.suffix);
  final String value;
  final String label;

  /// "/month", "/year", " once" — after the price.
  final String suffix;

  static CommunityPlanKey? from(String? v) => switch (v) {
    'monthly' => CommunityPlanKey.monthly,
    'yearly' => CommunityPlanKey.yearly,
    'lifetime' => CommunityPlanKey.lifetime,
    _ => null,
  };
}

/// One plan the owner turned on (price in paise).
class CommunityPlan extends Equatable {
  const CommunityPlan({required this.key, required this.price});

  final CommunityPlanKey key;
  final int price;

  @override
  List<Object?> get props => [key, price];
}

class CommunityMembership extends Equatable {
  const CommunityMembership({required this.role, required this.status, required this.muted, this.isPaid = false, this.plan, this.paidUntil});

  factory CommunityMembership.fromJson(Map<String, dynamic> json) => CommunityMembership(
    role: CommunityRole.from(J.strOrNull(json, 'role')),
    status: MembershipStatus.from(J.strOrNull(json, 'status')) ?? MembershipStatus.active,
    muted: J.boolean(json, 'notificationsMuted'),
    isPaid: J.str(json, 'access') == 'paid',
    plan: CommunityPlanKey.from(J.strOrNull(json, 'plan')),
    paidUntil: J.date(json, 'paidUntil'),
  );

  final CommunityRole role;
  final MembershipStatus status;
  final bool muted;

  /// Bought a plan (false = free access, e.g. joined before it went paid).
  final bool isPaid;
  final CommunityPlanKey? plan;

  /// End of the paid period; null for lifetime / free access.
  final DateTime? paidUntil;

  bool get isActive => status == MembershipStatus.active;
  bool get isExpired => status == MembershipStatus.expired;

  CommunityMembership copyWith({bool? muted, MembershipStatus? status}) =>
      CommunityMembership(role: role, status: status ?? this.status, muted: muted ?? this.muted, isPaid: isPaid, plan: plan, paidUntil: paidUntil);

  @override
  List<Object?> get props => [role, status, muted, isPaid, plan, paidUntil];
}

class Community extends Equatable {
  const Community({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.rules,
    required this.isPrivate,
    required this.onlyModeratorsPost,
    required this.chatEnabled,
    required this.isVerified,
    required this.isFeatured,
    required this.memberCount,
    required this.discussionCount,
    required this.pendingRequestCount,
    required this.canPost,
    required this.canModerate,
    required this.isOwner,
    required this.unreadChatCount,
    required this.moderators,
    this.category,
    this.coverImageUrl,
    this.iconUrl,
    this.membership,
    this.createdAt,
    this.isPaid = false,
    this.plans = const [],
    this.paidRevenue = 0,
    this.paidPayments = 0,
  });

  factory Community.fromJson(Map<String, dynamic> json) {
    final membership = J.map(json, 'membership');
    return Community(
      id: J.id(json),
      name: J.str(json, 'name'),
      slug: J.str(json, 'slug'),
      description: J.str(json, 'description'),
      rules: J.strings(json, 'rules'),
      isPrivate: J.str(json, 'visibility') == 'private',
      onlyModeratorsPost: J.str(json, 'postPermission') == 'moderators',
      chatEnabled: J.boolean(json, 'chatEnabled', true),
      isVerified: J.boolean(json, 'isVerified'),
      isFeatured: J.boolean(json, 'isFeatured'),
      memberCount: J.integer(json, 'memberCount'),
      discussionCount: J.integer(json, 'discussionCount'),
      pendingRequestCount: J.integer(json, 'pendingRequestCount'),
      canPost: J.boolean(json, 'canPost'),
      canModerate: J.boolean(json, 'canModerate'),
      isOwner: J.boolean(json, 'isOwner'),
      unreadChatCount: J.integer(json, 'unreadChatCount'),
      moderators: J.list(json, 'moderators', (m) {
        final user = J.map(m, 'user') ?? const <String, dynamic>{};
        return (UserLite.fromJson(user), CommunityRole.from(J.strOrNull(m, 'role')));
      }),
      category: Category.fromRef(json, 'category'),
      coverImageUrl: J.strOrNull(json, 'coverImageUrl'),
      iconUrl: J.strOrNull(json, 'iconUrl'),
      membership: membership == null ? null : CommunityMembership.fromJson(membership),
      createdAt: J.date(json, 'createdAt'),
      isPaid: J.boolean(json, 'isPaid'),
      plans: _readPlans(json),
      paidRevenue: J.integer(J.map(json, 'paidStats') ?? const {}, 'revenue'),
      paidPayments: J.integer(J.map(json, 'paidStats') ?? const {}, 'payments'),
    );
  }

  /// Turned-on plans, from `plans` ({ monthly: { enabled, price } … }).
  static List<CommunityPlan> _readPlans(Map<String, dynamic> json) {
    final raw = J.map(json, 'plans');
    if (raw == null) return const [];
    return [
      for (final key in CommunityPlanKey.values)
        if (J.boolean(J.map(raw, key.value) ?? const {}, 'enabled'))
          CommunityPlan(key: key, price: J.integer(J.map(raw, key.value) ?? const {}, 'price')),
    ];
  }

  final String id;
  final String name;
  final String slug;
  final String description;
  final List<String> rules;
  final bool isPrivate;
  final bool onlyModeratorsPost;
  final bool chatEnabled;
  final bool isVerified;
  final bool isFeatured;
  final int memberCount;
  final int discussionCount;
  final int pendingRequestCount;
  final bool canPost;
  final bool canModerate;
  final bool isOwner;
  final int unreadChatCount;
  final List<(UserLite, CommunityRole)> moderators;
  final Category? category;
  final String? coverImageUrl;
  final String? iconUrl;
  final CommunityMembership? membership;
  final DateTime? createdAt;

  /// Members pay to join (monthly / yearly / one-time).
  final bool isPaid;
  final List<CommunityPlan> plans;

  /// Owner only: total paid by members (paise) and number of payments.
  final int paidRevenue;
  final int paidPayments;

  bool get isMember => membership?.isActive ?? false;
  bool get isPending => membership?.status == MembershipStatus.pending;
  bool get isBanned => membership?.status == MembershipStatus.banned;
  bool get isExpired => membership?.isExpired ?? false;
  bool get canView => (!isPrivate && !isPaid) || isMember;

  /// Paid community and this viewer still has to buy a plan.
  bool get needsPlan => isPaid && !isMember && !isOwner && !isBanned;

  /// Cheapest turned-on plan (for "From ₹199/month").
  CommunityPlan? get cheapestPlan => plans.isEmpty ? null : (plans.toList()..sort((a, b) => a.price.compareTo(b.price))).first;

  Community copyWith({CommunityMembership? membership, bool clearMembership = false, int? memberCount}) => Community(
    id: id,
    name: name,
    slug: slug,
    description: description,
    rules: rules,
    isPrivate: isPrivate,
    onlyModeratorsPost: onlyModeratorsPost,
    chatEnabled: chatEnabled,
    isVerified: isVerified,
    isFeatured: isFeatured,
    memberCount: memberCount ?? this.memberCount,
    discussionCount: discussionCount,
    pendingRequestCount: pendingRequestCount,
    canPost: canPost,
    canModerate: canModerate,
    isOwner: isOwner,
    unreadChatCount: unreadChatCount,
    moderators: moderators,
    category: category,
    coverImageUrl: coverImageUrl,
    iconUrl: iconUrl,
    membership: clearMembership ? null : (membership ?? this.membership),
    createdAt: createdAt,
    isPaid: isPaid,
    plans: plans,
    paidRevenue: paidRevenue,
    paidPayments: paidPayments,
  );

  @override
  List<Object?> get props => [id, name, memberCount, discussionCount, membership, unreadChatCount, coverImageUrl, iconUrl, description, rules, isPaid, plans];
}

class PollOption extends Equatable {
  const PollOption({required this.text, required this.votes});

  final String text;
  final int votes;

  @override
  List<Object?> get props => [text, votes];
}

class PostPoll extends Equatable {
  const PostPoll({
    required this.question,
    required this.options,
    required this.totalVotes,
    required this.isClosed,
    this.myVote,
    this.endsAt,
  });

  static PostPoll? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final options = J.list(json, 'options', (o) => PollOption(text: J.str(o, 'text'), votes: J.integer(o, 'votes')));
    if (options.isEmpty) return null;
    return PostPoll(
      question: J.str(json, 'question'),
      options: options,
      totalVotes: J.integer(json, 'totalVotes'),
      isClosed: J.boolean(json, 'isClosed'),
      myVote: J.integerOrNull(json, 'myVote'),
      endsAt: J.date(json, 'endsAt'),
    );
  }

  final String question;
  final List<PollOption> options;
  final int totalVotes;
  final bool isClosed;
  final int? myVote;
  final DateTime? endsAt;

  @override
  List<Object?> get props => [question, options, totalVotes, isClosed, myVote];
}

class CommunityMedia extends Equatable {
  const CommunityMedia({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;

  @override
  List<Object?> get props => [url];
}

class CommunityPost extends Equatable {
  const CommunityPost({
    required this.id,
    required this.communityId,
    required this.author,
    required this.text,
    required this.media,
    required this.isAnnouncement,
    required this.isPinned,
    required this.likeCount,
    required this.commentCount,
    required this.isLiked,
    required this.createdAt,
    this.poll,
    this.editedAt,
    this.community,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final communityJson = J.map(json, 'community');
    return CommunityPost(
      id: J.id(json),
      communityId: J.refId(json, 'community') ?? '',
      author: UserLite.fromJson(J.map(json, 'author') ?? const {}),
      text: J.str(json, 'text'),
      media: J.list(json, 'mediaItems', (m) => CommunityMedia(url: J.str(m, 'url'), isVideo: J.str(m, 'type') == 'video')),
      poll: PostPoll.fromJson(J.map(json, 'poll')),
      isAnnouncement: J.boolean(json, 'isAnnouncement'),
      isPinned: J.boolean(json, 'isPinned'),
      likeCount: J.integer(json, 'likeCount'),
      commentCount: J.integer(json, 'commentCount'),
      isLiked: J.boolean(json, 'isLiked'),
      createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
      editedAt: J.date(json, 'editedAt'),
      community: communityJson == null ? null : Community.fromJson(communityJson),
    );
  }

  final String id;
  final String communityId;
  final UserLite author;
  final String text;
  final List<CommunityMedia> media;
  final PostPoll? poll;
  final bool isAnnouncement;
  final bool isPinned;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final DateTime createdAt;
  final DateTime? editedAt;

  /// Only set when a single post is loaded (notifications).
  final Community? community;

  CommunityPost copyWith({
    String? text,
    PostPoll? poll,
    bool? isPinned,
    int? likeCount,
    int? commentCount,
    bool? isLiked,
    DateTime? editedAt,
  }) =>
      CommunityPost(
        id: id,
        communityId: communityId,
        author: author,
        text: text ?? this.text,
        media: media,
        poll: poll ?? this.poll,
        isAnnouncement: isAnnouncement,
        isPinned: isPinned ?? this.isPinned,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        isLiked: isLiked ?? this.isLiked,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        community: community,
      );

  @override
  List<Object?> get props => [id, text, poll, isPinned, likeCount, commentCount, isLiked, editedAt];
}

class CommunityComment extends Equatable {
  const CommunityComment({
    required this.id,
    required this.author,
    required this.text,
    required this.likeCount,
    required this.isLiked,
    required this.createdAt,
    required this.replies,
    this.parentId,
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) => CommunityComment(
    id: J.id(json),
    author: UserLite.fromJson(J.map(json, 'author') ?? const {}),
    text: J.str(json, 'text'),
    likeCount: J.integer(json, 'likeCount'),
    isLiked: J.boolean(json, 'isLiked'),
    createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
    parentId: J.refId(json, 'parentComment'),
    replies: J.list(json, 'replies', CommunityComment.fromJson),
  );

  final String id;
  final UserLite author;
  final String text;
  final int likeCount;
  final bool isLiked;
  final DateTime createdAt;
  final String? parentId;
  final List<CommunityComment> replies;

  CommunityComment copyWith({int? likeCount, bool? isLiked, List<CommunityComment>? replies}) => CommunityComment(
    id: id,
    author: author,
    text: text,
    likeCount: likeCount ?? this.likeCount,
    isLiked: isLiked ?? this.isLiked,
    createdAt: createdAt,
    parentId: parentId,
    replies: replies ?? this.replies,
  );

  @override
  List<Object?> get props => [id, likeCount, isLiked, replies];
}

class CommunityMember extends Equatable {
  const CommunityMember({required this.user, required this.role, required this.status, this.joinedAt});

  factory CommunityMember.fromJson(Map<String, dynamic> json) => CommunityMember(
    user: UserLite.fromJson(J.map(json, 'user') ?? const {}),
    role: CommunityRole.from(J.strOrNull(json, 'role')),
    status: MembershipStatus.from(J.strOrNull(json, 'status')) ?? MembershipStatus.active,
    joinedAt: J.date(json, 'joinedAt'),
  );

  final UserLite user;
  final CommunityRole role;
  final MembershipStatus status;
  final DateTime? joinedAt;

  CommunityMember copyWith({CommunityRole? role}) => CommunityMember(user: user, role: role ?? this.role, status: status, joinedAt: joinedAt);

  @override
  List<Object?> get props => [user, role, status];
}

class CommunityChatMessage extends Equatable {
  const CommunityChatMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.isRemoved,
    required this.createdAt,
  });

  factory CommunityChatMessage.fromJson(Map<String, dynamic> json) => CommunityChatMessage(
    id: J.id(json),
    sender: UserLite.fromJson(J.map(json, 'sender') ?? const {}),
    text: J.str(json, 'text'),
    isRemoved: J.boolean(json, 'isRemoved'),
    createdAt: J.date(json, 'createdAt') ?? DateTime.now(),
  );

  final String id;
  final UserLite sender;
  final String text;
  final bool isRemoved;
  final DateTime createdAt;

  CommunityChatMessage removed() =>
      CommunityChatMessage(id: id, sender: sender, text: '', isRemoved: true, createdAt: createdAt);

  @override
  List<Object?> get props => [id, isRemoved];
}

enum MemberAction {
  approve('approve'),
  reject('reject'),
  makeModerator('make_moderator'),
  removeModerator('remove_moderator'),
  remove('remove'),
  ban('ban'),
  unban('unban');

  const MemberAction(this.value);
  final String value;
}