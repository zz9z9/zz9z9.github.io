---
title: HashMap의 put 메서드 들여다보기
date: 2025-02-21 22:25:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---

## 사용 예시

```java
@Slf4j
@Component
@RequiredArgsConstructor
@Profile("!test")
public class ApplicationShutdownListener implements ApplicationListener<ContextClosedEvent> {

    private final FileBackupManager fileBackupManager;

    @Value("${file.address-book}")
    private String fileName;

    @Value("${file.address-book-backup-prefix}")
    private String backupFilePrefix;

    @Override
    public void onApplicationEvent(ContextClosedEvent event) {
        try {
            fileBackupManager.backup(fileName, backupFilePrefix);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

}
```

## ApplicationListener
> Observer 패턴을 기반으로 한 이벤트 리스너 인터페이스

- 관심 있는 이벤트 타입을 제네릭으로 선언 가능
  - ApplicationListener<T> 형태로 특정 이벤트 타입을 지정할 수 있습니다.
  - 이렇게 하면 해당 이벤트 타입이 발생했을 때만 리스너가 실행됩니다.

- Spring ApplicationContext에 등록되면 자동으로 이벤트 필터링
  - ApplicationContext에 등록된 리스너는 Spring에서 자동으로 관리됩니다.
  - 등록된 이벤트 리스너는 자신이 관심 있는 이벤트 타입이 발생할 때만 호출됩니다.

```java
// org.springframework.context.ApplicationListener
@FunctionalInterface
public interface ApplicationListener<E extends ApplicationEvent> extends EventListener {
void onApplicationEvent(E event);

    static <T> ApplicationListener<PayloadApplicationEvent<T>> forPayload(Consumer<T> consumer) {
        return (event) -> {
            consumer.accept(event.getPayload());
        };
    }
}
```

### ApplicationListener 등록
- AbstractApplicationContext#addApplicationListener에서 담당

public void addApplicationListener(ApplicationListener<?> listener) {
Assert.notNull(listener, "ApplicationListener must not be null");
if (this.applicationEventMulticaster != null) {
this.applicationEventMulticaster.addApplicationListener(listener);
}

    this.applicationListeners.add(listener);
}

### 애플리케이션 종료시 ContextClosedEvent 발행
- AbstractApplicationContext#doClose
```java
protected void doClose() {
    if (this.active.get() && this.closed.compareAndSet(false, true)) {
        if (this.logger.isDebugEnabled()) {
          this.logger.debug("Closing " + this);
        }

        Throwable ex;
        try {
            this.publishEvent((ApplicationEvent)(new ContextClosedEvent(this)));
        } catch (Throwable var3) {
            ex = var3;
            this.logger.warn("Exception thrown from ApplicationListener handling ContextClosedEvent", ex);
        }

        if (this.lifecycleProcessor != null) {
            try {
                this.lifecycleProcessor.onClose();
            } catch (Throwable var2) {
                ex = var2;
                this.logger.warn("Exception thrown from LifecycleProcessor on context close", ex);
            }
        }

        this.destroyBeans();
        this.closeBeanFactory();
        this.onClose();
        if (this.earlyApplicationListeners != null) {
            this.applicationListeners.clear();
            this.applicationListeners.addAll(this.earlyApplicationListeners);
        }

        this.active.set(false);
    }

}

```

### ApplicationListener 호출
- SimpleApplicationEventMulticaster#doInvokeListener
```java
private void doInvokeListener(ApplicationListener listener, ApplicationEvent event) {
    try {
        listener.onApplicationEvent(event);
    } catch (ClassCastException var6) {
        ClassCastException ex = var6;
        String msg = ex.getMessage();
        if (msg != null && !this.matchesClassCastMessage(msg, event.getClass()) && (!(event instanceof PayloadApplicationEvent) || !this.matchesClassCastMessage(msg, ((PayloadApplicationEvent)event).getPayload().getClass()))) {
            throw ex;
        }

        Log loggerToUse = this.lazyLogger;
        if (loggerToUse == null) {
            loggerToUse = LogFactory.getLog(this.getClass());
            this.lazyLogger = loggerToUse;
        }

        if (loggerToUse.isTraceEnabled()) {
            loggerToUse.trace("Non-matching event type for listener: " + listener, ex);
        }
    }

}
```


## ApplicationContext
// org.springframework.context.ApplicationContext
public interface ApplicationContext extends EnvironmentCapable, ListableBeanFactory, HierarchicalBeanFactory, MessageSource, ApplicationEventPublisher, ResourcePatternResolver {
@Nullable
String getId();

    String getApplicationName();

    String getDisplayName();

    long getStartupDate();

    @Nullable
    ApplicationContext getParent();

    AutowireCapableBeanFactory getAutowireCapableBeanFactory() throws IllegalStateException;
}



## ApplicationContextEvent
> Base class for events raised for an ApplicationContext.
> 4가지 구현체가 존재 (스프링 6.0.4 버전 기준)
> ContextClosedEvent, ContextRefreshedEvent, ContextStartedEvent, ContextStoppedEvent

// org.springframework.context.event.ApplicationContextEvent
public abstract class ApplicationContextEvent extends ApplicationEvent {
public ApplicationContextEvent(ApplicationContext source) {
super(source);
}

    public final ApplicationContext getApplicationContext() {
        return (ApplicationContext)this.getSource();
    }
}

## ApplicationContext의 생명주기
> ApplicationContext는 애플리케이션의 전체 실행 흐름을 관리하며, 다음과 같은 주요 단계로 동작

| 단계 | 설명 |
| ---- | --- |
| 1. ApplicationContext 생성 (refresh() 호출)| ApplicationContext가 인스턴스화되고, 필요한 초기 작업을 수행 |
| 2. Bean 정의 로드 (BeanFactory 설정) | XML, JavaConfig, 또는 @ComponentScan을 통해 Bean 정의를 로드 |
| 3. Bean 객체 생성 (Instantiation & Dependency Injection) | BeanFactory가 Bean을 생성하고, 의존성을 주입 |
| 4. ApplicationEvent 발생 (ContextRefreshedEvent) | 	컨텍스트가 완전히 초기화되면 ContextRefreshedEvent를 발생 |
| 5. 애플리케이션 실행 | ApplicationContext를 통해 애플리케이션이 정상적으로 동작 |
| 6. 컨텍스트 종료 (ContextClosedEvent & ContextStoppedEvent) | 애플리케이션 종료 시, ContextClosedEvent가 발생 |
| 7. 컨텍스트 소멸 (destroy()) | 모든 @PreDestroy 및 DisposableBean 메서드가 실행되고 종료 |

### 관련 이벤트
> Spring은 ApplicationContext의 특정 시점에서 이벤트를 발생시켜, 개발자가 특정 타이밍에 작업을 수행할 수 있도록 합니다.

| 이벤트 | 설명 |
| ----- | ----|
| ContextRefreshedEvent | ApplicationContext가 초기화되었을 때 발생 |
| ContextStartedEvent | start() 메서드 호출 시 발생 (잘 사용하지 않음) |
| ContextStoppedEvent | stop() 메서드 호출 시 발생 (잘 사용하지 않음) |
| ContextClosedEvent | close() 메서드 호출 시 발생 (애플리케이션 종료) |
| ApplicationReadyEvent	| Spring Boot에서 ApplicationContext가 완전히 로드된 후 발생 |


## Spring Bean 생명주기
> ApplicationContext가 애플리케이션 전체의 생명주기를 관리하는 반면, Bean의 생명주기는 개별 객체에 초점이 맞춰져 있습니다.

| 단계 | 설명 |
| ----| ----|
| 1. 인스턴스 생성 (new) | Spring 컨테이너가 Bean 객체를 생성 (@Component, @Bean) |
| 2. 의존성 주입 (@Autowired) | 필요한 의존성을 주입 (@Autowired, @Inject) |
| 3. @PostConstruct 실행 | 초기화 직전 실행 (DB 연결, 캐시 로딩 등) |
| 4. InitializingBean#afterPropertiesSet() 실행 | @PostConstruct 이후 추가 설정 가능 |
| 5. Bean 사용 가능 (컨텍스트 실행 중) | Bean이 정상적으로 사용됨 |
| 6. 컨텍스트 종료 (ContextClosedEvent) | Spring 애플리케이션 종료 |
| 7. @PreDestroy 실행 | Bean이 삭제되기 전 정리 작업 수행 |
| 8. DisposableBean#destroy() 실행 | @PreDestroy 이후 추가 정리 작업 가능 |

### 관련 인터페이스, 어노테이션

| 방식 | 설명 |
| --- | ---- |
| @PostConstruct | Bean 초기화 시 자동 실행 |
| InitializingBean#afterPropertiesSet()	| Bean 생성 후 실행 (@PostConstruct보다 먼저 실행) |
| DisposableBean#destroy() | Bean 소멸 전에 실행 (@PreDestroy보다 먼저 실행) |
| @PreDestroy | Bean이 소멸되기 전 실행 |
| @Bean(initMethod, destroyMethod) | XML 또는 JavaConfig에서 초기화 & 종료 메서드 지정 가능 |

## 두 생명주기를 같이 보면 ?

> Spring 생명주기 타임라인 (시간 흐름)

| 단계 | ApplicationContext 생명주기 | Bean 생명주기 | 관련 이벤트 & 메서드 |
|--------|--------------------------------|------------------|------------------------|
| **1. ApplicationContext 생성** | SpringApplication.run() → createApplicationContext() 호출 | - | - |
| **2. ApplicationContext 초기화 시작** | refresh() 실행 | - | ContextRefreshedEvent 발생 |
| **3. Bean 정의 로드** | BeanFactory가 Bean 정의 로드 | - | - |
| **4. Bean 객체 생성 (new)** | BeanFactory.createBean() 호출 | Bean 인스턴스화 | - |
| **5. 의존성 주입 (DI)** | BeanFactory가 의존성 주입 수행 | @Autowired 주입 | - |
| **6. Bean 초기화** | - | @PostConstruct 실행 | - |
| **7. Bean 초기화 콜백** | - | InitializingBean#afterPropertiesSet() 실행 | - |
| **8. ApplicationContext 준비 완료** | finishRefresh() 호출 | Bean 사용 가능 | ContextRefreshedEvent 발생 |
| **9. 애플리케이션 실행 중** | 요청 처리, 이벤트 처리 | Bean 정상 동작 | - |
| **10. 애플리케이션 종료 요청 (close())** | ContextClosedEvent 발생 | @PreDestroy 실행 | - |
| **11. Bean 소멸 콜백** | destroy() 호출 | DisposableBean#destroy() 실행 | - |
| **12. ApplicationContext 종료** | 모든 Bean 제거 후 종료 | - | - |


## @Autowired vs @PostConstruct

| 차이점 | @Autowired 생성자에서 초기화 | @PostConstruct에서 초기화 |
|--------|--------------------------------|------------------------------|
| **실행 시점** | **객체 생성과 동시에 실행** (Spring이 Bean을 만들 때) | **Bean 초기화 직후 실행** (의존성 주입이 모두 완료된 후) |
| **의존성 주입 보장** | clientDataLoader가 **필수적으로** 주입되어야 함 | clientDataLoader가 선택적(@Autowired(required=false))일 수도 있음 |
| **테스트 용이성** | 생성자에서 초기화 → 단위 테스트 시 Mock 주입 필요 | @PostConstruct 사용 → Setter로 Mock 주입 가능 |
| **선택적 실행 가능 여부** | **항상 실행됨** (Bean이 생성될 때마다 실행) | 필요 시 프로퍼티로 활성화/비활성화 가능 |
| **Super 클래스와의 관계** | 부모 클래스의 생성자가 먼저 실행됨 | 자식 클래스의 @PostConstruct가 먼저 실행됨 |
| **순환 참조 문제** | A → B → A 순환 참조 시 예외 발생 가능 | 순환 참조를 늦출 수 있어 문제 완화 가능 |

---

## 예시: 특정 설정값에 따라 실행을 컨트롤해야 하는 경우 (@PostConstruct 활용)

** 시나리오:**
- ClientStore가 실행될 때, application.properties의 값에 따라 **초기 데이터를 로드할지 여부를 결정**해야 한다.
- 예를 들어 client.data.load.enabled=false라면 데이터를 로드하지 않고 빈 상태로 유지하고 싶다.
- **이 경우 @Autowired 생성자에서는 실행을 컨트롤할 수 없지만, @PostConstruct에서는 가능하다.**
