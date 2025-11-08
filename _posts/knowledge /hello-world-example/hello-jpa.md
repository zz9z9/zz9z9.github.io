---
title: Hibernate / Spring Data JPA 훑어보기
date: 2025-11-05 22:00:00 +0900
categories: [지식 더하기, Hello-World 구현]
tags: [JPA]
---

> JDBC부터 mybatis-spring까지 간단하게 사용해보면서 어떤지 느껴봤었는데, JPA는 어떨까

- 시나리오 : 회원 정보 저장시 이력 테이블에도 저장
- 회원 정보 조회시 이력정보도 조회

## JPA
---

```java
@Entity
public class Member {
    @Id
    @GeneratedValue
    private Long memberId;

    private String memberName;

    @OneToMany(mappedBy = "member", cascade = CascadeType.PERSIST)
    private List<MemberHistory> histories = new ArrayList<>();

    public void addHistory() {
        MemberHistory history = new MemberHistory();
        history.setMemberName(memberName);
        history.setActionType("REGISTER");
        history.setRegisteredAt(LocalDateTime.now());

        histories.add(history);
        history.setMember(this);
    }

}
```

```java

@Entity
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MemberHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long seq;

    @Column(name = "member_name", nullable = false)
    private String memberName;

    @Column(name = "action_type", nullable = false)
    private String actionType;

    @Column(name = "registered_at", nullable = false)
    private LocalDateTime registeredAt;

    @ManyToOne
    @JoinColumn(name = "member_id")
    private Member member;

}
```

```java
@Repository
public class MemberRepository {

    @PersistenceContext
    private EntityManager em;

    public void save(Member member) {
        em.persist(member);
    }

    public List<Member> findAll() {
        return em.createQuery("select m from Member m", Member.class)
                .getResultList();
    }

}
```

```java
@Service
@RequiredArgsConstructor
public class MemberService {

  private final MemberRepository memberRepository;

  public void join(Member member) {
    member.addHistory();
    memberRepository.save(member);
  }

  @Transactional
  public void updateName(Long memberId, String newName) {
    Member member = memberRepository.findById(memberId);

    member.updateName(newName);

    // 별도 save() 호출 불필요
    // 스프링 데이터 JPA도 영속 상태로 관리하므로 커밋 시 자동 dirty checking 수행
  }

  public List<Member> getMembers() {
    List<Member> members = memberRepository.findAll();
    return members;
  }

}
```

### 느낌
- 로직 구성이 member 테이블에 insert, member_history에 insert 이런 느낌보다 좀 더 객체의 행위(`member.addHistory()`, `member.updateName(newName)`)에 집중할 수 있게 만들어주는 것 같다.
- 조회시 회원의 키 값으로, 이력을 또 조회하는 방식이 아닌 연관된 이력을 함께 포함시켜준다.
  - 따라서, 어떤 키값으로 관련된 테이블을 조회해오는지 이런 테이블과 관련된 부분이 로직에 드러나지 않아서 로직을 좀 더 깔끔하게 유지할 수 있는 것 같다.
- 마법같이 알아서 처리돼서 편하기도 하지만, 내부적으로 어떤식으로 처리되는지를 정확히 알지 않으면, 비효율적이거나 의도와는 다르게 동작해서 이슈가 될 수 있을 것 같다.


## Spring Data JPA
---

```java
import org.springframework.data.jpa.repository.JpaRepository;

public interface MemberRepository extends JpaRepository<Member, Long> {
}
```

```java
@Transactional
public void updateName(Long memberId, String newName) {
    Member member = memberRepository.findById(memberId).orElseThrow();

    member.updateName(newName);

    // 별도 save() 호출 불필요
    // 스프링 데이터 JPA도 영속 상태로 관리하므로 커밋 시 자동 dirty checking 수행
}
```

- 나머지 코드 동일

### 느낌
