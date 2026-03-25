# 🏗️ JBCS 기반 3-Tier 폐쇄망 통합 구축 매뉴얼 (v2.1)

> **변경 이력**
> - v1.1 → v2.0: Day-1 다운로드 항목 대폭 보강, docker-compose.yml 추가, 방화벽 규칙 추가, /etc/hosts 설정, Jenkins 오프라인 플러그인, Nexus 초기 설정, 백업 전략, HTTP→HTTPS 리다이렉트, JBCS 타임아웃/로그 설정, systemd 서비스 파일 등
> - v2.0 → v2.1: **WAS를 Tomcat에서 JBoss EAP 7.4(JDK11) / EAP 8.0(JDK17) 으로 전면 교체**, standalone.xml 설정, port-offset 이중 인스턴스, mod_proxy 연동, jboss-cli 관리, EAP 바이너리 Day-1 다운로드 추가

---

## 1. 서버 구성도 및 역할 (Topology)

| 구분 | 서버명 | IP (예시) | 주요 스택 | 역할 |
| :--- | :--- | :--- | :--- | :--- |
| **WEB** | Server A | 192.168.0.10 | **Apache JBCS 2.4**, mod_ssl, mod_proxy, mod_headers | SSL 종단, 리버스 프록시, HTTP→HTTPS 리다이렉트 |
| **WAS** | Server B | 192.168.0.11 | **JDK 11 & 17**, **JBoss EAP 7.4** (JDK11) / **JBoss EAP 8.0** (JDK17), eGovFrame | 앱 실행 (port-offset 분리 운영) |
| **DevOps** | Server C | 192.168.0.12 | **Gitea, Nexus, Jenkins, Registry**, Docker, PostgreSQL | 형상/빌드/이미지 관리 |
| **DB** | Server D | 192.168.0.13 | **PostgreSQL/MariaDB/Oracle** 등 | 애플리케이션 데이터 저장소 |

### 1.1 통신 흐름도

```
[사용자 브라우저]
    │ HTTPS (443)
    ▼
[Server A - JBCS]
    │ HTTP (8080/8180) 또는 AJP (8009/8109)
    ▼
[Server B - JBoss EAP WAS]
    ├── EAP 7.4 (JDK11) → :8080 (기본)
    └── EAP 8.0 (JDK17) → :8180 (port-offset=100)
    │ JDBC
    ▼
[DB Server] (별도 구성 시)

[Server A - JBCS]
    │ HTTPS Reverse Proxy
    ▼
[Server C - DevOps]
    ├── Gitea     :3000
    ├── Nexus     :8081
    ├── Jenkins   :8080
    └── Registry  :5000
```

### 1.2 포트 맵 (Server B — JBoss EAP)

| 서비스 | EAP 7.4 (offset=0) | EAP 8.0 (offset=100) | 용도 |
| :--- | :--- | :--- | :--- |
| HTTP | 8080 | 8180 | 애플리케이션 서비스 |
| HTTPS | 8443 | 8543 | (WAS 직접 SSL 사용 시) |
| Management HTTP | 9990 | 10090 | 관리 콘솔 |
| AJP | 8009 | 8109 | JBCS AJP 연동 시 |

---

## 2. Day-1: 인터넷 허용 시 필수 확보 자산 (★ 최우선)

> ⚠️ **내일 하루만 인터넷이 열립니다.** 아래 항목을 빠짐없이 다운로드한 뒤 `/data/backup/`에 정리합니다.

### 2.1 Docker 이미지 타르볼 (Server C)

```bash
# 이미지 Pull
docker pull gitea/gitea:1.22
docker pull sonatype/nexus3:3.72.0
docker pull jenkins/jenkins:lts-jdk17
docker pull registry:2
docker pull postgres:15-alpine

# 오프라인 설치용 저장 (단일 tar)
docker save -o /data/backup/devops_infra.tar \
  gitea/gitea:1.22 \
  sonatype/nexus3:3.72.0 \
  jenkins/jenkins:lts-jdk17 \
  registry:2 \
  postgres:15-alpine

# 개별 tar도 백업 (장애 시 부분 복원용)
docker save -o /data/backup/gitea.tar gitea/gitea:1.22
docker save -o /data/backup/nexus3.tar sonatype/nexus3:3.72.0
docker save -o /data/backup/jenkins.tar jenkins/jenkins:lts-jdk17
docker save -o /data/backup/registry.tar registry:2
docker save -o /data/backup/postgres.tar postgres:15-alpine
```

> **v1.1 대비 변경:** `latest` 태그 대신 **특정 버전 태그** 사용 → 폐쇄망에서 재현성 보장

### 2.2 인프라 바이너리 (Local Storage → `/data/backup/binaries/`)

| 항목 | 파일명 (예시) | 용도 |
| :--- | :--- | :--- |
| **JBCS** | `jbcs-httpd24-httpd-2.4.57-*.zip` | Web 서버 (Red Hat 포탈) |
| **JDK 11** | `OpenJDK11U-jdk_x64_linux_*.tar.gz` | EAP 7.4 런타임 (Adoptium) |
| **JDK 17** | `OpenJDK17U-jdk_x64_linux_*.tar.gz` | EAP 8.0 런타임 (Adoptium) |
| **JBoss EAP 7.4** | `jboss-eap-7.4.0.zip` | JDK 11용 WAS (Red Hat 포탈) |
| **JBoss EAP 8.0** | `jboss-eap-8.0.0.zip` | JDK 17용 WAS (Red Hat 포탈) |
| **EAP 패치** | `jboss-eap-7.4.*.CP.zip`, `jboss-eap-8.0.*.zip` | 최신 누적 패치 (Red Hat 포탈) |
| **Maven** | `apache-maven-3.9.9-bin.tar.gz` | 빌드 도구 |
| **Git** | `git-2.x.x-*.rpm` 또는 소스 | 형상관리 클라이언트 |
| **mkcert** | `mkcert-v1.4.4-linux-amd64` | 자체 CA 인증서 생성 |
| **Docker Compose** | `docker-compose-linux-x86_64` | 컨테이너 오케스트레이션 |
| **Node.js (LTS)** | `node-v20.*-linux-x64.tar.xz` | 프론트엔드 빌드 시 필요 |
| **JDBC 드라이버** | `postgresql-*.jar`, `ojdbc8.jar` 등 | WAS-DB 연동용 (프로젝트에 맞게 준비) |

> ⚠️ **JBoss EAP는 Red Hat 구독 계정이 필요합니다.** Red Hat Customer Portal > Downloads > JBoss Enterprise Application Platform 에서 EAP 7.4 및 8.0 ZIP 파일과 최신 누적 패치를 반드시 확보하세요.

```bash
# Docker Compose v2 바이너리 다운로드
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
  -o /data/backup/binaries/docker-compose
chmod +x /data/backup/binaries/docker-compose
```

### 2.3 Jenkins 오프라인 플러그인

```bash
mkdir -p /data/backup/jenkins-plugins && cd /data/backup/jenkins-plugins

# 필수 플러그인 HPI 다운로드
PLUGINS=(
  "git" "git-client" "pipeline-model-definition" "workflow-aggregator"
  "pipeline-stage-view" "blueocean" "docker-workflow" "credentials"
  "ssh-credentials" "maven-plugin" "nexus-artifact-uploader"
  "locale" "antisamy-markup-formatter"
)

for p in "${PLUGINS[@]}"; do
  wget "https://updates.jenkins.io/latest/${p}.hpi" -O "${p}.hpi"
done
```

### 2.4 Maven 오프라인 리포지토리

```bash
# 프로젝트 소스에서 의존성 전체 다운로드
cd /path/to/project
mvn dependency:go-offline -Dmaven.repo.local=/data/backup/maven-repo

# eGovFrame 의존성도 포함
mvn dependency:resolve -Dmaven.repo.local=/data/backup/maven-repo
```

### 2.5 OS 패키지 오프라인 캐시

```bash
# Server A/B/C 공통 필요 패키지를 RPM으로 확보
sudo dnf install --downloadonly --downloaddir=/data/backup/rpms/ \
  vim wget curl net-tools pcre-devel openssl-devel fail2ban \
  firewalld policycoreutils-python-utils tar unzip bind-utils
```

### 2.6 다운로드 체크리스트

```bash
# 최종 확인 스크립트
echo "=== Day-1 다운로드 검증 ==="
ls -lh /data/backup/devops_infra.tar
echo "--- 바이너리 ---"
ls -lh /data/backup/binaries/
echo "--- JBoss EAP ---"
ls -lh /data/backup/binaries/jboss-eap-*.zip
echo "--- Jenkins 플러그인 ---"
ls -lh /data/backup/jenkins-plugins/*.hpi | wc -l
echo "--- Maven 리포 ---"
du -sh /data/backup/maven-repo/
echo "--- RPM 캐시 ---"
ls -lh /data/backup/rpms/*.rpm | wc -l
echo "=== 검증 완료 ==="
```

---

## 3. 서버 공통 환경 설정

### 3.1 OS 최적화 (3대 공통)

```bash
# 시스템 업데이트 및 필수 유틸리티
sudo dnf update -y
sudo dnf install -y vim wget curl net-tools pcre-devel openssl-devel \
  fail2ban firewalld policycoreutils-python-utils tar unzip bind-utils

# SELinux Permissive
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# 타임존 설정
sudo timedatectl set-timezone Asia/Seoul

# NTP 동기화 (폐쇄망에서도 서버 간 시간 동기 필수)
sudo dnf install -y chrony
sudo systemctl enable --now chronyd
```

### 3.2 리소스 제한 (ulimit) 설정 (3대 공통)

> 대규모 트래픽 처리를 위해 파일 디스크립터 및 프로세스 제한을 늘려줍니다.

```bash
cat >> /etc/security/limits.conf << 'EOF'
# === 3-Tier Infra Limits ===
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

# 적용을 위해 세션 재로그인 필요
```

### 3.3 /etc/hosts 설정 (3대 공통)

> 폐쇄망에는 DNS 서버가 없으므로 반드시 hosts 파일로 이름 해석

```bash
cat >> /etc/hosts << 'EOF'
# === 3-Tier Infra ===
192.168.0.10  web.dev.local
192.168.0.11  was.dev.local
192.168.0.12  devops.dev.local

# === DevOps Services (Server A가 프록시) ===
192.168.0.10  git.dev.local
192.168.0.10  nexus.dev.local
192.168.0.10  jenkins.dev.local
192.168.0.10  registry.dev.local
EOF
```

### 3.4 방화벽 설정

#### Server A (WEB)
```bash
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=http    # 리다이렉트용
sudo firewall-cmd --permanent --add-port=22022/tcp  # SSH 변경 시
sudo firewall-cmd --reload
```

#### Server B (WAS — JBoss EAP)
```bash
sudo systemctl enable --now firewalld
# Server A에서만 EAP 포트 접근 허용
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="8080" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="8180" protocol="tcp" accept'
# AJP 사용 시 (선택)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="8009" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="8109" protocol="tcp" accept'
# 관리 콘솔 (로컬 + DevOps 서버)
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.12" port port="9990" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.12" port port="10090" protocol="tcp" accept'
# SSH
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.12" port port="22022" protocol="tcp" accept'
sudo firewall-cmd --reload
```

#### Server C (DevOps)
```bash
sudo systemctl enable --now firewalld
# Server A에서만 서비스 포트 접근 허용
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="3000" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="5000" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="8080" protocol="tcp" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.0.10" port port="8081" protocol="tcp" accept'
sudo firewall-cmd --reload
```

---

## 4. Web(JBCS) - SSL 및 프록시 설정 (Server A)

### 4.1 JBCS 설치

```bash
cd /data/backup/binaries
unzip jbcs-httpd24-httpd-2.4.57-*.zip -d /opt/
ln -s /opt/jbcs-httpd24-2.4 /opt/jbcs

# 필요 디렉토리 생성
mkdir -p /opt/jbcs/httpd/conf/certs
mkdir -p /opt/jbcs/httpd/logs
```

### 4.2 인증서 생성 및 등록

```bash
cd /opt/jbcs/httpd/conf/certs

# mkcert 초기화 (rootCA 생성)
CAROOT=/opt/jbcs/httpd/conf/certs ./mkcert -install

# 와일드카드 인증서 생성 (모든 서비스 도메인 포함)
./mkcert -cert-file cert.pem -key-file key.pem \
  "*.dev.local" "dev.local" \
  "git.dev.local" "nexus.dev.local" "jenkins.dev.local" "registry.dev.local" \
  "web.dev.local" "was.dev.local" \
  127.0.0.1 192.168.0.10 192.168.0.11 192.168.0.12

# OS 신뢰 CA 등록 (3대 서버 모두 동일하게 적용)
sudo cp rootCA.pem /etc/pki/ca-trust/source/anchors/dev-local-ca.pem
sudo update-ca-trust

# Docker도 인증서 신뢰하도록 설정 (Server B, C 필요)
sudo mkdir -p /etc/docker/certs.d/registry.dev.local
sudo cp rootCA.pem /etc/docker/certs.d/registry.dev.local/ca.crt
sudo systemctl restart docker
```

### 4.3 JBCS 메인 설정 (`/opt/jbcs/httpd/conf/httpd.conf` 수정)

```apache
# 모듈 로드 확인
LoadModule ssl_module modules/mod_ssl.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
LoadModule proxy_ajp_module modules/mod_proxy_ajp.so
LoadModule headers_module modules/mod_headers.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule log_config_module modules/mod_log_config.so

# 서버 기본 설정
ServerName web.dev.local:443
ServerAdmin admin@dev.local

# 로그 설정
ErrorLog "/opt/jbcs/httpd/logs/error_log"
CustomLog "/opt/jbcs/httpd/logs/access_log" combined

# 보안 헤더
ServerTokens Prod
ServerSignature Off
TraceEnable Off

# 타임아웃 설정
Timeout 300
ProxyTimeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# vhost 설정 포함
IncludeOptional conf.d/*.conf
```

### 4.4 HTTP → HTTPS 리다이렉트

```apache
# /opt/jbcs/httpd/conf.d/redirect.conf
<VirtualHost *:80>
    ServerName web.dev.local
    ServerAlias *.dev.local

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}$1 [R=301,L]
</VirtualHost>
```

### 4.5 SSL 공통 설정 (`/opt/jbcs/httpd/conf.d/ssl-global.conf`)

```apache
# TLS 프로토콜 및 암호화 스위트
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSLCipherSuite HIGH:!aNULL:!MD5:!3DES:!RC4
SSLHonorCipherOrder on

# HSTS 헤더
Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"

# 보안 헤더 추가
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-XSS-Protection "1; mode=block"
```

### 4.6 JBCS vhost 설정 (`/opt/jbcs/httpd/conf.d/vhosts.conf`)

```apache
# ============================================================
# WAS 프록시 (JBoss EAP)
# ============================================================
<VirtualHost *:443>
    ServerName web.dev.local

    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    ProxyPreserveHost On

    # ── EAP 7.4 (JDK11) — 포트 8080 ──
    ProxyPass         /app1  http://192.168.0.11:8080/app1
    ProxyPassReverse  /app1  http://192.168.0.11:8080/app1

    # ── EAP 8.0 (JDK17) — 포트 8180 (offset=100) ──
    ProxyPass         /app2  http://192.168.0.11:8180/app2
    ProxyPassReverse  /app2  http://192.168.0.11:8180/app2

    # 헬스체크용
    ProxyPass         /health1 http://192.168.0.11:8080/health
    ProxyPass         /health2 http://192.168.0.11:8180/health

    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Real-IP "%{REMOTE_ADDR}s"

    # WAS 에러 시 사용자 친화적 페이지
    ProxyErrorOverride On
    ErrorDocument 503 /error/503.html
</VirtualHost>

# ============================================================
# (선택) AJP 프로토콜 사용 시 — HTTP 대신 AJP 연동
# ============================================================
# <VirtualHost *:443>
#     ServerName web.dev.local
#     SSLEngine on
#     SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
#     SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"
#
#     ProxyPreserveHost On
#     # EAP 7.4 AJP
#     ProxyPass         /app1  ajp://192.168.0.11:8009/app1  secret=your_ajp_secret
#     ProxyPassReverse  /app1  ajp://192.168.0.11:8009/app1
#     # EAP 8.0 AJP (offset)
#     ProxyPass         /app2  ajp://192.168.0.11:8109/app2  secret=your_ajp_secret
#     ProxyPassReverse  /app2  ajp://192.168.0.11:8109/app2
# </VirtualHost>

# ============================================================
# Gitea
# ============================================================
<VirtualHost *:443>
    ServerName git.dev.local

    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    ProxyPreserveHost On
    ProxyPass         / http://192.168.0.12:3000/
    ProxyPassReverse  / http://192.168.0.12:3000/

    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>

# ============================================================
# Nexus Repository
# ============================================================
<VirtualHost *:443>
    ServerName nexus.dev.local

    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    # Nexus 업로드 용량 제한 해제
    LimitRequestBody 0

    ProxyPreserveHost On
    ProxyPass         / http://192.168.0.12:8081/
    ProxyPassReverse  / http://192.168.0.12:8081/

    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>

# ============================================================
# Jenkins
# ============================================================
<VirtualHost *:443>
    ServerName jenkins.dev.local

    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    ProxyPreserveHost On
    ProxyPass         / http://192.168.0.12:8080/ nocanon
    ProxyPassReverse  / http://192.168.0.12:8080/
    AllowEncodedSlashes NoDecode

    RequestHeader set X-Forwarded-Proto "https"

    # Jenkins 웹소켓 지원
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*)  ws://192.168.0.12:8080/$1 [P,L]
</VirtualHost>

# ============================================================
# Docker Registry
# ============================================================
<VirtualHost *:443>
    ServerName registry.dev.local

    SSLEngine on
    SSLCertificateFile    "/opt/jbcs/httpd/conf/certs/cert.pem"
    SSLCertificateKeyFile "/opt/jbcs/httpd/conf/certs/key.pem"

    # 이미지 업로드 용량 무제한
    LimitRequestBody 0

    ProxyPreserveHost On
    ProxyPass         / http://192.168.0.12:5000/
    ProxyPassReverse  / http://192.168.0.12:5000/

    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>
```

### 4.7 JBCS systemd 서비스 등록

```bash
sudo cat > /etc/systemd/system/jbcs.service << 'EOF'
[Unit]
Description=JBCS Apache HTTP Server
After=network.target

[Service]
Type=forking
ExecStart=/opt/jbcs/httpd/sbin/apachectl start
ExecStop=/opt/jbcs/httpd/sbin/apachectl graceful-stop
ExecReload=/opt/jbcs/httpd/sbin/apachectl graceful
PIDFile=/opt/jbcs/httpd/logs/httpd.pid
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now jbcs
```

### 4.8 JBCS 로그 로테이션 (logrotate) 설정

> JBCS의 access_log와 error_log 무한 증가를 방지하기 위해 logrotate를 설정합니다.

```bash
sudo cat > /etc/logrotate.d/jbcs << 'EOF'
/opt/jbcs/httpd/logs/*_log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 root root
    sharedscripts
    postrotate
        /opt/jbcs/httpd/sbin/apachectl graceful > /dev/null 2>/dev/null || true
    endscript
}
EOF
```

### 4.9 JBCS 설정 검증

```bash
# 설정 문법 검사
/opt/jbcs/httpd/sbin/apachectl configtest

# 로드된 모듈 확인
/opt/jbcs/httpd/sbin/apachectl -M | grep -E "ssl|proxy|rewrite|headers"
```

---

## 5. WAS(JBoss EAP) 설정 (Server B)

### 5.1 JDK 멀티 버전 설치

```bash
# JDK 설치
sudo mkdir -p /opt/java
sudo tar xzf /data/backup/binaries/OpenJDK11U-*.tar.gz -C /opt/java/
sudo tar xzf /data/backup/binaries/OpenJDK17U-*.tar.gz -C /opt/java/

# 심볼릭 링크
sudo ln -s /opt/java/jdk-11.0.* /opt/java/jdk-11
sudo ln -s /opt/java/jdk-17.0.* /opt/java/jdk-17

# alternatives 등록
sudo alternatives --install /usr/bin/java java /opt/java/jdk-11/bin/java 1100
sudo alternatives --install /usr/bin/java java /opt/java/jdk-17/bin/java 1700

# 확인
/opt/java/jdk-11/bin/java -version
/opt/java/jdk-17/bin/java -version
```

### 5.2 JBoss EAP 이중 설치 (port-offset 분리)

```bash
# ── EAP 7.4 (JDK 11) — 기본 포트 ──
sudo mkdir -p /opt/jboss
cd /data/backup/binaries
sudo unzip jboss-eap-7.4.0.zip -d /opt/jboss/
sudo ln -s /opt/jboss/jboss-eap-7.4 /opt/jboss/eap74

# ── EAP 8.0 (JDK 17) — port-offset=100 ──
sudo unzip jboss-eap-8.0.0.zip -d /opt/jboss/
sudo ln -s /opt/jboss/jboss-eap-8.0 /opt/jboss/eap80

# EAP 누적 패치 적용 (있을 경우)
# /opt/jboss/eap74/bin/jboss-cli.sh --command="patch apply /data/backup/binaries/jboss-eap-7.4.x.CP.zip"
# /opt/jboss/eap80/bin/jboss-cli.sh --command="patch apply /data/backup/binaries/jboss-eap-8.0.x.zip"

# jboss 서비스 사용자 생성
sudo useradd -r -d /opt/jboss -s /sbin/nologin jboss
sudo chown -R jboss:jboss /opt/jboss/
```

### 5.3 EAP 7.4 관리자 계정 생성

```bash
sudo -u jboss /opt/jboss/eap74/bin/add-user.sh \
  -u admin -p 'YourAdminPassword!' -g ManagementRealm
```

### 5.4 EAP 8.0 관리자 계정 생성

```bash
sudo -u jboss /opt/jboss/eap80/bin/add-user.sh \
  -u admin -p 'YourAdminPassword!' -g ManagementRealm
```

### 5.5 EAP 7.4 standalone.xml 주요 설정 (`/opt/jboss/eap74/standalone/configuration/standalone.xml`)

> jboss-cli.sh로 설정하는 것을 권장하지만, 오프라인에서 직접 XML 편집도 가능

```bash
# ── jboss-cli 배치 스크립트로 설정 (EAP 기동 후 실행) ──
cat > /tmp/eap74-config.cli << 'CLI'
# 바인드 주소 변경 (외부 접근 허용)
/interface=public:write-attribute(name=inet-address, value="${jboss.bind.address:0.0.0.0}")
/interface=management:write-attribute(name=inet-address, value="${jboss.bind.address.management:0.0.0.0}")

# AJP 커넥터 활성화 (JBCS 연동 시)
/subsystem=undertow/server=default-server/ajp-listener=ajp:add(socket-binding=ajp, scheme=http)

# AJP secret 설정 (보안)
/socket-binding-group=standard-sockets/socket-binding=ajp:write-attribute(name=port, value=8009)

# 프록시 헤더 처리 (JBCS 뒤에서 클라이언트 IP 확인)
/subsystem=undertow/server=default-server/http-listener=default:write-attribute(name=proxy-address-forwarding, value=true)

# Access Log 활성화
/subsystem=undertow/server=default-server/host=default-host/setting=access-log:add( \
  pattern="%h %l %u %t \"%r\" %s %b %D", \
  directory="${jboss.home.dir}/standalone/log", \
  prefix="access_log", suffix=".txt")

# 배포 스캐너 비활성화 (수동 배포)
/subsystem=deployment-scanner/scanner=default:write-attribute(name=scan-enabled, value=false)

# 타임존 설정
/system-property=user.timezone:add(value="Asia/Seoul")

# 인코딩 설정
/system-property=file.encoding:add(value="UTF-8")

reload
CLI

# 기동 후 CLI 실행
/opt/jboss/eap74/bin/jboss-cli.sh --connect --file=/tmp/eap74-config.cli
```

### 5.6 EAP 8.0 standalone.xml 주요 설정

```bash
cat > /tmp/eap80-config.cli << 'CLI'
# 바인드 주소 변경
/interface=public:write-attribute(name=inet-address, value="${jboss.bind.address:0.0.0.0}")
/interface=management:write-attribute(name=inet-address, value="${jboss.bind.address.management:0.0.0.0}")

# AJP 커넥터 활성화
/subsystem=undertow/server=default-server/ajp-listener=ajp:add(socket-binding=ajp, scheme=http)

# 프록시 헤더 처리
/subsystem=undertow/server=default-server/http-listener=default:write-attribute(name=proxy-address-forwarding, value=true)

# Access Log 활성화
/subsystem=undertow/server=default-server/host=default-host/setting=access-log:add( \
  pattern="%h %l %u %t \"%r\" %s %b %D", \
  directory="${jboss.home.dir}/standalone/log", \
  prefix="access_log", suffix=".txt")

# 배포 스캐너 비활성화
/subsystem=deployment-scanner/scanner=default:write-attribute(name=scan-enabled, value=false)

# 타임존 / 인코딩
/system-property=user.timezone:add(value="Asia/Seoul")
/system-property=file.encoding:add(value="UTF-8")

reload
CLI

# EAP 8.0은 port-offset 적용하여 기동 후 CLI 실행 (관리 포트: 10090)
/opt/jboss/eap80/bin/jboss-cli.sh --connect --controller=localhost:10090 --file=/tmp/eap80-config.cli
```

### 5.7 JVM 튜닝 — standalone.conf

#### EAP 7.4 (`/opt/jboss/eap74/bin/standalone.conf`)

```bash
cat >> /opt/jboss/eap74/bin/standalone.conf << 'EOF'

# === Custom JVM Settings (EAP 7.4 / JDK 11) ===
JAVA_HOME="/opt/java/jdk-11"

JAVA_OPTS="$JAVA_OPTS -server"
JAVA_OPTS="$JAVA_OPTS -Xms1024m -Xmx2048m"
JAVA_OPTS="$JAVA_OPTS -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m"
JAVA_OPTS="$JAVA_OPTS -XX:+UseG1GC"
JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"
JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=UTF-8"
JAVA_OPTS="$JAVA_OPTS -Duser.timezone=Asia/Seoul"
JAVA_OPTS="$JAVA_OPTS -Djboss.modules.system.pkgs=org.jboss.byteman"

# GC 로그 (JDK 11 Unified Logging)
JAVA_OPTS="$JAVA_OPTS -Xlog:gc*:file=/opt/jboss/eap74/standalone/log/gc.log:time,uptime,level,tags:filecount=5,filesize=50m"
EOF
```

#### EAP 8.0 (`/opt/jboss/eap80/bin/standalone.conf`)

```bash
cat >> /opt/jboss/eap80/bin/standalone.conf << 'EOF'

# === Custom JVM Settings (EAP 8.0 / JDK 17) ===
JAVA_HOME="/opt/java/jdk-17"

JAVA_OPTS="$JAVA_OPTS -server"
JAVA_OPTS="$JAVA_OPTS -Xms1024m -Xmx2048m"
JAVA_OPTS="$JAVA_OPTS -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m"
JAVA_OPTS="$JAVA_OPTS -XX:+UseG1GC"
JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"
JAVA_OPTS="$JAVA_OPTS -Dfile.encoding=UTF-8"
JAVA_OPTS="$JAVA_OPTS -Duser.timezone=Asia/Seoul"

# JDK 17 모듈 시스템 열기 (EAP 8.0 필수)
JAVA_OPTS="$JAVA_OPTS --add-opens=java.base/java.lang=ALL-UNNAMED"
JAVA_OPTS="$JAVA_OPTS --add-opens=java.base/java.io=ALL-UNNAMED"
JAVA_OPTS="$JAVA_OPTS --add-opens=java.base/java.util=ALL-UNNAMED"

# GC 로그
JAVA_OPTS="$JAVA_OPTS -Xlog:gc*:file=/opt/jboss/eap80/standalone/log/gc.log:time,uptime,level,tags:filecount=5,filesize=50m"
EOF
```

### 5.8 JBoss EAP systemd 서비스

```bash
# ── EAP 7.4 서비스 (기본 포트, offset=0) ──
sudo cat > /etc/systemd/system/jboss-eap74.service << 'EOF'
[Unit]
Description=JBoss EAP 7.4 (JDK 11)
After=network.target

[Service]
Type=simple
User=jboss
Group=jboss

Environment="JAVA_HOME=/opt/java/jdk-11"
Environment="JBOSS_HOME=/opt/jboss/eap74"
Environment="JBOSS_MODULEPATH=/opt/jboss/eap74/modules"

ExecStart=/opt/jboss/eap74/bin/standalone.sh \
  -b 0.0.0.0 \
  -bmanagement 0.0.0.0 \
  -Djboss.server.base.dir=/opt/jboss/eap74/standalone

ExecStop=/opt/jboss/eap74/bin/jboss-cli.sh --connect --command=:shutdown

# 종료 시 30초 대기
TimeoutStopSec=30

Restart=on-failure
RestartSec=10

StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# ── EAP 8.0 서비스 (port-offset=100) ──
sudo cat > /etc/systemd/system/jboss-eap80.service << 'EOF'
[Unit]
Description=JBoss EAP 8.0 (JDK 17)
After=network.target

[Service]
Type=simple
User=jboss
Group=jboss

Environment="JAVA_HOME=/opt/java/jdk-17"
Environment="JBOSS_HOME=/opt/jboss/eap80"
Environment="JBOSS_MODULEPATH=/opt/jboss/eap80/modules"

ExecStart=/opt/jboss/eap80/bin/standalone.sh \
  -b 0.0.0.0 \
  -bmanagement 0.0.0.0 \
  -Djboss.socket.binding.port-offset=100 \
  -Djboss.server.base.dir=/opt/jboss/eap80/standalone

ExecStop=/opt/jboss/eap80/bin/jboss-cli.sh \
  --connect --controller=localhost:10090 \
  --command=:shutdown

TimeoutStopSec=30

Restart=on-failure
RestartSec=10

StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable jboss-eap74 jboss-eap80
```

### 5.9 JDBC 드라이버 및 Datasource 설정 (CLI)

> 애플리케이션(WAR) 구동 전 DB 연동을 위한 Datasource를 JBoss EAP에 설정합니다. (PostgreSQL 예시)

```bash
# EAP 기동 상태에서 jboss-cli를 통해 동적 설정
/opt/jboss/eap74/bin/jboss-cli.sh --connect << 'EOF'
# 1. JDBC 모듈 추가
module add --name=org.postgresql --resources=/data/backup/binaries/postgresql-42.6.0.jar --dependencies=javax.api,javax.transaction.api

# 2. JDBC 드라이버 등록
/subsystem=datasources/jdbc-driver=postgresql:add(driver-name=postgresql,driver-module-name=org.postgresql,driver-class-name=org.postgresql.Driver)

# 3. Datasource 등록
data-source add --name=MyDS --jndi-name=java:/MyDS --driver-name=postgresql \
  --connection-url=jdbc:postgresql://192.168.0.13:5432/mydb \
  --user-name=dbuser --password=dbpass \
  --use-java-context=true \
  --max-pool-size=50 --min-pool-size=10
EOF
```

### 5.10 애플리케이션 배포

```bash
# WAR 배포 — jboss-cli 사용 (권장)
# EAP 7.4
/opt/jboss/eap74/bin/jboss-cli.sh --connect \
  --command="deploy /path/to/app1.war --force"

# EAP 8.0 (관리 포트 10090)
/opt/jboss/eap80/bin/jboss-cli.sh --connect --controller=localhost:10090 \
  --command="deploy /path/to/app2.war --force"

# 또는 수동 복사
sudo -u jboss cp app1.war /opt/jboss/eap74/standalone/deployments/
sudo -u jboss cp app2.war /opt/jboss/eap80/standalone/deployments/
# → .deployed 파일 생성 확인
```

### 5.11 EAP 기동 확인

```bash
# EAP 7.4 상태
sudo systemctl start jboss-eap74
sudo systemctl status jboss-eap74
curl -s http://localhost:8080/    # HTTP 응답 확인
/opt/jboss/eap74/bin/jboss-cli.sh --connect --command=":read-attribute(name=server-state)"
# → "running"

# EAP 8.0 상태
sudo systemctl start jboss-eap80
sudo systemctl status jboss-eap80
curl -s http://localhost:8180/    # HTTP 응답 확인 (offset=100)
/opt/jboss/eap80/bin/jboss-cli.sh --connect --controller=localhost:10090 \
  --command=":read-attribute(name=server-state)"
# → "running"
```

### 5.12 Maven 오프라인 설정 (Server B)

```bash
# Maven 설치
sudo tar xzf /data/backup/binaries/apache-maven-3.9.*.tar.gz -C /opt/
sudo ln -s /opt/apache-maven-3.9.* /opt/maven

# 오프라인 리포지토리 복사
cp -r /data/backup/maven-repo /opt/maven-repo

# settings.xml 오프라인 모드 설정
cat > ~/.m2/settings.xml << 'EOF'
<settings>
  <localRepository>/opt/maven-repo</localRepository>
  <offline>true</offline>
  <mirrors>
    <mirror>
      <id>nexus-local</id>
      <mirrorOf>*</mirrorOf>
      <url>https://nexus.dev.local/repository/maven-public/</url>
    </mirror>
  </mirrors>
</settings>
EOF
```

---

## 6. DevOps 서버 설정 (Server C)

### 6.1 Docker 엔진 설정

```bash
# Docker daemon 설정 (insecure registry 제거 → CA 인증서 기반)
sudo mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker
```

### 6.2 Docker Compose 설치 및 구성

```bash
# docker-compose 바이너리 설치
sudo cp /data/backup/binaries/docker-compose /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
docker-compose --version
```

### 6.3 docker-compose.yml

```bash
mkdir -p /data/devops && cd /data/devops
cat > docker-compose.yml << 'YAML'
version: "3.8"

services:
  # ================================================
  # PostgreSQL (Gitea DB)
  # ================================================
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: gitea
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-ChangeMe!2024}
      POSTGRES_DB: gitea
    volumes:
      - pg_data:/var/lib/postgresql/data
    networks:
      - devops-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U gitea"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ================================================
  # Gitea (Git 형상관리)
  # ================================================
  gitea:
    image: gitea/gitea:1.22
    container_name: gitea
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - GITEA__database__DB_TYPE=postgres
      - GITEA__database__HOST=postgres:5432
      - GITEA__database__NAME=gitea
      - GITEA__database__USER=gitea
      - GITEA__database__PASSWD=${POSTGRES_PASSWORD:-ChangeMe!2024}
      - GITEA__server__DOMAIN=git.dev.local
      - GITEA__server__ROOT_URL=https://git.dev.local/
      - GITEA__server__HTTP_PORT=3000
    volumes:
      - gitea_data:/data
    ports:
      - "3000:3000"
      - "2222:22"
    networks:
      - devops-net

  # ================================================
  # Nexus (Maven/Docker Repository)
  # ================================================
  nexus:
    image: sonatype/nexus3:3.72.0
    container_name: nexus
    restart: unless-stopped
    environment:
      - INSTALL4J_ADD_VM_PARAMS=-Xms512m -Xmx2048m
    volumes:
      - nexus_data:/nexus-data
    ports:
      - "8081:8081"
      - "8082:8082"   # Docker hosted registry port
    networks:
      - devops-net

  # ================================================
  # Jenkins (CI/CD)
  # ================================================
  jenkins:
    image: jenkins/jenkins:lts-jdk17
    container_name: jenkins
    restart: unless-stopped
    user: root
    environment:
      - JAVA_OPTS=-Djava.awt.headless=true -Djenkins.install.runSetupWizard=false
    volumes:
      - jenkins_data:/var/jenkins_home
      - /var/run/docker.sock:/var/run/docker.sock
      - /usr/bin/docker:/usr/bin/docker
    ports:
      - "8080:8080"
      - "50000:50000"
    networks:
      - devops-net

  # ================================================
  # Docker Registry (Private)
  # ================================================
  registry:
    image: registry:2
    container_name: registry
    restart: unless-stopped
    environment:
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
    volumes:
      - registry_data:/var/lib/registry
    ports:
      - "5000:5000"
    networks:
      - devops-net

volumes:
  pg_data:
    driver: local
  gitea_data:
    driver: local
  nexus_data:
    driver: local
  jenkins_data:
    driver: local
  registry_data:
    driver: local

networks:
  devops-net:
    driver: bridge
YAML
```

### 6.4 오프라인 이미지 로드 및 기동

```bash
# 이미지 로드 (폐쇄망 전환 후)
docker load -i /data/backup/devops_infra.tar

# .env 파일 생성 (비밀번호 관리)
cat > /data/devops/.env << 'EOF'
POSTGRES_PASSWORD=YourSecurePassword2024!
EOF
chmod 600 /data/devops/.env

# 기동
cd /data/devops
docker-compose up -d

# 상태 확인
docker-compose ps
docker-compose logs --tail=20
```

### 6.5 Jenkins 오프라인 플러그인 설치

```bash
# Jenkins 기동 후 플러그인 디렉토리에 복사
docker cp /data/backup/jenkins-plugins/. jenkins:/var/jenkins_home/plugins/
docker restart jenkins

# 초기 어드민 비밀번호 확인
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

### 6.6 Nexus 초기 설정

```bash
# 초기 어드민 비밀번호 확인
docker exec nexus cat /nexus-data/admin.password

# 초기 로그인 후 수행할 작업 (Web UI):
# 1. 비밀번호 변경
# 2. Maven Proxy → maven-central 프록시 비활성화 (폐쇄망)
# 3. Maven Hosted 리포지토리 생성: maven-releases, maven-snapshots
# 4. Maven Group 리포지토리 생성: maven-public (hosted 포함)
# 5. Anonymous Access: 읽기 허용 설정
```

### 6.7 DevOps systemd 자동시작

```bash
sudo cat > /etc/systemd/system/devops-stack.service << 'EOF'
[Unit]
Description=DevOps Docker Compose Stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/data/devops
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable devops-stack
```

---

## 7. 보안 및 권한 관리

### 7.1 SSH 보안 강화

```bash
# /etc/ssh/sshd_config 수정 (3대 공통)
sudo sed -i 's/#Port 22/Port 22022/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# 키 배포 (관리자 PC에서)
ssh-keygen -t ed25519 -C "admin@dev.local"
ssh-copy-id -p 22022 admin@192.168.0.10
ssh-copy-id -p 22022 admin@192.168.0.11
ssh-copy-id -p 22022 admin@192.168.0.12

# sshd 재시작
sudo systemctl restart sshd
```

### 7.2 fail2ban 설정

```bash
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port    = 22022
logpath = /var/log/secure
EOF

sudo systemctl enable --now fail2ban
```

---

## 8. 백업 전략

### 8.1 DevOps 데이터 백업 스크립트

```bash
cat > /data/scripts/backup-devops.sh << 'SCRIPT'
#!/bin/bash
# DevOps 일일 백업 스크립트
BACKUP_DIR="/data/backup/daily/$(date +%Y%m%d)"
mkdir -p ${BACKUP_DIR}

echo "[$(date)] 백업 시작..."

# 1. Gitea 데이터
docker exec gitea bash -c 'cd /data && tar czf - .' > ${BACKUP_DIR}/gitea_data.tar.gz

# 2. PostgreSQL DB 덤프
docker exec postgres pg_dumpall -U gitea > ${BACKUP_DIR}/postgres_dump.sql

# 3. Jenkins 설정
docker exec jenkins bash -c 'cd /var/jenkins_home && tar czf - jobs/ config.xml credentials.xml' \
  > ${BACKUP_DIR}/jenkins_config.tar.gz

# 4. Nexus 설정 (데이터가 크므로 설정만)
docker cp nexus:/nexus-data/etc ${BACKUP_DIR}/nexus_etc

# 5. Docker Compose 파일
cp /data/devops/docker-compose.yml ${BACKUP_DIR}/
cp /data/devops/.env ${BACKUP_DIR}/

# 7일 이상 오래된 백업 삭제
find /data/backup/daily/ -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "[$(date)] 백업 완료: ${BACKUP_DIR}"
du -sh ${BACKUP_DIR}
SCRIPT

chmod +x /data/scripts/backup-devops.sh

# 크론 등록 (매일 새벽 2시)
echo "0 2 * * * /data/scripts/backup-devops.sh >> /var/log/backup.log 2>&1" | crontab -
```

### 8.2 WAS 백업 (Server B — JBoss EAP)

```bash
cat > /data/scripts/backup-was.sh << 'SCRIPT'
#!/bin/bash
BACKUP_DIR="/data/backup/was/$(date +%Y%m%d)"
mkdir -p ${BACKUP_DIR}

# EAP 7.4 설정 및 배포
tar czf ${BACKUP_DIR}/eap74_standalone.tar.gz \
  /opt/jboss/eap74/standalone/configuration/ \
  /opt/jboss/eap74/standalone/deployments/ \
  /opt/jboss/eap74/bin/standalone.conf

# EAP 8.0 설정 및 배포
tar czf ${BACKUP_DIR}/eap80_standalone.tar.gz \
  /opt/jboss/eap80/standalone/configuration/ \
  /opt/jboss/eap80/standalone/deployments/ \
  /opt/jboss/eap80/bin/standalone.conf

# 7일 이상 오래된 백업 삭제
find /data/backup/was/ -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

echo "[$(date)] WAS 백업 완료: ${BACKUP_DIR}"
SCRIPT

chmod +x /data/scripts/backup-was.sh
echo "0 3 * * * /data/scripts/backup-was.sh >> /var/log/backup.log 2>&1" | crontab -
```

### 8.3 WEB 백업 (Server A)

```bash
cat > /data/scripts/backup-web.sh << 'SCRIPT'
#!/bin/bash
BACKUP_DIR="/data/backup/web/$(date +%Y%m%d)"
mkdir -p ${BACKUP_DIR}

# JBCS 설정 파일
tar czf ${BACKUP_DIR}/jbcs_conf.tar.gz /opt/jbcs/httpd/conf/ /opt/jbcs/httpd/conf.d/

# 인증서
tar czf ${BACKUP_DIR}/certs.tar.gz /opt/jbcs/httpd/conf/certs/

find /data/backup/web/ -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
SCRIPT

chmod +x /data/scripts/backup-web.sh
echo "30 3 * * * /data/scripts/backup-web.sh >> /var/log/backup.log 2>&1" | crontab -
```

---

## 9. 최종 검증 (Acceptance Criteria)

### 9.1 필수 검증 체크리스트

```
[서버 공통]
- [ ] /etc/hosts에 모든 도메인이 등록되어 있는가?
- [ ] firewalld가 활성화되고 필요한 포트만 열려 있는가?
- [ ] chrony 시간 동기화가 3대 서버 간 정상인가?
- [ ] SSH 키 기반 인증만 허용되는가? (비밀번호 차단 확인)

[WEB - Server A]
- [ ] JBCS 기동: systemctl status jbcs
- [ ] HTTP→HTTPS 리다이렉트: curl -I http://web.dev.local
- [ ] HTTPS 접속: 모든 도메인이 브라우저에서 '안전함'으로 표시되는가?
- [ ] 설정 검증: apachectl configtest → Syntax OK

[WAS - Server B (JBoss EAP)]
- [ ] EAP 7.4 기동: jboss-cli.sh --connect --command=":read-attribute(name=server-state)" → "running"
- [ ] EAP 8.0 기동: jboss-cli.sh --connect --controller=localhost:10090 --command=":read-attribute(name=server-state)" → "running"
- [ ] JDK 확인: EAP 7.4는 JDK 11, EAP 8.0은 JDK 17을 사용하는가?
- [ ] HTTP 응답: curl http://localhost:8080 / curl http://localhost:8180
- [ ] JBCS → EAP 프록시: https://web.dev.local/app1, /app2 정상 응답?
- [ ] X-Forwarded-Proto, X-Real-IP 헤더 전달 확인 (proxy-address-forwarding=true)
- [ ] 관리 콘솔: http://localhost:9990 / http://localhost:10090 접속 가능?

[DevOps - Server C]
- [ ] docker-compose ps: 모든 컨테이너 Up 상태
- [ ] Gitea 접속: https://git.dev.local
- [ ] Nexus 접속: https://nexus.dev.local
- [ ] Jenkins 접속: https://jenkins.dev.local
- [ ] Registry Push: docker push registry.dev.local/test:v1 (1GB 이상 성공?)

[폐쇄망 생존 테스트]
- [ ] 외부망 차단 후 docker-compose down && docker-compose up -d 정상?
- [ ] Maven 빌드: mvn clean package (오프라인 리포지토리 연동)
- [ ] 3대 서버 리부팅 후 모든 서비스 자동 기동 확인
- [ ] EAP 재기동 후 배포된 WAR 자동 활성화 확인
```

### 9.2 검증 자동화 스크립트

```bash
#!/bin/bash
echo "=== 3-Tier 인프라 검증 ==="
echo ""

echo "[1] Server A - JBCS"
curl -sk -o /dev/null -w "  git.dev.local      → %{http_code}\n" https://git.dev.local
curl -sk -o /dev/null -w "  nexus.dev.local     → %{http_code}\n" https://nexus.dev.local
curl -sk -o /dev/null -w "  jenkins.dev.local   → %{http_code}\n" https://jenkins.dev.local
curl -sk -o /dev/null -w "  registry.dev.local  → %{http_code}\n" https://registry.dev.local/v2/
curl -sk -o /dev/null -w "  HTTP redirect       → %{http_code}\n" http://web.dev.local

echo ""
echo "[2] Server B - JBoss EAP"
curl -s -o /dev/null -w "  EAP 7.4 (8080)     → %{http_code}\n" http://192.168.0.11:8080
curl -s -o /dev/null -w "  EAP 8.0 (8180)     → %{http_code}\n" http://192.168.0.11:8180

echo "  EAP 7.4 state: $(/opt/jboss/eap74/bin/jboss-cli.sh --connect --command=':read-attribute(name=server-state)' 2>/dev/null | grep result)"
echo "  EAP 8.0 state: $(/opt/jboss/eap80/bin/jboss-cli.sh --connect --controller=localhost:10090 --command=':read-attribute(name=server-state)' 2>/dev/null | grep result)"

echo ""
echo "[3] Server C - DevOps"
docker-compose -f /data/devops/docker-compose.yml ps

echo ""
echo "=== 검증 완료 ==="
```

---

## 10. 트러블슈팅 가이드

| 증상 | 원인 | 해결 |
| :--- | :--- | :--- |
| `docker push` 시 x509 에러 | Registry CA 미신뢰 | `/etc/docker/certs.d/registry.dev.local/ca.crt`에 rootCA 복사 후 docker restart |
| JBCS 기동 실패: `AH00526` | 포트 충돌 | `ss -tlnp \| grep 443` 으로 점유 프로세스 확인 |
| EAP 기동 시 `Address already in use: 8080` | 두 인스턴스 포트 충돌 | EAP 8.0에 `-Djboss.socket.binding.port-offset=100` 확인 |
| EAP 8.0 `java.lang.reflect.InaccessibleObjectException` | JDK 17 모듈 접근 제한 | `standalone.conf`에 `--add-opens` 옵션 추가 |
| EAP 관리 콘솔 접속 불가 | 바인드 주소 127.0.0.1 | `-bmanagement 0.0.0.0` 확인 또는 CLI로 interface 변경 |
| Jenkins 접속 시 빈 화면 | 프록시 웹소켓 미지원 | vhost에 RewriteRule ws:// 설정 추가 |
| Nexus 접속 시 504 | 초기 기동 시간 김 (1~3분) | `docker logs nexus` 에서 Started 확인 후 재접속 |
| Maven 빌드 시 의존성 못 찾음 | offline 리포지토리 미완성 | Day-1에 `mvn dependency:go-offline` 재실행 |
| hosts 파일 적용 안됨 | nsswitch.conf 설정 | `/etc/nsswitch.conf`에서 `hosts: files dns` 확인 |
| `mkcert` 인증서 만료 | 기본 유효기간 2년 | 만료 전 재발급 후 3대 서버 CA 재배포 |
| EAP 배포 시 `.war.failed` 마커 생성 | 배포 오류 | `standalone/log/server.log` 확인, 의존성 누락 점검 |
| JBCS → EAP AJP 연결 거부 | AJP secret 불일치 | JBCS ProxyPass의 `secret=` 값과 EAP AJP 리스너 설정 일치 확인 |

---

## 11. 작업 순서 요약 (당일 체크리스트)

```
[Phase 1 - 인터넷 개방 중 (최우선)]
□ 1. Day-1 다운로드 전체 실행 (섹션 2)
     ★ JBoss EAP 7.4 + 8.0 ZIP 및 패치 (Red Hat 포탈)
□ 2. 다운로드 검증 스크립트 실행
□ 3. OS 패키지 업데이트 (3대)
□ 4. RPM 오프라인 캐시 확보

[Phase 2 - 공통 설정]
□ 5. /etc/hosts 설정 (3대)
□ 6. 방화벽 설정 (3대)
□ 7. SSH 보안 설정 (3대)
□ 8. chrony 시간 동기화

[Phase 3 - DevOps (Server C)]
□ 9.  Docker 설치/설정
□ 10. docker-compose.yml 배치
□ 11. 이미지 로드 & 컨테이너 기동
□ 12. Jenkins 플러그인 설치
□ 13. Nexus 초기 설정
□ 14. Gitea 초기 설정

[Phase 4 - WAS (Server B — JBoss EAP)]
□ 15. JDK 11/17 설치
□ 16. JBoss EAP 7.4/8.0 설치 (unzip)
□ 17. EAP 패치 적용 (있을 경우)
□ 18. 관리자 계정 생성 (add-user.sh)
□ 19. standalone.conf JVM 튜닝
□ 20. systemd 서비스 등록 (port-offset 확인)
□ 21. EAP 기동 → jboss-cli 배치 설정 실행
□ 22. JDBC 드라이버 패치 및 Datasource 생성
□ 23. 애플리케이션 WAR 배포
□ 24. Maven 오프라인 설정

[Phase 5 - WEB (Server A)]
□ 25. JBCS 설치
□ 26. mkcert 인증서 생성
□ 27. CA 인증서 3대 서버 배포
□ 28. vhost 설정 (EAP 프록시 8080/8180, SSL)
□ 29. HTTP→HTTPS 리다이렉트
□ 30. systemd 서비스 등록

[Phase 6 - 검증 & 백업]
□ 31. 최종 검증 스크립트 실행 (섹션 9)
□ 32. 백업 스크립트 설정 (섹션 8)
□ 33. 서버 리부팅 → 자동기동 확인
□ 34. 인터넷 차단 후 폐쇄망 생존 테스트
```

---

> **문서 작성일:** 2026-03-25
> **적용 환경:** CentOS Stream 10 / JBCS 2.4 / JBoss EAP 7.4 & 8.0 / JDK 11 & 17 / Docker CE
