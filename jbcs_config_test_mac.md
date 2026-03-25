# JBCS 메인 설정 macOS 시나리오 테스트 가이드

이 문서는 `jbcs_3tier_setup_guide_v2.1.md`의 **4.3 JBCS 메인 설정** 내용을 macOS 환경에서 로컬 검증하기 위한 테스트 시나리오입니다. 리눅스 환경과 경로 차이가 있으므로, macOS에 맞게 조정된 설정을 사용합니다.

---

## 0. 사전 준비 (Prerequisites)

테스트를 위해 다음 도구들이 설치되어 있어야 합니다.

1.  **Homebrew Apache**: macOS 기본 Apache 대신 brew 버전을 권장합니다.
    ```bash
    brew install httpd
    ```
2.  **mkcert**: 로컬 신뢰 인증서 생성을 위해 필요합니다.
    ```bash
    brew install mkcert
    ```

---

## 1. 테스트 환경 구성 (Directory Setup)

JBCS의 구조를 흉내 내기 위해 테스트용 전용 디렉토리를 생성합니다.

```bash
# 테스트 작업 디렉토리 생성
export TEST_DIR=$HOME/jbcs_test
mkdir -p $TEST_DIR/httpd/conf/certs
mkdir -p $TEST_DIR/httpd/conf.d
mkdir -p $TEST_DIR/httpd/logs
mkdir -p $TEST_DIR/httpd/modules

# 필요한 모듈 심볼릭 링크 (Homebrew 경로 기준)
ln -s $(brew --prefix httpd)/lib/httpd/modules/* $TEST_DIR/httpd/modules/
```

---

## 2. SSL 인증서 생성 (mkcert)

가이드 4.2절에 따라 로컬 테스트용 도메인 인증서를 생성합니다.

```bash
cd $TEST_DIR/httpd/conf/certs

# CA 설치 및 인증서 생성
mkcert -install
mkcert -cert-file cert.pem -key-file key.pem \
  "web.dev.local" "*.dev.local" localhost 127.0.0.1
```

---

## 3. 테스트용 httpd.conf 작성 (Section 4.3 반영)

가이드의 설정을 macOS 경로에 맞게 수정한 구성 파일입니다.

```apache
# $TEST_DIR/httpd/conf/httpd.conf

# 기본 경로 설정
Define ROOT "/Users/$(whoami)/jbcs_test/httpd"
ServerRoot "${ROOT}"
Listen 8080
Listen 8443

# 모듈 로드 (Section 4.3)
LoadModule mpm_event_module modules/mod_mpm_event.so
LoadModule authn_core_module modules/mod_authn_core.so
LoadModule authz_core_module modules/mod_authz_core.so
LoadModule unixd_module modules/mod_unixd.so
LoadModule ssl_module modules/mod_ssl.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
LoadModule headers_module modules/mod_headers.so
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule log_config_module modules/mod_log_config.so
LoadModule dir_module modules/mod_dir.so

# 서버 기본 설정 (Section 4.3)
ServerName web.dev.local:8443
ServerAdmin admin@dev.local

# 로그 설정 (Section 4.3)
ErrorLog "logs/error_log"
LogLevel warn
<IfModule log_config_module>
    CustomLog "logs/access_log" combined
</IfModule>

# 보안 헤더 (Section 4.3)
ServerTokens Prod
ServerSignature Off
TraceEnable Off

# 타임아웃 설정 (Section 4.3)
Timeout 300
ProxyTimeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# vhost 설정 포함 (Section 4.3)
IncludeOptional conf.d/*.conf
```

---

## 4. 가상 호스트 및 프록시 설정 (Section 4.4 ~ 4.6 반영)

```apache
# $TEST_DIR/httpd/conf.d/vhosts.conf

# SSL 공통 설정 (Section 4.5)
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSLCipherSuite HIGH:!aNULL:!MD5:!3DES:!RC4
SSLHonorCipherOrder on

<VirtualHost *:8443>
    ServerName web.dev.local
    SSLEngine on
    SSLCertificateFile    "conf/certs/cert.pem"
    SSLCertificateKeyFile "conf/certs/key.pem"

    # 보안 헤더 추가 (Section 4.5)
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"

    # WAS 프록시 테스트 (Section 4.6 - 로컬 dummy backend 연결)
    ProxyPreserveHost On
    ProxyPass         /app1  http://127.0.0.1:9090/app1
    ProxyPassReverse  /app1  http://127.0.0.1:9090/app1
    
    RequestHeader set X-Forwarded-Proto "https"
</VirtualHost>

# HTTP -> HTTPS 리다이렉트 (Section 4.4)
<VirtualHost *:8080>
    ServerName web.dev.local
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}:8443$1 [R=301,L]
</VirtualHost>
```

---

## 5. 검증 시나리오 (Validation Steps)

### 5.1 /etc/hosts 설정
테스트 도메인이 로컬을 바라보게 합니다.
```bash
sudo sh -c 'echo "127.0.0.1 web.dev.local" >> /etc/hosts'
```

### 5.2 더미 백엔드 실행
설정한 프록시 목적지(`127.0.0.1:9090`)에서 응답을 줄 서버를 띄웁니다.
```bash
# 새 터미널에서 실행
mkdir -p $TEST_DIR/backend/app1
echo "<h1>Hello from Dummy WAS (EAP 7.4)</h1>" > $TEST_DIR/backend/app1/index.html
cd $TEST_DIR/backend && python3 -m http.server 9090
```

### 5.3 Apache 구동 및 설정 체크
```bash
# 설정 문법 검사 (Section 4.9)
httpd -t -f $TEST_DIR/httpd/conf/httpd.conf

# Apache 시작 (foreground 모드로 로그 확인)
httpd -X -f $TEST_DIR/httpd/conf/httpd.conf
```

### 5.4 테스트 수행 (Verification)

1.  **SSL 인증서 정보 확인**:
    ```bash
    echo | openssl s_client -connect web.dev.local:8443 | openssl x509 -noout -text | grep "Subject:"
    ```
2.  **HTTP -> HTTPS 리다이렉트 체크**:
    ```bash
    curl -I http://web.dev.local:8080/app1
    # HTTP/1.1 301 Moved Permanently 가 나와야 함
    ```
3.  **Reverse Proxy 연동 확인 (Headers 포함)**:
    ```bash
    curl -k -v https://web.dev.local:8443/app1/
    # "Hello from Dummy WAS" 문구가 보여야 하며,
    # 응답 헤더에 Strict-Transport-Security, X-Frame-Options 등이 포함되어야 함
    ```
4.  **보안 설정(ServerTokens) 확인**:
    ```bash
    curl -k -I https://web.dev.local:8443/app1/ | grep Server
    # "Server: Apache" 만 나오고 버전 정보가 숨겨져야 함 (Prod 설정)
    ```

---

## 6. 결과 정리
모든 테스트가 패스되면 `jbcs_3tier_setup_guide_v2.1.md`의 설정 로직이 정상임을 맥에서 검증 완료한 것입니다.
