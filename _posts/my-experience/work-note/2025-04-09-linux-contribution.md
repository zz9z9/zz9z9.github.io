---
title: 리눅스 컨트리뷰션하기
date: 2025-04-09 22:25:00 +0900
categories: [경험하기, 작업 노트]
tags: [Linux]
---

> PR에 달린 bot의 코멘트

Linux kernel development happens on mailing lists, rather than on GitHub - this GitHub repository is a read-only mirror that isn't used for accepting contributions. So that your change can become part of Linux, **please email it to us as a patch.**
**=> patch 이메일 ??**


- 어떻게 해야하는지
1. Format your contribution according to kernel requirements
   **=> kernel requirements 포맷 ??**
2. Decide who to send your contribution to
   **=> 수신자 리스트는 어디에 있지 ?**
3. Set up your system to send your contribution as an email
   **=> 어떤식으로 세팅 ?**
4. Send your contribution and wait for feedback



## patch ?
> A patch is a plain text document showing the change you want to make to the code, and documenting why it is a good idea.

- git format-patch 명령어로 patch 생성 가능

- patch에는 커밋 메세지가 필요
  - 어떤 변경이고 왜 필요한지

- https://kernel.org/doc/html/latest/process/submitting-patches.html -> 여기 자세히 나와있음


## 메일 수신자 ?
- 리눅스 커널은 여러개의 서브시스템으로 구성된다.
- 각 서브시스템마다 담당자와 메일링 리스트가 있다.
- 내가 변경한 부분의 코드가 어떤 서브시스템에 포함되는지를 알아야한다.
  - https://github.com/torvalds/linux/blob/master/scripts/get_maintainer.pl 이걸 통해 파악할 수 있다고한다.

```
Ingo Molnar <mingo@redhat.com> (maintainer:SCHEDULER)
Peter Zijlstra <peterz@infradead.org> (maintainer:SCHEDULER)
Juri Lelli <juri.lelli@redhat.com> (maintainer:SCHEDULER)
Vincent Guittot <vincent.guittot@linaro.org> (maintainer:SCHEDULER)
Dietmar Eggemann <dietmar.eggemann@arm.com> (reviewer:SCHEDULER)
Steven Rostedt <rostedt@goodmis.org> (reviewer:SCHEDULER)
Ben Segall <bsegall@google.com> (reviewer:SCHEDULER)
Mel Gorman <mgorman@suse.de> (reviewer:SCHEDULER)
Valentin Schneider <vschneid@redhat.com> (reviewer:SCHEDULER)
linux-kernel@vger.kernel.org (open list:SCHEDULER)

```

```
git send-email --to=bsegall@google.com 0001-sched-loadavg-fix-comment-for-avenrun-calculation.patch
```

## 메일 보내기
- git send-email 명령어를 사용해야함
  - 이를 통해 패치가 표준 방식으로 포맷되도록 보장할 수 있습니다.
  - git send-email을 사용하려면 SMTP 이메일 서버를 사용하도록 git을 구성해야 합니다.

### SMTP 이메일 서버를 사용하도록 git을 구성 ?
- ㅇㅇ

## 실제 사례 참고
- https://docs.google.com/document/d/1jFGEeAPm8vPfCcPFKm5DtKR83nMlMaSM60ToOik7CTg/edit?tab=t.0#heading=h.c1aiq1s5fcjz
  => 완전상세함
- https://soonoo.me/docs/posts/2019/10/27/Linux-contributor-wannabe.html
- https://kldp.org/node/164720
- https://opensource.com/article/18/8/first-linux-kernel-patch
- https://devlog.jsyoo5b.net/ko/posts/linux-kernel/my-first-commit/
