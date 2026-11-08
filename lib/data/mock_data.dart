// 서버·데이터베이스를 연결하기 전까지 쓰는 임시 데이터입니다.
// 나중에 API를 붙이면 이 파일의 값만 실제 응답으로 바꾸면 됩니다.

class Shipment {
  const Shipment({
    required this.id,
    required this.vaccine,
    required this.route,
    required this.currentTempC,
    required this.targetRange,
    required this.eta,
    required this.status,
  });

  final String id;
  final String vaccine;
  final String route;
  final double currentTempC;
  final String targetRange;
  final String eta;
  final String status;
}

class QualityBatch {
  const QualityBatch({
    required this.lot,
    required this.vaccine,
    required this.compliance,
    required this.excursions,
    required this.status,
  });

  final String lot;
  final String vaccine;
  final int compliance;
  final int excursions;
  final String status;
}

class MedicalInventory {
  const MedicalInventory({
    required this.lot,
    required this.vaccine,
    required this.doses,
    required this.storageTempC,
    required this.ready,
  });

  final String lot;
  final String vaccine;
  final int doses;
  final double storageTempC;
  final bool ready;
}

const List<Shipment> kMockShipments = [
  Shipment(
    id: 'VT-24031',
    vaccine: 'mRNA COVID-19 (Lot A12)',
    route: '인천창고 → 서울대병원',
    currentTempC: -72.4,
    targetRange: '-80 ~ -60°C',
    eta: '오늘 14:20',
    status: '운송 중',
  ),
  Shipment(
    id: 'VT-24028',
    vaccine: '인플루엔자 4가',
    route: '오산허브 → 분당서울대병원',
    currentTempC: 4.1,
    targetRange: '2 ~ 8°C',
    eta: '오늘 16:05',
    status: '정상',
  ),
  Shipment(
    id: 'VT-24019',
    vaccine: '소아용 MMR',
    route: '김포CDC → 강남세브란스',
    currentTempC: 6.8,
    targetRange: '2 ~ 8°C',
    eta: '내일 09:10',
    status: '주의',
  ),
];

const List<QualityBatch> kMockBatches = [
  QualityBatch(
    lot: 'LOT-KR-8812',
    vaccine: 'mRNA COVID-19',
    compliance: 99,
    excursions: 0,
    status: '적합',
  ),
  QualityBatch(
    lot: 'LOT-KR-7740',
    vaccine: '인플루엔자 4가',
    compliance: 96,
    excursions: 1,
    status: '검토',
  ),
  QualityBatch(
    lot: 'LOT-KR-6621',
    vaccine: 'B형간염',
    compliance: 100,
    excursions: 0,
    status: '적합',
  ),
];

const List<MedicalInventory> kMockInventory = [
  MedicalInventory(
    lot: 'LOT-KR-8812',
    vaccine: 'mRNA COVID-19',
    doses: 48,
    storageTempC: -70.2,
    ready: true,
  ),
  MedicalInventory(
    lot: 'LOT-KR-7740',
    vaccine: '인플루엔자 4가',
    doses: 120,
    storageTempC: 3.6,
    ready: true,
  ),
  MedicalInventory(
    lot: 'LOT-KR-5518',
    vaccine: 'HPV 9가',
    doses: 16,
    storageTempC: 9.4,
    ready: false,
  ),
];
