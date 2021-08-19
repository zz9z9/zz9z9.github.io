---
title: XSSF로 인한 OOM 에러 그리고 SXSSF와 메모리 사용량 비교해보기
date: 2021-07-23 23:00:00 +0900
categories: [개발 일기]
tags: [Java, Heap Memory, Eclipse Memory Analyzer]
---

# 상황
---
- [이 글](https://zz9z9.github.io/posts/excel-using-poi-library/) 에서 언급했듯이, poi 라이브러리를 활용해서 엑셀을 만들 때, XSSF 클래스를 사용하면
데이터 건수(엑셀 row)가 많은 경우 OOM 에러가 발생한다.
- XSSF를 개선한 SXSSF를 사용하면 해당 문제를 해결할 수 있다고 하는데, 실제로 메모리 사용량을 비교해보고자 한다.
  - 메모리 단면을 분석하는 방법은 [이 글](https://zz9z9.github.io/posts/heap-analyze-with-jmap-and-mat/) 을 참고한다.

# 분석하기
---
> `jps` 명령어로 pid를 확인한 뒤, `jmap dump:<dump-options> <pid>`를 활용하여 덤프 파일을 생성하고 <br>
> 해당 파일을 MAT(Eclipse Memory Analyzer)로 분석하였다.

- 테스트 환경
  - CPU : 2.6 GHz 6코어 Intel Core i7
  - 메모리 : 32GB 2667 MHz DDR4
  - java 8
  - 메이븐 디펜던시 설정

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <properties>
        <maven.compiler.source>1.8</maven.compiler.source>
        <maven.compiler.target>1.8</maven.compiler.target>
    </properties>

    <groupId>org.example</groupId>
    <artifactId>performance-test</artifactId>
    <version>1.0-SNAPSHOT</version>

    <dependencies>
        <dependency>
            <groupId>org.apache.maven.plugins</groupId>
            <artifactId>maven-compiler-plugin</artifactId>
            <version>3.8.1</version>
        </dependency>
        <dependency>
            <groupId>org.apache.poi</groupId>
            <artifactId>poi</artifactId>
            <version>4.0.1</version>
        </dependency>
        <dependency>
            <groupId>org.apache.poi</groupId>
            <artifactId>poi-ooxml</artifactId>
            <version>4.0.1</version>
        </dependency>
        <dependency>
            <groupId>org.apache.commons</groupId>
            <artifactId>commons-compress</artifactId>
            <version>1.19</version>
        </dependency>
    </dependencies>

</project>
```

### 테스트 수행 클래스

```java
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.ss.usermodel.Workbook;
import org.apache.poi.ss.util.CellReference;

import java.io.FileOutputStream;

public class PoiTester {
    private final int ROW_CNT = 10000;
    private final int COL_CNT = 10;
    private final long THREAD_WAIT_TIME = 60000L;
    private Workbook workbook;
    private String fileName;

    public PoiTester(Workbook workbook, String fileName) {
        this.workbook = workbook;
        this.fileName = fileName;
    }

    public void test() {
        long beginTime = System.currentTimeMillis();
        Workbook wb = workbook;
        Sheet sh = wb.createSheet();

        for (int rownum = 0; rownum < ROW_CNT; rownum++) {
            Row row = sh.createRow(rownum);
            for (int cellnum = 0; cellnum < COL_CNT; cellnum++) {
                Cell cell = row.createCell(cellnum);
                String address = new CellReference(cell).formatAsString();
                cell.setCellValue(address);
            }
        }

        try {
            long endTime = System.currentTimeMillis();
            long totalTime = ( endTime - beginTime ) / 1000;

            System.out.println(fileName+" 경과 시간 : "+totalTime+"초");

            Thread.sleep(THREAD_WAIT_TIME);

            FileOutputStream out = new FileOutputStream(fileName+".xlsx");
            wb.write(out);
            out.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
```

## 테스트 케이스1. XSSF
---
### 테스트 코드

```java
import org.apache.poi.xssf.usermodel.XSSFWorkbook;

public class XssfTest {
    public static void main(String[] args) {
        XSSFWorkbook workbook = new XSSFWorkbook();
        String fileName = "xssf_ver";
        PoiTester tester = new PoiTester(workbook, fileName);

        tester.test();
    }
}
```

- 실행 결과 : `xssf_ver 경과 시간 : 1초`

### Histogram
- 히스토그램을 살펴보면 ElementXobj 클래스 XSSFSheet 클래스에서 메모리의 대부분을 차지하고 있음을 알 수 있다.
- XSSFSheet 하나가 차지하는 메모리 크는 80byte 이지만, 해당 객체가 점유하고 있는 객체들을 모두 합치면 약 70Mb 정도를 차지하고 있는 것을 알 수 있다.
- 또한, 아래쪽에 보면 XSSFRow 즉, 행이 10000개 만들어진 것도 확인할 수 있다.
![image](https://user-images.githubusercontent.com/64415489/126831964-c998774b-2df9-4906-b571-d829a54a608c.png)

### Dominator Tree
- Dominator Tree를 살펴보면 ElementXobj 객체로 인해 대부분의 메모리가 점유되고 있다.
- `.xlsx` 파일은 XML 기반이라고 하는데, XSSF는 이 XML을 처리하는데 메모리를 상당히 많이 차지하는 것 같다.
  - `.xlsx` 의 XML과 관련된 글은 [네이버 기술블로그의 다음 글](https://d2.naver.com/helloworld/9423440) 을 참고해보면 좋을 것 같다.
![image](https://user-images.githubusercontent.com/64415489/126833565-449cc779-cb63-4b37-ab8c-ebb9bb330892.png)

## 테스트 케이스2. SXSSF(auto-flush 사용하지 않음)
---
### 테스트 코드

```java
import org.apache.poi.xssf.streaming.SXSSFWorkbook;

public class SxssfNoAutoFlush {
    public static void main(String[] args) {
        SXSSFWorkbook workbook = new SXSSFWorkbook(-1); // -1 : not use auto-flush
        String fileName = "sxssf_no_autoflush_ver";
        PoiTester tester = new PoiTester(workbook, fileName);

        tester.test();
    }
}
```

- 실행 결과 : `sxssf_no_autoflush_ver 경과 시간 : 10초`

### Histogram
- 히스토그램을 살펴보면 XSSFSheet에 비해 SXSSFSheet 객체 자체가 점유하는 메모리가 작고, 모든 객체가 점유하는 메모리를 합쳐도 15Mb 정도로 이전 70Mb에 비해 약 5배 줄어든 것을 확인할 수 있다.
- 또한, 아래쪽에 보면 SXSSFRow 즉, 행이 10000개 만들어진 것도 확인할 수 있다.
  - 10000개의 행이 모두 메모리 상에 있는 것을 통해 auto-flush가 적용되지 않은 것을 확인할 수 있다.
  - XSSFRow가 10000개 였을 때 0.24Mb를 차지했는데, SXSSFRow는 0.4Mb를 차지하는 것을 볼 수 있다.
![image](https://user-images.githubusercontent.com/64415489/126835008-f8ebd717-e2d3-4817-bed5-3cf69bd6d1ba.png)

### Dominator Tree
- XSSF를 사용할 때와는 다르게 ElementXobj 객체로 인한 낭비는 보이지 않는 것 같다.
![image](https://user-images.githubusercontent.com/64415489/126836904-3fbee4e0-2d99-4e84-abb7-6842fd653db3.png)


## 테스트 케이스3. SXSSF(auto-flush 사용)
---
### 테스트 코드

```java
import org.apache.poi.xssf.streaming.SXSSFWorkbook;

public class SxssfAutoFlush {
    public static void main(String[] args) {
        SXSSFWorkbook workbook = new SXSSFWorkbook(1000); // keep 1000 rows in memory, exceeding rows will be flushed to disk
        String fileName = "sxssf_autoflush_ver";
        PoiTester tester = new PoiTester(workbook, fileName);

        tester.test();
    }
}
```

- 실행 결과 : `sxssf_autoflush_ver 경과 시간 : 2초`

### Histogram
- SXSSFSheet 객체와 그 안에 모든 객체가 점유하는 메모리를 합쳐도 1.6Mb 정도이다.
  - XSSF에 비해 약 50배, auto-flush를 사용하지 않을 때에 비해 약 10배의 메모리를 덜 점유한다.
- 또한, 아래쪽에 보면 SXSSFRow 즉, 행이 1000개만 있는 것을 볼 수 있다.
  - 지정한 row access window size(위 코드에서는 1000) 이상이 메모리에 적재되면 디스크로 flush하는 auto-flush 기능이 잘 작동하는 것을 알 수 있다.
![image](https://user-images.githubusercontent.com/64415489/126835149-ad4776e1-1b70-41ac-87c0-236238d7804a.png)


### Dominator Tree
- 메모리 낭비가 없다고 봐도 무방할 것 같다.
![image](https://user-images.githubusercontent.com/64415489/126835214-bf45207f-7866-4caa-a683-3523f767622e.png)


# 결론
---
- 추측 : XSSF는 XML 기반의 무언가를 처리함에 있어서 메모리 낭비가 심하다.
  - 이로 인해, 데이터 건수가 많으면 OOM이 발생하게 된다.
- poi를 활용해 엑셀을 만든다면 SXSSF를 auto-flush 기능을 활성화해서 사용하자.
