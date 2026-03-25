# 최초 빈 껍데기 OS (Bare OS) 초기 설정 가이드 (Day-1 온라인 환경)

이 문서는 아무것도 설치되지 않은 "빈 껍데기" Linux OS(RHEL/Rocky/CentOS 등)에 인터넷이 최초 하루(Day-1) 연결된 상태에서 수행해야 하는 **필수 사전 작업**을 정의합니다.

이 작업은 서버 자체에서 인터넷을 이용해 패키지를 설치하고 환경을 구성하므로 USB나 외장 하드를 통한 파일 이동이 필요 없습니다.

---

## 1. 인터넷 연결 확인 및 패키지 매니저 업데이트

서버가 인터넷에 정상적으로 연결되어 있는지 확인하고 기본 패키지 정보를 업데이트합니다.

```bash
# 인터넷 연결 확인
ping -c 3 8.8.8.8

# 패키지 정보 업데이트
sudo dnf makecache
sudo dnf update -y
```

---

## 2. 필수 유틸리티 온라인 설치

기본적인 파일 다운로드, 압축 해제, 네트워크 도구를 설치합니다.

```bash
# 필수 패키지 직접 설치
sudo dnf install -y vim wget curl net-tools pcre-devel openssl-devel tar unzip procps-ng bind-utils firewalld
```

---

## 3. Docker Engine 온라인 설치 (All Servers: WEB, WAS, DevOps)

모든 서버(Server A, B, C)에서 컨테이너 환경을 구동하기 위해 Docker 공식 저장소를 추가하고 바로 설치합니다. 

```bash
# Docker 의존성 설치 및 저장소 추가
sudo dnf install -y dnf-utils
sudo dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

# Docker Engine 설치
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker 서비스 활성화 및 기동
sudo systemctl enable --now docker

# 상태 확인
sudo systemctl status docker
```

---

## 4. 필수 OS 커널 및 보안 설정

원활한 시스템 통신과 성능을 위해 다음 설정들을 기본적으로 잡아주어야 합니다.

### 4.1 SELinux 허용 (Permissive) 모드
보안 정책 충돌 방지를 위해 임시로 완화합니다.
```bash
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
```

### 4.2 시스템 시간 동기화 (NTP)
서버 간 인증서 통신이나 로깅을 위해 시간이 완벽히 맞아야 합니다.
```bash
sudo dnf install -y chrony
sudo systemctl enable --now chronyd
```

### 4.3 방화벽 (firewalld) 활성화
오프라인 환경이라도 서버 간 통신 제어를 위해 방화벽은 활성화 상태를 유지합니다.
```bash
sudo systemctl enable --now firewalld
```

### 4.4 로컬 DNS (hosts) 설정
DNS 서버가 내부망에 없다면 `/etc/hosts` 파일에 모든 3-tier 서버 IP를 반드시 등록해야 합니다.
```bash
sudo sh -c 'cat >> /etc/hosts <<EOF
192.168.0.10  web.dev.local git.dev.local nexus.dev.local
192.168.0.11  was.dev.local
192.168.0.12  devops.dev.local
EOF'
```

### 4.5 프로세스/파일 리미트 설정 (ulimit)
대규모 트래픽 처리를 위해 최대 파일 오픈 개수를 늘려줍니다.
```bash
sudo sh -c 'cat >> /etc/security/limits.conf <<EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF'
```
*(적용을 위해 로그아웃 후 재로그인 필요)*

---

## 5. 다음 단계
각 노드(WEB, WAS, DevOps)의 뼈대와 Docker 설치가 인터넷 환경에서 깔끔하게 완료되었습니다.
이제 **같은 인터넷 환경(Day-1) 내에서** `day1_download_all.sh` 스크립트를 서버(주로 Server C)에서 직접 실행하여, 향후 인터넷이 차단된 후에도 사용할 자산(이미지, 바이너리 등)을 미리 캐싱 받는 단계로 넘어갑니다.
