/// 품질관리자가 남긴 검토 이력 한 건입니다.
/// 상태를 바꿔도 이전 행을 지우지 않고 새 행을 추가합니다.
class QualityReview {
  const QualityReview({
    required this.id,
    required this.shipmentId,
    required this.reviewerUserId,
    required this.reviewerLoginId,
    required this.status,
    required this.comment,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int shipmentId;
  final int reviewerUserId;
  final String reviewerLoginId;
  final QualityReviewStatus status;
  final String comment;
  final DateTime createdAt;
  final DateTime updatedAt;
}

enum QualityReviewStatus {
  notReviewed,
  inReview,
  needsInformation,
  onHold,
  reviewCompleted;

  String get storageValue => switch (this) {
    QualityReviewStatus.notReviewed => 'not_reviewed',
    QualityReviewStatus.inReview => 'in_review',
    QualityReviewStatus.needsInformation => 'needs_information',
    QualityReviewStatus.onHold => 'on_hold',
    QualityReviewStatus.reviewCompleted => 'review_completed',
  };

  String get label => switch (this) {
    QualityReviewStatus.notReviewed => '검토 전',
    QualityReviewStatus.inReview => '검토 중',
    QualityReviewStatus.needsInformation => '추가 확인 필요',
    QualityReviewStatus.onHold => '사용 보류',
    QualityReviewStatus.reviewCompleted => '검토 완료',
  };

  String get medicalMessage => switch (this) {
    QualityReviewStatus.notReviewed => '품질관리자의 검토 기록이 없습니다.',
    QualityReviewStatus.inReview => '품질관리자가 운송 기록을 검토하고 있습니다.',
    QualityReviewStatus.needsInformation => '운송 기록에 대한 추가 확인이 필요합니다.',
    QualityReviewStatus.onHold => '품질관리자가 사용 보류 상태로 기록했습니다.',
    QualityReviewStatus.reviewCompleted =>
      '운송 기록에 대한 품질관리자의 검토가 완료되었습니다.',
  };

  static const List<QualityReviewStatus> editable = <QualityReviewStatus>[
    QualityReviewStatus.inReview,
    QualityReviewStatus.needsInformation,
    QualityReviewStatus.onHold,
    QualityReviewStatus.reviewCompleted,
  ];

  static QualityReviewStatus fromStorage(String value) {
    for (final QualityReviewStatus status in QualityReviewStatus.values) {
      if (status.storageValue == value) {
        return status;
      }
    }
    throw FormatException('저장할 수 없는 검토 상태입니다: $value');
  }
}

class QualityReviewCounts {
  const QualityReviewCounts({
    required this.notReviewed,
    required this.inReview,
    required this.needsInformation,
    required this.onHold,
    required this.completed,
  });

  final int notReviewed;
  final int inReview;
  final int needsInformation;
  final int onHold;
  final int completed;

  static const QualityReviewCounts empty = QualityReviewCounts(
    notReviewed: 0,
    inReview: 0,
    needsInformation: 0,
    onHold: 0,
    completed: 0,
  );

  factory QualityReviewCounts.fromLatest(
    Iterable<int> shipmentIds,
    Map<int, QualityReview> latest,
  ) {
    int notReviewed = 0;
    int inReview = 0;
    int needsInformation = 0;
    int onHold = 0;
    int completed = 0;
    for (final int id in shipmentIds) {
      final QualityReviewStatus status =
          latest[id]?.status ?? QualityReviewStatus.notReviewed;
      switch (status) {
        case QualityReviewStatus.notReviewed:
          notReviewed += 1;
        case QualityReviewStatus.inReview:
          inReview += 1;
        case QualityReviewStatus.needsInformation:
          needsInformation += 1;
        case QualityReviewStatus.onHold:
          onHold += 1;
        case QualityReviewStatus.reviewCompleted:
          completed += 1;
      }
    }
    return QualityReviewCounts(
      notReviewed: notReviewed,
      inReview: inReview,
      needsInformation: needsInformation,
      onHold: onHold,
      completed: completed,
    );
  }
}
