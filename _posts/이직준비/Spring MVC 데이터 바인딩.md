

```java
@PutMapping("{contactNum}")
public ResponseEntity<ApiResponse<ClientUpdateResponseDto>> updateClient(@PathVariable 	String contactNum, @RequestBody ClientUpdateRequestDto requestDto) {
    ClientUpdateResult updateResult = clientUpdateService.update(requestDto.toClient(contactNum));
    return ResponseEntity.ok(ApiResponse.success(new ClientUpdateResponseDto(updateResult)));
}

@Setter
public class ClientUpdateRequestDto {

    private String email;
    private String name;
    private String address;

    public Client toClient(String contactNum) {
        if (StringUtils.areAllEmpty(email, name, address)) {
            throw new IllegalArgumentException("수정할 정보를 입력해주세요.");
        }

        if (!DataFormatValidator.isValidCellPhone(contactNum)) {
            throw new IllegalArgumentException("올바른 휴대폰 번호 형식을 입력해주세요.");
        }

        return Client.builder()
                .contactNum(contactNum)
                .email(email)
                .name(name)
                .address(address)
                .build();
    }

}
```

## 왜 ClientUpdateRequestDto의 @Setter 유무에 따라 Controller에서 requestDto에 데이터가 null인지 아닌지가 결정될까 ?

- Spring에서 @RequestBody를 사용하면 JSON 데이터를 **Jackson 라이브러리**를 통해 Java 객체로 변환(Deserialization)합니다.
- 이 과정에서 객체의 **기본 생성자와 Setter 메서드를 이용하여 JSON 값을 Java 객체 필드에 매핑**합니다.

### Spring에서 @RequestBody를 처리할 때 객체를 생성하고 값이 들어가는 과정

```
1. RequestResponseBodyMethodProcessor → HTTP 요청 본문을 읽음
2. MappingJackson2HttpMessageConverter → ObjectMapper를 사용하여 JSON을 Java 객체로 변환
3. ObjectMapper 내부에서 BeanDeserializer 실행
4. StdValueInstantiator에서 기본 생성자 호출 (newInstance())
5. BeanDeserializer에서 Setter를 사용하여 값 세팅 (deserializeAndSet())
```

(1) org.springframework.web.servlet.mvc.method.annotation.RequestResponseBodyMethodProcessor#resolveArgument : @RequestBody를 처리하는 부분

```java
public Object resolveArgument(MethodParameter parameter, @Nullable ModelAndViewContainer mavContainer, NativeWebRequest webRequest, @Nullable WebDataBinderFactory binderFactory) throws Exception {
    parameter = parameter.nestedIfOptional();
    Object arg = this.readWithMessageConverters(webRequest, parameter, parameter.getNestedGenericParameterType());
    String name = Conventions.getVariableNameForParameter(parameter);
    if (binderFactory != null) {
        WebDataBinder binder = binderFactory.createBinder(webRequest, arg, name);
        if (arg != null) {
            this.validateIfApplicable(binder, parameter);
            if (binder.getBindingResult().hasErrors() && this.isBindExceptionRequired(binder, parameter)) {
                throw new MethodArgumentNotValidException(parameter, binder.getBindingResult());
            }
        }

        if (mavContainer != null) {
            mavContainer.addAttribute(BindingResult.MODEL_KEY_PREFIX + name, binder.getBindingResult());
        }
    }

    return this.adaptArgumentIfNecessary(arg, parameter);
}
```

(2) Jackson을 호출하는 MappingJackson2HttpMessageConverter

```java
@Override
protected Object readInternal(Class<?> clazz, HttpInputMessage inputMessage) throws IOException {
    JavaType javaType = getJavaType(clazz);
    return this.objectMapper.readValue(inputMessage.getBody(), javaType);
}
```

- objectMapper.readValue() → Jackson의 ObjectMapper가 호출됨
- 이 과정에서 객체의 기본 생성자가 실행되고, Setter를 통해 값이 할당됨

(3) Jackson의 ObjectMapper에서 Deserialization 처리

```java
public <T> T readValue(JsonParser p, Class<T> valueType) throws IOException {
    return _readMapAndClose(p, _typeFactory.constructType(valueType));
}
```

- readValue() 내부에서 BeanDeserializer가 실행됨 → 기본 생성자 호출 및 Setter 사용

(4) 기본 생성자 호출 → StdValueInstantiator
```java
@Override
public Object createUsingDefault(DeserializationContext ctxt) throws IOException {
    if (_defaultCtor == null) {
        return super.createUsingDefault(ctxt);
    }
    try {
        return _defaultCtor.newInstance();
    } catch (Exception e) {
        return ctxt.handleInstantiationProblem(_valueClass, null, e);
    }
}
```

- `_defaultCtor.newInstance();` → 기본 생성자를 호출하여 객체를 생성

(5) Setter를 통해 값 세팅 → BeanDeserializer
```java
protected Object _deserializeUsingDefault(JsonParser p, DeserializationContext ctxt) throws IOException {
    Object bean = _valueInstantiator.createUsingDefault(ctxt); // 기본 생성자 호출

    while (p.nextToken() != JsonToken.END_OBJECT) {
        String propName = p.getCurrentName();
        p.nextToken();
        SettableBeanProperty prop = _beanProperties.find(propName);
        if (prop != null) {
            prop.deserializeAndSet(p, ctxt, bean); // Setter 호출하여 값 설정
        } else {
            handleUnknownProperty(p, ctxt, bean, propName);
        }
    }
    return bean;
}
```

- prop.deserializeAndSet(p, ctxt, bean); → Setter를 찾아서 값 설정


- `com.fasterxml.jackson.databind.deser.BeanDeserializer#deserializeFromObject`
> 기본 생성자 만들고 setter로 값 세팅

```java
public Object deserializeFromObject(JsonParser p, DeserializationContext ctxt) throws IOException {
    
    ...
    
    else {
            bean = this._valueInstantiator.createUsingDefault(ctxt); // 기본 생성자 생성
            ...
            
            if (p.hasTokenId(5)) {
                String propName = p.currentName();

                do {
                    p.nextToken();
                    SettableBeanProperty prop = this._beanProperties.find(propName);
                    if (prop != null) {
                        try {
                            prop.deserializeAndSet(p, ctxt, bean); // setter로 값 세팅
                        } catch (Exception var7) {
                            Exception e = var7;
                            this.wrapAndThrow(e, bean, propName, ctxt);
                        }
                    } else {
                        this.handleUnknownVanilla(p, ctxt, bean, propName);
                    }
                } while((propName = p.nextFieldName()) != null);
            }

            return bean;
        }
    }
}
```


- `com.fasterxml.jackson.databind.deser.impl.MethodProperty#deserializeAndSet`
> prop.deserializeAndSet(p, ctxt, bean); → Setter를 찾아서 값 설정

```java
public void deserializeAndSet(JsonParser p, DeserializationContext ctxt, Object instance) throws IOException {
    Object value;
    if (p.hasToken(JsonToken.VALUE_NULL)) {
        if (this._skipNulls) {
            return;
        }

        value = this._nullProvider.getNullValue(ctxt);
    } else if (this._valueTypeDeserializer == null) {
        value = this._valueDeserializer.deserialize(p, ctxt);
        if (value == null) {
            if (this._skipNulls) {
                return;
            }

            value = this._nullProvider.getNullValue(ctxt);
        }
    } else {
        value = this._valueDeserializer.deserializeWithType(p, ctxt, this._valueTypeDeserializer);
    }

    try {
        this._setter.invoke(instance, value);
    } catch (Exception var6) {
        Exception e = var6;
        this._throwAsIOE(p, e, value);
    }

}
```


### setter 사용 안하려면 ?
- @JsonProperty 활용
```java
public class ClientUpdateRequestDto {
    @JsonProperty
    private String email;

    @JsonProperty
    private String name;

    @JsonProperty
    private String address;
}
```

- @JsonCreator 활용
```java
public class ClientUpdateRequestDto {

    private final String email;
    private final String name;
    private final String address;

    @JsonCreator
    public ClientUpdateRequestDto(
        @JsonProperty("email") String email,
        @JsonProperty("name") String name,
        @JsonProperty("address") String address
    ) {
        this.email = email;
        this.name = name;
        this.address = address;
    }
}
```