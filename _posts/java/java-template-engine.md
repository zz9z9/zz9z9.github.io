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

-----------

When the web application page is displayed, it will contain the dynamic information fetched from the web server. There are two ways that dynamic information from the server can be included in the web page:

1. JavaScript running on the client (the web browser) can fetch the data from the server and insert the data into the page by modifying the in-memory representation (e.g., the DOM) of the page HTML.

2. The HTML for the web page can modified on the sever with the data inserted into the HTML for the page. This is often referred to as “server side rendering”.



# 템플릿 엔진이란 ?
---
> Template + data-model = output

A template engine is a specific kind of template processing module that exhibits all of the major features of a modern programming language. The term template engine evolved as a generalized description of programming languages whose primary or exclusive purpose was to process templates and data to output text. The use of this term is most notably applied to web development using a web template system, and it is also applied to other contexts as well.[4]

A template processor (also known as a template engine or template parser) is software designed to combine templates with a data model to produce result documents.[1][2][3] The language that the templates are written in is known as a template language or templating language. For purposes of this article, a result document is any kind of formatted output, including documents, web pages, or source code (in source code generation), either in whole or in fragments. A template engine is ordinarily included as a part of a web template system or application framework, and may be used also as a preprocessor or filter.


![image](https://user-images.githubusercontent.com/64415489/140649020-b35c9709-8e32-4631-b595-7a836fbbcb33.png)
https://en.wikipedia.org/wiki/Template_processor


Template engines typically include features common to most high-level programming languages, with an emphasis on features for processing plain text.

Such features include:

variables and functions
text replacement
file inclusion (or transclusion)
conditional evaluation and loops


## Benefits of using template engines
encourages organization of source code into operationally-distinct layers (see e.g., MVC)
enhances productivity by reducing unnecessary reproduction of effort
enhances teamwork by allowing separation of work based on skill-set (e.g., artistic vs. technical)


When the web application page is displayed, it will contain the dynamic information fetched from the web server. There are two ways that dynamic information from the server can be included in the web page:

JavaScript running on the client (the web browser) can fetch the data from the server and insert the data into the page by modifying the in-memory representation (e.g., the DOM) of the page HTML.
The HTML for the web page can modified on the sever with the data inserted into the HTML for the page. This is often referred to as “server side rendering”.
This article discusses three template engines that can be used for server side rendering for a Java application that leverages the Spring framework.

# Java Template Engine
---
One of the first template engines was PHP, which dates to the early days of the Web.

In 1999 Sun Microsystems released Java Server Pages (JSP), which is a template engine for Java web applications. In 2006 the Java Server Pages Tag Library (JSTL) was released. The JSTL makes JSP easier to use and the resulting web pages are easier to understand.

In addition to JSP/JSTL, there have been a number of template engines released for the Java software ecosystem. These include Apache Velocity, FreeMarker,Thymeleaf and Pippo (which seems to have evolved from an earlier template engine named Pebble). Groovy Server Pages (GSP) are used for Grails/Groovy applications.

A web application may consist of a large number of web pages. For example, the nderground social network, built by Topstone Software, has over 35 web pages. Designing and developing these web pages represents a significant portion of the effort that went into building the web application. Choosing the template engine for web page implementation is a important investment in the software architecture.

A core requirement in evaluating a Java template engine was whether it is supported by the Spring framework, which Topstone Software uses to develop web applications. Three template engines, which are supported by Spring, have been evaluated.

1. Java Server Pages with the Java Server Pages Tag Library (JSP/JSTL)
2. Thymeleaf
3. FreeMarker

In addition to supporting Spring, the template library needs to support the ability to include (insert) HTML fragements into the main page. This feature allows common CSS and JavaScript includes in the page header and common page headings and footers to be included in the application pages.

The best way to evaluate a template engine (or any software development framework) is to use it in a real application. Each of the template engines was used in a version of the Cognito Demonstration application.

## JSP and JSTL
JSTL supports the <c:import … > tag which allows HTML fragements to be included in the page or page header.

The example below shows how conditional logic can be added for server side page generation. When a page is sent to the client, it will consists of static HTML, which has been dynamically generated on the server.

![image](https://user-images.githubusercontent.com/64415489/140753718-46509dfe-0ac9-46ad-aa75-e53a8f009743.png)
https://hackernoon.com/java-template-engines-ef84cb1025a4

## Thymeleaf
Thymeleaf is currently popular in the Spring community. Many articles on Spring use Thymeleaf in the example web pages. One of the best references on the Spring framework, Spring in Action, Fifth Edition, by Craig Walls, Manning Press, October 2018, also uses Thymeleaf.

Thymeleaf has a number of issues, some of which are stylistic.

Thymeleaf embeds the Thymeleaf markup in HTML tags, usually <div> or <span> tags. I don’t find this as clean and easy to read and write as JSP/JSTL or FreeMarker tags. An example showing Thymeleaf markup is shown below.

![image](https://user-images.githubusercontent.com/64415489/140754134-9d59b894-81eb-4edf-b7b3-e9ba33953384.png)

Thymeleaf supports th:replace and th:include tags which allow sections of HTML to be inserted into the page. The example below shows how the th:replace tag can be used to insert the CSS and JavaScript links into the page head. The th:replace tag is also used to add a page header so that pages have common title headings.

![image](https://user-images.githubusercontent.com/64415489/140754244-447fcbdd-cf2a-4bf6-bdaf-1000eb5e2245.png)

Thymeleaf has some issues that go beyond the stylistic.

When Thymeleaf encounters an error while processing Thymeleaf markup, it throws a Java exception. This exception does not contain any information (i.e., line and character number) about what caused the error. This can make finding and correcting a Thymeleaf markup error time consuming, slowing application development.

Another concern is that Thymeleaf could become an orphan open source project.

Although Thymeleaf is popular in the Spring community and Thymeleaf is currently supported by the Spring Tool Suite project builder, I noticed that Thymeleaf is not supported by Pivotal (the company that supports the Spring framework). Thymeleaf is supported by three GitHub committers and most of the GitHub commits are from two people. If these GitHub committers are not able or willing to support Thymeleaf, the project could become an orphan.

## FreeMarker
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

------
FreeMarker is supported by an Apache Software Foundation and has a huge user community, including page templates for several content management systems (see Who Uses FreeMarker). FreeMarker also has support for the Spring framework.

On a stylistic level, I prefer FreeMarker’s JSP/JSTL like tag structure. An example is shown below. Note that the expressions within the conditionals do not have to be quoted.

![image](https://user-images.githubusercontent.com/64415489/140754937-dbc4a3ed-4f66-4440-b97a-f8408d9853c4.png)

FreeMarker supports an include tag that can be used to include HTML sections in the page. An example is shown below.

![image](https://user-images.githubusercontent.com/64415489/140755004-a7154698-c86e-47a5-a4cb-bbea451494fc.png)

FreeMarker is not without its quirks. I spent hours of frustrating experimentation before I could get images to load on the FreeMarker pages (see the Java configuration class cognitodemo.freemarker.config.AppConfig in the FreeMarker GitHub project).

Free marker also has a syntax that can take getting used to. In the example below the FreeMarker page references the String variable login_error. However, this FreeMaker markup will result in a FreeMarker parsing error.

![image](https://user-images.githubusercontent.com/64415489/140755111-befd320e-dc78-4dbc-9820-502a66883a4b.png)

FreeMarker requires you to use the FreeMarker operators for comparison to null and for string length. The null comparision operator is “??” The String length() function is not allowed. Instead the built-in FreeMarker length operator must be used: login_error?length. The correct FreeMarker markup is shown below:

![image](https://user-images.githubusercontent.com/64415489/140755202-63d70872-75b6-4a5a-adfd-08daec24383e.png)




# Choosing a Template Engine
---


# 참고 자료
---

https://www.baeldung.com/spring-template-engines

https://freemarker.apache.org/

https://en.wikipedia.org/wiki/Template_processor

https://hackernoon.com/java-template-engines-ef84cb1025a4
