# 개발 워크스테이션 구축

터미널과 Git으로 작업 환경을 구성하고, NGINX 정적 웹 서버를 Docker 이미지로 빌드해 포트 매핑, 바인드 마운트, 볼륨 영속성을 검증했다.

## 실행 환경

- OS 및 아키텍처: Linux 6.18.58.1-microsoft-standard-WSL2 x86_64
- 셸: Bash 5.3.9(1)-release
- 터미널 정보: xterm-256color
- Docker: Docker version 29.9.2, build a82e528
- Git: git version 2.53.0

## 수행 결과

- [x] 터미널 조작과 파일·디렉터리 권한 실습
- [x] Docker 엔진 점검, hello-world, Ubuntu 내부 명령 및 컨테이너 운영
- [x] [Dockerfile](Dockerfile)과 [웹 소스](app/index.html) 빌드 및 실행
- [x] 두 포트에서 HTTP 응답 확인 (`http://127.0.0.1:18080/`, `http://127.0.0.1:18081/`)
- [x] 호스트 파일 변경 반영과 Docker 볼륨 데이터 유지 확인
- [x] 저장소 범위 Git 사용자 정보와 기본 브랜치 설정
- [x] [브라우저 주소창과 페이지 캡처](evidence/browser.jpg) (동일 Dockerfile로 재실행한 8080 포트)
- [x] [VS Code GitHub 로그인 및 원격 저장소 연동 캡처](evidence/vscode.png) (계정 메뉴의 사용자명 마스킹)
- [x] [GitHub 저장소](https://github.com/sumer0608-53/codysseytest) 연결 및 main 브랜치 푸시

[전체 명령과 출력](evidence/terminal.txt)에서 각 검증의 실제 결과를 볼 수 있다. 로그의 `<MISSION_DIR>`와 `<TEMP_DIR>`는 실행 환경의 경로를 가린 표시다.

## 검증과 재현

Docker의 Linux 엔진을 시작하고 이 저장소의 루트에서 실행한다. Windows에서는 Docker Desktop의 WSL2 통합을 켜고 WSL2 셸에서 실행한다. macOS에서는 Docker Desktop이나 OrbStack을 사용할 수 있다. 사용 중인 호스트 포트는 다른 번호로 바꾼다.

[실습 실행 파일](workstation-mission.sh)을 `bash workstation-mission.sh`로 실행하면 새 폴더에서 전체 검증을 재현할 수 있다. 아래 명령은 웹 서버만 확인할 때 사용한다.

~~~bash
docker build -t mission-web .
docker run --rm -d --name mission-web -p 127.0.0.1:18080:80 mission-web
curl -fsS http://127.0.0.1:18080/
docker logs mission-web
docker stats --no-stream mission-web
docker stop mission-web
~~~

- **터미널과 권한** · `pwd`로 절대 경로를 확인했다. `notes.txt`와 같은 상대 경로는 현재 디렉터리를 기준으로 해석한다. `ls -ld`로 파일의 600→644, 디렉터리의 700→755 변경을 확인했다. 소유자·그룹·기타 사용자마다 읽기(4), 쓰기(2), 실행(1)을 더한다. 디렉터리의 실행 권한은 내부 경로에 접근하는 데 필요하다.
- **이미지와 컨테이너** · `nginx:alpine`을 베이스로 선택했다. `LABEL`로 이미지 제목을 지정했고, `COPY`로 기본 페이지를 교체했다. 이미지는 실행에 필요한 파일과 설정을 담고, 컨테이너는 그 이미지에서 격리되어 실행되는 인스턴스다.
- **컨테이너 내부 명령** · `docker exec`로 실행 중인 Ubuntu 컨테이너에서 명령을 실행하고, 해당 명령이 끝나도 컨테이너가 실행 중임을 확인했다. `docker start -a`는 주 프로세스 출력에 연결되며, 이 실습의 일회성 주 프로세스가 끝나면 컨테이너도 종료된다.
- **포트 매핑** · 두 호스트 포트에 각각 컨테이너의 80번을 연결했다. `curl`로 두 주소에서 `WORKSTATION_IMAGE_OK`를 확인했다. 주소를 127.0.0.1에 바인딩해 같은 컴퓨터의 브라우저에서 접속한다.
- **바인드 마운트** · 두 번째 포트의 컨테이너를 교체해 `bind-demo/`를 읽기 전용으로 연결했다. 호스트 파일 수정 후 같은 컨테이너에서 `BIND_BEFORE`가 `BIND_AFTER`로 바뀌었고 첫 번째 포트의 이미지 콘텐츠는 그대로 제공됐다.
- **볼륨** · 이름 있는 볼륨을 만들고 첫 컨테이너의 `/data`에 기록했다. 컨테이너를 삭제하고 같은 볼륨을 새 컨테이너에 연결한 뒤 `VOLUME_OK`를 확인했다.
- **Git과 GitHub** · Git은 로컬에서 커밋과 브랜치를 관리한다. GitHub는 원격 저장소를 호스팅해 공유와 협업을 지원한다. Git 사용자 설정은 이 저장소에만 적용했다.

## 트러블슈팅 재현

| 문제 | 원인 가설 | 확인 | 해결 |
| --- | --- | --- | --- |
| 웹 요청이 404를 반환 | 요청한 파일이 웹 이미지에 없음 | `curl`로 `/missing.html`의 404 응답을 기록 | `/`로 요청하여 정적 페이지 응답 확인 |
| 컨테이너 교체 후 파일을 찾을 수 없음 | `/tmp` 파일을 컨테이너의 쓰기 계층에 저장 | 새 컨테이너의 `/tmp/proof.txt` 부재 확인 | 이름 있는 볼륨을 `/data`에 재연결해 `proof.txt` 읽기 |

두 사례는 검증을 위해 재현했다. 자세한 명령, 출력 및 비교 결과는 [터미널 로그](evidence/terminal.txt)에 있다.
