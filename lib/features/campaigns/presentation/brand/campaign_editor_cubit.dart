import 'package:equatable/equatable.dart';

import '../../../../core/bloc/safe_cubit.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/services/media_picker.dart';
import '../../data/campaign_models.dart';
import '../../data/campaign_repository.dart';

enum EditorStep { basics, budget, brief, media, review }

class CampaignEditorState extends Equatable {
  const CampaignEditorState({
    this.campaign,
    this.step = EditorStep.basics,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.errorCode,
    this.published = false,
    this.tick = 0,
  });

  final Campaign? campaign;
  final EditorStep step;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? errorCode;
  final bool published;
  final int tick;

  CampaignEditorState copyWith({
    Campaign? campaign,
    EditorStep? step,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    String? errorCode,
    bool? published,
    int? tick,
  }) =>
      CampaignEditorState(
        campaign: campaign ?? this.campaign,
        step: step ?? this.step,
        isLoading: isLoading ?? this.isLoading,
        isSaving: isSaving ?? this.isSaving,
        errorMessage: errorMessage,
        errorCode: errorCode,
        published: published ?? this.published,
        tick: tick ?? this.tick,
      );

  @override
  List<Object?> get props => [campaign, step, isLoading, isSaving, errorMessage, errorCode, published, tick];
}

/// Drives the 5-step campaign wizard. Every step is saved to the draft on
/// the server before moving on, so a brand can leave and continue later.
class CampaignEditorCubit extends SafeCubit<CampaignEditorState> {
  CampaignEditorCubit(this._repo, {String? draftId}) : super(CampaignEditorState(isLoading: draftId != null)) {
    if (draftId != null) _load(draftId);
  }

  final CampaignRepository _repo;

  String? get _id => state.campaign?.id;

  Future<void> _load(String id) async {
    try {
      final campaign = await _repo.owned(id);
      safeEmit(state.copyWith(campaign: campaign, isLoading: false));
    } on ApiException catch (error) {
      safeEmit(state.copyWith(isLoading: false, errorMessage: error.displayMessage, tick: state.tick + 1));
    }
  }

  void goTo(EditorStep step) => safeEmit(state.copyWith(step: step));

  void back() {
    if (state.step.index > 0) goTo(EditorStep.values[state.step.index - 1]);
  }

  Future<bool> _save(Future<Campaign?> Function() task, {EditorStep? next}) async {
    if (state.isSaving) return false;
    safeEmit(state.copyWith(isSaving: true));
    try {
      final updated = await task();
      safeEmit(state.copyWith(campaign: updated, isSaving: false, step: next));
      return true;
    } on ApiException catch (error) {
      safeEmit(state.copyWith(isSaving: false, errorMessage: error.displayMessage, errorCode: error.errorCode, tick: state.tick + 1));
      return false;
    }
  }

  Future<bool> saveBasics({
    required String title,
    required CampaignType type,
    required LocationType locationType,
    required String locationValue,
    String? categoryId,
  }) {
    return _save(() async {
      var campaign = _id == null
          ? await _repo.createDraft(title: title, type: type, locationType: locationType, locationValue: locationValue)
          : null;
      final id = campaign?.id ?? _id!;
      campaign = await _repo.updateDraft(id, {
        'title': title,
        'campaignType': type.value,
        'locationType': locationType.value,
        'locationValue': locationValue,
        if (categoryId != null) 'category': categoryId,
      });
      return campaign;
    }, next: EditorStep.budget);
  }

  Future<bool> saveBudget({required int costPerInfluencer, required int maxInfluencers, required int milestoneCount, int? applicantLimit}) {
    return _save(
          () => _repo.updateDraft(_id!, {
        'costPerInfluencer': costPerInfluencer,
        'maxInfluencers': maxInfluencers,
        'milestoneCount': milestoneCount,
        if (applicantLimit != null) 'applicantLimit': applicantLimit,
      }),
      next: EditorStep.brief,
    );
  }

  Future<bool> addProduct({required String name, required int price, required int quantity, String description = '', PickedMedia? image}) {
    return _save(() async {
      await _repo.addProduct(_id!, name: name, price: price, quantity: quantity, description: description, image: image);
      return _repo.owned(_id!);
    });
  }

  Future<bool> removeProduct(String productId) {
    return _save(() async {
      await _repo.removeProduct(_id!, productId);
      return _repo.owned(_id!);
    });
  }

  Future<bool> saveBrief(Map<String, dynamic> fields) => _save(() => _repo.updateDraft(_id!, fields), next: EditorStep.media);

  /// Reference links (Instagram/YouTube posts etc.) — saved on the draft,
  /// then moves on to the review step.
  Future<bool> saveSampleLinks(List<String> links) =>
      _save(() => _repo.updateDraft(_id!, {'sampleMedia': links}), next: EditorStep.review);

  Future<bool> uploadMedia({PickedMedia? cover, List<PickedMedia> media = const []}) {
    return _save(() async {
      await _repo.uploadMedia(_id!, cover: cover, media: media);
      return _repo.owned(_id!);
    });
  }

  Future<bool> publish() async {
    final ok = await _save(() => _repo.publish(_id!));
    if (ok) safeEmit(state.copyWith(published: true));
    return ok;
  }
}