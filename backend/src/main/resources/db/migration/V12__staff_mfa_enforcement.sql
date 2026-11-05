-- When 'true', SUPER_ADMIN and FINANCE_ADMIN accounts without a second factor can only reach the MFA enrolment endpoints until they enrol.
-- Off by default so that turning it on is a deliberate decision made after the owner has enrolled their own account.
INSERT INTO application_settings(key,value,description) VALUES
('security.staff_mfa_required','false','Require two-factor enrolment for super admin and finance admin accounts (true/false)');
