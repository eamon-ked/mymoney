-- Test the RPC function exists
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name = 'delete_user_and_data';

-- Test calling the function (this will fail if not authenticated, but shows the function exists)
-- SELECT public.delete_user_and_data();

-- Check if RLS policies exist for DELETE operations
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE schemaname = 'public' 
AND cmd = 'DELETE';

-- Check table structure to verify user_id columns exist
SELECT 
    table_name,
    column_name,
    data_type
FROM information_schema.columns 
WHERE table_schema = 'public' 
AND table_name IN ('accounts', 'transactions', 'categories', 'goals', 'private_loans', 'user_profiles')
AND column_name LIKE '%user%'
ORDER BY table_name, column_name;
