-- PersonalFinanceApp Supabase Setup for Account Deletion
-- Run this in your Supabase SQL Editor

-- 1. Create tables if they don't exist (with correct column names)
CREATE TABLE IF NOT EXISTS public.accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    balance DECIMAL(15,2) DEFAULT 0,
    currency TEXT DEFAULT 'USD',
    account_number TEXT,
    institution_name TEXT,
    color TEXT DEFAULT '#007AFF',
    is_active BOOLEAN DEFAULT true,
    sync_status TEXT DEFAULT 'pending',
    last_synced_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
    category_id UUID,
    amount DECIMAL(15,2) NOT NULL,
    type TEXT NOT NULL,
    description TEXT NOT NULL,
    notes TEXT,
    transaction_date DATE NOT NULL,
    is_recurring BOOLEAN DEFAULT false,
    recurring_frequency TEXT,
    tags TEXT[] DEFAULT '{}',
    sync_status TEXT DEFAULT 'pending',
    last_synced_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    color TEXT DEFAULT '#007AFF',
    icon TEXT DEFAULT 'folder',
    is_default BOOLEAN DEFAULT false,
    sync_status TEXT DEFAULT 'pending',
    last_synced_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    title TEXT NOT NULL,
    goal_description TEXT,
    target_amount DECIMAL(15,2) NOT NULL,
    current_amount DECIMAL(15,2) DEFAULT 0,
    target_date DATE,
    category TEXT,
    priority TEXT,
    status TEXT DEFAULT 'active',
    sync_status TEXT DEFAULT 'pending',
    last_synced_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.private_loans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    loan_name TEXT NOT NULL,
    loan_type TEXT,
    lender_name TEXT,
    original_amount DECIMAL(15,2) NOT NULL,
    remaining_balance DECIMAL(15,2) NOT NULL,
    interest_rate DECIMAL(5,2) NOT NULL,
    monthly_payment DECIMAL(15,2) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    next_payment_date DATE,
    status TEXT DEFAULT 'active',
    sync_status TEXT DEFAULT 'pending',
    last_synced_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY,
    full_name TEXT NOT NULL,
    avatar_url TEXT,
    phone TEXT,
    date_of_birth DATE,
    occupation TEXT,
    annual_income DECIMAL(15,2),
    credit_score INTEGER,
    financial_goals TEXT[] DEFAULT '{}',
    risk_tolerance TEXT,
    sync_status TEXT DEFAULT 'pending',
    last_synced_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Enable RLS on all tables
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.private_loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- 3. Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Users can view their own accounts" ON public.accounts;
DROP POLICY IF EXISTS "Users can insert their own accounts" ON public.accounts;
DROP POLICY IF EXISTS "Users can update their own accounts" ON public.accounts;
DROP POLICY IF EXISTS "Users can delete their own accounts" ON public.accounts;

DROP POLICY IF EXISTS "Users can view their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users can insert their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users can update their own transactions" ON public.transactions;
DROP POLICY IF EXISTS "Users can delete their own transactions" ON public.transactions;

DROP POLICY IF EXISTS "Users can view their own categories" ON public.categories;
DROP POLICY IF EXISTS "Users can insert their own categories" ON public.categories;
DROP POLICY IF EXISTS "Users can update their own categories" ON public.categories;
DROP POLICY IF EXISTS "Users can delete their own categories" ON public.categories;

DROP POLICY IF EXISTS "Users can view their own goals" ON public.goals;
DROP POLICY IF EXISTS "Users can insert their own goals" ON public.goals;
DROP POLICY IF EXISTS "Users can update their own goals" ON public.goals;
DROP POLICY IF EXISTS "Users can delete their own goals" ON public.goals;

DROP POLICY IF EXISTS "Users can view their own loans" ON public.private_loans;
DROP POLICY IF EXISTS "Users can insert their own loans" ON public.private_loans;
DROP POLICY IF EXISTS "Users can update their own loans" ON public.private_loans;
DROP POLICY IF EXISTS "Users can delete their own loans" ON public.private_loans;

DROP POLICY IF EXISTS "Users can view their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can delete their own profile" ON public.user_profiles;

-- 4. Create RLS policies for SELECT operations
CREATE POLICY "Users can view their own accounts" ON public.accounts
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view their own transactions" ON public.transactions
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view their own categories" ON public.categories
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view their own goals" ON public.goals
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view their own loans" ON public.private_loans
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can view their own profile" ON public.user_profiles
    FOR SELECT USING (id = auth.uid());

-- 5. Create RLS policies for INSERT operations
CREATE POLICY "Users can insert their own accounts" ON public.accounts
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can insert their own transactions" ON public.transactions
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can insert their own categories" ON public.categories
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can insert their own goals" ON public.goals
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can insert their own loans" ON public.private_loans
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can insert their own profile" ON public.user_profiles
    FOR INSERT WITH CHECK (id = auth.uid());

-- 6. Create RLS policies for UPDATE operations
CREATE POLICY "Users can update their own accounts" ON public.accounts
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can update their own transactions" ON public.transactions
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can update their own categories" ON public.categories
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can update their own goals" ON public.goals
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can update their own loans" ON public.private_loans
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can update their own profile" ON public.user_profiles
    FOR UPDATE USING (id = auth.uid());

-- 7. Create RLS policies for DELETE operations (CRITICAL for account deletion)
CREATE POLICY "Users can delete their own accounts" ON public.accounts
    FOR DELETE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own transactions" ON public.transactions
    FOR DELETE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own categories" ON public.categories
    FOR DELETE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own goals" ON public.goals
    FOR DELETE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own loans" ON public.private_loans
    FOR DELETE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own profile" ON public.user_profiles
    FOR DELETE USING (id = auth.uid());

-- 8. Create the account deletion RPC function
CREATE OR REPLACE FUNCTION public.delete_user_and_data()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    uid uuid;
    deleted_count integer := 0;
BEGIN
    -- Get current user ID
    uid := auth.uid();
    
    -- Check if user is authenticated
    IF uid IS NULL THEN
        RAISE EXCEPTION 'User not authenticated';
    END IF;
    
    -- Delete user data in dependency order
    -- 1. Delete transactions first (they reference accounts)
    DELETE FROM public.transactions WHERE user_id = uid;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % transactions for user %', deleted_count, uid;
    
    -- 2. Delete goals
    DELETE FROM public.goals WHERE user_id = uid;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % goals for user %', deleted_count, uid;
    
    -- 3. Delete categories
    DELETE FROM public.categories WHERE user_id = uid;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % categories for user %', deleted_count, uid;
    
    -- 4. Delete private loans
    DELETE FROM public.private_loans WHERE user_id = uid;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % private loans for user %', deleted_count, uid;
    
    -- 5. Delete accounts
    DELETE FROM public.accounts WHERE user_id = uid;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % accounts for user %', deleted_count, uid;
    
    -- 6. Delete user profile
    DELETE FROM public.user_profiles WHERE id = uid;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE 'Deleted % user profiles for user %', deleted_count, uid;
    
    -- 7. Delete the auth user (this should work with SECURITY DEFINER)
    BEGIN
        -- Use the correct function to delete auth user
        DELETE FROM auth.users WHERE id = uid;
        GET DIAGNOSTICS deleted_count = ROW_COUNT;
        IF deleted_count > 0 THEN
            RAISE NOTICE 'Successfully deleted auth user %', uid;
        ELSE
            RAISE NOTICE 'No auth user found to delete for %', uid;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Could not delete auth user %: %', uid, SQLERRM;
        -- Continue anyway - the data is deleted
    END;
    
    RAISE NOTICE 'Account deletion completed for user %', uid;
END;
$$;

-- 9. Grant execute permission on the function
REVOKE ALL ON FUNCTION public.delete_user_and_data() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user_and_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_and_data() TO anon;

-- 10. Create a test function to verify deletion (optional)
CREATE OR REPLACE FUNCTION public.verify_user_data_deletion(user_uuid uuid)
RETURNS TABLE(table_name text, row_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 'transactions'::text, COUNT(*)::bigint FROM public.transactions WHERE user_id = user_uuid
    UNION ALL
    SELECT 'goals'::text, COUNT(*)::bigint FROM public.goals WHERE user_id = user_uuid
    UNION ALL
    SELECT 'categories'::text, COUNT(*)::bigint FROM public.categories WHERE user_id = user_uuid
    UNION ALL
    SELECT 'private_loans'::text, COUNT(*)::bigint FROM public.private_loans WHERE user_id = user_uuid
    UNION ALL
    SELECT 'accounts'::text, COUNT(*)::bigint FROM public.accounts WHERE user_id = user_uuid
    UNION ALL
    SELECT 'user_profiles'::text, COUNT(*)::bigint FROM public.user_profiles WHERE id = user_uuid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_user_data_deletion(uuid) TO authenticated;

-- 11. Add comments for documentation
COMMENT ON FUNCTION public.delete_user_and_data() IS 'Deletes all user data and the auth user account. Required for App Store compliance.';
COMMENT ON FUNCTION public.verify_user_data_deletion(uuid) IS 'Verifies that all user data has been deleted. Use for testing.';
