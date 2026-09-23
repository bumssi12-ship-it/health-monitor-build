# Health Monitor Web Viewer

Health Monitor의 JSON 백업과 CSV export를 Android, Windows, macOS 등 현대 브라우저에서 확인하기 위한 정적 PWA입니다.

## 개인정보 원칙

- 건강 파일은 브라우저의 `File` API로 로컬에서 읽습니다.
- 서버 업로드 API, analytics, 광고 SDK, 외부 JavaScript CDN을 사용하지 않습니다.
- 기본적으로 데이터는 메모리에만 존재하며 새로고침하면 사라집니다.
- 저장소와 웹 배포물에는 실제 건강 데이터를 포함하지 않습니다.

## 지원 파일

- `HealthMonitor-UserBackup-*.json`
- `summary.json`
- `health_samples.csv`
- `daily_metrics.csv`
- `symptoms.csv`
- `orthostatic_sessions.csv`
- `medications.csv`
- `report_7days.txt`

## Android

GitHub Pages로 배포한 URL을 Chrome에서 열고 브라우저 메뉴의 **홈 화면에 추가 / 앱 설치**를 사용하면 독립 실행형 PWA처럼 사용할 수 있습니다.

Apple Health/HealthKit 데이터는 Android나 일반 웹 브라우저에서 직접 읽을 수 없습니다. Health Monitor iPhone 앱에서 export한 파일을 이 뷰어에 불러오는 방식입니다.
