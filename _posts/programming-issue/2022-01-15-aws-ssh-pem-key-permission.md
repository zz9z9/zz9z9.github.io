---
title: Permissions 0644 for ~ are too open 그리고 Permission denied (publickey) 현상 해결하기
date: 2022-01-15 00:25:00 +0900
categories: [개발 일기]
tags: [AWS, SSH]
---

# 상황
---
회사에서 리눅스 서버를 다뤄야할 일이 많아서 익숙해질겸 연습용으로 막 다뤄볼 수 있는 AWS 서버 하나를 구해봐야지 생각했다. 예전에 만들어놓은 AWS EC2 인스턴스가 있어서
오랜만에 접속해보려고 했는데 `Permissions 0644 for keyname.pem are too open.`, `Permission denied (publickey)` 두 가지 에러를 맞닥들였다.

# 원인과 해결방법
---
## 1. Permissions 0644 for keyname.pem are too open.
> 문장 그대로 파일 권한이 너무 공개되어 있다는 의미.

```text
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Permissions 0644 for keyname.pem are too open.
It is required that your private key files are NOT accessible by others.
This private key will be ignored.
```

### Permissions 0644 ?
- Chmod 644 (chmod a+rwx,u-x,g-wx,o-wx)
  - (U)ser : 파일 소유자는 읽기/쓰기만 가능
  - (G)roup : 그룹은 읽기만 가능
  - (O)thers : 외부에서도 읽기만 가능

<figure align = "center">
  <img src = "https://user-images.githubusercontent.com/64415489/149607576-815cf6db-f6dd-4d79-9e42-6985fc65ecdc.png"/>
  <figcaption align="center">출처 : <a href="https://chmodcommand.com/" target="_blank"> https://chmodcommand.com/</a> </figcaption>
</figure>

### 해결 방법
- 파일 소유자만 해당 파일을 읽을 수 있도록 권한을 변경한다.
  - `chmod 400 keyname.pem`

## 2. Permission denied (publickey).
> 위 문제 해결 후, `ssh -i [key] [username@host]`로 접속 시도하니까 이러한 현상이 나타났다. <br>
> 대표적으로 세 가지 이유가 있다고 한다.
> 1. 잘못된 key 사용
> 2. 잘못된 username 사용
> 3. 잘못된 host로 접속 시도

### 해결 방법
- 해결이라고 하기도 민망하게 나의 경우는 다른 key를 사용하고 있었다... 알맞은 키를 사용하니 잘 접속됐다.

### ※ 참고 : 인스턴스별 username
> [AWS 공식 문서](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connection-prereqs.html#connection-prereqs-get-info-about-instance)에 보면 인스턴스별 username이 나와있다.

- Amazon Linux 2 or the Amazon Linux AMI : `ec2-user`
- CentOS AMI : `centos` or `ec2-user`
- Debian AMI : `admin`
- Fedora AMI : `fedora` or `ec2-user`
- RHEL AMI : `ec2-user` or `root`
- SUSE AMI : `ec2-user` or `root`
- Ubuntu AMI : `ubuntu`
- Oracle AMI : `ec2-user`
- Bitnami AMI: `bitnami`

# 참고 자료
- [https://99robots.com/how-to-fix-permission-error-ssh-amazon-ec2-instance/](https://99robots.com/how-to-fix-permission-error-ssh-amazon-ec2-instance/)
- [https://bobbyhadz.com/blog/aws-ssh-permission-denied-publickey](https://bobbyhadz.com/blog/aws-ssh-permission-denied-publickey)
- [https://stackoverflow.com/questions/18551556/permission-denied-publickey-when-ssh-access-to-amazon-ec2-instance](https://stackoverflow.com/questions/18551556/permission-denied-publickey-when-ssh-access-to-amazon-ec2-instance)
- [https://bobbyhadz.com/blog/aws-ssh-permission-denied-publickey](https://bobbyhadz.com/blog/aws-ssh-permission-denied-publickey)
