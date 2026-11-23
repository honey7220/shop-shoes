-- GOLDSOLE 데이터 구조 (index.html 의 PRODUCTS / inventory / users / orders 와 같은 구조)
-- 상품 표(1) - 재고 표(N, 사이즈별) / 회원 - 주문 - 주문상품 / 포인트 적립 건 / 쿠폰 / 리뷰

CREATE TABLE products (
  product_id    VARCHAR(10)  PRIMARY KEY,          -- 예: p01
  brand         VARCHAR(30)  NOT NULL,
  model         VARCHAR(50)  NOT NULL,
  colorway      VARCHAR(50)  NOT NULL,
  material      VARCHAR(100),                      -- 소재
  outsole       VARCHAR(100),                      -- 밑창
  description   TEXT,                              -- 상세 설명
  retail_price  INT          NOT NULL,             -- 발매가
  base_price    INT          NOT NULL,             -- 기준 판매가(리셀)
  limited_qty   INT          NOT NULL,             -- 한정 발매 수량
  release_year  SMALLINT     NOT NULL
);

CREATE TABLE inventory (
  sku         VARCHAR(20) PRIMARY KEY,             -- 상품ID-사이즈 (예: p01-260), 230~290 5mm 단위
  product_id  VARCHAR(10) NOT NULL REFERENCES products(product_id),
  size        SMALLINT    NOT NULL,                -- mm
  stock       INT         NOT NULL DEFAULT 0 CHECK (stock >= 0),
  price       INT         NOT NULL,                -- 사이즈별 즉시구매가
  UNIQUE (product_id, size)
);

CREATE TABLE stock_log (
  log_id      INT AUTO_INCREMENT PRIMARY KEY,
  logged_at   DATETIME    NOT NULL,
  sku         VARCHAR(20) NOT NULL REFERENCES inventory(sku),
  type        VARCHAR(10) NOT NULL,                -- 판매 / 조정 / 취소
  delta       INT         NOT NULL,                -- 재고 증감
  note        VARCHAR(100)                         -- 주문번호 등
);

CREATE TABLE members (
  member_id    INT AUTO_INCREMENT PRIMARY KEY,
  email        VARCHAR(100) UNIQUE NOT NULL,
  name         VARCHAR(50)  NOT NULL,
  phone        VARCHAR(20)  NOT NULL,
  pw_salt      VARCHAR(40)  NOT NULL,
  pw_hash      VARCHAR(100) NOT NULL,              -- 비밀번호는 해시로만 저장
  total_spent  INT NOT NULL DEFAULT 0,             -- 누적 구매금액(등급 기준)
  marketing    BOOLEAN NOT NULL DEFAULT FALSE,
  joined_at    DATE NOT NULL
);

CREATE TABLE orders (
  order_id      VARCHAR(20) PRIMARY KEY,           -- 예: GS261123-4560
  member_id     INT NOT NULL REFERENCES members(member_id),
  ordered_at    DATETIME NOT NULL,
  status        VARCHAR(10) NOT NULL,              -- 검수 대기/검수 중/검수 합격/배송중/배송 완료/취소 완료/환불 완료
  subtotal      INT NOT NULL,
  coupon_disc   INT NOT NULL DEFAULT 0,
  point_used    INT NOT NULL DEFAULT 0,
  shipping_fee  INT NOT NULL DEFAULT 0,
  paid          INT NOT NULL,                      -- 결제 금액
  point_earned  INT NOT NULL DEFAULT 0,
  pay_method    VARCHAR(20) NOT NULL,
  receiver      VARCHAR(50) NOT NULL,
  address       VARCHAR(200) NOT NULL,
  inspect_result VARCHAR(10),                      -- 합격 / 불합격
  inspect_grade  CHAR(1),                          -- S / A / B
  inspect_note   VARCHAR(200),
  courier       VARCHAR(20),
  tracking_no   VARCHAR(30),
  refunded_at   DATETIME,
  refund_reason VARCHAR(50)
);

CREATE TABLE order_items (
  order_id  VARCHAR(20) NOT NULL REFERENCES orders(order_id),
  sku       VARCHAR(20) NOT NULL REFERENCES inventory(sku),
  price     INT NOT NULL,                          -- 주문 시점 가격
  PRIMARY KEY (order_id, sku)
);

CREATE TABLE point_lots (                          -- 적립 건마다 유효기간을 둠
  lot_id     INT AUTO_INCREMENT PRIMARY KEY,
  member_id  INT NOT NULL REFERENCES members(member_id),
  source     VARCHAR(20) NOT NULL,                 -- 가입 보너스 / 구매 적립 / 리뷰 작성 / 환불 복원
  amount     INT NOT NULL,
  remaining  INT NOT NULL,
  expires_on DATE NOT NULL                         -- 구매 1년, 가입 3개월, 리뷰 1년
);

CREATE TABLE coupons (
  coupon_id  INT AUTO_INCREMENT PRIMARY KEY,
  member_id  INT NOT NULL REFERENCES members(member_id),
  name       VARCHAR(50) NOT NULL,
  discount   INT NOT NULL,
  min_order  INT NOT NULL,
  expires_on DATE NOT NULL,
  used_order VARCHAR(20) REFERENCES orders(order_id)
);

CREATE TABLE reviews (
  review_id  INT AUTO_INCREMENT PRIMARY KEY,
  order_id   VARCHAR(20) NOT NULL REFERENCES orders(order_id),
  sku        VARCHAR(20) NOT NULL REFERENCES inventory(sku),
  member_id  INT NOT NULL REFERENCES members(member_id),
  rating     TINYINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body       VARCHAR(300) NOT NULL,
  written_on DATE NOT NULL,
  UNIQUE (order_id, sku)                           -- 주문 상품당 리뷰 1건
);

-- 상품별 총 재고
SELECT p.product_id, p.brand, p.model, p.colorway, SUM(i.stock) AS total_stock
FROM products p JOIN inventory i ON i.product_id = p.product_id
GROUP BY p.product_id, p.brand, p.model, p.colorway;

-- 품절/부족 사이즈 (재고 2켤레 이하)
SELECT sku, size, stock FROM inventory WHERE stock <= 2 ORDER BY stock, sku;

-- 30일 안에 소멸하는 포인트
SELECT member_id, SUM(remaining) AS expiring
FROM point_lots
WHERE remaining > 0 AND expires_on BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 30 DAY
GROUP BY member_id;

-- 처리가 필요한 주문
SELECT order_id, status, ordered_at FROM orders
WHERE status IN ('검수 대기','검수 중','검수 합격','배송중') ORDER BY ordered_at;

-- 상품별 평균 평점
SELECT p.product_id, p.model, p.colorway, ROUND(AVG(r.rating), 1) AS avg_rating, COUNT(*) AS reviews
FROM reviews r JOIN inventory i ON i.sku = r.sku JOIN products p ON p.product_id = i.product_id
GROUP BY p.product_id, p.model, p.colorway;
