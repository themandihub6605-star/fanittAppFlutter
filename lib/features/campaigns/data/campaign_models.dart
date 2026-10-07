import 'package:equatable/equatable.dart';

import '../../../core/models/common_models.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/json.dart';

enum CampaignType {
  paid('paid', 'Paid'),
  barter('barter', 'Barter');

  const CampaignType(this.value, this.label);
  final String value;
  final String label;

  static CampaignType from(String? v) => v == 'barter' ? CampaignType.barter : CampaignType.paid;
}

enum LocationType {
  panIndia('pan_india', 'Pan India'),
  state('state', 'State'),
  city('city', 'City');

  const LocationType(this.value, this.label);
  final String value;
  final String label;

  static LocationType from(String? v) =>
      LocationType.values.firstWhere((t) => t.value == v, orElse: () => LocationType.panIndia);
}

enum CampaignStatus {
  draft('draft', 'Draft'),
  open('open', 'Open'),
  inProgress('in_progress', 'In progress'),
  submitted('submitted', 'Submitted'),
  approved('approved', 'Approved'),
  completed('completed', 'Completed'),
  disputed('disputed', 'Disputed'),
  cancelled('cancelled', 'Cancelled');

  const CampaignStatus(this.value, this.label);
  final String value;
  final String label;

  static CampaignStatus from(String? v) =>
      CampaignStatus.values.firstWhere((s) => s.value == v, orElse: () => CampaignStatus.draft);

  bool get isActive => this == open || this == inProgress || this == submitted || this == disputed;
}

class BrandSummary extends Equatable {
  const BrandSummary({required this.id, required this.name, required this.slug, this.logoUrl, this.userId});

  factory BrandSummary.fromJson(Map<String, dynamic> json) {
    final user = J.map(json, 'user');
    return BrandSummary(
      id: J.id(json),
      name: J.strOrNull(json, 'companyName') ?? (user == null ? 'Brand' : J.str(user, 'name', 'Brand')),
      slug: J.str(json, 'slug'),
      logoUrl: J.strOrNull(json, 'logoUrl') ?? (user == null ? null : J.strOrNull(user, 'avatarUrl')),
      userId: J.refId(json, 'user'),
    );
  }

  final String id;
  final String name;
  final String slug;
  final String? logoUrl;
  final String? userId;

  @override
  List<Object?> get props => [id];
}

class CampaignProduct extends Equatable {
  const CampaignProduct({required this.id, required this.name, required this.description, required this.quantity, required this.price, this.imageUrl});

  factory CampaignProduct.fromJson(Map<String, dynamic> json) => CampaignProduct(
    id: J.id(json),
    name: J.str(json, 'name'),
    description: J.str(json, 'description'),
    quantity: J.integer(json, 'quantity', 1),
    price: J.integer(json, 'price'),
    imageUrl: J.strOrNull(json, 'imageUrl'),
  );

  final String id;
  final String name;
  final String description;
  final int quantity;
  final int price;
  final String? imageUrl;

  @override
  List<Object?> get props => [id];
}

class Deliverables extends Equatable {
  const Deliverables({this.reel = 0, this.story = 0, this.post = 0});

  factory Deliverables.fromJson(Map<String, dynamic>? json) => json == null
      ? const Deliverables()
      : Deliverables(reel: J.integer(json, 'reel'), story: J.integer(json, 'story'), post: J.integer(json, 'post'));

  final int reel;
  final int story;
  final int post;

  bool get isEmpty => reel == 0 && story == 0 && post == 0;

  String get summary => [
    if (reel > 0) '$reel reel${reel == 1 ? '' : 's'}',
    if (post > 0) '$post post${post == 1 ? '' : 's'}',
    if (story > 0) '$story stor${story == 1 ? 'y' : 'ies'}',
  ].join(' · ');

  Map<String, int> toJson() => {'reel': reel, 'story': story, 'post': post};

  @override
  List<Object?> get props => [reel, story, post];
}

class Campaign extends Equatable {
  const Campaign({
    required this.id,
    required this.title,
    required this.description,
    required this.type,
    required this.costPerInfluencer,
    required this.budget,
    required this.products,
    required this.durationLabel,
    required this.location,
    required this.locationType,
    required this.locationValue,
    required this.creatorRequirement,
    required this.influencerCategories,
    required this.genderTarget,
    required this.ageMin,
    required this.ageMax,
    required this.maxInfluencers,
    required this.dos,
    required this.donts,
    required this.sampleMedia,
    required this.deliverables,
    required this.status,
    required this.isExclusive,
    required this.isFeatured,
    required this.applicantCount,
    this.approvalStatus,
    this.rejectionReason = '',
    required this.milestoneCount,
    required this.milestoneTitles,
    required this.isEscrowFunded,
    this.brand,
    this.category,
    this.minFollowers,
    this.campaignImageUrl,
    this.assignedCreatorId,
    this.assignedCreatorName,
    this.createdAt,
    this.publicVisibleAt,
    this.applicantLimit,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    final brand = J.map(json, 'brand');
    final assigned = J.map(json, 'assignedCreator');
    final assignedUser = assigned == null ? null : J.map(assigned, 'user');
    final age = J.map(json, 'ageRange') ?? const <String, dynamic>{};
    return Campaign(
      id: J.id(json),
      title: J.str(json, 'title'),
      description: J.str(json, 'description'),
      brand: brand == null ? null : BrandSummary.fromJson(brand),
      category: Category.fromRef(json, 'category'),
      type: CampaignType.from(J.strOrNull(json, 'campaignType')),
      costPerInfluencer: J.integer(json, 'costPerInfluencer'),
      budget: J.integer(json, 'budget'),
      products: J.list(json, 'products', CampaignProduct.fromJson),
      durationLabel: J.str(json, 'durationLabel'),
      location: J.str(json, 'location'),
      locationType: LocationType.from(J.strOrNull(json, 'locationType')),
      locationValue: J.str(json, 'locationValue'),
      creatorRequirement: J.str(json, 'creatorRequirement'),
      influencerCategories: J.strings(json, 'influencerCategories'),
      genderTarget: J.strings(json, 'genderTarget'),
      ageMin: J.integer(age, 'min', 18),
      ageMax: J.integer(age, 'max', 45),
      minFollowers: J.integerOrNull(json, 'minFollowers'),
      maxInfluencers: J.integer(json, 'maxInfluencers', 1),
      dos: J.strings(json, 'dos'),
      donts: J.strings(json, 'donts'),
      campaignImageUrl: J.strOrNull(json, 'campaignImageUrl'),
      sampleMedia: J.strings(json, 'sampleMedia'),
      deliverables: Deliverables.fromJson(J.map(json, 'deliverables')),
      status: CampaignStatus.from(J.strOrNull(json, 'status')),
      isExclusive: J.str(json, 'visibilityTier') == 'exclusive',
      isFeatured: J.boolean(json, 'isFeatured'),
      applicantCount: J.integer(json, 'applicantCount'),
      approvalStatus: J.strOrNull(json, 'approvalStatus'),
      rejectionReason: J.str(json, 'rejectionReason'),
      applicantLimit: J.integerOrNull(json, 'applicantLimit'),
      milestoneCount: J.integer(json, 'milestoneCount', 2),
      milestoneTitles: J.strings(json, 'milestoneTitles'),
      assignedCreatorId: J.refId(json, 'assignedCreator'),
      assignedCreatorName: assignedUser == null ? null : J.strOrNull(assignedUser, 'name'),
      isEscrowFunded: J.boolean(json, 'isEscrowFunded'),
      createdAt: J.date(json, 'createdAt'),
      publicVisibleAt: J.date(json, 'publicVisibleAt'),
    );
  }

  final String id;
  final String title;
  final String description;
  final BrandSummary? brand;
  final Category? category;
  final CampaignType type;
  final int costPerInfluencer;
  final int budget;
  final List<CampaignProduct> products;
  final String durationLabel;
  final String location;
  final LocationType locationType;
  final String locationValue;
  final String creatorRequirement;
  final List<String> influencerCategories;
  final List<String> genderTarget;
  final int ageMin;
  final int ageMax;
  final int? minFollowers;
  final int maxInfluencers;
  final List<String> dos;
  final List<String> donts;
  final String? campaignImageUrl;
  final List<String> sampleMedia;
  final Deliverables deliverables;
  final CampaignStatus status;
  final bool isExclusive;
  final bool isFeatured;
  final int applicantCount;

  /// Admin review: 'pending' | 'approved' | 'rejected' (null for older campaigns = live).
  final String? approvalStatus;
  final String rejectionReason;

  bool get isPendingReview => approvalStatus == 'pending';
  bool get isRejectedByReview => approvalStatus == 'rejected';
  final int? applicantLimit;
  final int milestoneCount;
  final List<String> milestoneTitles;
  final String? assignedCreatorId;
  final String? assignedCreatorName;
  final bool isEscrowFunded;
  final DateTime? createdAt;
  final DateTime? publicVisibleAt;

  bool get isPaid => type == CampaignType.paid;

  String get payLabel => isPaid ? Fmt.money(costPerInfluencer) : 'Barter';

  String get locationLabel => location.isEmpty ? locationType.label : location;

  @override
  List<Object?> get props => [id, title, status, applicantCount, assignedCreatorId, isEscrowFunded, products, sampleMedia, campaignImageUrl];
}

enum ProposalStatus {
  pending('pending', 'Pending'),
  accepted('accepted', 'Accepted'),
  rejected('rejected', 'Declined');

  const ProposalStatus(this.value, this.label);
  final String value;
  final String label;

  static ProposalStatus from(String? v) =>
      ProposalStatus.values.firstWhere((s) => s.value == v, orElse: () => ProposalStatus.pending);
}

class ProposalCreator extends Equatable {
  const ProposalCreator({required this.id, required this.userId, required this.name, required this.slug, required this.title, this.avatarUrl, this.followerCount = 0});

  factory ProposalCreator.fromJson(Map<String, dynamic> json) {
    final user = J.map(json, 'user') ?? const <String, dynamic>{};
    return ProposalCreator(
      id: J.id(json),
      userId: J.refId(json, 'user') ?? '',
      name: J.str(user, 'name', 'Creator'),
      avatarUrl: J.strOrNull(user, 'avatarUrl'),
      slug: J.str(json, 'slug'),
      title: J.str(json, 'title'),
      followerCount: J.integer(json, 'followerCount'),
    );
  }

  final String id;
  final String userId;
  final String name;
  final String? avatarUrl;
  final String slug;
  final String title;
  final int followerCount;

  String get initials => name.isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

  @override
  List<Object?> get props => [id];
}

class Proposal extends Equatable {
  const Proposal({
    required this.id,
    required this.campaignId,
    required this.creatorId,
    required this.pitch,
    required this.portfolioLinks,
    required this.deliveryTimeline,
    required this.status,
    this.quotedAmount,
    this.campaign,
    this.creator,
    this.rejectionReason,
    this.createdAt,
  });

  factory Proposal.fromJson(Map<String, dynamic> json) {
    final campaign = J.map(json, 'campaign');
    final creator = J.map(json, 'creator');
    return Proposal(
      id: J.id(json),
      campaignId: J.refId(json, 'campaign') ?? '',
      creatorId: J.refId(json, 'creator') ?? '',
      campaign: campaign == null ? null : Campaign.fromJson(campaign),
      creator: creator == null ? null : ProposalCreator.fromJson(creator),
      pitch: J.str(json, 'pitch'),
      quotedAmount: J.integerOrNull(json, 'quotedAmount'),
      portfolioLinks: J.strings(json, 'portfolioLinks'),
      deliveryTimeline: J.str(json, 'deliveryTimeline'),
      status: ProposalStatus.from(J.strOrNull(json, 'status')),
      rejectionReason: J.strOrNull(json, 'rejectionReason'),
      createdAt: J.date(json, 'createdAt'),
    );
  }

  final String id;
  final String campaignId;
  final String creatorId;
  final Campaign? campaign;
  final ProposalCreator? creator;
  final String pitch;
  final int? quotedAmount;
  final List<String> portfolioLinks;
  final String deliveryTimeline;
  final ProposalStatus status;
  final String? rejectionReason;
  final DateTime? createdAt;

  @override
  List<Object?> get props => [id, status];
}

class ProposalCounts {
  const ProposalCounts({this.all = 0, this.pending = 0, this.accepted = 0, this.rejected = 0});

  factory ProposalCounts.fromJson(Map<String, dynamic> json) => ProposalCounts(
    all: J.integer(json, 'all'),
    pending: J.integer(json, 'pending'),
    accepted: J.integer(json, 'accepted'),
    rejected: J.integer(json, 'rejected'),
  );

  final int all;
  final int pending;
  final int accepted;
  final int rejected;
}

enum MilestoneStatus {
  pending('pending', 'Awaiting funding'),
  funded('funded', 'Funded — in progress'),
  submitted('submitted', 'Work submitted'),
  changesRequested('changes_requested', 'Changes requested'),
  disputed('disputed', 'In dispute'),
  released('released', 'Paid');

  const MilestoneStatus(this.value, this.label);
  final String value;
  final String label;

  static MilestoneStatus from(String? v) =>
      MilestoneStatus.values.firstWhere((s) => s.value == v, orElse: () => MilestoneStatus.pending);
}

class Attachment extends Equatable {
  const Attachment({required this.name, required this.url});

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      Attachment(name: J.str(json, 'name', 'File'), url: J.str(json, 'url'));

  final String name;
  final String url;

  @override
  List<Object?> get props => [url];
}

class Milestone extends Equatable {
  const Milestone({
    required this.id,
    required this.title,
    required this.amount,
    required this.order,
    required this.status,
    required this.submissionDescription,
    required this.submissionLinks,
    required this.submissionAttachments,
    required this.changeDescription,
    required this.changeReferenceLinks,
    required this.changeAttachments,
    this.submittedAt,
    this.fundedAt,
    this.releasedAt,
    this.autoReleaseAt,
  });

  factory Milestone.fromJson(Map<String, dynamic> json) => Milestone(
    id: J.id(json),
    title: J.str(json, 'title'),
    amount: J.integer(json, 'amount'),
    order: J.integer(json, 'order', 1),
    status: MilestoneStatus.from(J.strOrNull(json, 'status')),
    submissionDescription: J.str(json, 'submissionDescription'),
    submissionLinks: J.strings(json, 'submissionLinks'),
    submissionAttachments: J.list(json, 'submissionAttachments', Attachment.fromJson),
    changeDescription: J.str(json, 'changeDescription'),
    changeReferenceLinks: J.strings(json, 'changeReferenceLinks'),
    changeAttachments: J.list(json, 'changeAttachments', Attachment.fromJson),
    submittedAt: J.date(json, 'submittedAt'),
    fundedAt: J.date(json, 'fundedAt'),
    releasedAt: J.date(json, 'releasedAt'),
    autoReleaseAt: J.date(json, 'autoReleaseAt'),
  );

  final String id;
  final String title;
  final int amount;
  final int order;
  final MilestoneStatus status;
  final String submissionDescription;
  final List<String> submissionLinks;
  final List<Attachment> submissionAttachments;
  final String changeDescription;
  final List<String> changeReferenceLinks;
  final List<Attachment> changeAttachments;
  final DateTime? submittedAt;
  final DateTime? fundedAt;
  final DateTime? releasedAt;
  final DateTime? autoReleaseAt;

  @override
  List<Object?> get props => [id, status, submittedAt];
}