-- This file assumes that you have run 01_ownershipchain.sql.
SET NOCOUNT ON
USE PermTest
go
-- 1. Create a certificate. Must specify password and subject.
CREATE CERTIFICATE DemoCert
ENCRYPTION BY PASSWORD = 'All You Need is Love'
WITH SUBJECT = '"A certificate to demonstrate procedure signing"'
go

-- 2. Sign the procedure with the certificate.
ADD SIGNATURE TO TestSP BY CERTIFICATE DemoCert
    WITH PASSWORD = 'All You Need is Love'
go
-- This is how we can view that procedure is signed:
SELECT s.name + '.' + o.name AS object, 
       c.name AS [Certificate], c.subject, cp.*
FROM   sys.crypt_properties cp
JOIN   sys.certificates c ON c.thumbprint = cp.thumbprint
JOIN   sys.objects o ON cp.major_id = o.object_id
JOIN   sys.schemas s ON s.schema_id = o.schema_id
go

-- 3. Create a user from the certificate. The user is needed to connect 
-- the certificate to the permission.
CREATE USER DemoCertUser FROM CERTIFICATE DemoCert
go
-- See this user in sys.database_principals
SELECT name, principal_id, type, type_desc,
       authentication_type_desc
FROM   sys.database_principals
go

-- 4. Grant the user the permission needed.
GRANT SELECT ON PermTable TO DemoCertUser
go

-- Now we can test with our test user. This is how the procedure looks 
-- like at this point:
/*
ALTER PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   IF object_id('PermTable') IS NOT NULL
   BEGIN
      INSERT PermTable (id, title) VALUES (@id, @title)
      SELECT id, title, enteredby FROM PermTable
   END
   ELSE
      PRINT 'No table today'
*/

EXECUTE AS USER = 'Molly'
go
EXEC TestSP 7, 'Across the Universe'
go
REVERT
go

-- What happens if we change the procedure? We modify the message.
ALTER PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   IF object_id('PermTable') IS NOT NULL
   BEGIN
      INSERT PermTable (id, title) VALUES (@id, @title)
      SELECT id, title, enteredby FROM PermTable
   END
   ELSE
      PRINT 'PermTable has not been created yet.'
go

EXECUTE AS USER = 'Molly'
go
EXEC TestSP 8, 'Here Comes the Sun'
-- Table is said to be missing. Note that the certificate user no longer 
-- appear among the user tokens.
go
REVERT
go

-- Signature was lost since contents changed, procedure must be re-signed.
SELECT s.name + '.' + o.name AS object, 
       c.name AS [Certificate], c.subject, cp.*
FROM   sys.crypt_properties cp
JOIN   sys.certificates c ON c.thumbprint = cp.thumbprint
JOIN   sys.objects o ON cp.major_id = o.object_id
JOIN   sys.schemas s ON s.schema_id = o.schema_id
go


ADD SIGNATURE TO TestSP BY CERTIFICATE DemoCert
    WITH PASSWORD = 'All You Need is Love'
go

-- Try again.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 8, 'Here Comes the Sun'
go
REVERT
go

-- Let's now see if we can overcome other limitations with ownership
-- chaining. For instance, dynamic SQL?
ALTER PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
   PRINT 'The dynamic part'
   EXEC('SELECT id, title, enteredby
         FROM   PermTable
         WHERE  title = ''' + @title + '''')
go
ADD SIGNATURE TO TestSP BY CERTIFICATE DemoCert
    WITH PASSWORD = 'All You Need is Love'
go

-- Test it!
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 9, 'Taxman'
go
REVERT
go

-- Molly has been a naughty girl so will we explicitly deny
-- her access to the PermTable.
DENY SELECT, INSERT, UPDATE, DELETE ON PermTable TO Molly
go
-- Molly tries to run the test procedure again
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 10, 'The Long and Winding Road'
-- sp_helpindex fails, but the INSERT still works - ownership chaining.
go
REVERT
go

-- Remove the DENY - it is best avoided.
REVOKE SELECT, INSERT, UPDATE, DELETE ON PermTable TO Molly
go

-- The certificate propagates into dynamic SQL. What about other scopes?
-- We create a trigger.
CREATE TRIGGER PermTable_tri ON PermTable FOR INSERT AS
  SELECT 'PermTable_tri', * FROM tokeninfo
go
-- And an inner procedure.
CREATE PROCEDURE inner_sp AS
   SELECT 'inner_sp', * FROM tokeninfo
go

-- Change the test procedure to call these as well as a system procedure.
ALTER PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   EXEC sp_helpindex PermTable
   EXEC inner_sp
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
go

-- Try before signing.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 11, 'Revolution No. 9'
-- sp_helpindex errors out.
go
REVERT
go

-- Sign it.
ADD SIGNATURE TO TestSP BY CERTIFICATE DemoCert
    WITH PASSWORD = 'All You Need is Love'
go

EXECUTE AS USER = 'Molly'
go
EXEC TestSP 12, 'Helter Skelter'
-- sp_helpindex works, but note that cert token is not in inner_sp
-- and the trigger!
go
REVERT
go

-- Drop trigger for now.
DROP TRIGGER PermTable_tri
go

