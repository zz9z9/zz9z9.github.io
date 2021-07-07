---
title: 엔티티에 있는 enum 타입 필드를 DB 컬럼에 어떻게 맵핑시킬 수 있을까 ?
date: 2021-07-07 00:29:00 +0900
categories: [JPA]
tags: [JAVA, JPA] # TAG names should always be lowercase
---

> 예를 들어 주문 엔티티의 '주문 상태'와 같이 enum 타입으로 선언하기 적합한 필드들이 있다. 문자열, 숫자, 날짜 등도 아닌 enum 타입은 DB에 어떻게 저장시켜야할까 ?

# @Enumerated
---
## 1. EnumType.ORDINAL
- 아래와 같이 사용하게되면 JPA는 `ENUM` 클래스의 `ordinal()`메서드를 사용하여 값을 저장한다(0부터 시작해서 상수가 선언된 순서대로 값이 맵핑)
- 따라서, 아래의 경우는 DB의 Article 테이블 status 컬럼에 0이 저장된다.
- 문제점
  - 중간에 새 값을 추가하거나 순서를 재정렬하면 기존 데이터 정합성이 깨진다.

```java
public enum Status {
    OPEN, REVIEW, APPROVED, REJECTED;
}
```

```java
@Entity
public class Article {
    @Id
    private int id;

    private String title;

    @Enumerated(EnumType.ORDINAL)
    private Status status;
}
```

```java
Article article = new Article();
article.setId(1);
article.setTitle("ordinal title");
article.setStatus(Status.OPEN);
```

## 2. EnumType.STRING
- 아래와 같이 사용하게되면 JPA는 `ENUM` 클래스의 `name()`메서드를 사용하여 값을 저장한다(상수 이름을 문자열로 반환)
- 따라서, 아래의 경우는 DB의 Article 테이블 status 컬럼에 OPEN이 저장된다.
- 문제점
  - enum 값을 변경하게 되면 기존 데이터 정합성이 깨진다.
  - 필요 이상으로 많은 공간을 소비한다.

```java
@Entity
public class Article {
    @Id
    private int id;

    private String title;

    @Enumerated(EnumType.STRING)
    private Status status;
}
```

```java
Article article = new Article();
article.setId(1);
article.setTitle("ordinal title");
article.setStatus(Status.OPEN);
```

# @PostLoad, @PrePersist
---
- JPA 콜백 메서드인 @PostLoad, @PrePersist를 활용하여 DB에 저장할 때의 값과 가져와서 맵핑할 값을 분리한다.
  - @PrePersist : 새로운 엔티티를 저장하기 이전에 호출됨
  - @PostPersist : 새로운 엔티티를 저장한 이후에 호출됨
- 아래와 같이 사용하게 되면 DB의 Article 테이블 priorityValue 컬럼에 300이 저장된다.
- 문제점
  - 하나의 값을 위해 두 개의 속성을 가져야한다.
  - JPQL 쿼리에서 Enum 값을 사용할 수 없다.

```java
public enum Priority {
    LOW(100), MEDIUM(200), HIGH(300);

    private int priority;

    private Priority(int priority) {
        this.priority = priority;
    }

    public int getPriority() {
        return priority;
    }

    public static Priority of(int priority) {
        return Stream.of(Priority.values())
          .filter(p -> p.getPriority() == priority)
          .findFirst()
          .orElseThrow(IllegalArgumentException::new);
    }
}
```

```java
@Entity
public class Article {

    @Id
    private int id;

    private String title;

    @Basic
    private int priorityValue; // DB에 저장될 값

    @Transient // 엔티티 객체의 데이터와 테이블의 컬럼과 매핑하고 있는 관계를 제외하기 위해 사용
    private Priority priority; // DB에서 가져와서 맵핑될 값

    @PostLoad
    void fillTransient() {
        if (priorityValue > 0) {
            this.priority = Priority.of(priorityValue);
        }
    }

    @PrePersist
    void fillPersistent() {
        if (priority != null) {
            this.priorityValue = priority.getPriority();
        }
    }
}
```

```java
Article article = new Article();
article.setId(3);
article.setTitle("callback title");
article.setPriority(Priority.HIGH);
```

# @Converter
---
> 위 방법들의 한계를 극복하기 위해, JPA 2.1에서는 엔티티 속성을 DB 값으로 변환할 수 있도록 @Converter, AttributeConverter를 제공한다.

- 아래와 같이 사용하게 되면 DB의 Article 테이블 category 컬럼에 M이 저장된다.
- 장점
  - 새로운 값을 추가하거나 상수명을 바꾼다 하더라도 기존 데이터에 지장을 주지않는다.
  - 하나의 엔티티 속성으로 DB 컬럼과 맵핑될 수 있다.
- 굳이 단점(?)이라고 한다면 부가적인 코드(생성자, getter 등)가 추가된다는 점 일것 같다.

```java
public enum Category {
    SPORT("S"), MUSIC("M"), TECHNOLOGY("T");

    private String code;

    private Category(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
```
```java
@Entity
public class Article {

    @Id
    private int id;

    private String title;

    private Category category;
}
```

```java
@Converter(autoApply = true) // Category 타입으로 선언된 필드에 자동으로 컨버팅 적용
public class CategoryConverter implements AttributeConverter<Category, String> {

    @Override
    public String convertToDatabaseColumn(Category category) {
        if (category == null) {
            return null;
        }
        return category.getCode();
    }

    @Override
    public Category convertToEntityAttribute(String code) {
        if (code == null) {
            return null;
        }

        return Stream.of(Category.values())
          .filter(c -> c.getCode().equals(code))
          .findFirst()
          .orElseThrow(IllegalArgumentException::new);
    }
}
```

```java
Article article = new Article();
article.setId(4);
article.setTitle("converted title");
article.setCategory(Category.MUSIC);
```


# 더 공부해야할 부분
---
- JPA Entity 라이프사이클
- @Transient, @Basic 등과 영속성

# 참고자료
---
- [https://www.baeldung.com/jpa-persisting-enums-in-jpa](https://www.baeldung.com/jpa-persisting-enums-in-jpa)
- [https://www.baeldung.com/jpa-entity-lifecycle-events](https://www.baeldung.com/jpa-entity-lifecycle-events)

