import '../models/vaccine_product.dart';

/// 2026-11-19에 식품의약품안전처 의약품통합정보시스템에서 확인한 초기 목록입니다.
/// 확인하지 못한 값은 비워 두고, 맞지 않는 제조사 조합은 확정하지 않습니다.
class VaccineCatalogSeed {
  const VaccineCatalogSeed({
    required this.productName,
    required this.manufacturer,
    required this.vaccineType,
    required this.authorizationReference,
    required this.authorizationItemCode,
    required this.sourceDocument,
    required this.sourceUrl,
    required this.sourceCheckedAt,
    required this.verificationStatus,
    required this.profiles,
  });

  static const String checkedOn = '2026-11-19';
  static const String mfds = '식품의약품안전처 의약품통합정보시스템';

  /// 신규 운송 등록에서 고를 수 있는 제품입니다. 나머지 제품 행은 과거 기록용으로 남깁니다.
  static const Set<String> selectableProductNames = <String>{
    '코미나티제이엔원주',
    '스카이셀플루4가프리필드시린지',
  };

  static String nedrugUrl(String itemCode) {
    return 'https://nedrug.mfds.go.kr/pbp/CCBBB01/getItemDetail?itemSeq=$itemCode';
  }

  static String reference({
    required String document,
    required String? itemCode,
    required String? url,
    required StorageVerificationStatus status,
  }) {
    final StringBuffer text = StringBuffer()
      ..writeln(mfds)
      ..writeln(document);
    if (itemCode != null) {
      text.writeln('품목기준코드 $itemCode');
    }
    if (url != null) {
      text.writeln(url);
    }
    text
      ..writeln('확인일 $checkedOn')
      ..write('검증 상태: ${status.label}');
    return text.toString();
  }

  final String productName;
  final String? manufacturer;
  final String? vaccineType;
  final String? authorizationReference;
  final String? authorizationItemCode;
  final String? sourceDocument;
  final String? sourceUrl;
  final String sourceCheckedAt;
  final StorageVerificationStatus verificationStatus;
  final List<VaccineProfileSeed> profiles;

  bool get selectableForNewShipment {
    return selectableProductNames.contains(productName);
  }

  static final List<VaccineCatalogSeed> products = <VaccineCatalogSeed>[
    VaccineCatalogSeed(
      productName: '코미나티제이엔원주',
      manufacturer: '한국화이자제약(주)',
      vaccineType: 'mRNA 백신',
      authorizationReference: mfds,
      authorizationItemCode: '202402096',
      sourceDocument: '코미나티제이엔원주(브레토바메란)(사스코로나바이러스-2 mRNA 백신)',
      sourceUrl: nedrugUrl('202402096'),
      sourceCheckedAt: checkedOn,
      verificationStatus: StorageVerificationStatus.verified,
      profiles: <VaccineProfileSeed>[
        VaccineProfileSeed(
          profileName: '냉동 보관',
          storageStage: 'frozen',
          minTemperature: -90,
          maxTemperature: -60,
          freezingProhibited: false,
          refreezingProhibited: false,
          lightProtectionRequired: true,
          handlingNotes: '차광하여 보관합니다. 해동과 사용 전 취급 조건은 이 냉동 범위와 별도로 확인합니다.',
          timeLimitNotes: null,
          verificationStatus: StorageVerificationStatus.verified,
        ),
        VaccineProfileSeed(
          profileName: '해동 후 냉장 보관',
          storageStage: 'thawed_refrigerated',
          minTemperature: 2,
          maxTemperature: 8,
          freezingProhibited: true,
          refreezingProhibited: true,
          lightProtectionRequired: true,
          handlingNotes: '해동 후 재냉동 금지. 차광. 제품별 해동 및 사용 전 취급 조건을 확인합니다.',
          timeLimitNotes:
              '해동 후 냉장 보관 가능 기간은 최대 10주입니다. '
              '사용 직전 8~30°C 최대 12시간 조건과는 다른 개념이며 운송 온도 범위로 쓰지 않습니다.',
          verificationStatus: StorageVerificationStatus.verified,
        ),
      ],
    ),
    VaccineCatalogSeed(
      productName: '스카이셀플루4가프리필드시린지',
      manufacturer: '에스케이바이오사이언스(주)',
      vaccineType: '세포배양 인플루엔자 백신',
      authorizationReference: mfds,
      authorizationItemCode: '201508425',
      sourceDocument: '스카이셀플루4가프리필드시린지(세포배양인플루엔자표면항원백신)',
      sourceUrl: nedrugUrl('201508425'),
      sourceCheckedAt: checkedOn,
      verificationStatus: StorageVerificationStatus.verified,
      profiles: <VaccineProfileSeed>[
        VaccineProfileSeed(
          profileName: '냉장 보관',
          storageStage: 'refrigerated',
          minTemperature: 2,
          maxTemperature: 8,
          freezingProhibited: true,
          refreezingProhibited: false,
          lightProtectionRequired: true,
          handlingNotes: '동결 금지. 차광하여 보관. 밀봉용기인 원래 포장 상태를 유지합니다.',
          timeLimitNotes: null,
          verificationStatus: StorageVerificationStatus.verified,
        ),
      ],
    ),
    VaccineCatalogSeed(
      productName: '싱그릭스주',
      manufacturer: '(주)글락소스미스클라인',
      vaccineType: '유전자재조합 대상포진 백신',
      authorizationReference: mfds,
      authorizationItemCode: '202106382',
      sourceDocument: '싱그릭스주[대상포진바이러스백신(유전자재조합)]',
      sourceUrl: nedrugUrl('202106382'),
      sourceCheckedAt: checkedOn,
      verificationStatus: StorageVerificationStatus.verified,
      profiles: <VaccineProfileSeed>[
        VaccineProfileSeed(
          profileName: '냉장 보관',
          storageStage: 'refrigerated',
          minTemperature: 2,
          maxTemperature: 8,
          freezingProhibited: true,
          refreezingProhibited: false,
          lightProtectionRequired: true,
          handlingNotes: '동결 금지. 차광을 위해 원래 포장에 보관. 재구성 후 사용 조건은 별도로 확인합니다.',
          timeLimitNotes:
              '재구성 후 6시간 이내 사용은 사용 전 조건입니다. '
              '운송 시간 제한이 아니며 자동으로 세지 않습니다.',
          verificationStatus: StorageVerificationStatus.verified,
        ),
      ],
    ),
    VaccineCatalogSeed(
      productName: '프리베나프리필드시린지',
      manufacturer: null,
      vaccineType: null,
      authorizationReference: null,
      authorizationItemCode: null,
      sourceDocument:
          '사용자 제공 자료에는 제조사가 MSD로 적혀 있었습니다. '
          '2026-11-19 식품의약품안전처 의약품통합정보시스템에서 '
          '제품명 프리베나프리필드시린지와 제조사 MSD가 일치하는 품목을 확인하지 못했습니다. '
          '유사 품목인 프리베나20프리필드시린지(한국화이자제약, 품목기준코드 202402578)로 대체하지 않습니다.',
      sourceUrl: null,
      sourceCheckedAt: checkedOn,
      verificationStatus: StorageVerificationStatus.verificationRequired,
      profiles: <VaccineProfileSeed>[
        VaccineProfileSeed(
          profileName: '냉장 보관',
          storageStage: 'refrigerated',
          minTemperature: 2,
          maxTemperature: 8,
          freezingProhibited: true,
          refreezingProhibited: false,
          lightProtectionRequired: true,
          handlingNotes: '동결 금지. 차광. 제품명과 제조사 조합은 아직 확인되지 않았습니다.',
          timeLimitNotes: null,
          verificationStatus: StorageVerificationStatus.verificationRequired,
        ),
      ],
    ),
    VaccineCatalogSeed(
      productName: '스카이조스터주',
      manufacturer: '에스케이바이오사이언스(주)',
      vaccineType: '대상포진 생바이러스 백신',
      authorizationReference: mfds,
      authorizationItemCode: '201707343',
      sourceDocument: '스카이조스터주(대상포진생바이러스백신)',
      sourceUrl: nedrugUrl('201707343'),
      sourceCheckedAt: checkedOn,
      verificationStatus: StorageVerificationStatus.verified,
      profiles: <VaccineProfileSeed>[
        VaccineProfileSeed(
          profileName: '냉장 보관',
          storageStage: 'refrigerated',
          minTemperature: 2,
          maxTemperature: 8,
          freezingProhibited: true,
          refreezingProhibited: false,
          lightProtectionRequired: true,
          handlingNotes: '동결 금지. 차광. 재구성 후 사용시간은 별도로 관리합니다.',
          timeLimitNotes: '재구성 후 30분 이내 사용. 이 시간은 운송 시간 제한이 아닙니다.',
          verificationStatus: StorageVerificationStatus.verified,
        ),
      ],
    ),
    VaccineCatalogSeed(
      productName: '로타릭스액',
      manufacturer: '(주)글락소스미스클라인',
      vaccineType: '경구용 로타바이러스 생백신',
      authorizationReference: mfds,
      authorizationItemCode: '201100256',
      sourceDocument: '로타릭스 액(경구용 약독화 로타 생바이러스 백신)',
      sourceUrl: nedrugUrl('201100256'),
      sourceCheckedAt: checkedOn,
      verificationStatus: StorageVerificationStatus.verified,
      profiles: <VaccineProfileSeed>[
        VaccineProfileSeed(
          profileName: '냉장 보관',
          storageStage: 'refrigerated',
          minTemperature: 2,
          maxTemperature: 8,
          freezingProhibited: true,
          refreezingProhibited: false,
          lightProtectionRequired: true,
          handlingNotes: '동결 금지. 차광. 원래 포장 상태 유지.',
          timeLimitNotes: null,
          verificationStatus: StorageVerificationStatus.verified,
        ),
      ],
    ),
  ];
}

class VaccineProfileSeed {
  const VaccineProfileSeed({
    required this.profileName,
    required this.storageStage,
    required this.minTemperature,
    required this.maxTemperature,
    required this.freezingProhibited,
    required this.refreezingProhibited,
    required this.lightProtectionRequired,
    required this.handlingNotes,
    required this.timeLimitNotes,
    required this.verificationStatus,
  });

  final String profileName;
  final String storageStage;
  final double minTemperature;
  final double maxTemperature;
  final bool freezingProhibited;
  final bool refreezingProhibited;
  final bool lightProtectionRequired;
  final String? handlingNotes;
  final String? timeLimitNotes;
  final StorageVerificationStatus verificationStatus;

  String referenceFor(VaccineCatalogSeed product) {
    return VaccineCatalogSeed.reference(
      document: product.sourceDocument ?? product.productName,
      itemCode: product.authorizationItemCode,
      url: product.sourceUrl,
      status: verificationStatus,
    );
  }
}
