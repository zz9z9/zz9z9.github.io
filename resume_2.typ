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

  기술 스택, 데이터 특성, 조직 구조 등을 고려하여 상황에 맞는 해결책을 찾는 데 집중하고,\
  코드의 전제조건을 줄여, 예측 가능성을 높이는 것을 중요하게 생각합니다.

  AI 시대에도 결과를 그대로 수용하기보다, 스스로 사고하는 과정을 놓치지 않으려 노력합니다.
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
#text(8.5pt, fill: subtle)[기존 정산 시스템을 참고하되, 비효율적인 부분은 개선하는 방향으로 설계]
#v(5pt)
#tag("멀티모듈 구조 설계")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[기존 구조는 core(공통) 모듈이 비대해지면서 불필요한 의존성 확산, 의존성 변경 시 영향도 파악의 어려움, 사용하지 않는 DB 커넥션 점유 등의 문제가 있었음]]
- 관심사에 따라 6개 모듈로 분리:
  - domain: 정산 도메인 모델 및 공통 비즈니스 로직
  - starters: 기술별 의존성·설정 관리
  - clients: 외부 시스템 연동
  - support: 횡단 관심사 (국제화 처리 등)
  - utils: 외부 라이브러리/Spring 의존 없는 순수 Java 유틸
  - applications: 각 애플리케이션이 필요한 모듈만 선택적으로 의존
    - 예: 모든 애플리케이션이 기본적으로 JPA(starter-jpa 모듈)를 사용하되, 네이티브 쿼리 사용이 필요한 특정 애플리케이션에서는 MyBatis(starter-mybatis 모듈)도 함께 사용 가능

- Gradle 빌드 시점에 모듈 간 의존 방향을 검증하고, 의존성은 기본적으로 implementation으로 선언해 불필요한 전이를 차단

#v(5pt)
#tag("Kafka 기반 결제 데이터 동기화")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[기존에는 배치가 결제 시스템 DB를 직접 조회하여 매일 자정 이후 전날 결제 데이터를 동기화하는 구조로, 데이터 증가에 따라 동기화 시간이 길어지고 시스템 간 결합도가 높아지는 문제가 있었음]]
- Kafka를 통해 결제 시스템과의 결합도를 낮추면서 데이터를 준실시간으로 동기화하도록 설계
- 메시지 유실·정합성 어긋남에 대비한 안전망 구성:
  - 컨슈머 처리에 실패한 메시지는 DLT(Dead Letter Topic)로 격리한 뒤, 별도 배치로 원본 토픽에 재발행하여 재처리
  - 일별 정산 처리에 앞서 결제 시스템 집계 API와 정산 DB 집계를 대사하고, 차이가 있으면 후속 정산 작업이 자동 차단되도록 구성
  - 위 단계에서 발견된 이슈 목록 등을 운영·개발팀에 알림으로 발송

#v(5pt)
#tag("AI 도구 활용 워크플로우 구축")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[Claude Code 도입 후 개발자마다 활용 수준과 결과물의 품질 편차가 크다고 판단. AI가 작성한 코드라도 운영 책임은 개발자에게 있으므로, 품질을 담보할 수 있는 안전망이 필요하다고 판단]]
- 요구사항 명세 작성 → 테스트 작성 → 구현 → 문서 동기화 워크플로우를 정의하고 커스텀 스킬로 구성
- 애플리케이션별로 고려해야 할 관점이 다르다고 판단하여, 스킬 사용 시 각각의 대화 흐름을 별도로 설계
  - 예: 배치는 멱등성·재처리·Chunk/Tasklet 판단, 컨슈머는 중복 메시지 처리 등

#v(5pt)
#tag("배치 스케줄링 환경 개선")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[기존 배치 스케줄러는 Jenkins Freestyle Job을 UI에서 직접 조작하는 방식이라, 변경 이력 관리·환경 재현이 어렵고 부분 재수행 시 트리거 복원 누락 등 운영 사고가 발생한 적이 있었음]]
- 코드 기반 전환: Freestyle → Pipeline(Jenkinsfile) + Shared Library로 Job 정의·연계·재시도·알림을 모두 코드로 관리 → Git 기반 변경 이력/리뷰, 환경 간 동일 재현, 공통 로직 재사용 가능
- 구조·가시성: 역할(단독 Job / 연계 Job)·도메인 기반 네이밍과 디렉토리 분리로 연계·단독·도메인 식별을 즉시 가능, 순번 의존 제거
- 재수행 워크플로우: 연계 Job 단위 파라미터로 일자 일괄 전파, 단계별 선택 실행을 파라미터로 노출, 선행 Job은 당일 성공 이력이 있으면 스킵하는 멱등 트리거 적용 → 코드 수정·복원 불필요
- 운영 가시성: 연계 Job 한 번 실행으로 전체 수행 시간 자동 측정, 실패 시 CloudWatch 에러 로그 자동 출력, 사내 장애 모니터링 시스템으로 자동 전파 (spring batch admin 수동 유지 종료)


#v(8pt)

#text(11pt, weight: "bold")[2. Cubrid → MySQL DB 전환]
#v(2pt)
#text(8.5pt, fill: subtle)[기술 지원이 종료된 Cubrid 9.3 운영 DB를 MySQL로 전환 · 약 126개 테이블 대상]
#v(5pt)
#tag("쿼리 검증 체계 구축")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[MyBatis 기반 Cubrid 쿼리를 MySQL용으로 변환해야 하며, 변환된 쿼리가 기존과 동일한 결과를 반환하는지 검증할 체계가 필요]]
- Spring AOP로 Cubrid DAO 호출을 인터셉트하여, JoinPoint의 메서드·클래스 정보 기반으로 MySQL DAO 빈을 ApplicationContext에서 동적 조회 후 동일 파라미터로 병렬 실행하는 구조 설계
- SELECT 쿼리는 비동기로 실행하되 List·Map·DTO 등 리턴 타입별로 비교하고, 쿼리 에러·데이터 불일치를 별도 테이블에 기록하여 개발자에게 알림 전달
- 실제 운영 트래픽으로 쿼리 정합성을 사전 검증

#v(5pt)
#tag("서비스 점검 시간 최소화")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[데이터 이관 중 애플리케이션을 읽기 전용 DB로 연결하여 서비스를 유지하되, 쓰기 불가 시간을 최소화해야 했음]]
- CDC(Change Data Capture) 방식을 검토했으나 Cubrid를 지원하는 플랫폼이 존재하지 않음
- 이력·배치 전용 테이블을 사전 이관하여 실제 전환 시 처리해야 할 데이터량을 축소
- 서비스 점검 시간을 약 20분 수준으로 제한

#v(5pt)
#tag("롤백 대비 이중 적재 및 분산 트랜잭션")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[전환 후 Cubrid 롤백 가능성에 대비해 두 DB 모두에 데이터 적재해야 하며, 분산 트랜잭션 전략 선택이 필요했음]]
- 2PC(2Phase Commit)는 트랜잭션을 조율하는 컴포넌트가 단일 장애점이 될 수 있는 문제와, Cubrid의 XA(분산 트랜잭션 표준 인터페이스) 환경에서 HA failover를 지원하지 않는 제약으로 배제함.
- 대안으로 Spring Data의 ChainedTransactionManager를 적용
  - 원자성이 완전히 보장되지 않아 deprecated 상태이나, 해당 한계를 인지하고 사용
  - 커밋 순서를 MySQL 우선으로 설정하여, MySQL 커밋 후 Cubrid 커밋이 실패하더라도 주 DB인 MySQL에는 데이터가 보존되도록 설계.
  - 이러한 불일치는 발생 확률이 매우 낮고, Cubrid 측만의 누락이므로 운영 영향이 없어 허용 가능한 트레이드오프로 판단

#v(5pt)
#tag("application.yml 기반 단계적 전환 제어")
#v(1pt)
#block(inset: (left: 8pt), stroke: (left: 2pt + rgb("#d0d0d0")))[#text(8.5pt, fill: subtle)[검증·전환·동시 운영 등 단계별로 읽기/쓰기 대상 DB를 유연하게 전환할 수 있는 구조가 필요]]
- 프로퍼티 설정으로 읽기/쓰기 각각의 대상 DB와 이중 실행 여부를 제어하도록 구성
  - 쿼리 검증 단계: 읽기·쓰기 모두 이중 실행, MySQL은 비동기로 처리하고 결과는 Cubrid 기준
  - MySQL 전환 후 동시 운영 단계: 읽기는 MySQL, 쓰기는 이중 적재

#v(8pt)

#text(11pt, weight: "bold")[3. 상품권 주문 API 동시성 개선]
#v(5pt)
- 상품권 핀번호 발행 시 SELECT FOR UPDATE의 잠금 경합을 SKIP LOCKED + 복합 인덱스로 해소하여 동시 주문 처리 성능 개선
- 동시 차감 환경에서 관리자 알림이 누락되는 이슈를 낙관적 락 기반 임계값 감지로 해결하고, 알림 발송을 트랜잭션 밖으로 분리하여 커넥션 점유 시간 단축
