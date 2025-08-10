# Account Deletion Test Guide

## Setup Instructions

1. **Run the SQL Setup**:
   - Copy the contents of `supabase_setup.sql`
   - Paste into your Supabase SQL Editor
   - Execute the entire script

2. **Test Account Deletion**:

### Step 1: Create Test Data
1. Open your app
2. Sign up with a test email (e.g., `test@example.com`)
3. Add some test data:
   - Create 2-3 accounts
   - Add 5-10 transactions
   - Create 2-3 categories
   - Add 1-2 goals
   - Add 1 private loan
   - Fill out profile information

### Step 2: Verify Data Exists
1. Go to Supabase Dashboard → Table Editor
2. Check each table has data for your test user:
   - `accounts` table
   - `transactions` table
   - `categories` table
   - `goals` table
   - `private_loans` table
   - `user_profiles` table

### Step 3: Test Deletion
1. In your app, go to **Settings → Account → Delete Account**
2. The app should:
   - Call the RPC function
   - Delete all user data
   - Sign out the user
   - Return to login screen

### Step 4: Verify Deletion
1. Check Supabase Dashboard → Table Editor
2. All tables should have **0 rows** for your test user
3. Go to Supabase Dashboard → Authentication → Users
4. The test user should be deleted (or at least all data should be gone)

### Step 5: Verify Sign-in Fails
1. Try to sign in with the deleted account
2. Should fail with "Invalid login credentials"

## Troubleshooting

### If RPC Fails:
- Check Supabase Logs for errors
- Verify RLS policies are in place
- Ensure the function has proper permissions

### If Client-side Deletion Fails:
- Check that DELETE policies exist for all tables
- Verify `user_id` column names match your schema
- Check network connectivity

### If Data Remains:
- Run the verification function:
  ```sql
  SELECT * FROM verify_user_data_deletion('your-user-uuid');
  ```
- This will show which tables still have data

## App Store Compliance Checklist

✅ **In-app deletion**: Settings → Account → Delete Account  
✅ **Immediate deletion**: Data deleted when button is pressed  
✅ **Complete deletion**: All user data removed from all tables  
✅ **Auth user deletion**: User cannot sign in after deletion  
✅ **Local data cleanup**: App wipes local data on sign out  
✅ **Error handling**: App shows errors if deletion fails  

## Notes for App Review

Include in your App Review notes:
> "Account deletion is available at Settings → Account → Delete Account. This immediately deletes all user data and the account. The user is signed out and cannot sign back in. Test with account: [your-test-email]"
