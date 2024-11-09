---
title: Java - 자바로 엑셀을 만들기 위한 POI 라이브러리 살펴보기
date: 2021-07-22 00:29:00 +0900
categories: [지식 더하기, 이론]
tags: [Java]
---

회사 프로젝트에서 조회한 화면에 대해 엑셀 파일로 다운받게 만들어주는 기능을 구현해야 했다. 방법을 찾다보니 POI 라이브러리라는게 있었고 이를 활용해서 구현할 수 있었다.
하지만, 다른 파트에서 해당 라이브러리를 사용하다 OOM(Out Of Memory)에러가 발생했고, 구현체를 살펴보니 XSSF의 usermodel을 사용하고 있었다.
해당 파트에서는 문제 해결을 위해 알아보던 중, SXSSF가 더 효율적이라는 것을 찾아냈고 이를 적용하여 OOM 문제를 해결했다.
([이 글](https://lhb0517.tistory.com/entry/OOM-%EB%A7%9E%EA%B3%A0-%EB%82%98%EC%84%9C-%EC%95%8C%EC%95%84%EB%B3%B8-apache-poi-xlsx) 에서도 비슷한 경험을 공유해주신다.)<br>
아직 우리 파트에선 OOM이 발생하진 않았지만, 현재 XSSF를 사용하고 있기 때문에 OOM이 발생할 잠재적 가능성을 갖고있는 것이다.
따라서, SXSSF를 적용하기에 앞서 어떤 원리로 이런 차이가 만들어지는건지 알고 싶었다.

# HSSF & XSSF
---
- HSSF는 Excel '97(-2007) 파일 형식(.xls)를 지원한다.
- XSSF는 Excel 2007 OOXML(.xlsx) 파일 형식을 지원한다.
- HSSF, XSSF는 다음과 같은 기능을 제공한다.
  - low level structures
  - 효율적인 읽기 전용 액세스를 위한 이벤트 모델(eventmodel) API
  - XLS 파일을 만들고, 읽고, 수정하기 위한 전체 사용자 모델(usermodel) API
- 권고사항
  - 스프레드시트 데이터만 읽는 경우, 파일 형식에 따라 org.apache.poi.hssf.eventusermodel 패키지 또는 org.apache.poi.xssf.eventusermodel 패키지의 eventmodel api를 사용
  - 스프레드시트 데이터를 수정, 생성하는 경우 usermodel API를 사용
- usermodel 시스템은 low level의 eventusermodel보다 memory footprint가 더 높지만 작업하기는 훨씬 간단하다.
- XSSF가 지원되는 Excel 2007(.xlsx) 파일은 XML 기반, HSSF가 지원되는 Excel '97 파일(.xls)은 바이너리 기반이다.
  - XML을 처리하는데 필요한 memory footprint가 더 높다.

### ***※ memory footprint : 프로그램이 실행하는 동안 사용하거나 참조하는 기본 메모리의 양***

# SXSSF
---
> Since 3.8-beta3, POI ***provides a low-memory footprint*** SXSSF API built on top of XSSF. <br>

- SXSSF는 매우 큰 스프레드시트를 생성하거나 힙 공간이 제한될 때 사용할 수 있는 XSSF의 API 호환 스트리밍 확장이다.
- SXSSF는 sliding window 내에 있는 행에 대한 액세스를 제한하여 low memory footprint를 가능하게 한다. <br> (window : 메모리 버퍼의 일정 영역)
  - 반면, XSSF는 문서의 모든 행에 대한 액세스를 제공한다.

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/126660736-7a3a3d0a-d972-4c89-b37c-2dde36b68db1.png"/>
  <figcaption align="center"> <b>Sliding Window Memory Buffer Architecture</b>  <br> (출처 : https://www.researchgate.net/figure/Sliding-Window-Memory-Buffer-Architecture_fig1_272854151)</figcaption>
</figure>

- 더 이상 window에 없는 이전 행은 디스크에 기록될 때 액세스할 수 없게 된다.
- auto-flush 모드에서는 access window의 크기를 지정하여 일정한 수의 행을 메모리에 보관할 수 있다.
  - 이 값에 도달했을 때 추가 행을 만들면, 가장 낮은 인덱스를 가진 행이 access window에서 제거되고 디스크에 기록된다.
```java
public static void main(String[] args) throws Throwable {
       SXSSFWorkbook wb = new SXSSFWorkbook(100); // keep 100 rows in memory, exceeding rows will be flushed to disk
       Sheet sh = wb.createSheet();
       for(int rownum = 0; rownum < 1000; rownum++){
           Row row = sh.createRow(rownum);
           for(int cellnum = 0; cellnum < 10; cellnum++){
               Cell cell = row.createCell(cellnum);
               String address = new CellReference(cell).formatAsString();
               cell.setCellValue(address);
           }
       }
       // Rows with rownum < 900 are flushed and not accessible
       for(int rownum = 0; rownum < 900; rownum++){
         Assert.assertNull(sh.getRow(rownum));
       }
       // ther last 100 rows are still in memory
       for(int rownum = 900; rownum < 1000; rownum++){
           Assert.assertNotNull(sh.getRow(rownum));
       }
       FileOutputStream out = new FileOutputStream("/temp/sxssf.xlsx");
       wb.write(out);
       out.close();
       // dispose of temporary files backing this workbook on disk
       wb.dispose();
   }
```
- window 크기를 동적으로 조정하고 필요에 따라 행을 flushRows(int keepRows)하는 명시적 호출로 주기적으로 잘라낼 수 있다.
```java
   public static void main(String[] args) throws Throwable {
       SXSSFWorkbook wb = new SXSSFWorkbook(-1); // turn off auto-flushing and accumulate all rows in memory
       Sheet sh = wb.createSheet();
       for(int rownum = 0; rownum < 1000; rownum++){
           Row row = sh.createRow(rownum);
           for(int cellnum = 0; cellnum < 10; cellnum++){
               Cell cell = row.createCell(cellnum);
               String address = new CellReference(cell).formatAsString();
               cell.setCellValue(address);
           }
          // manually control how rows are flushed to disk
          if(rownum % 100 == 0) {
               ((SXSSFSheet)sh).flushRows(100); // retain 100 last rows and flush all others
               // ((SXSSFSheet)sh).flushRows() is a shortcut for ((SXSSFSheet)sh).flushRows(0),
               // this method flushes all rows
          }
       }
       FileOutputStream out = new FileOutputStream("/temp/sxssf.xlsx");
       wb.write(out);
       out.close();
       // dispose of temporary files backing this workbook on disk
       wb.dispose();
  }
```

- 스트리밍 특성으로 인해 XSSF와 비교할 때 다음과 같은 제한이 있다.
  - 한 시점에는 제한된 수의 행만 액세스할 수 있습니다.
  - Sheet.clone()은 지원되지 않습니다.
  - Formula evaluation이 지원되지 않는다.

# Spreadsheet API Feature Summary
---
<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/126656972-e65a38bf-4ea7-45b2-9cd3-164e4e0586bc.png" width="110%"/>
  <figcaption align="center">출처 : https://poi.apache.org/components/spreadsheet/</figcaption>
</figure>

# 실제 메모리 사용량 비교해보기
---
- [XSSF vs SXSSF 클래스 메모리 사용량 비교해보기](https://zz9z9.github.io/posts/xssf-oom-analyze/)

# 더 공부할 부분
---
- sliding window memory 아키텍처

# 참고 자료
---
- [https://poi.apache.org/components/spreadsheet/how-to.html#sxssf](https://poi.apache.org/components/spreadsheet/how-to.html#sxssf)
