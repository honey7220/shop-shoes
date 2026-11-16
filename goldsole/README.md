# GOLDSOLE

한정판 스니커 리셀 쇼핑몰 (단일 `index.html` + `img/`).

- 회원가입/로그인, 장바구니, 결제(체험용), 등급별 포인트 적립
- **상품 표 / 재고 표 분리**: 사이즈별 재고(SKU), 주문 시 재고 차감, 품절 표시, 입출고 기록
- 관리자 재고 화면: 푸터의 `재고 관리 (관리자)` (데모 비밀번호는 `index.html`의 `ADMIN_PASS`)
- `data/` : `schema.sql`(표 설계), `products.csv`, `inventory.csv`(초기 데이터)

데이터는 브라우저 localStorage에 저장되는 체험용입니다. 실제 운영 시 서버·DB와 PG 연동이 필요합니다.
