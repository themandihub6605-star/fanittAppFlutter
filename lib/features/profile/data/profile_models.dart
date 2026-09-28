import 'package:equatable/equatable.dart';

import '../../../core/enums/user_role.dart';
import '../../../core/models/common_models.dart';
import '../../../core/utils/json.dart';

class Socials extends Equatable {
  const Socials(this.values);

  factory Socials.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Socials({});
    return Socials({
      for (final entry in json.entries)
        if (entry.value is String && (entry.value as String).trim().isNotEmpty) entry.key: (entry.value as String).trim(),
    });
  }

  final Map<String, String> values;

  String get(String key) => values[key] ?? '';

  @override
  List<Object?> get props => [values];
}

class CreatorProfile extends Equatable {
  const CreatorProfile({
    required this.id,
    required this.userId,
    required this.slug,
    required this.name,
    required this.bio,
    required this.title,
    required this.skills,
    required this.languages,
    required this.location,
    required this.socials,
    required this.isAvailableForWork,
    required this.followerCount,
    required this.averageRating,
    required this.reviewCount,
    required this.verificationStatus,
    required this.portfolioLink,
    required this.responseTime,
    required this.planName,
    required this.isProPlan,
    required this.isFollowing,
    required this.totalEarnings,
    this.avatarUrl,
    this.coverImageUrl,
    this.category,
    this.yearsOfExperience,
    this.agencyId,
  });

  factory CreatorProfile.fromJson(Map<String, dynamic> json) {
    final user = J.map(json, 'user') ?? const <String, dynamic>{};
    return CreatorProfile(
      id: J.id(json),
      userId: J.refId(json, 'user') ?? '',
      slug: J.str(json, 'slug'),
      name: J.str(user, 'name', 'Creator'),
      avatarUrl: J.strOrNull(user, 'avatarUrl'),
      bio: J.str(json, 'bio'),
      title: J.str(json, 'title'),
      category: Category.fromRef(json, 'category'),
      skills: J.strings(json, 'skills'),
      languages: J.strings(json, 'languages'),
      location: J.str(json, 'location'),
      socials: Socials.fromJson(J.map(json, 'socials')),
      isAvailableForWork: J.boolean(json, 'isAvailableForWork', true),
      followerCount: J.integer(json, 'followerCount'),
      averageRating: J.dbl(json, 'averageRating'),
      reviewCount: J.integer(json, 'reviewCount'),
      verificationStatus: VerificationStatus.fromValue(J.strOrNull(json, 'verificationStatus')) ?? VerificationStatus.unverified,
      portfolioLink: J.str(json, 'portfolioLink'),
      responseTime: J.str(json, 'responseTime'),
      yearsOfExperience: J.integerOrNull(json, 'yearsOfExperience'),
      coverImageUrl: J.strOrNull(json, 'coverImageUrl'),
      planName: J.str(json, 'planName', 'Lite'),
      isProPlan: J.boolean(json, 'isProPlan'),
      isFollowing: J.boolean(json, 'isFollowing'),
      totalEarnings: J.integer(json, 'totalEarnings'),
      agencyId: J.refId(json, 'agency'),
    );
  }

  final String id;
  final String userId;
  final String slug;
  final String name;
  final String? avatarUrl;
  final String bio;
  final String title;
  final Category? category;
  final List<String> skills;
  final List<String> languages;
  final String location;
  final Socials socials;
  final bool isAvailableForWork;
  final int followerCount;
  final double averageRating;
  final int reviewCount;
  final VerificationStatus verificationStatus;
  final String portfolioLink;
  final String responseTime;
  final int? yearsOfExperience;
  final String? coverImageUrl;
  final String planName;
  final bool isProPlan;
  final bool isFollowing;
  final int totalEarnings;
  final String? agencyId;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  CreatorProfile copyWith({bool? isFollowing, int? followerCount}) => CreatorProfile(
        id: id,
        userId: userId,
        slug: slug,
        name: name,
        avatarUrl: avatarUrl,
        bio: bio,
        title: title,
        category: category,
        skills: skills,
        languages: languages,
        location: location,
        socials: socials,
        isAvailableForWork: isAvailableForWork,
        followerCount: followerCount ?? this.followerCount,
        averageRating: averageRating,
        reviewCount: reviewCount,
        verificationStatus: verificationStatus,
        portfolioLink: portfolioLink,
        responseTime: responseTime,
        yearsOfExperience: yearsOfExperience,
        coverImageUrl: coverImageUrl,
        planName: planName,
        isProPlan: isProPlan,
        isFollowing: isFollowing ?? this.isFollowing,
        totalEarnings: totalEarnings,
        agencyId: agencyId,
      );

  @override
  List<Object?> get props => [id, name, avatarUrl, bio, title, category, skills, followerCount, isFollowing, verificationStatus];
}

class BrandProfile extends Equatable {
  const BrandProfile({
    required this.id,
    required this.userId,
    required this.slug,
    required this.companyName,
    required this.tagline,
    required this.industry,
    required this.about,
    required this.location,
    required this.website,
    required this.companySize,
    required this.whatWeOffer,
    required this.targetAudience,
    required this.contactDesignation,
    required this.socials,
    required this.averageRating,
    required this.totalCampaigns,
    required this.totalSpent,
    required this.verificationStatus,
    required this.planName,
    this.logoUrl,
    this.foundedYear,
    this.agencyId,
  });

  factory BrandProfile.fromJson(Map<String, dynamic> json) => BrandProfile(
        id: J.id(json),
        userId: J.refId(json, 'user') ?? '',
        slug: J.str(json, 'slug'),
        companyName: J.str(json, 'companyName'),
        logoUrl: J.strOrNull(json, 'logoUrl'),
        tagline: J.str(json, 'tagline'),
        industry: J.str(json, 'industry'),
        about: J.str(json, 'about'),
        location: J.str(json, 'location'),
        website: J.str(json, 'website'),
        foundedYear: J.integerOrNull(json, 'foundedYear'),
        companySize: J.str(json, 'companySize'),
        whatWeOffer: J.strings(json, 'whatWeOffer'),
        targetAudience: J.str(json, 'targetAudience'),
        contactDesignation: J.str(json, 'contactDesignation'),
        socials: Socials.fromJson(J.map(json, 'socials')),
        averageRating: J.dbl(json, 'averageRating'),
        totalCampaigns: J.integer(json, 'totalCampaigns'),
        totalSpent: J.integer(json, 'totalSpent'),
        verificationStatus: VerificationStatus.fromValue(J.strOrNull(json, 'verificationStatus')) ?? VerificationStatus.unverified,
        planName: J.str(json, 'planName', 'Lite'),
        agencyId: J.refId(json, 'agency'),
      );

  final String id;
  final String userId;
  final String slug;
  final String companyName;
  final String? logoUrl;
  final String tagline;
  final String industry;
  final String about;
  final String location;
  final String website;
  final int? foundedYear;
  final String companySize;
  final List<String> whatWeOffer;
  final String targetAudience;
  final String contactDesignation;
  final Socials socials;
  final double averageRating;
  final int totalCampaigns;
  final int totalSpent;
  final VerificationStatus verificationStatus;
  final String planName;
  final String? agencyId;

  @override
  List<Object?> get props => [id, companyName, logoUrl, tagline, verificationStatus];
}

class AgencyProfile extends Equatable {
  const AgencyProfile({
    required this.id,
    required this.agencyName,
    required this.ownerName,
    required this.mobile,
    required this.city,
    required this.state,
    required this.gstNumber,
    required this.teamSize,
    required this.specialization,
    required this.referralCode,
    required this.commissionPercent,
    required this.verificationStatus,
    required this.rejectionReason,
    this.yearsInBusiness,
    this.documentUrl,
  });

  factory AgencyProfile.fromJson(Map<String, dynamic> json) => AgencyProfile(
        id: J.id(json),
        agencyName: J.str(json, 'agencyName'),
        ownerName: J.str(json, 'ownerName'),
        mobile: J.str(json, 'mobile'),
        city: J.str(json, 'city'),
        state: J.str(json, 'state'),
        gstNumber: J.str(json, 'gstNumber'),
        teamSize: J.str(json, 'teamSize'),
        yearsInBusiness: J.integerOrNull(json, 'yearsInBusiness'),
        specialization: J.str(json, 'specialization'),
        documentUrl: J.strOrNull(json, 'documentUrl'),
        referralCode: J.str(json, 'referralCode'),
        commissionPercent: J.dbl(json, 'commissionPercent'),
        verificationStatus: VerificationStatus.fromValue(J.strOrNull(json, 'verificationStatus')) ?? VerificationStatus.unverified,
        rejectionReason: J.str(json, 'rejectionReason'),
      );

  final String id;
  final String agencyName;
  final String ownerName;
  final String mobile;
  final String city;
  final String state;
  final String gstNumber;
  final String teamSize;
  final int? yearsInBusiness;
  final String specialization;
  final String? documentUrl;
  final String referralCode;
  final double commissionPercent;
  final VerificationStatus verificationStatus;
  final String rejectionReason;

  @override
  List<Object?> get props => [id, agencyName, documentUrl, verificationStatus];
}
