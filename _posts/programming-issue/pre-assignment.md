
삽질 list

- 파일 경로
- json 변환
https://hianna.tistory.com/630

- stream filter map 으로 객체 하나만 가져오기

- writer랑 dos 같이사용하는 경우에는 writer로 헤더 먼저 flush해야하는건가 ???

- 왜 ../../../etc/pwd 이런식으로 요청하면 ../../ 이부분은 다 사라지지 ??

```java
class Solution {
    public static void main(String[] args) throws IOException {
        String filePath = "../../files/record.txt";
        File file = new File(filePath);
        String path = file.getPath();
        System.out.println(path); // ../../files/record.txt
        System.out.println(file.getAbsoluteFile()); // /Users/jeayoon/dev/src/algorithm/../../files/record.txt
        System.out.println(file.getCanonicalPath()); // /Users/jeayoon/dev/files/record.txt

    }
}
```

- 소켓 서버 테스트하는 법 ??
왜 new HttpServer().start 하면 계속 돌지 ??
--> 계속 대기상태이기 때문에 같은 테스트에서 하면안된다 ??
```
