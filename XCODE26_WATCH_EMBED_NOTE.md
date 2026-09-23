# Xcode 26 watchOS embed compatibility

2026년 현재 XcodeGen 2.46.0이 최신 안정판이지만,
Xcode 26에서 companion watchOS app을 legacy `Watch/` 위치에 embed하면
설치 실패가 발생할 수 있다는 공개 이슈가 남아 있습니다.

V5의 `project.yml`은 생성 후:
`scripts/patch_xcode26_watch_embed.py`

를 자동 실행합니다.

Xcode 26 이상:
- Embed Watch Content
- `dstSubfolderSpec = 13`
- `dstPath = ""`

로 보정하여 parent iOS app의 `PlugIns/` 위치를 사용합니다.

Xcode 25 이하로 감지되면 자동 패치를 하지 않습니다.
