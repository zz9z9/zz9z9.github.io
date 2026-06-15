

## 흐름
1. StatementImpl에서 인젝션 성립하는 원리 (SQL 표준 ?)
> 작은따옴표를 ''로 처리하는 건 **SQL 표준 방식(문자열 리터럴 안에서 따옴표를 두 번 쓰면 리터럴 한 글자)* ??

2. ClientPreparedStatement, ServerPreparedStatement 결정되는 방식
```java
ConnectionImpl.prepareStatement(sql, type, concurrency) — ConnectionImpl.java:1602 가 A/B/C를 가르는 단 하나의 메서드입니다:

if (this.useServerPrepStmts.getValue() && canServerPrepare) {   // ← C 경로
if (this.cachePrepStmts.getValue()) {
pStmt = this.serverSideStatementCache.remove(key);      // ← E 데모: 캐시 hit 면 재사용
if (pStmt == null)
pStmt = ServerPreparedStatement.getInstance(...);   // miss → 새 서버 prepare
} else {
pStmt = ServerPreparedStatement.getInstance(...);       // D 데모: 매번 새로
}
} else {                                                        // ← B 경로 (기본값)
pStmt = clientPrepareStatement(...);   // → ClientPreparedStatement
}

useServerPrepStmts=false(기본)면 무조건 else → ClientPreparedStatement. 이게 B가 서버 prepare 안 하는 코드 레벨 근거입니다.
```

2-1. ClientPreparedStatement가 인젝션 막는 방식
2-2. ServerPreparedStatement가 인젝션 막는 방식
부록. DB opcode (COM_QUERY, COM_PREPARE, COM_STMT)

3. ClientPreparedStatement vs ServerPreparedStatement
- 캐싱 관점, 기타 등등 ?

4. 결론

---


## 결론
>  private static final String EVIL = "' OR '1'='1";
> "SELECT id FROM users WHERE pw = '" + EVIL + "'

### com.mysql.cj.jdbc.StatementImpl
- 입력받은 SQL(파라미터 포함)을 MySQL 파서가 정해진 규칙대로 해석
- 따라서, 악의적인 파라미터로 파서가 읽는 것을 제어할 수 있음
- COM_QUERY 호출

![img.png](img.png)

### com.mysql.cj.jdbc.ClientPreparedStatement
> PreparedStatement 기본 구현체

- 문자열을 치환해서 인젝션 방지
- COM_QUERY 호출


- com.mysql.cj.util.StringUtils.escapeString
```java
 case '\'':
                    buf.append('\'');
                    buf.append('\'');
                    break;
```

여기서 '\''는 자바 char 리터럴로 작은따옴표(') 한 글자입니다. 풀어보면:
- '\'' → 작은따옴표 문자 자체 (\'는 char 안에서 '를 나타내는 이스케이프)
- buf.append('\'') → 버퍼에 작은따옴표 1개 추가

즉 입력 문자열에서 '를 만나면 → ''(작은따옴표 2개)로 복제해서 버퍼에 씁니다. 이게 우리가 로그에서 본 ' OR '1'='1 → ''' OR ''1''=''1' 변환의 바로 그 줄입니다.

헷갈리기 쉬운 점 정리

┌────────────────────────┬────────────────────────────────────────────────────────────┐
│          코드          │                            의미                            │
├────────────────────────┼────────────────────────────────────────────────────────────┤
│ case '\'':             │ 입력 char가 작은따옴표일 때 (홑따옴표 안의 \' = ' 한 글자) │
├────────────────────────┼────────────────────────────────────────────────────────────┤
│ buf.append('\'') 두 번 │ 작은따옴표를 2개 출력 (' → '')                             │
├────────────────────────┼────────────────────────────────────────────────────────────┤
│ case '\\':             │ 입력 char가 백슬래시(\) 일 때 → \\로 복제                  │
├────────────────────────┼────────────────────────────────────────────────────────────┤
│ case '"':              │ 큰따옴표 — ANSI 모드일 때만 escape                         │
└────────────────────────┴────────────────────────────────────────────────────────────┘

참고로 작은따옴표를 ''로 처리하는 건 **SQL 표준 방식(문자열 리터럴 안에서 따옴표를 두 번 쓰면 리터럴 한 글자)**이고,다. 그래서 sql_mode에 NO_BACKSLASH_ESCAPES가 켜진 서버에서도 작은따옴표 '' 처리는 안전하게 동작합니다 — 이게 MySQL
escape가 단순 문자 치환인데도 인젝션을 막는 핵심입니다.

![img_1.png](img_1.png)


### com.mysql.cj.jdbc.ServerPreparedStatement
> useServerPrepStmts=true 일 때 PreparedStatement 구현체

- COM_STMT_PREPARE + COM_STMT_EXECUTE 호출


## DB 레벨

공식 문서 링크 + 명령 코드

┌──────────────────┬──────┬────────────────────────────────────────────────────────────────────────┐
│       명령        │ 코드 │                              공식 페이지                               │
├──────────────────┼──────┼────────────────────────────────────────────────────────────────────────┤
│ COM_QUERY        │ 0x03 │ dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_query.html │
├──────────────────┼──────┼────────────────────────────────────────────────────────────────────────┤
│ COM_STMT_PREPARE │ 0x16 │ …/page_protocol_com_stmt_prepare.html                                  │
├──────────────────┼──────┼────────────────────────────────────────────────────────────────────────┤
│ COM_STMT_EXECUTE │ 0x17 │ …/page_protocol_com_stmt_execute.html                                  │
└──────────────────┴──────┴────────────────────────────────────────────────────────────────────────┘

상위 인덱스: page_protocol_command_phase.html (Text Protocol = COM_QUERY, Prepared Statements = COM_STMT_*로 묶여 있음)
문서 내용이 우리 분석을 확정해주는 부분

COM_QUERY (0x03) — "Text Protocol-based SQL query, query: string<EOF>"
→ SQL이 텍스트 문자열 통째로 실립니다. A(날 SQL)와 B(escape된 SQL)가 둘 다 이 패킷인 이유. 값이 SQL 텍스트의 일부로 들어간다는 게 스펙으로 못박혀 있음.

COM_STMT_PREPARE (0x16) — 요청은 command(0x16) + query: string<EOF> 딱 두 필드. 응답(COM_STMT_PREPARE_OK)에 statement_id int<4> + num_params.
→ 요청 페이로드에 파라미터 값 필드가 아예 없음(query 문자열만, ? 그대로). 우리가 본 Prepare: ...=?의 근거. 서버가 statement_id(=핸들)를 돌려준다는 것도 명시 — Connector/J가 cachePrepStmts로 재사용하던 그 핸들입니다.

COM_STMT_EXECUTE (0x17) — statement_id int<4> + flags + null_bitmap + new_params_bind_flag + parameter_values (binary).
→ 값이 Binary Protocol Value 형식으로 실린다고 명시. 즉 SQL 텍스트가 아니라 타입별 바이너리. 이게 "값이 파서에 안 닿는다 = 인젝션 구조적 차단"의 스펙 레벨 근거입니다. C에서만 이 패킷이 나갔죠.

한 가지 흥미로운 디테일 (COM_QUERY의 Query Attributes)

COM_QUERY 페이지를 보면 CLIENT_QUERY_ATTRIBUTES capability가 켜지면 COM_QUERY에도 parameter_values (binary) 필드가 붙습니다. 이건 **쿼리 속성(query attributes)**용이지 일반 ? 바인딩용이 아닙니다 — 즉 평범한 WHERE pw=?는 여전히 COM_QUERY에선 텍스트로 escape돼 나가고(B), 바이너리 바인딩은 COM_STMT_EXECUTE에서만(C) 일어납니다. 헷갈리기 쉬운 지점입니다.

---
요약하면 — Connector/J 소스에서 본 buildComQuery/buildComStmtPrepare/buildComStmtExecute는 각각 이 공식 패킷 스펙(0x03/0x16/0x17)을 바이트로 구현한 것이고, general_log의 Query/Prepare/Execute 표기는 서버가 그 패킷을 받아 찍은 흔적입니다. 문서·드라이버 코드·서버 로그 세 개가 정확히 일치하네요.


### 근데 COM_STMT_EXECUTE 때 인젝션 되지 않는 쿼리로 나가는데 PREPARE는 왜 필요한거야 ?

핵심을 정확히 짚으셨는데, 여기에 함정이 있습니다. 인젝션 안전성은 PREPARE의 목적이 아니라 바이너리 바인딩의 부산물이고, PREPARE가 필요한 진짜 이유는 따로 있습니다.

COM_STMT_EXECUTE 패킷에는 SQL이 없다

공식 스펙으로 EXECUTE 페이로드를 다시 보면:

status(0x17) + statement_id(4) + flags + iteration_count
+ null_bitmap + new_params_bind_flag + parameter_values(binary)

여기 SQL 문자열이 한 글자도 없습니다. 있는 건 statement_id(핸들) 하나. 즉 EXECUTE는 "N번 statement를, 이 값들로 실행해"라고만 말합니다. 그 N번 statement가 SELECT ... WHERE pw = ?라는 걸 서버가 알고 있어야 하는데 — 그걸 등록하는 게 PREPARE입니다.

PREPARE를 안 하면 서버는 statement_id=N이 뭘 가리키는지 모릅니다. EXECUTE만 보내면 "그런 statement 없음" 에러.

그럼 "템플릿 + 바이너리값"을 한 방에 보내면 되잖아?

이게 사용자 질문의 핵심일 텐데 — 맞습니다, 이론상 가능합니다. 하지만 클래식 prepared 프로토콜은 그렇게 설계 안 됨. EXECUTE는 SQL 텍스트를 안 싣고 핸들만 참조하도록 분리돼 있습니다. 왜 굳이 둘로 쪼갰나:

┌───────────────┬───────────────────────────────────────────────────────────────┬──────────────┐
│     단계      │                            하는 일                            │     비용     │
├───────────────┼───────────────────────────────────────────────────────────────┼──────────────┤
│ PREPARE (1회) │ SQL 파싱 + 실행계획 수립 + 핸들 등록 + param/column 개수 응답 │ 무거움 (①②③) │
├───────────────┼───────────────────────────────────────────────────────────────┼──────────────┤
│ EXECUTE (N회) │ 핸들에 값만 바인딩해서 실행                                   │ 가벼움 (④)   │
└───────────────┴───────────────────────────────────────────────────────────────┴──────────────┘

핵심은 재사용입니다. 같은 쿼리를 N번 돌릴 때 파싱(①②③)을 1번만 하려고 쪼갠 거예요. PREPARE의 존재 이유 = "파싱 결과를 핸들 뒤에 저장해두고 EXECUTE가 값만 바꿔 재탕".

역설: 1회만 실행하면 PREPARE는 오히려 손해

진짜 재밌는 지점 — 쿼리를 딱 한 번만 실행하면:
- COM_QUERY (client emulation): 왕복 1회
- PREPARE + EXECUTE: 왕복 2회 (+ 핸들 관리 비용)

그래서 Connector/J 기본값이 useServerPrepStmts=false(client emulation)인 겁니다. 대부분의 쿼리는 1회성이라 PREPARE 오버헤드가 손해거든요. 서버 prepare는 cachePrepStmts=true로 핸들을 재사용해 PREPARE를 1회로 amortize할 때만 이득 — 우리가 D/E 데모에서 본 그거.

정리

- 인젝션 안전 ≠ PREPARE의 목적. 안전성은 EXECUTE가 값을 바이너리로 따로 싣기 때문에 생기는 부산물.
- PREPARE가 필수인 구조적 이유: EXECUTE 패킷엔 SQL이 없고 핸들만 있어서, 그 핸들 뒤에 파싱된 statement를 미리 등록해둘 주체가 필요함.
- PREPARE/EXECUTE 분리의 설계 의도: 파싱 1회 + 실행 N회 (재사용/성능). 안전성은 덤.
- 안전성만 원하고 재사용이 없으면 → client emulation(escape → COM_QUERY)이 왕복 1회로 더 효율적. 그래서 그게 기본값.

즉 "EXECUTE가 안전한 쿼리로 나가는데 왜 PREPARE가 필요하냐"의 답은 — EXECUTE는 안전한 쿼리를 내보내는 게 아니라, 핸들이 가리킬 파싱된 쿼리를 만들어두는 게 PREPARE라서, 둘은 떼려야 뗄 수 없습니다.


구조: 명령 코드 + 내용물

MySQL 프로토콜에서 클라이언트가 서버로 보내는 패킷은 이렇게 생겼습니다:

[1바이트 명령코드][그 명령의 내용물...]

- COM_QUERY (0x03) + SQL 텍스트 → "이 SQL 문자열을 실행해"
- COM_STMT_PREPARE (0x16) + SQL 텍스트 → "이 SQL을 prepare해서 핸들 만들어줘"
- COM_STMT_EXECUTE (0x17) + 핸들 + 바이너리 값 → "그 핸들을 이 값으로 실행해"
- COM_PING (0x0e) + (내용 없음) → "살아있니?"
- COM_QUIT (0x01) + (내용 없음) → "연결 끊을게"

즉 명령코드는 "동사", SQL은 그 동사의 "목적어" 입니다.

HTTP에 비유하면 가장 직관적

┌─────────────────────────────────────────┬─────────────────────┐
│             MySQL 프로토콜              │        HTTP         │
├─────────────────────────────────────────┼─────────────────────┤
│ COM_QUERY / COM_STMT_PREPARE (명령코드) │ GET / POST (메서드) │
├─────────────────────────────────────────┼─────────────────────┤
│ SQL 텍스트 / 바이너리 값 (payload)      │ 요청 body           │
├─────────────────────────────────────────┼─────────────────────┤
│ 0x03, 0x16, 0x17 (1바이트 코드)         │ 메서드 이름         │
└─────────────────────────────────────────┴─────────────────────┘

POST가 "쿼리"가 아니라 HTTP 메서드인 것처럼, COM_QUERY도 SQL이 아니라 프로토콜 명령입니다. SQL은 COM_QUERY라는 봉투에 담겨 가는 편지 내용일 뿐.

전체 명령 목록 (소스의 NativeConstants)

방금 본 enum이 MySQL이 정의한 명령 전부입니다. 종류별로 묶으면:

- 연결 수명주기: COM_QUIT(1), COM_INIT_DB(2, DB 선택), COM_CHANGE_USER(17), COM_RESET_CONNECTION(31), COM_PING(14)
- 일반 쿼리(Text Protocol): COM_QUERY(3) — 우리 A·B가 쓴 것
- Prepared Statement(Binary Protocol): COM_STMT_PREPARE(22), COM_STMT_EXECUTE(23), COM_STMT_SEND_LONG_DATA(24), COM_STMT_CLOSE(25), COM_STMT_RESET(26), COM_STMT_FETCH(28) — C가 쓴 것
- 복제: COM_BINLOG_DUMP(18), COM_BINLOG_DUMP_GTID(30) — CDC가 binlog 읽을 때 쓰는 그것
- 관리/기타: COM_STATISTICS(9), COM_SET_OPTION(27), COM_DEBUG(13)

MySQL 서버 소스에선 이게 enum_server_command라는 enum으로 정의돼 있고, 공식 문서에선 "Commanommand_phase.html)에 모여 있습니다.

그래서 general_log의 command_type와 연결됨

우리가 본 general_log의 command_type 컬럼(Query / Prepare / Execute)이 바로 이 명령코드를 사니다:
- COM_QUERY → 로그엔 Query
- COM_STMT_PREPARE → 로그엔 Prepare
- COM_STMT_EXECUTE → 로그엔 Execute

그래서 C에서 Prepare + Execute 두 줄이 찍힌 건 = 서버가 COM_STMT_PREPARE 패킷 하나, COM_STMT 다는 뜻입니다.

정리

- COM_*는 SQL이 아니라 프로토콜 명령(opcode). COM = command.
- 패킷 = [명령코드 1바이트] + [내용물]. SQL은 COM_QUERY/COM_STMT_PREPARE의 내용물.
- HTTP 메서드(GET/POST)와 같은 레이어. "무엇을 할지"를 가리키는 동사.
- 연결 수립(handshake) 이후의 **"Command Phase"**에서 오가는 메시지 타입들이고, MySQL이 정의s.COM_*.


---


```java
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;

/**
 * MySQL 서버가 "실제 와이어로 무엇을 받는가"를 general_log 로 직접 확인하는 데모.
 *
 * 사전 조건: docker 로 mysql:8 이 127.0.0.1:13306 에 떠 있어야 함 (run-mysql-demo.sh 가 처리).
 * 실행: ./gradlew :jdbc-in-action:runMysql
 *
 * 확인 포인트 — 같은 입력값 "' OR '1'='1" 에 대해 서버 로그에 찍히는 command_type:
 *   A) plain Statement              → Query   (escape 안 된 날 SQL, 인젝션 성립)
 *   B) PreparedStatement (기본값)    → Query   (드라이버가 escape 한 SQL, 클라이언트 에뮬레이션)
 *   C) useServerPrepStmts=true       → Prepare(?) + Execute  (값은 바이너리, 파서에 안 닿음)
 */
public class MysqlWireDemo {

    private static final String HOST = "127.0.0.1:13306";
    private static final String BASE = "jdbc:mysql://" + HOST + "/demo?user=root&password=root";
    private static final String CLIENT_URL = BASE;                          // 기본값: 클라이언트 에뮬레이션
    private static final String SERVER_URL = BASE + "&useServerPrepStmts=true"; // 서버 prepare

    private static final String EVIL = "' OR '1'='1";

    public static void main(String[] args) throws SQLException {
        try (Connection setup = DriverManager.getConnection(CLIENT_URL)) {
            initSchema(setup);
            exec(setup, "SET GLOBAL log_output = 'TABLE'");
        }

        // A) Statement — 개발자가 합친 문자열 그대로
        try (Connection c = DriverManager.getConnection(CLIENT_URL)) {
            capture(c, "A) plain Statement", () -> {
                try (Statement st = c.createStatement();
                     ResultSet rs = st.executeQuery(
                             "SELECT id FROM users WHERE pw = '" + EVIL + "'")) {
                    return count(rs);
                }
            });
        }

        // B) PreparedStatement 기본값 — 클라이언트 에뮬레이션 (escape 후 COM_QUERY)
        try (Connection c = DriverManager.getConnection(CLIENT_URL)) {
            capture(c, "B) PreparedStatement (기본값 = client emulation)", () -> {
                try (PreparedStatement ps = c.prepareStatement(
                        "SELECT id FROM users WHERE pw = ?")) {
                    ps.setString(1, EVIL);
                    try (ResultSet rs = ps.executeQuery()) {
                        return count(rs);
                    }
                }
            });
        }

        // C) useServerPrepStmts=true — 서버 prepare (Prepare + Execute, 값은 바이너리)
        try (Connection c = DriverManager.getConnection(SERVER_URL)) {
            capture(c, "C) PreparedStatement (useServerPrepStmts=true = server prepare)", () -> {
                try (PreparedStatement ps = c.prepareStatement(
                        "SELECT id FROM users WHERE pw = ?")) {
                    ps.setString(1, EVIL);
                    try (ResultSet rs = ps.executeQuery()) {
                        return count(rs);
                    }
                }
            });
        }

        // D) 서버 prepare + cachePrepStmts=false — 같은 쿼리 3회면 Prepare 도 3회
        String noCacheUrl = BASE + "&useServerPrepStmts=true&cachePrepStmts=false";
        try (Connection c = DriverManager.getConnection(noCacheUrl)) {
            capture(c, "D) server prepare, cachePrepStmts=false — 같은 쿼리 3회",
                    () -> repeatPrepare(c, 3));
        }

        // E) 서버 prepare + cachePrepStmts=true — Prepare 는 1회만, Execute 는 3회
        String cacheUrl = BASE + "&useServerPrepStmts=true&cachePrepStmts=true"
                + "&prepStmtCacheSize=25&prepStmtCacheSqlLimit=2048";
        try (Connection c = DriverManager.getConnection(cacheUrl)) {
            capture(c, "E) server prepare, cachePrepStmts=true — 같은 쿼리 3회",
                    () -> repeatPrepare(c, 3));
        }
    }

    /**
     * 같은 SQL 을 times 번 prepare→execute→close 반복.
     * close 시: 캐시 OFF 면 COM_STMT_CLOSE, 캐시 ON 이면 핸들을 풀에 반납(다음 prepare 가 재사용).
     */
    private static int repeatPrepare(Connection c, int times) throws SQLException {
        int rows = 0;
        for (int i = 0; i < times; i++) {
            try (PreparedStatement ps = c.prepareStatement(
                    "SELECT id FROM users WHERE pw = ?")) {
                ps.setString(1, EVIL);
                try (ResultSet rs = ps.executeQuery()) {
                    rows += count(rs);
                }
            }
        }
        return rows;
    }

    @FunctionalInterface
    private interface Op {
        int run() throws SQLException;
    }

    /**
     * general_log 를 깨끗이 비우고 ON → 작업 실행 → OFF → 서버가 받은 로그를 출력.
     * (SET/SELECT 같은 제어 쿼리는 출력에서 걸러낸다)
     */
    private static void capture(Connection c, String label, Op op) throws SQLException {
        exec(c, "SET GLOBAL general_log = 'OFF'");
        exec(c, "TRUNCATE mysql.general_log");
        exec(c, "SET GLOBAL general_log = 'ON'");

        int rows = op.run();   // ← 이 작업이 서버로 보내는 패킷만 로그에 남는다

        exec(c, "SET GLOBAL general_log = 'OFF'");

        System.out.println("\n========================================");
        System.out.println(label + "   → 결과 " + rows + "건 "
                + (rows > 0 ? "❌ 인증 우회" : "✅ 0건"));
        System.out.println("----- 서버 general_log 가 받은 것 -----");
        try (Statement st = c.createStatement();
             ResultSet rs = st.executeQuery(
                     "SELECT command_type, CONVERT(argument USING utf8mb4) AS arg "
                   + "FROM mysql.general_log "
                   + "WHERE command_type IN ('Query','Prepare','Execute') "
                   + "  AND argument NOT LIKE '%general_log%' "
                   + "  AND argument NOT LIKE '%log_output%' "
                   + "ORDER BY event_time, thread_id")) {
            while (rs.next()) {
                System.out.printf("  [%-8s] %s%n", rs.getString("command_type"), rs.getString("arg"));
            }
        }
    }

    private static void initSchema(Connection c) throws SQLException {
        exec(c, "DROP TABLE IF EXISTS users");
        exec(c, "CREATE TABLE users (id BIGINT PRIMARY KEY, name VARCHAR(50), pw VARCHAR(100))");
        exec(c, "INSERT INTO users VALUES (1,'alice','secret123'),(2,'bob','qwerty')");
    }

    private static void exec(Connection c, String sql) throws SQLException {
        try (Statement st = c.createStatement()) {
            st.execute(sql);
        }
    }

    private static int count(ResultSet rs) throws SQLException {
        int n = 0;
        while (rs.next()) {
            n++;
        }
        return n;
    }
}
```

### 로그 결과
```
========================================
A) plain Statement   → 결과 2건 ❌ 인증 우회
----- 서버 general_log 가 받은 것 -----
  [Query   ] SELECT id FROM users WHERE pw = '' OR '1'='1'

========================================
B) PreparedStatement (기본값 = client emulation)   → 결과 0건 ✅ 0건
----- 서버 general_log 가 받은 것 -----
  [Query   ] SELECT id FROM users WHERE pw = ''' OR ''1''=''1'

========================================
C) PreparedStatement (useServerPrepStmts=true = server prepare)   → 결과 0건 ✅ 0건
----- 서버 general_log 가 받은 것 -----
  [Prepare ] SELECT id FROM users WHERE pw = ?
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'

========================================
D) server prepare, cachePrepStmts=false — 같은 쿼리 3회   → 결과 0건 ✅ 0건
----- 서버 general_log 가 받은 것 -----
  [Prepare ] SELECT id FROM users WHERE pw = ?
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'
  [Prepare ] SELECT id FROM users WHERE pw = ?
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'
  [Prepare ] SELECT id FROM users WHERE pw = ?
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'

========================================
E) server prepare, cachePrepStmts=true — 같은 쿼리 3회   → 결과 0건 ✅ 0건
----- 서버 general_log 가 받은 것 -----
  [Prepare ] SELECT id FROM users WHERE pw = ?
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'
  [Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'

```

### 그럼 execute에서는 값만 나가야하는거 아니야 ?
C) PreparedStatement (useServerPrepStmts=true = server prepare)   → 결과 0건 ✅ 0건
----- 서버 general_log 가 받은 것 -----
[Prepare ] SELECT id FROM users WHERE pw = ?
[Execute ] SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1'



맞습니다, 와이어에는 값만(정확히는 statement_id + 바이너리 값) 나갑니다. 로그에 보이는 전체 SQL은 서버가 사람 보라고 재구성한 표시일 뿐, 실제 전송 바이트가 아닙니다.

general_log의 argument는 "받은 바이트"가 아니라 "서버의 렌더링"

COM_STMT_EXECUTE 패킷 실제 내용(스펙):
0x17 + statement_id(4) + flags + iteration_count + null_bitmap + param_values(binary)
→ SQL 텍스트도, ?도, pw = 도 한 글자도 안 들어있습니다. 핸들 번호 + 바이너리 값뿐.

그럼 로그의 SELECT id FROM users WHERE pw = '\' OR \'1\'=\'1' 는 어디서 왔나?
→ 서버가 PREPARE 때 저장해둔 파싱된 SQL(...pw = ?) + EXECUTE로 받은 바이너리 값(' OR '1'='1)을 합쳐서 로그용 문자열로 재조립한 것입니다. 가독성을 위해서요. 와이어를 그대로 찍은 게 아닙니다.

증거: B와 C의 escape 스타일이 다르다

이게 결정적 단서입니다. 같은 입력값 ' OR '1'='1인데:

┌──────────────────────┬───────────────────┬──────────────────────┬─────────────────────────────────────────────────────────┐
│                      │     로그 표시     │     escape 방식      │                    누가 만든 문자열?                    │
├──────────────────────┼───────────────────┼──────────────────────┼─────────────────────────────────────────────────────────┤
│ B (COM_QUERY)        │ ''' OR ''1''=''1' │ ' → '' (따옴표 복제) │ 클라이언트 드라이버 (escapeString) — 진짜 와이어 바이트 │
├──────────────────────┼───────────────────┼──────────────────────┼─────────────────────────────────────────────────────────┤
│ C (COM_STMT_EXECUTE) │ '\' OR \'1\'=\'1' │ ' → \' (백슬래시)    │ 서버가 로그용으로 재구성                                │
└──────────────────────┴───────────────────┴──────────────────────┴─────────────────────────────────────────────────────────┘

- B는 '' (SQL 표준 복제) — 우리가 소스에서 본 StringUtils.escapeString의 결과물. 이건 실제로 COM_QUERY 패킷에 그대로 실려 간 텍스트라서 로그도 동일.
- C는 \' (백슬래시 escape) — 클라이언트는 이런 escape를 한 적이 없습니다(바이너리로 보냈으니까). 이 \'는 서버가 자기 표기 규칙으로 바이너리 값을 문자열로 그려낸 것.

escape 스타일이 다르다는 것 자체가 "C의 로그 줄은 클라이언트가 보낸 게 아니라 서버가 만든 표현"이라는 증거입니다

정리

- 와이어: B = SQL 텍스트(escape됨), C = 핸들 + 바이너리 값 (SQL 텍스트 없음). 사용자 직관이 맞음.
- 로그: general_log의 argument 컬럼은 "서버가 실행한 쿼리를 사람이 읽을 수 있게 표현한 것"이라, 서버 prepared st 보여줍니다. 그래서 마치 전체 SQL이 나간 것처럼 착시가 생깁니다.
- 핵심 불변: C에서 값은 끝까지 SQL 텍스트로 합쳐져 전송되지 않습니다. 로그의 완성형은 서버의 사후 렌더링.

원하시면 이걸 직접 증명할 수 있습니다 — tcpdump로 13306 포트 패킷을 떠서 COM_STMT_EXECUTE(0x17) 바이트를 hex로  tatement_id + 바이너리 값만 있는 걸 눈으로 확인할 수 있어요. 떠볼까요?


---

┌───────────────────────────────┬────────────────────────────────────────┬────────┬─────────────────────────────────────────────────────────────┐
│             경로               │             서버가 받은 것                 │  결과  │                          소스 근거                             │
├───────────────────────────────┼────────────────────────────────────────┼────────┼─────────────────────────────────────────────────────────────┤
│ A) plain Statement            │ Query: ...pw = '' OR '1'='1'           │ 2건 ❌ │ NativeMessageBuilder.java:163 — 날 SQL을 COM_QUERY로 그대로    │
├───────────────────────────────┼────────────────────────────────────────┼────────┼─────────────────────────────────────────────────────────────┤
│ B) PreparedStatement (기본값)   │ Query: ...pw = ''' OR ''1''=''1'       │ 0건 ✅ │ StringUtils.escapeString:1768 — '→'' 복제 후 COM_QUERY       │
├───────────────────────────────┼────────────────────────────────────────┼────────┼─────────────────────────────────────────────────────────────┤
│ C) useServerPrepStmts=true    │ Prepare: ...pw = ?<br>Execute: 값 별도   │ 0건 ✅ │ buildComStmtPrepare:334 + sendExecutePacket:260             │
└───────────────────────────────┴────────────────────────────────────────┴────────┴─────────────────────────────────────────────────────────────┘


하나씩 짚으면

A) ' OR '1'='1이 escape 없이 그대로 → 서버 파서가 pw = ''(빈 문자열) OR '1'='1'(항상 참)으로 해석 → 전체 row 노출. 인젝션 성립.

B) 똑같은 입력인데 서버가 받은 건 ''' OR ''1''=''1' — 모든 '가 ''로 복제됐습니다. 이게 우리가 읽은 case '\'': buf.append('\''); buf.append('\'') 코드의 결과물입니다. 서버 파서는 따옴표 안의 ''를 "리터럴 따옴표 1글자"로 읽어서 → pw = (문자열: ' OR '1'='1) 하나로 인식 → 0건.
→ 주목: command_type이 Prepare가 아니라 **Query**입니다. 기본값에선 PreparedStatement를 써도 서버 prepare를 안 하고 평민 쿼리로 나간다는 게 로그로 증명됐습니다.

C) 여기서만 Prepare + Execute 두 줄로 갈립니다.
- Prepare에는 ?만 있고 값이 아예 없음 → 서버가 이 시점에 파싱
- Execute에 값이 따로 실림 → SQL 텍스트에 합쳐진 게 아니라 바인딩 파라미터로 전달


┌──────┬──────────────────────┬─────────┬─────────┐
│ 단계 │         설정         │ Prepare │ Execute │
├──────┼──────────────────────┼─────────┼─────────┤
│ D    │ cachePrepStmts=false │ 3회     │ 3회     │
├──────┼──────────────────────┼─────────┼─────────┤
│ E    │ cachePrepStmts=true  │ 1회 ✅  │ 3회     │
└──────┴──────────────────────┴─────────┴─────────┘

ConnectionImpl.prepareStatement(sql, type, concurrency) — ConnectionImpl.java:1602 가 A/B/C를 가르는 단 하나의 메서드입니다:

if (this.useServerPrepStmts.getValue() && canServerPrepare) {   // ← C 경로
if (this.cachePrepStmts.getValue()) {
pStmt = this.serverSideStatementCache.remove(key);      // ← E 데모: 캐시 hit 면 재사용
if (pStmt == null)
pStmt = ServerPreparedStatement.getInstance(...);   // miss → 새 서버 prepare
} else {
pStmt = ServerPreparedStatement.getInstance(...);       // D 데모: 매번 새로
}
} else {                                                        // ← B 경로 (기본값)
pStmt = clientPrepareStatement(...);   // → ClientPreparedStatement
}

useServerPrepStmts=false(기본)면 무조건 else → ClientPreparedStatement. 이게 B가 서버 prepare 안 하는 코드 레벨 근거입니다.

---
A) plain Statement → COM_QUERY (날 SQL)

StatementImpl.executeQuery(sql)                         StatementImpl.java:1172
→ NativeSession.execSQL(this, sql, …, packet=null, …) StatementImpl.java:1250
→ packet == null 이라 여기서 패킷 생성:
NativeMessageBuilder.buildComQuery(null, sql)   NativeSession.java:800
→ NativeProtocol.sendQueryPacket(…)               NativeSession.java:801  → COM_QUERY
createStatement()(ConnectionImpl.java:1093)는 그냥 StatementImpl을 만들 뿐. sql 문자열이 execSQL까지 날것 그대로 내려가 거기서 COM_QUERY로 포장됩니다. → 로그의 Query: ...pw='' OR '1'='1'.

B) ClientPreparedStatement → COM_QUERY (escape된 SQL)

ClientPreparedStatement.executeQuery()                  ClientPreparedStatement.java:942
→ ClientPreparedQuery.fillSendPacket(bindings)        ClientPreparedStatement.java:981
→ NativeMessageBuilder.buildComQuery(…, bindings) ClientPreparedQuery.java:223
(조각 SQL + StringValueEncoder.escapeString 한 값 → 완성 패킷)
→ executeInternal(…, sendPacket, …)                   ClientPreparedStatement.java:1004
→ NativeSession.execSQL(this, null, …, sendPacket)ClientPreparedStatement.java:917
(packet != null → buildComQuery 건너뜀, 이미 만든 패킷 그대로)
→ NativeProtocol.sendQueryPacket(…)                                   → COM_QUERY
핵심 대비: A는 execSQL에서 패킷을 만들고(packet==null), B는 fillSendPacket에서 미리 escape해 만든 패킷을 넘깁니다(packet!=null). 근데 둘 다 명령은 같은 COM_QUERY. → 로그의 Query: ...pw=''' OR ''1''=''1'.

NativeMessageBuilder.buildComQuery:291
bindValues[i].writeAsText(sendPacket)
↓
NativeQueryBindValue.writeAsText:374
this.valueEncoder.encodeAsText(intoMessage, this)
↓  (valueEncoder 는 setString 때 VARCHAR → StringValueEncoder 로 세팅됨, :143)
AbstractValueEncoder.encodeAsText:81
intoPacket.writeBytes(STRING_FIXED, getBytes(binding))   ← getBytes 호출!
↓  (StringValueEncoder 가 getBytes 를 오버라이드)
StringValueEncoder.getBytes:63
StringUtils.escapeString(buf, x, …)   :88                ← ' → '' escape

C) ServerPreparedStatement → COM_STMT_PREPARE + COM_STMT_EXECUTE

[prepare 시점 — prepareStatement() 안에서 이미 발생]
ServerPreparedStatement.getInstance(…)                  ConnectionImpl.java:1633
→ 생성자 → serverPrepare(sql)                          ServerPreparedStatement.java:126
→ ServerPreparedQuery.serverPrepare(sql)          ServerPreparedStatement.java:599
→ NativeMessageBuilder.buildComStmtPrepare(sql)   ServerPreparedQuery.java:123  → COM_STMT_PREPARE
(sql 에 ? 그대로, 값 없음. 서버가 handle 반환)

[execute 시점]
ServerPreparedStatement.executeQuery()
→ executeInternal → serverExecute(…)                  ServerPreparedStatement.java:335
→ ServerPreparedQuery.serverExecute(…)            ServerPreparedStatement.java:588
→ prepareExecutePacket() → buildComStmtExecute(handle, …)  ServerPreparedQuery.java:61
(값을 binary 로 인코딩, handle 에 바인딩)
→ NativeProtocol.sendCommand(packet)          ServerPreparedQuery.java:74   → COM_STMT_EXECUTE
prepare와 execute가 물리적으로 다른 메서드·다른 패킷입니다. → 로그의 Prepare: ...=? + Execute: ....

---
한눈에 — 세 경로가 합류/분기하는 지점

┌────────────────┬───────────────────────────────┬──────────────────────────────────────────┬─────────────────────────────────────────┐
│      계층      │          A Statement          │             B ClientPrepared             │            C ServerPrepared             │
├────────────────┼───────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────┤
│ jdbc Statement │ StatementImpl                 │ ClientPreparedStatement                  │ ServerPreparedStatement                 │
├────────────────┼───────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────┤
│ cj Query       │ SimpleQuery                   │ ClientPreparedQuery                      │ ServerPreparedQuery                     │
├────────────────┼───────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────┤
│ 패킷 빌더       │ buildComQuery<br>(execSQL 안) │ buildComQuery<br>(fillSendPacket서 미리) │ buildComStmtPrepare+buildComStmtExecute │
├────────────────┼───────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────┤
│ 전송           │ sendQueryPacket               │ sendQueryPacket                          │ sendCommand                             │
├────────────────┼───────────────────────────────┼──────────────────────────────────────────┼─────────────────────────────────────────┤
│ 와이어         │ COM_QUERY                     │ COM_QUERY                                │ COM_STMT_PREPARE / EXECUTE              │
└────────────────┴───────────────────────────────┴──────────────────────────────────────────┴─────────────────────────────────────────┘

A와 B는 NativeSession.execSQL(NativeSession.java:782)에서 합류해 똑같이 COM_QUERY로 나가고(차이는 escape 유무뿐), C만 serverExecute 경로로 갈라져 별도 패킷을 씁니다.

ConnectionImpl에서 안 보였던 이유가 이겁니다 — ConnectionImpl은 "어떤 Statement/Query 객체를 줄까"만 결정(1602줄)하고, 실제 호출 흐름은 Query(cj 계층) → NativeSession → NativeProtocol 로 내려갑니다. 거기를 봐야 패킷이 보입니다.


