# JBCS 리눅스 설치 시뮬레이션 가이드 (Docker 기반)

이 문서는 macOS에서 Docker를 사용하여 실제 운영 환경(RHEL/Rocky Linux)과 동일한 구조로 JBCS를 설치하고 설정하는 연습을 하기 위한 시뮬레이션 가이드입니다.

---

## 1. 시뮬레이션 환경 준비

### 1.1 Dockerfile 작성
운영 환경과 유사한 패키지 환경을 구성하기 위해 `rockylinux:9` 이미지를 베이스로 사용합니다.

```dockerfile
# Dockerfile
FROM rockylinux:9

# 필수 유틸리티 및 의존성 설치
RUN dnf update -y && \
    dnf install -y vim wget curl net-tools pcre-devel openssl-devel tar unzip procps-ng && \
    dnf clean all

# JBCS 설치 경로 생성
RUN mkdir -p /opt/jbcs /data/backup/binaries

WORKDIR /opt/jbcs
```

### 1.2 컨테이너 실행
JBCS 설치 파일(ZIP)이 있는 로컬 디렉토리를 컨테이너와 연결하여 실행합니다.

```bash
# 이미지 빌드
docker build -t jbcs-sim .

# 컨테이너 실행 (로컬 binaries 폴더를 마운트)
docker run -it --name jbcs-lab \
  -v $HOME/Downloads:/data/backup/binaries \
  -p 80:80 -p 443:443 \
  jbcs-sim /bin/bash
```

---

## 2. JBCS 설치 (Section 4.1 재현)

컨테이너 내부 bash 쉘에서 진행합니다.

```bash
# 1. 압축 해제 및 심볼릭 링크 생성
cd /data/backup/binaries
# 실제 파일명에 맞게 조정 (예: jbcs-httpd24-httpd-2.4.57-*.zip)
unzip jbcs-httpd24-httpd-*.zip -d /opt/
ln -s /opt/jbcs-httpd24-2.4 /opt/jbcs

# 2. 필요 디렉토리 생성
mkdir -p /opt/jbcs/httpd/conf/certs
mkdir -p /opt/jbcs/httpd/conf.d
mkdir -p /opt/jbcs/httpd/logs
```

---

## 3. 인증서 및 메인 설정 (Section 4.2 & 4.3 반영)

### 3.1 self-signed 인증서 생성 (테스트용)
실제 운영에서는 `mkcert`를 쓰지만, 컨테이너 내부에서는 간단히 `openssl`로 생성합니다.

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/jbcs/httpd/conf/certs/key.pem \
  -out /opt/jbcs/httpd/conf/certs/cert.pem \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=Dev/CN=web.dev.local"
```

### 3.2 httpd.conf 편집
`/opt/jbcs/httpd/conf/httpd.conf` 파일을 열어 다음 지시어들이 포함되도록 수정합니다.

```apache
# 주요 모듈 로드 확인
LoadModule ssl_module modules/mod_ssl.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
LoadModule headers_module modules/mod_headers.so
LoadModule rewrite_module modules/mod_rewrite.so

# 서버 기본 설정
ServerName web.dev.local:443
ServerRoot "/opt/jbcs/httpd"

# 보안 설정
ServerTokens Prod
ServerSignature Off
TraceEnable Off

# vhost 설정 포함
IncludeOptional conf.d/*.conf
```

---

## 4. 가상 호스트 설정 (Section 4.4 ~ 4.6 반영)

`/opt/jbcs/httpd/conf.d/vhosts.conf` 파일을 생성합니다.

```apache
<VirtualHost *:443>
    ServerName web.dev.local
    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    # Reverse Proxy 설정 연습
    ProxyPreserveHost On
    ProxyPass         /app1  http://172.17.0.1:8080/app1
    ProxyPassReverse  /app1  http://172.17.0.1:8080/app1
    
    # 172.17.0.1은 보통 Docker 호스트(맥)의 IP입니다.
    # 맥에서 8080 포트에 WAS를 띄워두면 연동 테스트가 가능합니다.
</VirtualHost>
```

---

## 5. 서비스 기동 및 검증

### 5.1 설정 문법 체크
```bash
/opt/jbcs/httpd/sbin/apachectl configtest
```

### 5.2 서비스 시작
```bash
/opt/jbcs/httpd/sbin/apachectl start
```

### 5.3 내부 검증
```bash
# 프로세스 확인
ps -ef | grep httpd

# 443 포트 리슨 확인
netstat -tpln | grep 443

# 로컬 접속 테스트
curl -k -I https://localhost
```

---

## 7. 데브옵스 서버(Server C) 서비스 시뮬레이션

실제 환경의 Server C(Gitea, Nexus, Jenkins, Registry)를 Docker Compose를 통해 통합 시뮬레이션합니다.

### 7.1 dummy-devops 디렉토리 구성
가이드의 설정을 테스트하기 위해 각 서비스의 포트를 흉내 내는 설정을 만듭니다.

```bash
mkdir -p $HOME/jbcs_lab/devops
cd $HOME/jbcs_lab/devops
```

### 7.2 docker-compose.yml 작성
실제 이미지를 다 받기는 무거우므로, 포트 응답만 주는 가벼운 nginx 이미지를 사용하여 프록시 연동을 연습합니다. (실제 이미지를 사용해도 무방합니다.)

```yaml
# docker-compose.yml
services:
  # JBCS (Server A 역할)
  jbcs:
    build: .
    container_name: jbcs-server
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - $HOME/Downloads:/data/backup/binaries
    networks:
      - jbcs-net

  # DevOps Services (Server C 역할)
  gitea:
    image: nginx:alpine
    container_name: gitea-sim
    networks:
      - jbcs-net
    # 실제 Gitea 포트 3000 준수

  nexus:
    image: nginx:alpine
    container_name: nexus-sim
    networks:
      - jbcs-net
    # 실제 Nexus 포트 8081 준수

networks:
  jbcs-net:
```

### 7.3 JBCS Vhost 프록시 설정 (Section 4.6 반영)
JBCS 컨테이너 내부의 `/opt/jbcs/httpd/conf.d/vhosts.conf`에 컨테이너 이름을 이용한 프록시 설정을 추가합니다.

```apache
# Gitea Proxy (git.dev.local)
<VirtualHost *:443>
    ServerName git.dev.local
    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    ProxyPreserveHost On
    # 컨테이너 이름을 호스트 이름으로 사용
    ProxyPass         / http://gitea:3000/
    ProxyPassReverse  / http://gitea:3000/
</VirtualHost>

# Nexus Proxy (nexus.dev.local)
<VirtualHost *:443>
    ServerName nexus.dev.local
    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    ProxyPass         / http://nexus:8081/
    ProxyPassReverse  / http://nexus:8081/
</VirtualHost>
```

### 7.4 최종 검증
맥의 `/etc/hosts`에 가상 도메인을 등록한 후 브라우저나 curl로 접속을 확인합니다.

```bash
# 맥 호스트에서 실행
sudo sh -c 'echo "127.0.0.1 git.dev.local nexus.dev.local" >> /etc/hosts'

# 접속 테스트
curl -k https://git.dev.local
curl -k https://nexus.dev.local
```

---

## 8. 결론
이 다중 컨테이너 시뮬레이션을 통해 **Server A(JBCS) -> Server C(DevOps)** 간의 통합적인 프록시 흐름과 SSL 설정을 로컬 맥에서 완벽하게 연습하고 검증할 수 있습니다.
