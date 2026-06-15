

## 결론
### DB 레벨
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
