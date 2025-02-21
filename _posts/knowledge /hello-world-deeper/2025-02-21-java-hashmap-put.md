---
title: HashMap의 put 메서드 들여다보기
date: 2025-02-21 22:25:00 +0900
categories: [지식 더하기, 들여다보기]
tags: [Java]
---

> 자바 17 기준, GPT 선생님과 함께 공부해보았다.

```java
static class Node<K,V> implements Map.Entry<K,V> {
    final int hash;
    final K key;
    V value;
    Node<K,V> next;

    Node(int hash, K key, V value, Node<K,V> next) {
        this.hash = hash;
        this.key = key;
        this.value = value;
        this.next = next;
    }

    public final K getKey()        { return key; }
    public final V getValue()      { return value; }
    public final String toString() { return key + "=" + value; }

    public final int hashCode() {
        return Objects.hashCode(key) ^ Objects.hashCode(value);
    }

    public final V setValue(V newValue) {
        V oldValue = value;
        value = newValue;
        return oldValue;
    }

    public final boolean equals(Object o) {
        if (o == this)
            return true;

        return o instanceof Map.Entry<?, ?> e
                && Objects.equals(key, e.getKey())
                && Objects.equals(value, e.getValue());
    }
}
```

```java
transient Node<K,V>[] table; // (0)

public V put(K key, V value) {
    return putVal(hash(key), key, value, false, true);
}

final V putVal(int hash, K key, V value, boolean onlyIfAbsent, boolean evict) {
  Node<K,V>[] tab; Node<K,V> p; int n, i;

  // (1)
  if ((tab = table) == null || (n = tab.length) == 0)
    n = (tab = resize()).length;

  // (2)
  if ((p = tab[i = (n - 1) & hash]) == null)
    tab[i] = newNode(hash, key, value, null);

  // (3)
  else {
    Node<K,V> e; K k;
    // (3-1)
    if (p.hash == hash && ((k = p.key) == key || (key != null && key.equals(k))))
      e = p;
    // (3-2)
    else if (p instanceof TreeNode)
      e = ((TreeNode<K,V>)p).putTreeVal(this, tab, hash, key, value);
    // (3-3)
    else {
      for (int binCount = 0; ; ++binCount) {
        if ((e = p.next) == null) {
          p.next = newNode(hash, key, value, null);
          if (binCount >= TREEIFY_THRESHOLD - 1) // -1 for 1st
            treeifyBin(tab, hash);
          break;
        }

        if (e.hash == hash && ((k = e.key) == key || (key != null && key.equals(k))))
          break;

        p = e;
      }
    }

    // (4)
    if (e != null) {
      V oldValue = e.value;
      if (!onlyIfAbsent || oldValue == null)
        e.value = value;

      afterNodeAccess(e);
      return oldValue;
    }
  }

  // (5)
  ++modCount;
  if (++size > threshold)
    resize();

  // (6)
  afterNodeInsertion(evict);

  return null;
}
```

## (0) Node<K,V>[] table
```java
transient Node<K,V>[] table;
```
- `HashMap`은 `Node`객체를 담고있는 배열로 구현된다.

## (1) 테이블 크기 확인 및 초기화
```java
if ((tab = table) == null || (n = tab.length) == 0)
  n = (tab = resize()).length;
```

- table이 아직 생성되지 않았거나, 길이가 0이면 `resize()`를 호출하여 초기화한다.
- 해시 테이블(table)이 존재하지 않으면 기본 크기(`DEFAULT_INITIAL_CAPACITY = 16`)로 초기화된다.

## (2) 해시 충돌 없이 바로 저장 가능한 경우
```java
if ((p = tab[i = (n - 1) & hash]) == null)
  tab[i] = newNode(hash, key, value, null);
```

- (n - 1) & hash 연산을 수행하여 해시 값을 배열 인덱스로 변환한다.
  - (n - 1) & hash는 hash % n과 동일한 역할을 하면서 성능을 최적화한다.
- 해당 위치(`tab[i]`)가 null이면 새로운 노드를 생성하여 저장한다.

## (3) 해시 충돌한 경우
> 즉, `tab[i = (n - 1) & hash]`가 null이 아닌 경우

### (3-1) 이미 존재하는 키인 경우
```java
if (p.hash == hash && ((k = p.key) == key || (key != null && key.equals(k))))
  e = p;
```

- `p.hash == hash`이고 `p.key.equals(key)`라는건 이미 존재하는 키
- `(4)`에서 기존 값을 현재 값으로 덮어쓴다. `(e.value = value)`

### (3-2) 트리로 저장해야 하는 경우
```java
else if (p instanceof TreeNode)
  e = ((TreeNode<K,V>)p).putTreeVal(this, tab, hash, key, value);
```

- 기존 노드 p가 트리 구조(`TreeNode`)로 저장된 경우 트리에 값을 추가한다.
  - HashMap은 특정 조건(`TREEIFY_THRESHOLD = 8`)에서 연결 리스트 대신 레드-블랙 트리를 사용한다. <br> (3-3에서 살펴봄)

### (3-3) 연결 리스트로 저장해야 하는 경우
```java
for (int binCount = 0; ; ++binCount) {
  if ((e = p.next) == null) {
    p.next = newNode(hash, key, value, null);
    if (binCount >= TREEIFY_THRESHOLD - 1) // -1 for 1st
      treeifyBin(tab, hash);
    break;
  }

  if (e.hash == hash && ((k = e.key) == key || (key != null && key.equals(k))))
    break;

  p = e;
}
```

- 다음 노드를 가리키는 `p.next`를 통해 연결 리스트를 순회
  - 동일한 키를 찾았다면 `(4)`에서 기존 값을 현재 값으로 덮어쓴다.
  - 동일한 키를 찾지 못하면 연결 리스트의 마지막 노드의 다음(`p.next`)에 새로운 노드 추가
  - 노드 추가시 연결 리스트의 크기가 8이 된다면 `TreeNode` 구조로 변경

### (4) 기존 키가 존재하는 경우 값 덮어쓰기
```java
if (e != null) { // existing mapping for key
    V oldValue = e.value;
    if (!onlyIfAbsent || oldValue == null)
        e.value = value;
    afterNodeAccess(e);
    return oldValue;
}
```

- 기존 키가 존재하면(e가 null이 아님) 값을 덮어씌운다.
- onlyIfAbsent가 true이면 기존 값이 없을 때만 변경.
- afterNodeAccess(e)는 LRU 캐시 같은 구조에서 사용될 수 있다.

### (5) HashMap 크기 증가 및 리사이징
```java
++modCount;
if (++size > threshold)
    resize();
```

- modCount는 구조적 변경(삽입/삭제 등) 횟수를 의미하며, 반복문에서 변경 감지를 위해 사용된다.
- size(현재 요소 개수)가 threshold(용량 * loadFactor)보다 크면 해시 테이블을 두 배로 확장한다.

### (6) 후처리 및 반환
```java
afterNodeInsertion(evict);
return null;
```
- afterNodeInsertion(evict)는 LRU 캐시 같은 경우 특정 조건에서 노드를 제거할 때 사용된다.
- 새 값을 추가한 경우 null을 반환한다.

# 궁금한 부분

## 1. HashMap의 연결 리스트와 LinkedList 비교

| 비교 항목	                                                            | HashMap의 연결 리스트                       |	LinkedList (Java java.util.LinkedList) |
|-------------------------------------------------------------------|---------------------------------------|----------------------------------------- |
| 목적                                                                | 	해시 충돌 해결 (체이닝)                       | 일반적인 자료구조 활용 |
| 사용 방식	| `Node<K,V>`의 next 필드를 사용하여 직접 연결 리스트 구현 |	`Node<E>` 클래스를 내부적으로 사용 |
| 이중 연결 리스트 여부                                                      | X                                     | O |

## 2. binCount, treeifyBin에서 쓰는 bin이란 ?
> 3-3 코드

```java
for (int binCount = 0; ; ++binCount) {
  if ((e = p.next) == null) {
    p.next = newNode(hash, key, value, null);
    if (binCount >= TREEIFY_THRESHOLD - 1) // -1 for 1st
      treeifyBin(tab, hash);
    break;
  }

      ...
```

### slot, bin, bucket 용어 정리
**slot**
- slot은 일반적인 해시 테이블 개념에서 해시 테이블의 인덱스 하나를 의미
- 예를 들어, `table[3]`에 값이 저장되었다면 3번 슬롯(slot)에 저장된것

**bin(=bucket)**
- HashMap을 설명할 때 보통 bucket이라는 단어를 많이 사용
- `table[index]`에 여러 개의 값이 저장될 경우, 이 공간을 bucket(버킷)이라고 부른다.
  - 즉, bin(bucket)은 같은 해시값을 가진 노드들이 저장되는 공간

```
HashMap 내부 (배열 + 연결 리스트)

Index (Slot)      Bucket (bin) 내용
-----------------------------------
table[0]   →   null
table[1]   →   (5, "X") -> (15, "Y") -> null
table[2]   →   (10, "A") -> (20, "B") -> null
table[3]   →   (30, "C") -> null
table[4]   →   null
```

**버킷 충돌 ?**
- 엄밀히 말하면 "슬롯이 충돌한다"는 표현이 더 정확하지만, "버킷에 충돌이 발생한다"는 표현이 일반적으로 많이 사용됨
