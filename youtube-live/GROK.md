# Grok 봇 실행 지시문: ODDBOUT YouTube Live 송출 테스트

아래 내용을 Grok 봇에 그대로 붙여넣는다. 봇이 명령을 실행할 수 있는 Linux 환경을 갖고 있어야 한다.

---

너는 Linux 셸에서 ODDBOUT 에이전트 exhibition 화면을 YouTube Live로 송출하는 테스트를 수행한다. 각 단계의 명령과 출력 요약을 보고하고, 실패하면 거기서 멈추고 원인을 보고한다.

규칙:
- `YOUTUBE_STREAM_KEY` 값을 출력·로그·파일·대화에 절대 쓰지 않는다. `set -x`, `env`, `printenv`를 실행하지 않는다.
- 저장소 코드를 수정하지 않는다. 시스템 설치는 `youtube-live/setup.sh`만 사용한다.
- 4단계(공개 송출)는 내가 "송출 시작"이라고 말하기 전에는 실행하지 않는다.

1. 저장소 가져오기 (공개 저장소)
   ```sh
   git clone https://github.com/jeonghwanko/oddbout-youtube-live.git
   cd oddbout-youtube-live
   ```
2. 환경 점검과 준비
   ```sh
   youtube-live/preflight.sh      # 표 전체를 보고
   youtube-live/setup.sh          # 마지막 RESULT 줄을 보고
   ```
   `rtmps-443`이나 `background`가 FAIL이면 이 환경에서는 송출할 수 없다. 이유와 함께 멈춘다.
3. 키 없이 리허설 (약 3분, 녹화만)
   ```sh
   youtube-live/run.sh --record=170 --cups=1
   ls -la youtube-live/recordings/
   ffmpeg -v error -ss 120 -i youtube-live/recordings/*.mkv -frames:v 1 youtube-live/recordings/check.png
   ```
   runner 로그의 `"event":"cup"` 줄(우승자·digest)과 녹화 파일 크기를 보고하고, 가능하면 `check.png`를 보여준다. OBS가 바로 종료되면 `--encoder=ffmpeg`로 다시 시도하고 둘 중 어느 쪽이 됐는지 보고한다.
4. 공개 송출 ("송출 시작" 지시 후에만)
   ```sh
   export YOUTUBE_STREAM_KEY='<내가 따로 전달한 키>'
   youtube-live/run.sh                     # 또는 --encoder=ffmpeg (3단계에서 성공한 쪽)
   ```
   송출은 내가 멈추라고 할 때까지 유지한다. 실행 시간 제한이나 네트워크 차단으로 끊기면 끊긴 시각과 마지막 로그를 보고한다. 종료는 Ctrl-C(SIGINT)로 한다.

보고 형식: 단계별 PASS/FAIL, preflight 표, 사용한 encoder, 경기 결과 줄, 오류 마지막 30줄.
