1. Spring 빈으로 관리할 때 (@Component, @Service, @Repository 등 사용)
✅ 장점
1️⃣ 의존성 주입(DI, Dependency Injection) 가능

@Autowired 또는 생성자 주입을 통해 객체 생성과 관리를 Spring이 자동으로 처리
예: ClientDataLoader가 CsvFileReader를 자동으로 주입받을 수 있음
java
복사
편집
@Component
public class ClientDataLoader {
    private final CsvReader csvReader;

    @Autowired
    public ClientDataLoader(CsvReader csvReader) {  // DI 적용
        this.csvReader = csvReader;
    }
}
2️⃣ 싱글톤(Singleton)으로 관리됨 (기본 설정)

기본적으로 Spring 빈은 애플리케이션 실행 동안 단 하나의 인스턴스만 유지
불필요한 객체 생성을 방지하여 메모리 절약
예: CsvFileReader가 여러 곳에서 사용될 때, 하나의 객체만 공유함
3️⃣ AOP(Aspect-Oriented Programming) 적용 가능

트랜잭션(@Transactional), 로깅(@Slf4j), 모니터링 등을 쉽게 추가할 수 있음
예: CSV 파일을 읽을 때, 파일 접근 속도를 로깅하는 AOP 적용 가능
java
복사
편집
@Aspect
@Component
public class LoggingAspect {
    @Before("execution(* CsvFileReader.read(..))")
    public void logBefore(JoinPoint joinPoint) {
        log.info("파일 읽기 시작: " + Arrays.toString(joinPoint.getArgs()));
    }
}
4️⃣ 스프링 생명주기 관리 가능

@PostConstruct, @PreDestroy 등을 활용하여 객체 초기화 및 정리 가능
java
복사
편집
@Component
public class CsvFileReader {
    @PostConstruct
    public void init() {
        log.info("CsvFileReader 초기화 완료");
    }
}
✅ 적합한 경우
✔ 여러 컴포넌트에서 공유하는 객체
✔ 상태를 관리하는 서비스 또는 데이터 액세스 클래스 (@Service, @Repository)
✔ AOP, 트랜잭션, 보안 등의 기능을 추가해야 하는 경우

🚀 2. Spring 빈으로 관리하지 않을 때 (일반 클래스로 사용, static 메서드 활용 등)
✅ 장점
1️⃣ Spring 컨텍스트 없이 독립적으로 사용 가능

Spring 환경이 필요하지 않으므로 일반적인 Java 애플리케이션에서도 활용 가능
예: CsvFileReader를 스프링과 무관하게 유틸리티 클래스처럼 사용 가능
java
복사
편집
public class CsvFileReader {
    public static List<String> read(String filename) throws IOException {
        return Files.readAllLines(Paths.get(filename));
    }
}
2️⃣ 불필요한 빈 등록을 피할 수 있음 (메모리 절약)

가벼운 유틸리티 클래스(예: StringUtils)는 굳이 스프링 빈으로 만들 필요 없음
예: CsvFileReader가 단순한 파일 읽기만 한다면 굳이 빈으로 관리하지 않아도 됨
3️⃣ 테스트가 간단해짐

Spring 컨텍스트 로딩 없이 바로 객체를 생성하고 테스트할 수 있음 → 테스트 속도가 빨라짐
예:
java
복사
편집
@Test
void testReadFile() throws IOException {
    List<String> lines = CsvFileReader.read("test.csv"); // Spring 없이 사용 가능
    assertFalse(lines.isEmpty());
}
4️⃣ 정적(static) 메서드를 활용하여 인스턴스 생성 없이 사용 가능

유틸리티 성격이 강한 클래스는 객체 생성 없이 직접 호출 가능
java
복사
편집
public class StringUtils {
    public static boolean isEmpty(String s) {
        return s == null || s.isEmpty();
    }
}
위처럼 상태(state)를 가지지 않는 경우 static 메서드가 적합함.
✅ 적합한 경우
✔ 상태를 가지지 않는 유틸리티 클래스 (예: StringUtils, CsvFileReader)
✔ 객체 생성을 피하고 싶을 때 (메모리 절약 목적)
✔ 스프링 없이도 독립적으로 사용해야 할 때

🎯 3. 비교 정리
Spring 빈 (@Component)	Spring 빈이 아님 (일반 클래스, static)
객체 관리	Spring이 관리 (DI, Singleton)	직접 객체를 생성해야 함
의존성 주입	가능 (@Autowired, 생성자 주입)	불가능 (static 사용 시)
싱글톤 패턴	기본적으로 싱글톤	필요 시 직접 싱글톤 구현
테스트 용이성	Spring 컨텍스트 필요 (@SpringBootTest 사용 가능)	Spring 없이 단위 테스트 가능
AOP 적용	가능 (트랜잭션, 로깅 등)	불가능
유틸리티 기능	적합하지 않음 (불필요한 객체 생성)	적합 (static 메서드 활용)
상태(state) 관리	가능 (@Service, @Repository 등)	상태를 가지면 안 됨