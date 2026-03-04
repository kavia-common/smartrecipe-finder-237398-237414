-- SnapChef (demo auth mode) schema + seed data (idempotent)
-- This script is intended to be executed via psql (e.g. from startup.sh).
-- It is safe to run multiple times: uses IF NOT EXISTS / ON CONFLICT where possible.

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helper trigger function to maintain updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- =========================
-- Users (demo auth mode)
-- =========================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  demo_username TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- =========================
-- Scans (ingredient recognition sessions)
-- =========================
CREATE TABLE IF NOT EXISTS public.scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  source TEXT NOT NULL CHECK (source IN ('camera','gallery','manual')),
  image_url TEXT,
  recognized_ingredients JSONB NOT NULL DEFAULT '[]'::jsonb,
  confidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending','processing','completed','failed')),
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scans_user_created_at ON public.scans(user_id, created_at DESC);

-- =========================
-- Recipes (catalog + user generated)
-- =========================
CREATE TABLE IF NOT EXISTS public.recipes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  source TEXT NOT NULL DEFAULT 'seed' CHECK (source IN ('seed','user','imported')),
  created_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,

  title TEXT NOT NULL,
  description TEXT,
  cuisine TEXT,
  diet_tags TEXT[] NOT NULL DEFAULT '{}'::text[],
  allergen_tags TEXT[] NOT NULL DEFAULT '{}'::text[],
  prep_time_minutes INTEGER NOT NULL DEFAULT 0 CHECK (prep_time_minutes >= 0),
  cook_time_minutes INTEGER NOT NULL DEFAULT 0 CHECK (cook_time_minutes >= 0),
  total_time_minutes INTEGER GENERATED ALWAYS AS (prep_time_minutes + cook_time_minutes) STORED,
  servings INTEGER NOT NULL DEFAULT 2 CHECK (servings > 0),
  instructions TEXT[] NOT NULL DEFAULT '{}'::text[],
  image_url TEXT,
  difficulty TEXT NOT NULL DEFAULT 'easy' CHECK (difficulty IN ('easy','medium','hard')),
  calories_est INTEGER,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_recipes_updated_at ON public.recipes;
CREATE TRIGGER trg_recipes_updated_at
BEFORE UPDATE ON public.recipes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_recipes_title_trgm ON public.recipes USING gin (title gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_recipes_cuisine ON public.recipes(cuisine);

-- Need pg_trgm for trigram index; create extension if available.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
EXCEPTION
  WHEN insufficient_privilege THEN
    -- Ignore if extension creation isn't allowed in some environments.
    NULL;
END $$;

-- =========================
-- Recipe ingredients (normalized)
-- =========================
CREATE TABLE IF NOT EXISTS public.recipe_ingredients (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id UUID NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  quantity NUMERIC,
  unit TEXT,
  optional BOOLEAN NOT NULL DEFAULT FALSE,
  notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_recipe ON public.recipe_ingredients(recipe_id);
CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_name ON public.recipe_ingredients(name);

-- =========================
-- Favorites (user <-> recipe)
-- =========================
CREATE TABLE IF NOT EXISTS public.favorites (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  recipe_id UUID NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, recipe_id)
);

CREATE INDEX IF NOT EXISTS idx_favorites_user_created_at ON public.favorites(user_id, created_at DESC);

-- =========================
-- Shopping lists + items
-- =========================
CREATE TABLE IF NOT EXISTS public.shopping_lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  is_archived BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_shopping_lists_updated_at ON public.shopping_lists;
CREATE TRIGGER trg_shopping_lists_updated_at
BEFORE UPDATE ON public.shopping_lists
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_shopping_lists_user ON public.shopping_lists(user_id);

CREATE TABLE IF NOT EXISTS public.shopping_list_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopping_list_id UUID NOT NULL REFERENCES public.shopping_lists(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  quantity NUMERIC,
  unit TEXT,
  is_checked BOOLEAN NOT NULL DEFAULT FALSE,
  category TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_shopping_list_items_updated_at ON public.shopping_list_items;
CREATE TRIGGER trg_shopping_list_items_updated_at
BEFORE UPDATE ON public.shopping_list_items
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_shopping_list_items_list ON public.shopping_list_items(shopping_list_id);
CREATE INDEX IF NOT EXISTS idx_shopping_list_items_checked ON public.shopping_list_items(shopping_list_id, is_checked);

-- =========================
-- Meal plans + entries
-- =========================
CREATE TABLE IF NOT EXISTS public.meal_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'My Meal Plan',
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_date >= start_date)
);

DROP TRIGGER IF EXISTS trg_meal_plans_updated_at ON public.meal_plans;
CREATE TRIGGER trg_meal_plans_updated_at
BEFORE UPDATE ON public.meal_plans
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_meal_plans_user_dates ON public.meal_plans(user_id, start_date, end_date);

CREATE TABLE IF NOT EXISTS public.meal_plan_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_plan_id UUID NOT NULL REFERENCES public.meal_plans(id) ON DELETE CASCADE,
  plan_date DATE NOT NULL,
  meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast','lunch','dinner','snack')),
  recipe_id UUID REFERENCES public.recipes(id) ON DELETE SET NULL,
  notes TEXT,
  servings INTEGER NOT NULL DEFAULT 1 CHECK (servings > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (meal_plan_id, plan_date, meal_type)
);

CREATE INDEX IF NOT EXISTS idx_meal_plan_entries_plan_date ON public.meal_plan_entries(meal_plan_id, plan_date);

-- =========================
-- Analytics events (lightweight)
-- =========================
CREATE TABLE IF NOT EXISTS public.analytics_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  event_name TEXT NOT NULL,
  event_properties JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_analytics_events_name_created_at ON public.analytics_events(event_name, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_events_user_created_at ON public.analytics_events(user_id, created_at DESC);

-- =========================
-- Seed data (demo)
-- =========================

-- Demo users
INSERT INTO public.users (demo_username, display_name, avatar_url)
VALUES
  ('demo', 'Demo User', NULL),
  ('chef', 'Chef Retro', NULL)
ON CONFLICT (demo_username) DO NOTHING;

-- Seed recipes (use stable titles for idempotency and lookup)
INSERT INTO public.recipes (
  source, created_by_user_id, title, description, cuisine, diet_tags, allergen_tags,
  prep_time_minutes, cook_time_minutes, servings, instructions, image_url, difficulty, calories_est
)
SELECT
  'seed',
  NULL,
  v.title,
  v.description,
  v.cuisine,
  v.diet_tags,
  v.allergen_tags,
  v.prep_time_minutes,
  v.cook_time_minutes,
  v.servings,
  v.instructions,
  v.image_url,
  v.difficulty,
  v.calories_est
FROM (
  VALUES
    (
      'Citrus Quinoa Bowl',
      'A bright, retro-fresh bowl with quinoa, citrus, and herbs.',
      'mediterranean',
      ARRAY['vegetarian','gluten-free']::text[],
      ARRAY[]::text[],
      10, 15, 2,
      ARRAY[
        'Rinse quinoa and cook until fluffy.',
        'Segment orange and chop herbs.',
        'Toss quinoa with citrus, olive oil, lemon, salt, and pepper.',
        'Top with herbs and optional feta.'
      ]::text[],
      NULL,
      'easy',
      520
    ),
    (
      'Pantry Tomato Pasta',
      'Classic pantry pasta with garlic, tomato, and basil vibes.',
      'italian',
      ARRAY['vegetarian']::text[],
      ARRAY['gluten']::text[],
      5, 15, 2,
      ARRAY[
        'Boil pasta in salted water.',
        'Sauté garlic in olive oil.',
        'Add tomatoes and simmer.',
        'Toss pasta with sauce and basil.'
      ]::text[],
      NULL,
      'easy',
      680
    ),
    (
      'Green Power Omelet',
      'Eggs + greens + citrus zest for a playful kick.',
      'american',
      ARRAY['high-protein']::text[],
      ARRAY['egg']::text[],
      5, 7, 1,
      ARRAY[
        'Whisk eggs with salt and pepper.',
        'Sauté spinach briefly.',
        'Pour eggs, cook gently, fold.',
        'Finish with zest and herbs.'
      ]::text[],
      NULL,
      'easy',
      410
    )
) AS v(
  title, description, cuisine, diet_tags, allergen_tags,
  prep_time_minutes, cook_time_minutes, servings, instructions, image_url, difficulty, calories_est
)
WHERE NOT EXISTS (
  SELECT 1 FROM public.recipes r WHERE r.title = v.title
);

-- Seed ingredients for those recipes (idempotent by checking existing name+recipe)
WITH r AS (
  SELECT id, title FROM public.recipes WHERE title IN ('Citrus Quinoa Bowl','Pantry Tomato Pasta','Green Power Omelet')
)
INSERT INTO public.recipe_ingredients (recipe_id, name, quantity, unit, optional, notes)
SELECT r.id, x.name, x.quantity, x.unit, x.optional, x.notes
FROM r
JOIN (
  VALUES
    ('Citrus Quinoa Bowl','quinoa',1,'cup',FALSE,NULL),
    ('Citrus Quinoa Bowl','orange',1,'pc',FALSE,'segmented'),
    ('Citrus Quinoa Bowl','lemon',0.5,'pc',TRUE,'juice'),
    ('Citrus Quinoa Bowl','olive oil',1,'tbsp',FALSE,NULL),
    ('Citrus Quinoa Bowl','feta',0.25,'cup',TRUE,'crumbled'),

    ('Pantry Tomato Pasta','pasta',200,'g',FALSE,NULL),
    ('Pantry Tomato Pasta','canned tomatoes',1,'can',FALSE,NULL),
    ('Pantry Tomato Pasta','garlic',2,'cloves',FALSE,'minced'),
    ('Pantry Tomato Pasta','olive oil',1,'tbsp',FALSE,NULL),
    ('Pantry Tomato Pasta','basil',0.25,'cup',TRUE,'fresh'),

    ('Green Power Omelet','eggs',2,'pc',FALSE,NULL),
    ('Green Power Omelet','spinach',2,'cups',FALSE,'packed'),
    ('Green Power Omelet','salt',NULL,NULL,TRUE,'to taste'),
    ('Green Power Omelet','black pepper',NULL,NULL,TRUE,'to taste')
) AS x(title, name, quantity, unit, optional, notes)
  ON x.title = r.title
WHERE NOT EXISTS (
  SELECT 1
  FROM public.recipe_ingredients ri
  WHERE ri.recipe_id = r.id AND ri.name = x.name
);

-- Create a default shopping list for demo user
INSERT INTO public.shopping_lists (user_id, title)
SELECT u.id, 'Demo Shopping List'
FROM public.users u
WHERE u.demo_username = 'demo'
AND NOT EXISTS (
  SELECT 1 FROM public.shopping_lists sl WHERE sl.user_id = u.id AND sl.title = 'Demo Shopping List'
);

-- Seed a couple shopping list items
WITH sl AS (
  SELECT sl.id
  FROM public.shopping_lists sl
  JOIN public.users u ON u.id = sl.user_id
  WHERE u.demo_username = 'demo' AND sl.title = 'Demo Shopping List'
  LIMIT 1
)
INSERT INTO public.shopping_list_items (shopping_list_id, name, quantity, unit, is_checked, category)
SELECT sl.id, v.name, v.quantity, v.unit, v.is_checked, v.category
FROM sl
JOIN (
  VALUES
    ('orange',2,'pc',FALSE,'produce'),
    ('quinoa',1,'bag',FALSE,'pantry'),
    ('spinach',1,'bag',FALSE,'produce')
) AS v(name, quantity, unit, is_checked, category)
  ON TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM public.shopping_list_items i WHERE i.shopping_list_id = sl.id AND i.name = v.name
);

-- Seed a meal plan for demo user (current week)
WITH u AS (
  SELECT id FROM public.users WHERE demo_username = 'demo' LIMIT 1
)
INSERT INTO public.meal_plans (user_id, title, start_date, end_date)
SELECT u.id, 'Demo Week Plan', date_trunc('week', CURRENT_DATE)::date, (date_trunc('week', CURRENT_DATE) + INTERVAL '6 days')::date
FROM u
WHERE NOT EXISTS (
  SELECT 1 FROM public.meal_plans mp WHERE mp.user_id = u.id AND mp.title = 'Demo Week Plan'
);

-- Seed one meal entry
WITH mp AS (
  SELECT mp.id
  FROM public.meal_plans mp
  JOIN public.users u ON u.id = mp.user_id
  WHERE u.demo_username = 'demo' AND mp.title = 'Demo Week Plan'
  LIMIT 1
),
rcp AS (
  SELECT id FROM public.recipes WHERE title = 'Citrus Quinoa Bowl' LIMIT 1
)
INSERT INTO public.meal_plan_entries (meal_plan_id, plan_date, meal_type, recipe_id, notes, servings)
SELECT mp.id, CURRENT_DATE, 'lunch', rcp.id, 'Quick and bright!', 1
FROM mp, rcp
ON CONFLICT (meal_plan_id, plan_date, meal_type) DO NOTHING;

-- Seed one scan record for demo user
WITH u AS (
  SELECT id FROM public.users WHERE demo_username = 'demo' LIMIT 1
)
INSERT INTO public.scans (user_id, source, image_url, recognized_ingredients, confidence, status)
SELECT
  u.id,
  'manual',
  NULL,
  '["orange","quinoa","spinach"]'::jsonb,
  '{"orange":0.98,"quinoa":0.88,"spinach":0.92}'::jsonb,
  'completed'
FROM u
WHERE NOT EXISTS (
  SELECT 1 FROM public.scans s WHERE s.user_id = u.id
);

-- Seed one analytics event
WITH u AS (
  SELECT id FROM public.users WHERE demo_username = 'demo' LIMIT 1
)
INSERT INTO public.analytics_events (user_id, event_name, event_properties)
SELECT u.id, 'app_open', '{"mode":"demo-auth"}'::jsonb
FROM u
WHERE NOT EXISTS (
  SELECT 1 FROM public.analytics_events e WHERE e.user_id = u.id AND e.event_name = 'app_open'
);
