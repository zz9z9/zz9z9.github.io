---
title: Java - PreparedStatement는 어떻게 SQL Injection을 방어할까 (feat. MySQL)
date: 2026-06-14 21:29:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---

## java.sql.Statement (Interface)
---

> [공식문서](https://docs.oracle.com/javase/8/docs/api/java/sql/Statement.html) : "The object used for executing a static SQL statement and returning the results it produces."

**users 테이블**

| id | name | pw |
| ---| --- | --- |
| 1 | alice | secret123 |
| 2 | bob | qwerty |

```java
public boolean isExistUser(String id, String pw) throws SQLException {
  try (Connection c = DriverManager.getConnection(CLIENT_URL); Statement st = c.createStatement()) {
    ResultSet rs = st.executeQuery("SELECT id FROM users WHERE id = '" + id + "'" + " AND pw = '" + pw + "'");
    return rs.next();
  }
}
```
**SQL Injection 시도**
> 아래처럼 시도하면 isExistUser()의 결과는 true가 된다.

```java
String id = "alice";
String pw = "' OR '1'='1";

if (!isExistUser(id, pw)) {
  // blocking !
}

// do something ...
```

### 왜 SQL Injection이 가능할까 ?
> mysql-connector-j:8.4.0 기준으로 Statement가 DB로 전달되는 흐름을 살펴보자

```
StatementImpl.executeQuery(sql)
  │
  └─ NativeSession.execSQL(this, sql, …, packet=null, …)
        │
        │   packet == null  →  보낼 패킷이 없으니 여기서 직접 만든다
        │
        ├─ NativeMessageBuilder.buildComQuery(...)
        │     sendPacket.writeInteger(INT1, COM_QUERY)
        │     = 메모리 버퍼에 [0x03][SQL...] 패킷 "조립"  (네트워크 X)
        │
        └─ NativeProtocol.sendQueryPacket(packet, ...)
              │   조립된 패킷을 와이어로 내보내는 경로 시작
              │
              └─ sendCommand(...)
                    └─ send(packet, len)
                          └─ packetSender.send(...)
                                └─ socket OutputStream.write(...)   ← 여기서 진짜 전송 (COM_QUERY 패킷 전송)
```

**NativeProtocol.sendQueryPacket의 queryPacket**
![NativeProtocol.sendQueryPacket의 queryPacket (Statement)](/assets/img/prepared-statement-img1.png)

- 즉, 악의적인 입력이 의도한대로 `SELECT id FROM users WHERE id = 'alice' AND pw = '' OR '1' = '1'` 쿼리가 날아가게됨
- SQL 파서는 작은따옴표로 감싸진 문자열 리터럴을 컬럼명/키워드 등이 아닌 **값으로 인식**


## PreparedStatement(Interface)
---

> [공식문서](https://docs.oracle.com/javase/8/docs/api/java/sql/PreparedStatement.html) : "An object that represents a precompiled SQL statement. A SQL statement is precompiled and stored in a PreparedStatement object. This object can then be used to efficiently execute this statement multiple times."

```java
public static boolean isExistUser(String id, String pw) throws SQLException {
    try (Connection c = DriverManager.getConnection(CLIENT_URL); PreparedStatement ps = c.prepareStatement("SELECT id FROM users WHERE id = ? AND pw = ?")) {
        ps.setString(1, id);
        ps.setString(2, pw);
        ResultSet rs = ps.executeQuery();
        return rs.next();
    }
}
```

### ClientPreparedStatement, ServerPreparedStatement
> 위와 마찬가지로 mysql-connector-j:8.4.0 기준

```
// com.mysql.cj.jdbc.ConnectionImpl#prepareStatement
prepareStatement(sql)
  │
  ├─ useServerPrepStmts == false ─────────────────► ClientPreparedStatement   (기본값)
  │
  └─ useServerPrepStmts == true
        │
        ├─ emulateUnsupportedPstmts && !canHandleAsServerPreparedStatement(sql)
        │       (멀티쿼리 등 서버가 못 다루는 구문) ──► ClientPreparedStatement
        │
        └─ canServerPrepare == true
                │
                ├─ ServerPreparedStatement.getInstance() 성공 ─► ServerPreparedStatement
                │
                └─ 실패(SQLException)
                       ├─ emulateUnsupportedPstmts == true ──► ClientPreparedStatement (폴백)
                       └─ else ───────────────────────────► throw
```

- useServerPrepStmts && canServerPrepare 가 둘 다 참일 때만 `ServerPreparedStatement` 그 외엔 `ClientPreparedStatement`

### 왜 SQL Injection이 불가능할까 ? (ClientPreparedStatement)
> 앞서 살펴본 Statement와 흐름은 동일하지만, **작은따옴표를 escape 처리**함

```
ClientPreparedStatement.executeQuery()
  │
  └─ ClientPreparedQuery.fillSendPacket(bindings)
        │
        └─ NativeMessageBuilder.buildComQuery(pkt, sess, query, bindings, enc)
              │   writeInteger(INT1, COM_QUERY)  ← Statement와 같은 0x03
              │   정적 SQL 조각 사이에 바인드값을 끼워넣는데, 그 값은:
              │
              └─ StringValueEncoder.getBytes(binding)          // VARCHAR 경로
                    │   if (isEscapeNeededForString(x))         // ' " \ \n \r 등 있으면
                    └─ StringUtils.escapeString(buf, x, ...)    // ★ 실제 escape 여기서
```

- 핵심 escape 코드 : `com.mysql.cj.util.StringUtils#escapeString`

```java
buf.append('\'');                 // 값 앞에 여는 따옴표
for (char c : x) {
    switch (c) {
        case '\'':                // ← 작은따옴표는 '' 로 doubling
            buf.append('\'');
            buf.append('\'');
            break;
        case '\\':                // 백슬래시는 \\ 로
            buf.append('\\');
            buf.append('\\');
            break;
        case 0:    buf.append("\\0"); break;   // NUL
        case '\n': buf.append("\\n"); break;
        case '\r': buf.append("\\r"); break;
        case '\032': buf.append("\\Z"); break;
        // " 는 ANSI_QUOTES 모드일 때만 escape, ¥/₩ 는 charset 따라 처리
        default:   buf.append(c);
    }
}
buf.append('\'');                 // 값 뒤에 닫는 따옴표
```

**NativeProtocol.sendQueryPacket의 queryPacket**

![NativeProtocol.sendQueryPacket의 queryPacket (ClientPreparedStatement)](/assets/img/prepared-statement-img2.png)

### 왜 SQL Injection이 불가능할까 ? (ServerPreparedStatement)

```
[1단계] PREPARE — conn.prepareStatement() 시점
─────────────────────────────────────────────
ConnectionImpl.prepareStatement("...id = ? AND pw = ?")
  │
  └─ ServerPreparedStatement.getInstance(...)
        └─ (생성자) ServerPreparedQuery.serverPrepare(sql)
              │
              └─ NativeMessageBuilder.buildComStmtPrepare(pkt, sql, enc)
                    │   writeInteger(INT1, COM_STMT_PREPARE)  ← 0x16 (? 그대로, 값 없음)
                    │
                    └─ NativeProtocol.sendCommand(...)   // 전송 + 응답 대기
                          ◄─ serverStatementId, parameterCount(=2)
                                = "네 SQL을 #id번으로 파싱해 저장해놨다"


[2단계] EXECUTE — ps.executeQuery() 시점
─────────────────────────────────────────────
ServerPreparedStatement.executeQuery()
  │
  └─ ServerPreparedQuery.prepareExecutePacket()
        │
        └─ NativeMessageBuilder.buildComStmtExecute(pkt, serverStatementId, ...)
              │   writeInteger(INT1, COM_STMT_EXECUTE)   ← 0x17
              │   writeInteger(INT4, serverStatementId)  ← "#id번 SQL 실행해줘"
              │   [null-bitmap][파라미터 타입] + 값은:
              │
              └─ StringValueEncoder.encodeAsBinary(...)  // 바이너리, escape 없음
                    └─ NativeProtocol.sendCommand(...)   // 전송 → 결과 row
```

- 즉, SQL을 `COM_STMT_PREPARE`로 먼저 파싱시켜 두고 값은 `COM_STMT_EXECUTE`에서 바이너리로 따로 보내므로, 값이 SQL 파서에 닿을 일이 없어 인젝션이 구조적으로 불가능

**PREPARE 단계**
![COM_STMT_PREPARE 패킷 (PREPARE 단계)](/assets/img/prepared-statement-img3.png)

**EXECUTE 단계**
![COM_STMT_EXECUTE 패킷 (EXECUTE 단계)](/assets/img/prepared-statement-img4.png)

#### serverStatementId

`serverStatementId`는 서버가 PREPARE 단계에서 받은 SQL 골격을 자기 메모리에 저장해두고, **저장해둔 SQL을 가리키도록** 클라이언트에게 발급해주는 번호표다.

PREPARE 응답에서 서버가 이 번호를 내려준다.

```java
// serverPrepare()
this.serverStatementId = prepareResultPacket.readInteger(INT4);
// ↑ 서버가 "네 SQL을 파싱해서 #42번으로 저장해놨어" 라고 알려준 번호
```

그리고 EXECUTE할 때 그 번호를 같이 보낸다.

```java
// buildComStmtExecute()
writeInteger(INT1, COM_STMT_EXECUTE);
writeInteger(INT4, serverStatementId);   // "#42번 SQL 실행해줘"
// + 값(바이너리)
```

- **EXECUTE 패킷에는 SQL 문장이 들어가지 않는다.** `statementId(#42)`와 값만 보내면, 서버는 `#42 = SELECT id FROM users WHERE id = ? AND pw = ?`를 이미 알고 있으니 그 `?` 자리에 값만 끼워 실행한다.
- `statementId`는 **그 커넥션 안에서만**, 서버 메모리에 그 SQL이 살아있는 동안만 유효하다.
  - 커넥션이 끊기면 무효 (다른 커넥션에서 `#42`를 쓸 수 없음)
  - 다 쓰면 `COM_STMT_CLOSE(#42)`로 "이제 그 번호 지워도 돼"라고 반납 → 서버 메모리 정리

#### cachePrepStmts

같은 쿼리를 반복 실행할 때 매번 PREPARE 왕복을 하면 손해다. `cachePrepStmts` 옵션이 이를 제어한다.

- `false` : 매번 `PREPARE → EXECUTE → CLOSE`(`COM_STMT_CLOSE`, `0x19`) → 같은 쿼리 3회면 PREPARE도 3회
- `true` : PREPARE 1회로 받은 `statementId`를 캐시 → 이후 EXECUTE만 반복

```
PREPARE 1회 → statementId #42 받음
EXECUTE(#42, 값1)
EXECUTE(#42, 값2)   ← SQL 안 보냄, #42 + 값만
EXECUTE(#42, 값3)
```

**캐시의 실체**

여기서 말하는 "캐시"는 DB 커넥션 풀 같은 별도 풀이 아니라, `ConnectionImpl` 안에 있는 `serverSideStatementCache`다. 즉 **JDBC 커넥션 하나에 종속된** prepared statement 캐시다.

```java
private LRUCache<CompoundCacheKey, ServerPreparedStatement> serverSideStatementCache;
//        ↑ LRU 맵            ↑ key = (database, sql)   ↑ 캐시되는 대상
```

| 항목 | 내용 |
| --- | --- |
| 위치 | `ConnectionImpl` 인스턴스 필드 → 커넥션 1개당 1개 |
| 자료구조 | `LRUCache` (size 초과 시 가장 오래된 것 evict) |
| key | `CompoundCacheKey(database, sql)` — DB명 + SQL 문자열 |
| value | `ServerPreparedStatement` (그 안에 `serverStatementId` 보유) |
| 크기 한도 | `prepStmtCacheSize` (기본 25) |
| SQL 길이 한도 | `prepStmtCacheSqlLimit` (기본 256) — 더 길면 캐시 안 함 |

**close()가 진짜 close가 아니다**

핵심은 `ps.close()`가 서버 핸들을 바로 닫지 않고 이 캐시에 반납한다는 점이다.

```java
ps.close()
└─ ConnectionImpl.recachePreparedStatement(ps)     // 줄 1793
   └─ serverSideStatementCache.put((db, sql), ps)  // COM_STMT_CLOSE 안 보냄!
      // statementId가 서버에 살아있는 채로 캐시에 보관됨

// 다음번 conn.prepareStatement(같은 sql)
└─ serverSideStatementCache.remove((db, sql))       // 줄 1624 — 캐시에서 꺼냄
   → 기존 ServerPreparedStatement(이미 serverStatementId 있음) 재사용
   → COM_STMT_PREPARE 다시 안 보냄
```

즉 같은 SQL을 다시 prepare하면 캐시에 보관된 `statementId`를 그대로 꺼내 써서 PREPARE 왕복을 건너뛴다.

`LRU evict 시점`: 캐시가 `prepStmtCacheSize`를 넘기면 가장 오래된 항목을 버리는데, 이때 비로소 진짜 `COM_STMT_CLOSE`가 서버로 나가 서버 측 핸들을 해제한다. (그렇지 않으면 서버 메모리에 `statementId`가 무한정 쌓여 `max_prepared_stmt_count` 초과 장애로 이어진다.)

**커넥션 풀과의 관계**

이 캐시는 물리 커넥션에 묶여 있다.

- HikariCP 같은 DB 커넥션 풀을 쓰면, 풀이 커넥션을 재사용하므로 그 커넥션의 `serverSideStatementCache`도 계속 살아서 캐시 효과를 본다.
- 반대로 매번 새 커넥션을 열고 닫으면 캐시가 매번 비어 있어 PREPARE를 매번 다시 하게 된다 → server prepare의 이점이 거의 사라진다.

> 한 줄 정리: 여기서 "캐시"는 `ConnectionImpl.serverSideStatementCache` — 커넥션마다 가진 `(db, sql) → ServerPreparedStatement(statementId)` LRU 캐시다. `close()` 때 `statementId`를 이 캐시에 반납하고, 같은 SQL 재요청 시 꺼내 재사용해 PREPARE를 생략한다.

## ClientPreparedStatement vs ServerPreparedStatement
---

> useServerPrepStmts의 기본값이 false(= ClientPreparedStatement)인 이유는, 대부분의 쿼리에서 server prepare가 오히려 손해

**1. 왕복 횟수**

```
ClientPreparedStatement:  COM_QUERY                           → 왕복 1회
ServerPreparedStatement:  COM_STMT_PREPARE + COM_STMT_EXECUTE  → 왕복 2회
```

- 쿼리를 한 번만 실행하면 server prepare는 PREPARE 왕복이 통째로 추가 비용이다. 네트워크 RTT가 1ms라면 그 한 번 더가 그대로 지연으로 잡힌다.
- 그런데 실제 애플리케이션 쿼리의 상당수는 "한 번 만들어 한 번 실행하고 버리는" 패턴이라 → 이 경우 client 쪽이 빠르다.

**2. server prepare의 이점은 "조건부"**

> server prepare가 이기려면 두 조건이 동시에 충족돼야 한다.

1. 같은 SQL을 여러 번 실행하고 (그래야 PREPARE 1회를 N번에 분산)
2. 커넥션이 재사용돼서 `statementId` 캐시가 살아있어야 함 (앞서 본 `serverSideStatementCache`)

- 매번 새 커넥션을 열거나 SQL이 매번 다르면 → PREPARE를 매번 다시 하니 왕복만 2배다. 기본값을 server로 두면 이런 케이스에서 전부 손해를 본다. 그래서 "공통 케이스에 안전한 쪽"인 client를 기본으로 둔 것이다.

**3. 서버 자원 소모**
- server prepare는 `statementId`마다 서버 메모리를 잡고, `max_prepared_stmt_count`(기본 16382) 한도가 있다.
- 캐시/정리가 어긋나면 누수·초과 장애로 이어질 수 있다.
- client emulation은 서버에 아무 상태도 남기지 않는다.

**4. 그러면서도 핵심 이점은 그대로**

- 기본값이 client여도 사람들이 PreparedStatement에 기대하는 것 — 파라미터 바인딩 + 인젝션 방어(`StringUtils.escapeString`) + 통일된 API — 은 추가 왕복 없이 다 제공된다.
- 즉 "안전은 챙기되 비용은 안 무는" 절충이 client emulation이다.

| | client (기본) | server |
| --- | --- | --- |
| 왕복 | 1회 | 2회 |
| 1회성 쿼리 | 유리 | 불리 |
| 반복 + 커넥션 재사용 | 불리 | 유리 (파싱 1회 재사용) |
| 서버 자원 | 안 씀 | `statementId` 점유 |
| 인젝션 방어 |  (escape) |  (구조적) |

> 한 줄: 기본값 client는 "대다수인 1회성/다양한 쿼리에서 추가 왕복 없이 안전을 보장"하는 무난한 선택. server prepare의 진가(파싱 재사용)는 반복 실행 + 커넥션 재사용이라는 특정 조건에서만 나오므로, 필요한 사람이 `useServerPrepStmts=true`로 명시적으로 켜도록 설계한 것이다.

> 참고: 과거엔 "server prepared statement는 MySQL query cache를 못 탄다"는 이유도 컸는데, query cache 자체가 MySQL 8.0에서 제거돼 지금은 의미 없는 historical 이유다.

실무 팁으로, 반복 실행이 많은 서비스(배치, 핫패스 쿼리)는 `useServerPrepStmts=true&cachePrepStmts=true`를 켜는 게 정석이다.


## 정리
---

| | Statement | ClientPreparedStatement | ServerPreparedStatement |
| --- | --- | --- | --- |
| 와이어 명령 | `COM_QUERY` | `COM_QUERY` | `COM_STMT_PREPARE` + `COM_STMT_EXECUTE` |
| 왕복 횟수 | 1회 | 1회 | 2회 (prepare 1 + execute N) |
| 값 전송 형태 | SQL 텍스트에 직접 합침 | SQL 텍스트에 escape해서 합침 | 바이너리, 별도 필드 |
| SQL 파싱 시점 | 매 실행마다 | 매 실행마다 | prepare 때 1회 (재실행 시 플랜 재사용) |
| 인젝션 방어 | 없음  | escape 로직에 의존  | 구조적으로 불가 |
| escape 필요? | (안 함) | 필요 (`StringUtils.escapeString`) | 불필요 |

## 부록 — 패킷

소켓 write로 전송되는 건 `COM_QUERY` 바이트 하나가 아니라, 그걸 감싼 MySQL 프로토콜 패킷 한 개다.

```
┌──────────── MySQL Packet ─────────────┐
│ [3 byte] payload length               │ ← 패킷 헤더
│ [1 byte] sequence id                  │
├───────────────────────────────────────┤
│ [1 byte] 0x03  ← COM_QUERY            │ ← payload
│ [N byte] "SELECT id FROM users ..."   │
└───────────────────────────────────────┘
```

- `buildComQuery`가 채운 건 payload 부분(`0x03` + SQL)이다.
- 실제 `socket.write` 직전에 드라이버가 앞에 **헤더(length + seq)**를 붙여 완성된 패킷을 내보낸다.

```
└─ socket OutputStream.write(...)   ← COM_QUERY 패킷을 와이어로 전송
                                      (헤더 + [0x03 SELECT...])
```

- `COM_QUERY` = payload 첫 바이트가 가리키는 명령 종류(`0x03` = "이 패킷은 텍스트 쿼리다")
- 전송 단위 = 그 명령을 담은 패킷(packet)
