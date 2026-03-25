# Day-1 온라인 자산 다운로드 가이드 (타겟 서버 직접 실행)

이 문서는 인터넷이 "최초 하루(Day-1)" 동안 허용된 타겟 서버 내부에서 향후 폐쇄망 전환 후 사용할 필수 자산을 모두 다운로드하여 캐싱해두는 가이드입니다.

---

## 1. 전제 조건
이 다운로드 가이드는 **`bare_os_setup_guide.md`의 온라인 필수 설정(디펜던시 설치 및 Docker 기동)이 모두 끝난 직후**에 수행되어야 합니다.

## 2. 다운로드 스크립트 실행 방법 (`day1_download_all.sh`)

이 스크립트는 Docker 레지스트리 역할 및 주요 자산을 보관할 **DevOps 서버(Server C)**에서 실행하는 것을 강력히 권장합니다.

1.  **스크립트 파일 서버 업로드**:
    로컬 PC에서 작성한 `day1_download_all.sh` 스크립트를 Server C 내부로 옮깁니다 (sftp 또는 복사/붙여넣기).
2.  **권한 부여 및 실행**:
    ```bash
    chmod +x day1_download_all.sh
    ./day1_download_all.sh
    ```
3.  **저장 구조 확인**:
    스크립트는 `~/day1_assets` 폴더 안에 카테고리별로 파일을 정리합니다.
    - `docker_images/`: 오프라인 로드용 인프라 이미지 타르볼 (`devops_infra.tar`)
    - `binaries/`: JDK, Maven, Docker Compose, mkcert 등
    - `jenkins_plugins/`: Jenkins 오프라인 설치를 위한 `.hpi` 풀 셋업

---

## 3. 유료 바이너리 수동 다운로드업로드 (★ 중요)

WEB(JBCS) 및 WAS(JBoss EAP)를 Docker 컨테이너로 띄우기 위해서라도, Red Hat의 원본 ZIP 파일이 컨테이너 빌드 페이로드(Payload)로 필요합니다. 

1.  [Red Hat Customer Portal](https://access.redhat.com/downloads)에 접속.
2.  **JBoss Enterprise Application Platform** 검색.
3.  아래 파일들을 받아 서버(주로 Server C의 `~/day1_assets/binaries/`)로 업로드합니다:
    - `jboss-eap-7.4.0.zip`
    - `jboss-eap-8.0.0.zip`
    - `jbcs-httpd24-httpd-2.4.57-*.zip`
*참고: 스크립트에서 다운받은 `rockylinux:9` 이미지를 베이스로 위 ZIP 파일들을 복사(ADD)하여 커스텀 `Dockerfile`을 구성하게 됩니다.*

---

## 4. Maven 프로젝트 사전 다운로드 캐시 (선택 작업)

자바 기반 애플리케이션 빌드가 예정되어 있다면, 빌드에 필요한 모든 라이브러리를 지금(인터넷이 될 때) 땡겨와야 합니다. 

```bash
cd /path/to/your/project
mvn dependency:go-offline -Dmaven.repo.local=~/day1_assets/maven_repo

# 또는 pom.xml만 활용하여
mvn dependency:go-offline -f pom.xml -Dmaven.repo.local=~/day1_assets/maven_repo
```

---

## 5. 다운로드 완료 후 조치

1. `~/day1_assets` 폴더 내 모든 파일이 올바르게 위치해 있는지 용도별로 확인합니다 (`du -sh ~/day1_assets`).
2. Day-1 다운로드가 모두 끝났다면, 서버의 인터넷 차단이 이루어져 폐쇄망 환경으로 전환됩니다.
3. 이제 **`setup-closed-network.md`의 Phase 2 (서비스 구축 및 연동)** 본 과정으로 돌입합니다.
