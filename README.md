# Bike Ride

엑사이더 ES370 실내자전거(제조 XIAMEN KSTAR SPORTS)를 Web Bluetooth로 연결하는 웹 앱이에요. 파일은 `index.html` 하나뿐이에요.

## 지원 프로토콜
- **FTMS** (0x1826) Indoor Bike Data: 속도, 케이던스, 거리, 저항, 파워, 칼로리, 심박. Control Point로 시작, 정지, 저항 조절도 해요.
- **CSC** (0x1816): 속도와 케이던스
- **Cycling Power** (0x1818), **Heart Rate** (0x180D)
- 표준 방식이 아니면 '개발자 / 기기 탐색'에 서비스 목록과 수신 데이터(hex)가 표시돼요. 이 로그로 전용 프로토콜을 분석할 수 있어요.

## 아이폰에서 쓰는 법
1. App Store에서 **Bluefy – Web BLE Browser**를 설치해요. 사파리는 Web Bluetooth를 지원하지 않아요.
2. HTTPS로 호스팅된 이 페이지를 Bluefy로 열어요. GitHub Pages를 쓰면 돼요.
3. 자전거를 켜고 페달을 몇 번 돌려 깨운 뒤 '자전거 연결'을 눌러요.

운동 기록은 브라우저 localStorage에 저장되고, CSV로 내보낼 수 있어요.
