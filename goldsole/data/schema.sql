-- GOLDSOLE 데이터 구조: 상품 표(1) - 재고 표(N) - 입출고 기록
-- index.html의 PRODUCTS / inventory / stockLog 와 같은 구조입니다.

CREATE TABLE products (
  product_id    VARCHAR(10)  PRIMARY KEY,          -- 예: p01
  brand         VARCHAR(30)  NOT NULL,
  model         VARCHAR(50)  NOT NULL,
  colorway      VARCHAR(50)  NOT NULL,
  retail_price  INT          NOT NULL,             -- 발매가
  base_price    INT          NOT NULL,             -- 기준 판매가(리셀)
  limited_qty   INT          NOT NULL,             -- 한정 발매 수량
  release_year  SMALLINT     NOT NULL
);

CREATE TABLE inventory (
  sku         VARCHAR(20) PRIMARY KEY,             -- 상품ID-사이즈 (예: p01-260)
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
  type        VARCHAR(10) NOT NULL,                -- 판매 / 조정
  delta       INT         NOT NULL,                -- 재고 증감
  note        VARCHAR(100)                         -- 주문번호 등
);

-- 상품별 총 재고
SELECT p.product_id, p.brand, p.model, p.colorway, SUM(i.stock) AS total_stock
FROM products p JOIN inventory i ON i.product_id = p.product_id
GROUP BY p.product_id, p.brand, p.model, p.colorway;

-- 품절/부족 사이즈 (재고 2켤레 이하)
SELECT sku, size, stock FROM inventory WHERE stock <= 2 ORDER BY stock, sku;
