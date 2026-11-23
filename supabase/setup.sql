-- GOLDSOLE · Supabase(PostgreSQL) 설정
-- 사용법: Supabase 대시보드 → SQL Editor → New query → 이 파일 전체를 붙여넣고 Run
-- (여러 번 실행해도 되도록 IF NOT EXISTS / DROP POLICY IF EXISTS 를 썼습니다)

-- 1) 주문 표 : status 칸이 주문의 현재 단계이고, 단계가 바뀔 때 UPDATE 합니다.
CREATE TABLE IF NOT EXISTS orders (
  order_id       text PRIMARY KEY,                    -- 예: GS261123-4560
  member_email   text NOT NULL,
  member_name    text NOT NULL,
  ordered_at     timestamptz NOT NULL DEFAULT now(),
  status         text NOT NULL DEFAULT '검수 대기',
  subtotal       integer NOT NULL,
  coupon_disc    integer NOT NULL DEFAULT 0,
  point_used     integer NOT NULL DEFAULT 0,
  shipping_fee   integer NOT NULL DEFAULT 0,
  paid           integer NOT NULL,
  point_earned   integer NOT NULL DEFAULT 0,
  pay_method     text NOT NULL,
  receiver       text NOT NULL,
  address        text NOT NULL,
  inspect_result text,                                -- 합격 / 불합격
  inspect_grade  text,                                -- S / A / B
  inspect_note   text,
  courier        text,
  tracking_no    text,
  refunded_at    timestamptz,
  refund_reason  text,
  updated_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_order_status CHECK (status IN
    ('검수 대기','검수 중','검수 합격','포장 중','배송중','배송 완료','취소 완료','환불 완료'))
);

CREATE TABLE IF NOT EXISTS order_items (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id  text NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  sku       text NOT NULL,                            -- 상품ID-사이즈 (예: p01-260)
  price     integer NOT NULL
);

-- 2) 단계 이력 : 상태가 바뀔 때마다 한 줄씩 쌓입니다.
CREATE TABLE IF NOT EXISTS order_status_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id    text NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
  status      text NOT NULL,
  note        text,
  changed_at  timestamptz NOT NULL DEFAULT now()
);

-- updated_at 자동 갱신
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_orders_touch ON orders;
CREATE TRIGGER trg_orders_touch BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- 3) 접근 규칙(RLS)
-- ⚠ 데모용입니다: 공개(anon) 키로 누구나 주문을 읽고, 만들고, 상태를 바꿀 수 있습니다. (삭제는 불가)
--   실제 운영 전에는 Supabase Auth 로그인 + "본인 주문만 조회, 상태 변경은 관리자만"으로 바꿔야 합니다.
ALTER TABLE orders           ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS demo_orders_select ON orders;
DROP POLICY IF EXISTS demo_orders_insert ON orders;
DROP POLICY IF EXISTS demo_orders_update ON orders;
CREATE POLICY demo_orders_select ON orders FOR SELECT TO anon USING (true);
CREATE POLICY demo_orders_insert ON orders FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY demo_orders_update ON orders FOR UPDATE TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS demo_items_select ON order_items;
DROP POLICY IF EXISTS demo_items_insert ON order_items;
CREATE POLICY demo_items_select ON order_items FOR SELECT TO anon USING (true);
CREATE POLICY demo_items_insert ON order_items FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS demo_log_select ON order_status_log;
DROP POLICY IF EXISTS demo_log_insert ON order_status_log;
CREATE POLICY demo_log_select ON order_status_log FOR SELECT TO anon USING (true);
CREATE POLICY demo_log_insert ON order_status_log FOR INSERT TO anon WITH CHECK (true);

-- 4) 확인용 쿼리
-- SELECT status, count(*) FROM orders GROUP BY status;
-- SELECT status, changed_at, note FROM order_status_log WHERE order_id = 'GS...' ORDER BY changed_at;
