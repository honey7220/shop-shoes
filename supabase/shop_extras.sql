-- ============================================================
-- GOLDSOLE 추가 SQL (shop_supabase.sql 을 먼저 실행한 뒤 이 파일을 실행합니다)
-- 기존 4개 표의 이름·열은 하나도 바꾸지 않습니다. 새로 만드는 것:
--   · shop_order_points : 주문마다 쓴 포인트 · 적립한 포인트 기록 (취소 때 되돌리려고)
--   · shop_grade_for / shop_grade_rate : 등급 기준 · 적립률 함수
--   · shop_settle_order : 결제 직후 재고 · 포인트 · 등급을 DB 안에서 반영
--   · shop_cancel_order : 주문 취소(재고 · 포인트 되돌림)
--   · 주문 상태 값 추가 : '검수중', '포장중' (shop_orders_status_check 만 넓힘. 표 · 열 이름은 그대로)
--   · 상품 12개 (예시 상품 6개는 주문이 없으면 삭제)
-- 왜 함수인가: shop_profiles 의 points · grade 는 보안 규칙상 회원이 직접 고칠 수 없습니다.
--              (shop_supabase.sql 에서 UPDATE 권한을 name, phone 에만 줬기 때문)
--              그래서 DB 안의 함수가 대신 계산해서 고칩니다. 화면에서 숫자를 보내도 믿지 않고 DB 의 값으로 다시 계산합니다.
-- 사용법: SQL Editor → New query → 전체 붙여넣기 → Run (두 번 실행해도 안전)
-- ============================================================

-- 0. 주문 상태 값 넓히기: 결제완료 → 검수중 → 포장중 → 배송중 → 배송완료 (취소는 어느 단계에서나 관리자가 가능)
ALTER TABLE public.shop_orders DROP CONSTRAINT IF EXISTS shop_orders_status_check;
ALTER TABLE public.shop_orders ADD CONSTRAINT shop_orders_status_check
  CHECK (status IN ('결제완료', '검수중', '포장중', '배송중', '배송완료', '취소'));

-- 1. 주문별 포인트 기록
CREATE TABLE IF NOT EXISTS public.shop_order_points (
  order_id   bigint PRIMARY KEY REFERENCES public.shop_orders(id) ON DELETE CASCADE,
  used       integer NOT NULL DEFAULT 0 CHECK (used >= 0),
  earned     integer NOT NULL DEFAULT 0 CHECK (earned >= 0),
  shipping   integer NOT NULL DEFAULT 0 CHECK (shipping >= 0),
  settled_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.shop_order_points ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shop_order_points FROM anon, authenticated;
GRANT SELECT ON public.shop_order_points TO authenticated;
DROP POLICY IF EXISTS shop_order_points_select ON public.shop_order_points;
CREATE POLICY shop_order_points_select ON public.shop_order_points FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.shop_orders o WHERE o.id = order_id AND (o.user_id = auth.uid() OR public.shop_is_admin())));

-- 2. 등급 기준 (쇼핑몰 화면의 TIERS 와 같은 금액) · 적립률
CREATE OR REPLACE FUNCTION public.shop_grade_for(p_total bigint) RETURNS text
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE WHEN p_total >= 10000000 THEN 'VIP'
              WHEN p_total >=  3000000 THEN 'GOLD'
              WHEN p_total >=  1000000 THEN 'SILVER'
              ELSE 'WELCOME' END;
$fn$;

CREATE OR REPLACE FUNCTION public.shop_grade_rate(p_grade text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE p_grade WHEN 'VIP' THEN 12 WHEN 'GOLD' THEN 5 WHEN 'SILVER' THEN 3 ELSE 1 END;
$fn$;

-- 3. 결제 직후 반영: 재고 차감 · 포인트 사용/적립 · 등급 갱신 (한 트랜잭션)
CREATE OR REPLACE FUNCTION public.shop_settle_order(p_order_id bigint, p_use_points integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid  uuid := auth.uid();
  v_ord  public.shop_orders;
  v_prof public.shop_profiles;
  v_use  integer := coalesce(p_use_points, 0);
  v_sub  integer; v_ship integer; v_total integer; v_earn integer; v_bad integer; v_sum bigint;
  r record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_ord FROM public.shop_orders WHERE id = p_order_id AND user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '내 주문이 아닙니다' USING ERRCODE = '42501'; END IF;
  IF EXISTS (SELECT 1 FROM public.shop_order_points WHERE order_id = p_order_id) THEN
    RAISE EXCEPTION '이미 처리된 주문입니다';
  END IF;
  SELECT * INTO v_prof FROM public.shop_profiles WHERE id = v_uid FOR UPDATE;

  SELECT coalesce(sum(qty * unit_price), 0) INTO v_sub FROM public.shop_order_items WHERE order_id = p_order_id;
  IF v_sub = 0 THEN RAISE EXCEPTION '주문 상품이 없습니다'; END IF;

  -- 사이즈별 가격 차이(-5% ~ +7%)까지만 허용: 화면에서 보낸 단가를 그대로 믿지 않는다
  SELECT count(*) INTO v_bad FROM public.shop_order_items i JOIN public.shop_products p ON p.id = i.product_id
   WHERE i.order_id = p_order_id AND (i.unit_price < p.price * 0.9 OR i.unit_price > p.price * 1.1);
  IF v_bad > 0 THEN RAISE EXCEPTION '상품 가격이 맞지 않습니다'; END IF;

  IF v_use < 0 OR v_use > v_prof.points OR v_use > v_sub OR (v_use > 0 AND (v_use < 1000 OR v_use % 100 <> 0)) THEN
    RAISE EXCEPTION '포인트 사용 값이 올바르지 않습니다 (1,000P 이상, 100P 단위, 보유 한도 이내)';
  END IF;

  v_ship  := CASE WHEN v_prof.grade = 'WELCOME' AND v_sub < 500000 THEN 3000 ELSE 0 END;
  v_total := v_sub - v_use + v_ship;
  v_earn  := floor((v_sub - v_use) * public.shop_grade_rate(v_prof.grade) / 100.0)::integer;

  FOR r IN SELECT product_id, qty FROM public.shop_order_items WHERE order_id = p_order_id LOOP
    UPDATE public.shop_products SET stock = stock - r.qty WHERE id = r.product_id AND stock >= r.qty;
    IF NOT FOUND THEN RAISE EXCEPTION '재고가 부족합니다 (상품 #%)', r.product_id; END IF;
  END LOOP;

  UPDATE public.shop_orders SET total = v_total WHERE id = p_order_id;
  INSERT INTO public.shop_order_points (order_id, used, earned, shipping) VALUES (p_order_id, v_use, v_earn, v_ship);

  SELECT coalesce(sum(total), 0) INTO v_sum FROM public.shop_orders WHERE user_id = v_uid AND status <> '취소';
  UPDATE public.shop_profiles
     SET points = points - v_use + v_earn, grade = public.shop_grade_for(v_sum)
   WHERE id = v_uid RETURNING * INTO v_prof;

  RETURN jsonb_build_object('order_id', p_order_id, 'total', v_total, 'used', v_use, 'earned', v_earn,
                            'shipping', v_ship, 'points', v_prof.points, 'grade', v_prof.grade);
END;
$fn$;

-- 4. 주문 취소: 본인은 '결제완료'(검수 시작 전)일 때만, 관리자는 배송중까지. 재고 · 포인트 · 등급을 되돌린다
CREATE OR REPLACE FUNCTION public.shop_cancel_order(p_order_id bigint)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_ord public.shop_orders;
  v_pt  public.shop_order_points;
  v_sum bigint;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION '로그인이 필요합니다' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_ord FROM public.shop_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '주문을 찾을 수 없습니다'; END IF;
  IF NOT (v_ord.user_id = v_uid OR public.shop_is_admin()) THEN RAISE EXCEPTION '권한이 없습니다' USING ERRCODE = '42501'; END IF;
  IF v_ord.status = '취소' THEN RAISE EXCEPTION '이미 취소된 주문입니다'; END IF;
  IF v_ord.status = '배송완료' THEN RAISE EXCEPTION '배송이 끝난 주문은 취소할 수 없습니다'; END IF;
  IF v_ord.status <> '결제완료' AND NOT public.shop_is_admin() THEN RAISE EXCEPTION '검수가 시작된 주문은 취소할 수 없습니다'; END IF;

  SELECT * INTO v_pt FROM public.shop_order_points WHERE order_id = p_order_id;
  IF FOUND THEN
    UPDATE public.shop_products p SET stock = p.stock + i.qty
      FROM public.shop_order_items i WHERE i.order_id = p_order_id AND p.id = i.product_id;
    UPDATE public.shop_profiles SET points = greatest(0, points + v_pt.used - v_pt.earned) WHERE id = v_ord.user_id;
  END IF;
  UPDATE public.shop_orders SET status = '취소' WHERE id = p_order_id;
  SELECT coalesce(sum(total), 0) INTO v_sum FROM public.shop_orders WHERE user_id = v_ord.user_id AND status <> '취소';
  UPDATE public.shop_profiles SET grade = public.shop_grade_for(v_sum) WHERE id = v_ord.user_id;
END;
$fn$;

-- 5. 함수 권한: 로그인한 회원만 부를 수 있다
REVOKE EXECUTE ON FUNCTION public.shop_settle_order(bigint, integer) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.shop_cancel_order(bigint)          FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.shop_settle_order(bigint, integer) TO authenticated;
GRANT  EXECUTE ON FUNCTION public.shop_cancel_order(bigint)          TO authenticated;

-- 6. 쇼핑몰 상품 12개 (이름 · 분류=브랜드 · 가격 · 재고 · 이미지). 예시 상품 6개는 주문이 없을 때만 지웁니다.
DELETE FROM public.shop_products
 WHERE name LIKE '예시 상품%'
   AND NOT EXISTS (SELECT 1 FROM public.shop_order_items i WHERE i.product_id = shop_products.id);

INSERT INTO public.shop_products (name, category, price, stock, image_url)
SELECT v.name, v.category, v.price, v.stock, v.image_url
FROM (VALUES
  ('Lo-1 ‘블랙 옐로’', 'AERO', 1290000, 30, 'img/p01_left.png'),
  ('Lo-1 ‘크림슨 코트’', 'AERO', 890000, 30, 'img/p02.png'),
  ('Pulse ‘코발트 펄스’', 'KINETIC', 540000, 33, 'img/p03.png'),
  ('Grove ‘포레스트 크림’', 'NOVA', 420000, 27, 'img/p04.png'),
  ('Dune ‘모카 크림’', 'VOLT', 380000, 31, 'img/p05.png'),
  ('Pulse ‘로열 퍼플’', 'KINETIC', 610000, 28, 'img/p06.png'),
  ('Classic ‘에스프레소 크림’', 'AERO', 460000, 33, 'img/p07.png'),
  ('Blaze ‘블랙 오렌지’', 'VOLT', 350000, 30, 'img/p08.png'),
  ('Stride ‘버건디 샌드’', 'NOVA', 330000, 0, 'img/p09.png'),
  ('Bloom ‘로즈 핑크’', 'NOVA', 520000, 27, 'img/p10.png'),
  ('Lo-1 ‘미드나잇 옐로’', 'AERO', 1650000, 24, 'img/p11_left.png'),
  ('Chrome ‘크롬 실버’', 'KINETIC', 720000, 30, 'img/p12.png')
) AS v(name, category, price, stock, image_url)
WHERE NOT EXISTS (SELECT 1 FROM public.shop_products x WHERE x.name = v.name);

-- 끝. 확인: SELECT id, name, category, price, stock, image_url FROM public.shop_products ORDER BY id;
