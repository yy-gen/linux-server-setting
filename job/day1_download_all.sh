#!/bin/bash

# ==============================================================================
# Day-1 Closed Network Setup: Asset Download Script (v2.0 - Online Servers)
# ==============================================================================
# 이 스크립트는 인터넷이 "최초 하루(Day-1)" 동안 허용된 타겟 서버 내부에서
# 직접 실행하여, 향후 폐쇄 시점 이후에 사용할 필수 파일을 캐싱합니다.

set -e

# --- 0. 기본 설정 ---
BASE_DIR="$HOME/day1_assets"
BIN_DIR="$BASE_DIR/binaries"
DOCKER_DIR="$BASE_DIR/docker_images"
PLUGINS_DIR="$BASE_DIR/jenkins_plugins"

echo "[1/5] 디렉토리 구조 생성 중..."
mkdir -p "$BIN_DIR" "$DOCKER_DIR" "$PLUGINS_DIR"

# --- 1. Docker 이미지 다운로드 및 저장 ---
# 주의: 이 스크립트 실행 전, bare_os_setup_guide.md 에 따라 해당 서버에
# Docker Engine이 미리 온라인으로 설치되어 있고 구동 중이어야 합니다.
echo "[2/5] Docker 이미지 추출 및 Tar 저장 중..."
IMAGES=(
    "gitea/gitea:1.22"
    "sonatype/nexus3:3.72.0"
    "jenkins/jenkins:lts-jdk17"
    "registry:2"
    "postgres:15-alpine"
    "redis:7-alpine"
    "rockylinux:9"
)

for img in "${IMAGES[@]}"; do
    echo "  -> Pulling $img..."
    docker pull "$img"
done

echo "  -> 이미지 통합 저장 (devops_infra.tar)..."
docker save -o "$DOCKER_DIR/devops_infra.tar" "${IMAGES[@]}"

# --- 2. 공용 인프라 바이너리 다운로드 ---
echo "[3/5] 공용 인프라 오픈소스 바이너리 다운로드 중..."
# OpenJDK 11 & 17 (Adoptium)
wget -nc "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.21+9/OpenJDK11U-jdk_x64_linux_hotspot_11.0.21_9.tar.gz" -P "$BIN_DIR"
wget -nc "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.9+9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.9_9.tar.gz" -P "$BIN_DIR"

# Maven, mkcert, Docker Compose
wget -nc "https://dlcdn.apache.org/maven/maven-3/3.9.6/binaries/apache-maven-3.9.6-bin.tar.gz" -P "$BIN_DIR"
wget -nc "https://github.com/FiloSottile/mkcert/releases/download/v1.4.4/mkcert-v1.4.4-linux-amd64" -O "$BIN_DIR/mkcert"
wget -nc "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -O "$BIN_DIR/docker-compose"
chmod +x "$BIN_DIR/mkcert" "$BIN_DIR/docker-compose"

# --- 3. JBoss EAP & JBCS 안내 ---
echo "[4/5] RED HAT 유료 바이너리 (JBCS, EAP) 확보 안내..."
echo "  !! 중요: JBCS와 JBoss EAP는 Red Hat 계정 인증이 필요하여 자동 다운로드가 불가합니다."
echo "  !! 데스크탑 등에서 브라우저를 통해 받아 현재 서버의 '$BIN_DIR' 폴더에 직접 업로드하세요."
echo "     - jbcs-httpd24-httpd-2.4.57-*.zip"
echo "     - jboss-eap-7.4.0.zip / jboss-eap-8.0.0.zip"

# --- 4. Jenkins 플러그인 다운로드 ---
echo "[5/5] Jenkins 필수 플러그인 캐시 중..."
PLUGINS=(
    "git" "git-client" "workflow-aggregator" "docker-workflow" "maven-plugin"
    "nexus-artifact-uploader" "blueocean" "credentials" "ssh-credentials"
)

for p in "${PLUGINS[@]}"; do
    echo "  -> Downloading Jenkins plugin: $p..."
    wget -q -nc "https://updates.jenkins.io/latest/${p}.hpi" -P "$PLUGINS_DIR"
done

# --- 5. 최종 확인 ---
echo "=========================================================="
du -sh "$BASE_DIR"/*
echo "=========================================================="
echo "작업 완료. '$BASE_DIR' 내 자산은 향후 폐쇄망 전환 후에도 즉시 사용 가능합니다."
