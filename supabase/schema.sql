-- Monya Auto Spares: Phase 1 Supabase schema
-- Apply this script in the Supabase SQL Editor on a new project.
-- This creates the database foundation and read policies. Live stock-changing
-- operations remain disabled until audited transactional RPC functions are added.

begin;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

-- One shop location, configured for Kenya.
create table if not exists public.shops (
  id smallint primary key check (id = 1),
  shop_name text not null,
  currency_code text not null default 'KES' check (currency_code = 'KES'),
  timezone text not null default 'Africa/Nairobi',
  created_at timestamptz not null default now()
);

insert into public.shops (id, shop_name, currency_code, timezone)
values (1, 'Monya Auto Spares', 'KES', 'Africa/Nairobi')
on conflict (id) do nothing;

-- A profile is created for each Supabase Auth user. New accounts default to
-- employee; promote the shop owner only through a trusted admin process.
create table if not exists public.user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  shop_id smallint not null default 1 references public.shops(id),
  display_name text not null,
  role text not null default 'employee' check (role in ('owner', 'employee')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_profiles (user_id, display_name, role)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(split_part(coalesce(new.email, 'employee'), '@', 1), ''),
      'Employee'
    ),
    'employee'
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_monya on auth.users;
create trigger on_auth_user_created_monya
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create or replace function private.is_active_user()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.is_active = true
  );
$$;

create or replace function private.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles p
    where p.user_id = (select auth.uid())
      and p.role = 'owner'
      and p.is_active = true
  );
$$;

revoke all on function private.handle_new_auth_user() from public, anon, authenticated;
revoke all on function private.is_active_user() from public, anon;
revoke all on function private.is_owner() from public, anon;
grant execute on function private.is_active_user() to authenticated;
grant execute on function private.is_owner() to authenticated;

-- Master data.
create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, name)
);

create unique index if not exists product_categories_shop_lower_name_idx
  on public.product_categories (shop_id, lower(name));

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  supplier_name text not null,
  contact_person text,
  phone text,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  sku text,
  product_name text not null,
  category_id uuid references public.product_categories(id) on delete set null,
  brand text,
  vehicle_fitment text,
  unit_name text not null default 'piece',
  buying_price numeric(14,2) not null default 0 check (buying_price >= 0),
  selling_price numeric(14,2) not null default 0 check (selling_price >= 0),
  low_stock_threshold integer not null default 0 check (low_stock_threshold >= 0),
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, sku)
);

create index if not exists products_shop_name_idx
  on public.products (shop_id, product_name);
create index if not exists products_category_idx
  on public.products (category_id);

-- Purchase records. Actual receiving/stock posting will be performed only by a
-- later transactional function, not by direct client writes.
create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  supplier_id uuid references public.suppliers(id) on delete set null,
  supplier_invoice_number text,
  purchase_date date not null default (now() at time zone 'Africa/Nairobi')::date,
  status text not null default 'draft'
    check (status in ('draft', 'received', 'cancelled')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  received_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists purchases_shop_date_idx
  on public.purchases (shop_id, purchase_date desc);

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  line_total numeric(16,2) generated always as (quantity * unit_cost) stored,
  created_at timestamptz not null default now()
);

create index if not exists purchase_items_purchase_idx
  on public.purchase_items (purchase_id);
create index if not exists purchase_items_product_idx
  on public.purchase_items (product_id);

-- Sales store the employee and client-generated idempotency key. Price and cost
-- are snapshotted on each sale line so later price changes do not rewrite profit.
create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  client_transaction_id uuid not null default gen_random_uuid(),
  created_by uuid not null default auth.uid() references auth.users(id),
  sold_at timestamptz not null default now(),
  status text not null default 'completed'
    check (status in ('completed', 'voided')),
  payment_method text not null default 'cash'
    check (payment_method in ('cash', 'mpesa', 'bank', 'credit', 'other')),
  customer_name text,
  customer_phone text,
  notes text,
  created_at timestamptz not null default now(),
  unique (shop_id, client_transaction_id)
);

create index if not exists sales_shop_sold_at_idx
  on public.sales (shop_id, sold_at desc);
create index if not exists sales_employee_sold_at_idx
  on public.sales (created_by, sold_at desc);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(16,2) generated always as (quantity * unit_price) stored,
  cost_total numeric(16,2) generated always as (quantity * unit_cost) stored,
  gross_profit numeric(16,2) generated always as (quantity * (unit_price - unit_cost)) stored,
  created_at timestamptz not null default now()
);

create index if not exists sale_items_sale_idx on public.sale_items (sale_id);
create index if not exists sale_items_product_idx on public.sale_items (product_id);

-- Append-only stock ledger. quantity_delta is positive for stock in and
-- negative for stock out. On-hand balances are derived from this ledger.
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  product_id uuid not null references public.products(id),
  movement_type text not null
    check (movement_type in ('opening', 'purchase', 'sale', 'adjustment', 'sale_void', 'purchase_return')),
  quantity_delta integer not null check (quantity_delta <> 0),
  reference_type text,
  reference_id uuid,
  quantity_before integer check (quantity_before is null or quantity_before >= 0),
  quantity_after integer check (quantity_after is null or quantity_after >= 0),
  reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists stock_movements_product_time_idx
  on public.stock_movements (shop_id, product_id, created_at desc);
create index if not exists stock_movements_reference_idx
  on public.stock_movements (reference_type, reference_id);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  shop_id smallint not null default 1 references public.shops(id),
  actor_user_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create index if not exists audit_logs_shop_time_idx
  on public.audit_logs (shop_id, created_at desc);

-- Keep updated_at current on editable master/header records.
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

drop trigger if exists user_profiles_set_updated_at on public.user_profiles;
create trigger user_profiles_set_updated_at before update on public.user_profiles
for each row execute function private.set_updated_at();

drop trigger if exists product_categories_set_updated_at on public.product_categories;
create trigger product_categories_set_updated_at before update on public.product_categories
for each row execute function private.set_updated_at();

drop trigger if exists suppliers_set_updated_at on public.suppliers;
create trigger suppliers_set_updated_at before update on public.suppliers
for each row execute function private.set_updated_at();

drop trigger if exists products_set_updated_at on public.products;
create trigger products_set_updated_at before update on public.products
for each row execute function private.set_updated_at();

drop trigger if exists purchases_set_updated_at on public.purchases;
create trigger purchases_set_updated_at before update on public.purchases
for each row execute function private.set_updated_at();

-- RLS is enabled on every exposed table.
alter table public.shops enable row level security;
alter table public.user_profiles enable row level security;
alter table public.product_categories enable row level security;
alter table public.suppliers enable row level security;
alter table public.products enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.audit_logs enable row level security;

-- Shops: active shop users can read the single shop profile.
drop policy if exists shops_read_active_users on public.shops;
create policy shops_read_active_users on public.shops
for select to authenticated
using ((select private.is_active_user()));

-- Profiles: users can read their own profile; owner can read/manage all profiles.
drop policy if exists profiles_read_self_or_owner on public.user_profiles;
create policy profiles_read_self_or_owner on public.user_profiles
for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_owner()));

drop policy if exists profiles_owner_update on public.user_profiles;
create policy profiles_owner_update on public.user_profiles
for update to authenticated
using ((select private.is_owner()))
with check ((select private.is_owner()));

-- Active staff can see product categories and product catalogue.
drop policy if exists categories_read_active_users on public.product_categories;
create policy categories_read_active_users on public.product_categories
for select to authenticated
using ((select private.is_active_user()));

drop policy if exists categories_owner_insert on public.product_categories;
create policy categories_owner_insert on public.product_categories
for insert to authenticated
with check ((select private.is_owner()));

drop policy if exists categories_owner_update on public.product_categories;
create policy categories_owner_update on public.product_categories
for update to authenticated
using ((select private.is_owner()))
with check ((select private.is_owner()));

drop policy if exists categories_owner_delete on public.product_categories;
create policy categories_owner_delete on public.product_categories
for delete to authenticated
using ((select private.is_owner()));

drop policy if exists products_read_active_users on public.products;
create policy products_read_active_users on public.products
for select to authenticated
using ((select private.is_active_user()));

drop policy if exists products_owner_insert on public.products;
create policy products_owner_insert on public.products
for insert to authenticated
with check ((select private.is_owner()));

drop policy if exists products_owner_update on public.products;
create policy products_owner_update on public.products
for update to authenticated
using ((select private.is_owner()))
with check ((select private.is_owner()));

drop policy if exists products_owner_delete on public.products;
create policy products_owner_delete on public.products
for delete to authenticated
using ((select private.is_owner()));

-- Supplier and purchasing records are owner-readable in this foundation.
-- No client write policy exists until stock-receiving RPC is implemented.
drop policy if exists suppliers_owner_read on public.suppliers;
create policy suppliers_owner_read on public.suppliers
for select to authenticated
using ((select private.is_owner()));

drop policy if exists purchases_owner_read on public.purchases;
create policy purchases_owner_read on public.purchases
for select to authenticated
using ((select private.is_owner()));

drop policy if exists purchase_items_owner_read on public.purchase_items;
create policy purchase_items_owner_read on public.purchase_items
for select to authenticated
using (
  exists (
    select 1 from public.purchases p
    where p.id = purchase_id
      and (select private.is_owner())
  )
);

-- Employees can read their own sales; owner can read all shop sales.
drop policy if exists sales_read_own_or_owner on public.sales;
create policy sales_read_own_or_owner on public.sales
for select to authenticated
using (
  (select private.is_owner())
  or (
    created_by = (select auth.uid())
    and (select private.is_active_user())
  )
);

drop policy if exists sale_items_read_parent_sale on public.sale_items;
create policy sale_items_read_parent_sale on public.sale_items
for select to authenticated
using (
  exists (
    select 1 from public.sales s
    where s.id = sale_id
      and (
        (select private.is_owner())
        or s.created_by = (select auth.uid())
      )
  )
);

-- Staff can read the stock ledger; there are deliberately no client write policies.
drop policy if exists stock_movements_read_active_users on public.stock_movements;
create policy stock_movements_read_active_users on public.stock_movements
for select to authenticated
using ((select private.is_active_user()));

-- Audit trail is owner-only.
drop policy if exists audit_logs_owner_read on public.audit_logs;
create policy audit_logs_owner_read on public.audit_logs
for select to authenticated
using ((select private.is_owner()));

-- Remove broad default API access, then grant only operations expected at this stage.
revoke all on public.shops, public.user_profiles, public.product_categories,
  public.suppliers, public.products, public.purchases, public.purchase_items,
  public.sales, public.sale_items, public.stock_movements, public.audit_logs
from anon, authenticated;

grant select on public.shops to authenticated;
grant select, update on public.user_profiles to authenticated;
grant select, insert, update, delete on public.product_categories to authenticated;
grant select on public.suppliers to authenticated;
grant select, insert, update, delete on public.products to authenticated;
grant select on public.purchases, public.purchase_items, public.sales,
  public.sale_items, public.stock_movements, public.audit_logs to authenticated;

-- Product stock is ledger-derived. Clients cannot directly alter movements,
-- purchases, purchase items, sales, sale items, or audit records.
-- Owner product updates are limited to master-data columns; quantity is not a
-- products column and must be changed by a future stock transaction RPC.
revoke insert, update, delete on public.suppliers from authenticated;
revoke insert, update, delete on public.purchases, public.purchase_items,
  public.sales, public.sale_items, public.stock_movements, public.audit_logs
from authenticated;

-- RLS-aware views (Supabase Postgres 15+).
create or replace view public.inventory_balances
with (security_invoker = true)
as
select
  p.id as product_id,
  p.shop_id,
  p.sku,
  p.product_name,
  p.category_id,
  p.brand,
  p.vehicle_fitment,
  p.unit_name,
  p.buying_price,
  p.selling_price,
  p.low_stock_threshold,
  coalesce(sum(sm.quantity_delta), 0)::bigint as on_hand_quantity,
  p.is_active
from public.products p
left join public.stock_movements sm
  on sm.product_id = p.id and sm.shop_id = p.shop_id
where p.is_active = true
group by
  p.id, p.shop_id, p.sku, p.product_name, p.category_id, p.brand,
  p.vehicle_fitment, p.unit_name, p.buying_price, p.selling_price,
  p.low_stock_threshold, p.is_active;

create or replace view public.daily_sales_profit
with (security_invoker = true)
as
select
  (s.sold_at at time zone 'Africa/Nairobi')::date as sale_day,
  s.shop_id,
  count(distinct s.id)::bigint as transaction_count,
  coalesce(sum(si.line_total), 0)::numeric(16,2) as sales_total,
  coalesce(sum(si.cost_total), 0)::numeric(16,2) as cost_of_goods_sold,
  coalesce(sum(si.gross_profit), 0)::numeric(16,2) as gross_profit
from public.sales s
join public.sale_items si on si.sale_id = s.id
where s.status = 'completed'
group by (s.sold_at at time zone 'Africa/Nairobi')::date, s.shop_id;

grant select on public.inventory_balances, public.daily_sales_profit to authenticated;

commit;

-- IMPORTANT FIRST-OWNER SETUP:
-- 1. Create your first account through Supabase Auth.
-- 2. In SQL Editor, identify that account's UUID from Authentication > Users.
-- 3. Assign owner role with a trusted admin action, replacing the UUID:
--    update public.user_profiles
--    set role = 'owner'
--    where user_id = 'YOUR-AUTH-USER-UUID';
-- 4. Do not allow users to edit their own role. Only a trusted project admin
--    should promote/demote owner and employee accounts.
--
-- This schema intentionally does not implement sale posting, purchase receipt,
-- stock adjustment, void/refund, or offline queue synchronization. Those must
-- be implemented as atomic, authorized, idempotent database functions and
-- tested before using the system for live shop transactions.
