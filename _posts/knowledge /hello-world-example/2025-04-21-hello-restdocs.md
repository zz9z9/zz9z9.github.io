

```
plugins {
    id 'org.springframework.boot' version "3.4.4"
    id 'io.spring.dependency-management' version '1.1.4'
    id 'org.asciidoctor.jvm.convert' version '2.4.0'  // Apply the Asciidoctor plugin.
    id 'java'
}


group = 'com.zz9z9.blogcode.restdocs'
version = '1.0-SNAPSHOT'

repositories {
    mavenCentral()
}

ext {
    // Configure a snippetsDir property that defines the output location for generated snippets.
    snippetsDir = file('build/generated-snippets')
}

dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'

    implementation 'org.projectlombok:lombok:1.18.30'
    annotationProcessor 'org.projectlombok:lombok:1.18.30'

    testImplementation 'org.springframework.restdocs:spring-restdocs-mockmvc'
}

test {
    // Make Gradle aware that running the test task will write output to the snippetsDir
    outputs.dir snippetsDir
    useJUnitPlatform()
}

// Configure the asciidoctor task.
asciidoctor {
    inputs.dir snippetsDir  // Make Gradle aware that running the task will read input from the snippetsDir.
    attributes 'snippets': snippetsDir
    dependsOn test
}

bootJar {
    dependsOn asciidoctor
    from("${asciidoctor.outputDir}") {
        into 'static/docs'
    }
}
```

```java
@RestController
@RequestMapping("/api")
public class HelloController {

    @GetMapping("/hello")
    public Map<String, String> hello() {
        return Map.of("message", "Hello, Spring REST Docs!");
    }

}
```

```java
@AutoConfigureMockMvc
@AutoConfigureRestDocs(outputDir = "build/generated-snippets")
@SpringBootTest
public class HelloControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void helloRestDocs() throws Exception {
        mockMvc.perform(get("/api/hello"))
                .andExpect(status().isOk())
                .andDo(document("hello",
                        responseFields(
                                fieldWithPath("message").description("The hello message")
                        )
                ));
    }

}
```

## 참고 자료
- https://docs.spring.io/spring-restdocs/docs/current/reference/htmlsingle/
