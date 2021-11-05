---
title: 자바 템플릿 엔진
date: 2021-11-03 23:00:00 +0900
categories: [General Topic]
tags: [Thymeleaf, FreeMarker]
---

# 들어가기 전
---
이직하게 될 팀의 기술 스택 중 하나가 `FreeMarker, Jsp`라고 한다. `FreeMarker`는 자바 템플릿 엔진이라고 하는데,
사실 뭔지 잘 몰라서 '템플릿 엔진'은 무엇인지부터 시작해서 자바 템플릿 엔진인 FreeMarker, Thymeleaf 등에 대해 살펴보고자 한다.


The Spring web framework is built around the MVC (Model-View-Controller) pattern, which makes it easier to separate concerns in an application. This allows for the possibility to use different view technologies, from the well established JSP technology to a variety of template engines.

In this article, we're going to take a look at the main template engines that can be used with Spring, their configuration, and examples of use.

2. Spring View Technologies
Given that concerns in a Spring MVC application are cleanly separated switching from one view technology to another is primarily a matter of configuration.

To render each view type, we need to define a ViewResolver bean corresponding to each technology. This means that we can then return the view names from @Controller mapping methods in the same way we usually return JSP files.

In the following sections, we're going to go over more traditional technologies like Java Server Pages, as well as the main template engines that can be used with Spring: Thymeleaf, Groovy, FreeMarker, Jade.

# 템플릿 엔진이란 ?
---



# Thymeleaf
---

# FreeMarker
---
Apache FreeMarker™ is a template engine: a Java library to generate text output (HTML web pages, e-mails, configuration files, source code, etc.) based on templates and changing data. Templates are written in the FreeMarker Template Language (FTL), which is a simple, specialized language (not a full-blown programming language like PHP). Usually, a general-purpose programming language (like Java) is used to prepare the data (issue database queries, do business calculations). Then, Apache FreeMarker displays that prepared data using templates. In the template you are focusing on how to present the data, and outside the template you are focusing on what data to present.

![image](https://user-images.githubusercontent.com/64415489/140529292-f3dc6b00-be2e-4349-a6d3-dd24f0bab139.png)

This approach is often referred to as the MVC (Model View Controller) pattern, and is particularly popular for dynamic web pages. It helps in separating web page designers (HTML authors) from developers (Java programmers usually). Designers won't face complicated logic in templates, and can change the appearance of a page without programmers having to change or recompile code.

While FreeMarker was originally created for generating HTML pages in MVC web application frameworks, it isn't bound to servlets or HTML or anything web-related. It's used in non-web application environments as well.

Features
A few highlights of FreeMarker:

Powerful template language: Conditional blocks, iterations, assignments, string and arithmetic operations and formatting, macros and functions, including other templates, escaping by default (optional), and many more

Multipurpose and lightweight: Zero dependencies, any output format, can load templates from any place (pluggable), many configuration options

Internationalization/localization-aware: Locale sensitive number and date/time formatting, localized template variations.

XML processing capabilities: Drop XML DOM-s into the data-model and traverse them, or even process them declaratively

Versatile data-model: Java objects are exposed to the template as a tree of variables through pluggable adapters, which decides how the template sees them.


https://www.baeldung.com/spring-template-engines

https://freemarker.apache.org/


