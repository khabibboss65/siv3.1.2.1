-- Create specific accounts for each payment method (only if they don't exist by code)
INSERT INTO accounts (id, tenant_id, code, name, account_type, balance, is_active, is_cash, is_bank)
SELECT 'aaa00001-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', '1020', 'Bank Account', 'asset', 0, true, false, true
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = '1020');

INSERT INTO accounts (id, tenant_id, code, name, account_type, balance, is_active, is_cash, is_bank)
SELECT 'aaa00001-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', '1021', 'Card Payments', 'asset', 0, true, false, true
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = '1021');

INSERT INTO accounts (id, tenant_id, code, name, account_type, balance, is_active, is_cash, is_bank)
SELECT 'aaa00001-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', '1022', 'bKash', 'asset', 0, true, false, true
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = '1022');

INSERT INTO accounts (id, tenant_id, code, name, account_type, balance, is_active, is_cash, is_bank)
SELECT 'aaa00001-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', '1023', 'Nagad', 'asset', 0, true, false, true
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = '1023');

INSERT INTO accounts (id, tenant_id, code, name, account_type, balance, is_active, is_cash, is_bank)
SELECT 'aaa00001-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', '1024', 'Cheque Receivable', 'asset', 0, true, false, true
WHERE NOT EXISTS (SELECT 1 FROM accounts WHERE code = '1024');

-- Update payment_methods with account links
UPDATE payment_methods pm SET account_id = (SELECT id FROM accounts WHERE code = '1001' LIMIT 1) WHERE pm.code = 'cash';
UPDATE payment_methods pm SET account_id = (SELECT id FROM accounts WHERE code = '1020' LIMIT 1) WHERE pm.code = 'bank_transfer';
UPDATE payment_methods pm SET account_id = (SELECT id FROM accounts WHERE code = '1021' LIMIT 1) WHERE pm.code = 'card';
UPDATE payment_methods pm SET account_id = (SELECT id FROM accounts WHERE code = '1022' LIMIT 1) WHERE pm.code = 'bkash';
UPDATE payment_methods pm SET account_id = (SELECT id FROM accounts WHERE code = '1023' LIMIT 1) WHERE pm.code = 'nagad';
UPDATE payment_methods pm SET account_id = (SELECT id FROM accounts WHERE code = '1024' LIMIT 1) WHERE pm.code = 'cheque';

-- Update the payment accounting trigger to use dynamic account from payment method
CREATE OR REPLACE FUNCTION public.payment_accounting_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_tenant_id uuid;
  v_account_code text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_tenant_id := COALESCE(NEW.tenant_id, '00000000-0000-0000-0000-000000000001');
    
    -- Get the account code linked to this payment method
    SELECT a.code INTO v_account_code
    FROM payment_methods pm
    JOIN accounts a ON a.id = pm.account_id
    WHERE pm.code = LOWER(NEW.payment_method)
       OR pm.name ILIKE '%' || NEW.payment_method || '%'
       OR pm.id::text = NEW.payment_method;
    
    -- Fallback to default logic if no linked account found
    IF v_account_code IS NULL THEN
      v_account_code := CASE 
        WHEN NEW.payment_method ILIKE '%bank%' OR NEW.payment_method ILIKE '%transfer%' THEN '1020'
        WHEN NEW.payment_method ILIKE '%card%' THEN '1021'
        WHEN NEW.payment_method ILIKE '%bkash%' THEN '1022'
        WHEN NEW.payment_method ILIKE '%nagad%' THEN '1023'
        WHEN NEW.payment_method ILIKE '%cheque%' THEN '1024'
        ELSE '1001' -- Cash in Hand
      END;
    END IF;
    
    PERFORM post_journal_entry(
      p_description := 'Payment received - ' || COALESCE(NEW.payment_method, 'Payment') || ' - Ref: ' || COALESCE(NEW.reference_number, NEW.id::text),
      p_lines := jsonb_build_array(
        jsonb_build_object('account_code', v_account_code, 'debit', NEW.amount, 'description', 'Payment Received'),
        jsonb_build_object('account_code', '1100', 'credit', NEW.amount, 'description', 'Accounts Receivable')
      ),
      p_entry_date := NEW.payment_date,
      p_reference_type := 'payment',
      p_reference_id := NEW.id,
      p_tenant_id := v_tenant_id
    );
  END IF;
  
  RETURN NEW;
END;
$function$;