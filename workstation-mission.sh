#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
사용법: bash workstation-mission.sh [새 결과 폴더] [--capture] [--publish OWNER/REPO]
기본 결과 폴더: ~/workstation-mission-날짜-시간
환경: Linux, WSL2 또는 macOS / Bash, Docker 엔진, Git, curl
--capture  웹 서버를 실행한 채 브라우저 및 VS Code 캡처 파일 경로를 입력받습니다.
--publish  gh 로그인 후 지정한 새 공개 GitHub 저장소를 만들고 푸시합니다.
           캡처 옵션이 필요합니다. 업로드 직전에 공개 여부를 다시 확인합니다.
PORT_ONE, PORT_TWO 환경 변수로 호스트 포트를 변경할 수 있습니다 (기본 8080, 8081).
Git 커밋에는 실습용 공개 이름과 이메일을 사용합니다.
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

destination='' capture=0 publish=''
while (($#)); do
    case "$1" in
        -h|--help) usage; exit ;;
        --capture) capture=1; shift ;;
        --publish)
            [[ ${2:-} =~ ^[a-zA-Z0-9-]+/[a-zA-Z0-9_.-]+$ ]] ||
                die '--publish 뒤에 OWNER/REPO를 지정하세요.'
            publish=$2
            shift 2 ;;
        -*) die "알 수 없는 옵션: $1" ;;
        *) [[ -z $destination ]] || die '결과 폴더는 한 개만 지정하세요.'
           destination=$1; shift ;;
    esac
done

[[ $(uname -s) == Linux || $(uname -s) == Darwin ]] ||
    die 'Windows에서는 WSL2의 Linux 터미널에서 실행하세요.'
for program in docker git curl; do
    command -v "$program" >/dev/null || die "$program 설치와 PATH 설정을 확인하세요."
done
if [[ -n $publish ]]; then
    ((capture)) || die '--publish와 함께 --capture를 지정하세요.'
    command -v gh >/dev/null || die 'GitHub CLI(gh)를 설치하세요.'
    gh auth status --hostname github.com >/dev/null 2>&1 ||
        die '먼저 gh auth login --hostname github.com 을 실행하세요.'
fi
if ((capture)); then
    [[ -t 0 ]] || die '--capture는 대화형 터미널에서 실행하세요.'
fi
engine=$(docker info --format '{{.OSType}}' 2>/dev/null) ||
    die 'Docker 엔진에 연결하지 못했습니다. Docker Desktop 또는 OrbStack을 시작하고, WSL에서는 배포판 통합을 확인하세요.'
[[ $engine == linux ]] || die 'Docker에서 Linux 컨테이너 엔진을 선택하세요.'

port_one=${PORT_ONE:-8080}
port_two=${PORT_TWO:-8081}
for port in "$port_one" "$port_two"; do
    [[ $port =~ ^[1-9][0-9]{0,4}$ ]] && ((port <= 65535)) ||
        die "잘못된 포트: $port"
done
[[ $port_one != "$port_two" ]] || die '두 호스트 포트는 서로 달라야 합니다.'
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
script_path="$script_dir/$(basename -- "${BASH_SOURCE[0]}")"
destination=${destination:-"$HOME/workstation-mission-$(date +%Y%m%d-%H%M%S)"}
mkdir -- "$destination" || die '존재하지 않는 새 결과 폴더를 지정하세요.'
cd -- "$destination"
root=$PWD
mkdir app evidence
cp -- "$script_path" workstation-mission.sh
log=$root/evidence/terminal.txt
scratch=$(mktemp -d "${TMPDIR:-/tmp}/workstation-mission.XXXXXXXX")
prefix="workstation-$(date +%s)-$$-$RANDOM"
image="$prefix:1.0"
volume="$prefix-data"
containers=()
volume_created=0 image_created=0

cleanup() {
    local result=$?
    trap - EXIT
    if [[ -n ${containers[0]:-} ]]; then
        docker rm -f "${containers[@]}" >/dev/null 2>&1 || true
    fi
    if ((volume_created)); then docker volume rm "$volume" >/dev/null 2>&1 || true; fi
    if ((image_created)); then docker image rm "$image" >/dev/null 2>&1 || true; fi
    if [[ -f $scratch/practice/permissions/file ]]; then
        rm -- "$scratch/practice/permissions/file"
    fi
    if [[ -e $scratch/practice/permissions ]]; then rmdir -- "$scratch/practice/permissions"; fi
    if [[ -f $scratch/practice/notes.txt ]]; then rm -- "$scratch/practice/notes.txt"; fi
    if [[ -f $scratch/practice/copy.txt ]]; then rm -- "$scratch/practice/copy.txt"; fi
    if [[ -f $scratch/practice/renamed.txt ]]; then rm -- "$scratch/practice/renamed.txt"; fi
    if [[ -f $scratch/practice/.empty ]]; then rm -- "$scratch/practice/.empty"; fi
    if [[ -d $scratch/practice ]]; then rmdir -- "$scratch/practice"; fi
    rmdir -- "$scratch"
    if ((result)); then printf '중단되었습니다. 부분 결과: %s\n' "$root" >&2; fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

record() {
    local line
    line=$(printf '%q ' "$@")
    # 작업 폴더와 임시 폴더의 실제 절대 경로는 제출 로그에서 치환합니다.
    line=${line//"$root"/'<MISSION_DIR>'}
    line=${line//"$scratch"/'<TEMP_DIR>'}
    printf '\n$ %s\n' "$line" | tee -a "$log"
}

logged() {
    record "$@"
    # 파이프의 양쪽이 성공해야 검증을 계속합니다.
    "$@" 2>&1 |
        while IFS= read -r line || [[ -n $line ]]; do
            line=${line//"$root"/'<MISSION_DIR>'}
            line=${line//"$scratch"/'<TEMP_DIR>'}
            printf '%s\n' "$line"
        done | tee -a "$log"
}

section() { printf '\n=== %s ===\n' "$1" | tee -a "$log"; }

cat > app/index.html <<'EOF'
<!doctype html>
<html lang="ko">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>개발 워크스테이션</title>
<main>
  <h1>개발 워크스테이션</h1>
  <p>WORKSTATION_IMAGE_OK</p>
  <p>Dockerfile로 빌드한 NGINX가 이 페이지를 제공하고 있습니다.</p>
</main>
</html>
EOF
cat > Dockerfile <<'EOF'
FROM nginx:alpine
LABEL org.opencontainers.image.title="Development Workstation Mission"
COPY app/index.html /usr/share/nginx/html/index.html
EOF
printf '%s\n' '*' '!app/' '!app/index.html' > .dockerignore
: > "$log"

section '실행 환경'
os=$(uname -srm)
docker_version=$(docker --version)
git_version=$(git --version)
logged uname -srm
logged bash --version
logged docker --version
logged docker info --format 'OS={{.OSType}} Arch={{.Architecture}} Server={{.ServerVersion}} Driver={{.Driver}}'
logged git --version

section '터미널 기본 조작'
logged pwd
logged mkdir "$scratch/practice"
record cd "$scratch/practice"
cd "$scratch/practice"
logged pwd
logged touch .empty
record sh -c 'printf "%s\n" "terminal practice" > notes.txt'
printf '%s\n' 'terminal practice' > notes.txt
logged ls -a
logged cat notes.txt
logged cp notes.txt copy.txt
logged mv copy.txt renamed.txt
logged ls -a
logged rm renamed.txt
logged ls -a

section '파일 및 디렉터리 권한 변경'
logged mkdir permissions
logged touch permissions/file
logged chmod 700 permissions
logged chmod 600 permissions/file
logged ls -ldn permissions permissions/file
logged chmod 755 permissions
logged chmod 644 permissions/file
logged ls -ldn permissions permissions/file
[[ $(LC_ALL=C ls -ld permissions) == drwxr-xr-x* &&
   $(LC_ALL=C ls -ld permissions/file) == -rw-r--r--* ]] ||
    die 'UNIX 권한을 지원하는 파일시스템이 필요합니다. Linux의 /tmp 또는 홈 디렉터리를 사용하세요.'
record cd "$root"
cd "$root"
logged pwd

section 'Docker 이미지와 Ubuntu 컨테이너'
logged docker pull hello-world
logged docker pull ubuntu:24.04
hello="$prefix-hello"
ubuntu="$prefix-ubuntu"
attached="$prefix-attach"
containers+=("$hello" "$ubuntu" "$attached")
logged docker run --rm --name "$hello" hello-world
logged docker run -d --name "$ubuntu" ubuntu:24.04 sleep infinity
logged docker exec "$ubuntu" sh -c 'echo EXEC_OK; ls /'
logged docker inspect --format 'running={{.State.Running}}' "$ubuntu"
[[ $(docker inspect -f '{{.State.Running}}' "$ubuntu") == true ]]
logged docker create --name "$attached" ubuntu:24.04 sh -c 'echo ATTACHED_TO_MAIN_PROCESS'
logged docker start -a "$attached"
logged docker inspect --format 'running={{.State.Running}} exit={{.State.ExitCode}}' "$attached"
[[ $(docker inspect -f '{{.State.Status}}:{{.State.ExitCode}}' "$attached") == exited:0 ]]

section '웹 이미지 빌드 및 포트 매핑'
logged docker build -t "$image" .
image_created=1
web_one="$prefix-web-one"
web_two="$prefix-web-two"
mounted="$prefix-bind"
containers+=("$web_one" "$web_two" "$mounted")
logged docker images "$image"
logged docker run -d --name "$web_one" -p "127.0.0.1:$port_one:80" "$image"
logged docker run -d --name "$web_two" -p "127.0.0.1:$port_two:80" "$image"
url_one="http://127.0.0.1:$port_one"
url_two="http://127.0.0.1:$port_two"

verify_http() {
    local url=$1 expected=$2 body attempt
    for ((attempt=0; attempt<30; attempt++)); do
        if body=$(curl -fsS --max-time 2 "$url" 2>/dev/null) && [[ $body == *"$expected"* ]]; then
            logged curl -fsS --max-time 5 "$url"
            return
        fi
        sleep 1
    done
    die "HTTP 검증 실패: $url ($expected)"
}

verify_http "$url_one/" WORKSTATION_IMAGE_OK
verify_http "$url_two/" WORKSTATION_IMAGE_OK
logged docker ps --filter "name=$prefix"
logged docker logs "$web_one"
logged docker stats --no-stream "$web_one"

section '트러블슈팅 재현 1 — 잘못된 URL'
record curl -sS -o /dev/null -w '%{http_code}' "$url_one/missing.html"
status=$(curl -sS -o /dev/null -w '%{http_code}' "$url_one/missing.html")
printf '%s\n' "$status" | tee -a "$log"
[[ $status == 404 ]] || die '잘못된 경로에서 404 응답을 예상했습니다.'
verify_http "$url_one/" WORKSTATION_IMAGE_OK

section '바인드 마운트 변경 전후'
mkdir bind-demo
printf '%s\n' 'BIND_BEFORE' > bind-demo/index.html
logged docker stop "$web_two"
logged docker run -d --name "$mounted" -p "127.0.0.1:$port_two:80" \
    --mount "type=bind,source=$root/bind-demo,target=/usr/share/nginx/html,readonly" "$image"
verify_http "$url_two/" BIND_BEFORE
record sh -c 'echo BIND_AFTER > bind-demo/index.html'
echo BIND_AFTER > bind-demo/index.html
verify_http "$url_two/" BIND_AFTER
verify_http "$url_one/" WORKSTATION_IMAGE_OK

section '볼륨 영속성과 트러블슈팅 재현 2 — 컨테이너 파일 소실'
first="$prefix-volume-first"
second="$prefix-volume-second"
containers+=("$first" "$second")
logged docker volume create "$volume"
volume_created=1
logged docker run -d --name "$first" --mount "type=volume,source=$volume,target=/data" ubuntu:24.04 sleep infinity
logged docker exec "$first" sh -c 'echo VOLUME_OK > /data/proof.txt; echo EPHEMERAL > /tmp/proof.txt; cat /data/proof.txt /tmp/proof.txt'
logged docker rm -f "$first"
logged docker run -d --name "$second" --mount "type=volume,source=$volume,target=/data" ubuntu:24.04 sleep infinity
logged docker exec "$second" sh -ec 'test ! -e /tmp/proof.txt; echo /tmp/proof.txt: absent; cat /data/proof.txt'
[[ $(docker exec "$second" cat /data/proof.txt) == VOLUME_OK ]]
logged docker stop "$ubuntu" "$second"
logged docker ps -a --filter "name=$prefix"

section 'Git 저장소와 기본 브랜치'
logged git init -b main
logged git config --local init.defaultBranch main
logged git config --local user.name 'Workstation Mission'
logged git config --local user.email 'workstation-mission@example.invalid'
logged git config --local --list
logged git branch --show-current

browser_evidence='[ ] 브라우저 주소창 캡처 첨부'
vscode_evidence='[ ] VS Code GitHub 로그인 및 연동 캡처 첨부'
github_evidence='[ ] GitHub 원격 저장소 생성 및 푸시'

if [[ -n $publish ]]; then
    logged git remote add origin "https://github.com/$publish.git"
    github_evidence="[ ] GitHub 저장소 생성 및 푸시 확인 대기 ([저장소](https://github.com/$publish))"
fi

capture_png() {
    local message=$1 target=$2 source signature
    while true; do
        printf '\n%s\n개인정보와 인증 정보가 보이지 않는지 확인하세요.\nPNG 파일의 절대 경로 (건너뛰려면 Enter): ' "$message" >&2
        IFS= read -r source || return 1
        [[ -n $source ]] || return 1
        # WSL 터미널에 Windows 탐색기에서 복사한 경로도 받을 수 있습니다.
        source=${source#\"}
        source=${source%\"}
        if [[ $source =~ ^[a-zA-Z]: ]] && command -v wslpath >/dev/null; then
            source=$(wslpath -u "$source") || continue
        fi
        if [[ -f $source && -r $source ]]; then
            signature=$(od -An -tx1 -N8 "$source" | tr -d '[:space:]')
            if [[ $signature == 89504e470d0a1a0a ]]; then
                cp -- "$source" "$target"
                return
            fi
        fi
        printf '읽을 수 있는 PNG 파일 경로를 입력하세요.\n' >&2
    done
}

if ((capture)); then
    if capture_png "브라우저에서 $url_one/ 을 열고 주소창과 페이지가 함께 보이게 캡처하세요." evidence/browser.png; then
        browser_evidence='[x] [브라우저 주소창 및 페이지](evidence/browser.png)'
    fi
    if capture_png "VS Code에서 이 폴더를 열고 GitHub에 로그인하세요. 계정명, 이메일, 토큰 등을 가린 뒤 로그인 및 저장소 연결이 보이는 화면을 캡처하세요.
결과 폴더: $root" evidence/vscode.png; then
        vscode_evidence='[x] [VS Code GitHub 로그인 및 연동](evidence/vscode.png)'
    fi
fi

write_readme() {
    cat > README.md <<EOF
# 개발 워크스테이션 구축

터미널과 Git으로 작업 환경을 구성하고, NGINX 정적 웹 서버를 Docker 이미지로 빌드해 포트 매핑, 바인드 마운트, 볼륨 영속성을 검증했다.

## 실행 환경

- OS 및 아키텍처: $os
- 셸: Bash $BASH_VERSION
- 터미널 정보: ${TERM:-unknown}
- Docker: $docker_version
- Git: $git_version

## 수행 결과

- [x] 터미널 조작과 파일·디렉터리 권한 실습
- [x] Docker 엔진 점검, hello-world, Ubuntu 내부 명령 및 컨테이너 운영
- [x] [Dockerfile](Dockerfile)과 [웹 소스](app/index.html) 빌드 및 실행
- [x] 두 포트에서 HTTP 응답 확인 (\`$url_one/\`, \`$url_two/\`)
- [x] 호스트 파일 변경 반영과 Docker 볼륨 데이터 유지 확인
- [x] 저장소 범위 Git 사용자 정보와 기본 브랜치 설정
- $browser_evidence
- $vscode_evidence
- $github_evidence

[전체 명령과 출력](evidence/terminal.txt)에서 각 검증의 실제 결과를 볼 수 있다. 로그의 \`<MISSION_DIR>\`와 \`<TEMP_DIR>\`는 실행 환경의 경로를 가린 표시다.

## 검증과 재현

Docker의 Linux 엔진을 시작하고 이 저장소의 루트에서 실행한다. Windows에서는 Docker Desktop의 WSL2 통합을 켜고 WSL2 셸에서 실행한다. macOS에서는 Docker Desktop이나 OrbStack을 사용할 수 있다. 사용 중인 호스트 포트는 다른 번호로 바꾼다.

[실습 실행 파일](workstation-mission.sh)을 \`bash workstation-mission.sh\`로 실행하면 새 폴더에서 전체 검증을 재현할 수 있다. 아래 명령은 웹 서버만 확인할 때 사용한다.

~~~bash
docker build -t mission-web .
docker run --rm -d --name mission-web -p 127.0.0.1:$port_one:80 mission-web
curl -fsS $url_one/
docker logs mission-web
docker stats --no-stream mission-web
docker stop mission-web
~~~

- **터미널과 권한** · \`pwd\`로 절대 경로를 확인했다. \`notes.txt\`와 같은 상대 경로는 현재 디렉터리를 기준으로 해석한다. \`ls -ld\`로 파일의 600→644, 디렉터리의 700→755 변경을 확인했다. 소유자·그룹·기타 사용자마다 읽기(4), 쓰기(2), 실행(1)을 더한다. 디렉터리의 실행 권한은 내부 경로에 접근하는 데 필요하다.
- **이미지와 컨테이너** · \`nginx:alpine\`을 베이스로 선택했다. \`LABEL\`로 이미지 제목을 지정했고, \`COPY\`로 기본 페이지를 교체했다. 이미지는 실행에 필요한 파일과 설정을 담고, 컨테이너는 그 이미지에서 격리되어 실행되는 인스턴스다.
- **컨테이너 내부 명령** · \`docker exec\`로 실행 중인 Ubuntu 컨테이너에서 명령을 실행하고, 해당 명령이 끝나도 컨테이너가 실행 중임을 확인했다. \`docker start -a\`는 주 프로세스 출력에 연결되며, 이 실습의 일회성 주 프로세스가 끝나면 컨테이너도 종료된다.
- **포트 매핑** · 두 호스트 포트에 각각 컨테이너의 80번을 연결했다. \`curl\`로 두 주소에서 \`WORKSTATION_IMAGE_OK\`를 확인했다. 주소를 127.0.0.1에 바인딩해 같은 컴퓨터의 브라우저에서 접속한다.
- **바인드 마운트** · 두 번째 포트의 컨테이너를 교체해 \`bind-demo/\`를 읽기 전용으로 연결했다. 호스트 파일 수정 후 같은 컨테이너에서 \`BIND_BEFORE\`가 \`BIND_AFTER\`로 바뀌었고 첫 번째 포트의 이미지 콘텐츠는 그대로 제공됐다.
- **볼륨** · 이름 있는 볼륨을 만들고 첫 컨테이너의 \`/data\`에 기록했다. 컨테이너를 삭제하고 같은 볼륨을 새 컨테이너에 연결한 뒤 \`VOLUME_OK\`를 확인했다.
- **Git과 GitHub** · Git은 로컬에서 커밋과 브랜치를 관리한다. GitHub는 원격 저장소를 호스팅해 공유와 협업을 지원한다. Git 사용자 설정은 이 저장소에만 적용했다.

## 트러블슈팅 재현

| 문제 | 원인 가설 | 확인 | 해결 |
| --- | --- | --- | --- |
| 웹 요청이 404를 반환 | 요청한 파일이 웹 이미지에 없음 | \`curl\`로 \`/missing.html\`의 404 응답을 기록 | \`/\`로 요청하여 정적 페이지 응답 확인 |
| 컨테이너 교체 후 파일을 찾을 수 없음 | \`/tmp\` 파일을 컨테이너의 쓰기 계층에 저장 | 새 컨테이너의 \`/tmp/proof.txt\` 부재 확인 | 이름 있는 볼륨을 \`/data\`에 재연결해 \`proof.txt\` 읽기 |

두 사례는 검증을 위해 재현했다. 자세한 명령, 출력 및 비교 결과는 [터미널 로그](evidence/terminal.txt)에 있다.
EOF
}

write_readme
git add -- .dockerignore Dockerfile app bind-demo evidence README.md workstation-mission.sh
git -c commit.gpgsign=false commit -m 'Document verified workstation mission'

if [[ -n $publish ]]; then
    [[ -f evidence/browser.png && -f evidence/vscode.png ]] ||
        die '캡처 두 장이 필요합니다. 로컬 결과는 저장했습니다.'
    printf '\n%s 저장소와 커밋 내용을 공개하려면 공개를 입력하세요.\n' "$publish"
    printf 'README, 로그와 캡처에 공개하면 안 되는 정보가 없는지 확인하세요: '
    IFS= read -r answer
    if [[ $answer == 공개 ]]; then
        gh repo create "$publish" --public
        git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -u origin main
        github_evidence="[x] [GitHub 공개 저장소](https://github.com/$publish) 생성 및 main 브랜치 푸시"
        write_readme
        git add -- README.md
        git -c commit.gpgsign=false commit -m 'Link verified GitHub repository'
        git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push origin main
        printf '\n제출 링크: https://github.com/%s\n' "$publish"
    fi
fi

printf '\n결과 폴더: %s\nREADME.md에서 체크리스트 및 증거를 확인하세요.\n' "$root"
