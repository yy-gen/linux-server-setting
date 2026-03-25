---
description: 폐쇄망(Closed Network) 3-Tier 기반 인프라 통합 구축 워크플로우 (Day-1 온라인 버전)
---

# 폐쇄망 통합 구축 워크플로우 (Closed Network Setup)

이 워크플로우는 **최초 하루 동안 타겟 서버 자체에 인터넷이 연결된다는 전제(Day-1)** 하에, 인프라를 구축하고 인터넷이 단절된 이후 서비스를 연동하는 전체 단계를 정의합니다.

## Phase 0: 빈 껍데기 OS 초기 설정 및 자산 확보 (Day-1 / 온라인 환경)
서버가 인터넷에 정상적으로 열려있는 짧은 기간 내에 모든 필수 기반을 닦습니다.
(*상세 명령어는 `bare_os_setup_guide.md` 및 `day1_download_guide.md` 참고*)

1.  **OS 필수 튜닝 및 패키지 설치** (Server A, B, C 공통)
    - `dnf install`을 통해 `vim`, `wget`, `curl`, `net-tools`, `tar`, `firewalld` 등을 바로 설치.
    - `/etc/security/limits.conf` (ulimit) 및 `/etc/hosts` 설정.
    - 방화벽(`firewalld`) 기동 및 SELinux `permissive` 변경.
2.  **Docker 엔진 설치** (Server A, B, C 공통)
    - 공식 저장소를 추가하고 `docker-ce`를 모든 서버에 공통으로 설치 후 기동.
3.  **Day-1 스크립트 실행을 통한 자산 캐싱** (주로 Server C에서 실행)
    - `day1_download_all.sh`를 실행하여 오프라인에서 사용할 인프라 이미지(`devops_infra.tar`), JDK, Maven, Jenkins 필수 플러그인을 다운받아 둡니다.
    - *Red Hat 계정 로그인이 필요한 JBCS, EAP ZIP 파일은 수동으로 PC에서 다운받아 서버로 올립니다.*

> **인터넷 차단: 이 시점부터 서버의 외부 통신이 차단되고 완전한 폐쇄망(Offline)이 되었다고 가정합니다.**

## Phase 1: 컨테이너 오프라인 로드 및 서비스 배포 준비 (Day-2 / 오프라인)

2.  **이미지 오프라인 로드** (Server A, B, C 공통)
    - `docker load -i ~/day1_assets/docker_images/devops_infra.tar` 명령으로 `rockylinux:9` 등 빌드 베이스 이미지 및 서비스 이미지를 로드.
2.  **DevOps 서비스 기동** (Server C)
    - 다운로드한 `docker-compose` 바이너리를 이용하여 Gitea, Nexus, Jenkins, Registry를 한꺼번에 기동합니다.

## Phase 2: WEB / WAS 설치 및 프록시 설정 (오프라인)

1.  **WEB 서버 (JBCS) 컨테이너 설치** (Server A)
    - 수동 다운로드한 JBCS ZIP 파일과 `rockylinux:9` 베이스 이미지를 활용하여 커스텀 `Dockerfile`을 작성하고 빌드.
    - 다운받은 `mkcert` (또는 `openssl`)로 SSL 인증서 생성 후 호스트-컨테이너 간 볼륨 매핑.
    - `httpd.conf` 및 `conf.d/*.conf` 설정을 호스트에 위치시키고 서버 B(WAS) 방향 프록시 연동.

2.  **WAS 서버 (JBoss EAP) 컨테이너 설치** (Server B)
    - 다운로드한 JDK 타르볼과 EAP ZIP 파일, `rockylinux:9` 베이스 이미지를 활용하여 EAP 7.4 및 8.0 커스텀 `Dockerfile`을 빌드.
    - `standalone.xml` 등을 외부 볼륨으로 분리하여 AJP 및 프록시 주소 포워딩 수용.

## Phase 3: 최종 검증 (오프라인)

1.  **방화벽(firewalld) 제어 룰 점검**
    - Server A -> Server B, Server A -> Server C 접근이 정상적으로 정책화되었는지 확인.
2.  **통합 연동 테스트**
    - 내부 전용 PC의 브라우저에서 `https://web.dev.local` (Server A 도메인) 접속 시 EAP 서버 응답 확인.
    - `https://git.dev.local`, `https://nexus.dev.local` 등 데브옵스 도구가 정상 프록시 되는지 확인.
3.  **모니터링 및 백업**
    - JBCS `access_log`와 JBoss `server.log`를 주기적으로 `logrotate` 할 수 있는지 점검.
