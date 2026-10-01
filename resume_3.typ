// ──────────────────────────────────────────
// 이재윤 이력서 — Typst
// ──────────────────────────────────────────

#set page(
  paper: "a4",
  margin: (top: 28mm, bottom: 24mm, left: 22mm, right: 22mm),
)

#set text(
  font: ("Apple SD Gothic Neo",),
  size: 9.5pt,
  fill: rgb("#2d2d2d"),
)

#set par(leading: 0.7em, justify: false)
#set list(marker: [•])

// ── 색상 ──
#let accent = rgb("#1a56db")
#let subtle  = rgb("#6b7280")
#let divider = rgb("#d1d5db")

// ── 유틸 ──
#let section-title(title) = {
  v(10pt)
  text(12pt, weight: "bold", fill: accent)[#title]
  v(2pt)
  line(length: 100%, stroke: 0.6pt + divider)
  v(4pt)
}

#let entry(l, r) = {
  grid(
    columns: (1fr, auto),
    l, text(size: 9pt, fill: subtle)[#r]
  )
}

#let tag(label) = {
  box(
    inset: (x: 5pt, y: 2pt),
    radius: 3pt,
    fill: rgb("#eff6ff"),
    text(8pt, fill: accent)[#label]
  )
}

// ═══════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════

#align(left)[
  #text(24pt, weight: "bold", fill: rgb("#111827"))[이재윤]
  #h(8pt)
  #text(12pt, fill: subtle)[서버 개발자]
]

#v(6pt)

#text(9pt, fill: subtle)[Email: ronyoon.dev\@gmail.com]\
#text(9pt, fill: subtle)[Blog: https://zz9z9.github.io]

#v(6pt)

#text(9.5pt, fill: rgb("#374151"))[
맥락을 기반으로 최적의 선택을 고민하는 개발자 이재윤입니다.

특정 기술에 얽매이기보다 비즈니스 요구사항, 데이터 특성, 트래픽 규모, 운영 환경을 함께 고려하여 상황에 맞는 해결책을 찾는 데 집중합니다.

또한 코드가 특정 가정이나 전제조건에 과도하게 의존하지 않도록 설계하여 시스템의 예측 가능성과 유지보수성을 높이는 것을 중요하게 생각합니다.

AI 시대에도 결과를 그대로 수용하기보다 왜 그런 결론이 나왔는지 스스로 검증하고 사고하는 과정을 놓치지 않으려 노력합니다.
]

// ═══════════════════════════════════════════
// SKILLS
// ═══════════════════════════════════════════

#section-title("기술 스택")

#v(2pt)
#grid(
  columns: (auto, 1fr),
  row-gutter: 6pt,
  text(9pt, weight: "bold")[Backend], h(8pt) + [Java, Spring Boot, Spring Batch, JPA, MyBatis],
  text(9pt, weight: "bold")[Messaging], h(8pt) + [Kafka],
  text(9pt, weight: "bold")[DB], h(8pt) + [MySQL, Cubrid],
  text(9pt, weight: "bold")[Infra], h(8pt) + [Nginx, Tomcat, Jenkins, Linux],
)

// ═══════════════════════════════════════════
// EXPERIENCE
// ═══════════════════════════════════════════

#section-title("경력")

// ── NHN PAYCO ──
#entry(
  [#text(11pt, weight: "bold")[NHN PAYCO] #h(6pt) #text(9pt, fill: subtle)[가맹점개발파트 · 선임]],
  [2021.11 — 현재]
)
#v(3pt)
- 신규 정산 시스템 설계 및 구축
- 페이코 상품권·가맹점 도메인의 서버 개발 및 운영 전반 담당
- 인증심사 대응 (개인정보 분리보관 및 암호화), 보안 취약점 개선
- 온프레미스 리눅스 서버 운영 (Nginx, Tomcat, Jenkins, SSL 인증서 등)

#v(6pt)

// ── 포스코디엑스 ──
#entry(
  [#text(11pt, weight: "bold")[포스코디엑스] #h(6pt) #text(9pt, fill: subtle)[MES3.0추진반 · 사원]],
  [2018.10 — 2021.11]
)
#v(3pt)
- 냉연조업 연속소둔 공정 비즈니스 로직 보완
- 서비스 운영 및 유지보수, 사용자 클레임 대응

// ═══════════════════════════════════════════
// EDUCATION
// ═══════════════════════════════════════════

#section-title("학력")

#entry(
  [#text(11pt, weight: "bold")[인천대학교] #h(6pt) #text(9pt, fill: subtle)[정보통신공학]],
  [2011.03 — 2018.02]
)

// ═══════════════════════════════════════════
// PROJECTS
// ═══════════════════════════════════════════

#pagebreak()
#section-title("프로젝트")

// ── NHN PAYCO 프로젝트 ──
#text(9pt, fill: subtle)[NHN PAYCO]

#v(6pt)

#text(11pt, weight: "bold")[1. 신규 정산 시스템 구축]
#v(2pt)
#text(8.5pt, fill: subtle)[신규 결제 서비스의 정산 시스템 설계 및 구현 · 3인 팀 리드 · 서비스 오픈 예정]\
#text(8.5pt, fill: subtle)[기존 정산 시스템의 구조적 한계와 운영 과정에서 발생한 문제를 개선하는 방향으로 신규 정산 시스템 설계]
#v(5pt)
#tag("아키텍처 및 운영 환경 개선")
#v(1pt)
- 공통 모듈 비대화로 인한 의존성 확산, 영향도 파악의 어려움을 해결하기 위해 도메인·기술 관심사 기준의 멀티모듈 구조 설계
- Gradle 빌드 단계에서 모듈 간 의존 방향을 검증하고 implementation 기반 의존성 관리로 불필요한 의존 전이 차단
- Jenkins Freestyle Job을 Pipeline + Shared Library 기반으로 전환하여 배치 연계 실행 등을 코드로 관리

#v(5pt)
#tag("Kafka 기반 결제 데이터 동기화")
#v(1pt)
- 배치가 결제 시스템 DB를 직접 조회하던 구조를 Kafka 기반 이벤트 동기화 방식으로 변경하여 시스템 간 결합도 감소
- 컨슈머 실패 메시지는 DLT로 격리 후 재처리할 수 있도록 구성
- 일별 정산 수행 전 결제 시스템 집계 결과와 정산 DB 데이터를 자동 대사하여 정합성 이상 시 후속 정산 작업을 차단하고 운영팀에 알림 발송

#v(5pt)
#tag("AI 활용 개발 워크플로우 구축")
#v(1pt)
- Claude Code 기반 요구사항 → 테스트 → 구현 → 문서 동기화 워크플로우를 정의
- 배치·API 등 애플리케이션 특성에 맞는 커스텀 스킬을 설계하여 AI 활용 시 품질 편차를 최소화

#v(8pt)

#text(11pt, weight: "bold")[2. Cubrid → MySQL DB 전환]
#v(2pt)
#text(8.5pt, fill: subtle)[기술 지원이 종료된 Cubrid 9.3 운영 DB를 MySQL로 전환 · 약 126개 테이블 대상]
#v(5pt)
#tag("쿼리 검증 및 단계적 전환 체계 구축")
#v(1pt)
- Spring AOP를 활용하여 Cubrid DAO 호출 시 동일 요청을 MySQL에도 병렬 실행하는 구조를 설계하여 실제 운영 트래픽 \ 기반으로 쿼리 정합성 검증
- 쿼리 오류 및 데이터 불일치를 기록하고 개발자에게 알림을 제공하여 전환 리스크 감소
- 전환 이후 롤백 가능성을 고려하여 동일 구조를 활용한 이중 적재 체계를 구축
- 설정 기반으로 읽기·쓰기 대상 DB를 단계적으로 전환할 수 있도록 구성

#v(5pt)
#tag("데이터 마이그레이션 전략 수립")
#v(1pt)
- 데이터 이관 중에도 서비스를 유지하기 위해 애플리케이션을 읽기 전용 DB로 연결하는 방식 검토
- Cubrid는 CDC(Change Data Capture) 기반 증분 동기화를 지원하지 않아 이력·배치성 테이블을 사전 이관하여 전환 시 \ 데이터 이관량 축소
- 서비스 점검 시간을 약 20분 수준으로 제한

#v(5pt)
#tag("분산 트랜잭션 전략 수립")
#v(1pt)
- XA 기반 2PC(2Phase Commit) 적용 시 발생하는 제약사항을 검토하고 ChainedTransactionManager 기반 구조 채택
- MySQL 우선 커밋 전략을 적용하여 주 DB 데이터 보존을 우선하도록 설계

#pagebreak()
#v(8pt)

#text(11pt, weight: "bold")[3. 상품권 주문 API 동시성 개선]
#text(8.5pt, fill: subtle)[상품권 핀번호 발급 및 재고 차감 과정의 동시성 이슈 개선]

#v(5pt)
#tag("주문 처리 성능 개선")
#v(1pt)
- 상품권 핀번호 발행 과정의 SELECT FOR UPDATE 잠금 경합을 분석하고, SKIP LOCKED + 복합 인덱스를 적용하여 동시 주문 처리 성능 개선

#v(5pt)
#tag("재고 임계치 알림 정합성 개선")
#v(1pt)
- 재고 동시 차감 환경에서 관리자 알림이 누락되는 문제를 낙관적 락 기반 임계값 감지 방식으로 해결
- 알림 발송을 트랜잭션 외부로 분리하여 커넥션 점유 시간 단축 및 처리 효율 개선
