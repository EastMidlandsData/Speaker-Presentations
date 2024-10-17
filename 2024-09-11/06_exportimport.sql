-- This file assumes that you have executed 05_certsignserver.sql.
SET NOCOUNT ON
USE PermTest
go
-- We opened a support case, and CSS saw that we were using our own system
-- procedure. They made it clear that this is very unsupported, so we
-- will move the procedure to the user databases.

-- We need the view for login-token information in PermTest as well.
CREATE VIEW logintokeninfo AS
   SELECT name AS token_name, type, usage,
          original_login() AS original_login,
          SYSTEM_USER AS [SYSTEM_USER], USER AS DBUSER
   FROM   sys.login_token
go
-- Here is a database-local version of sp_showusersindb to be more
-- supported. While the permission check is not really needed here,
-- we keep it.
CREATE PROCEDURE ShowSessions AS
   SELECT * FROM logintokeninfo

   IF is_srvrolemember('SuperUsers') = 1 OR
      has_perms_by_name(NULL, NULL, 'CONTROL SERVER') = 1
     SELECT * FROM sys.dm_exec_sessions WHERE database_id = db_id()
   ELSE
     RAISERROR('You are not permitted to run this procedure.', 16, 1)
go

-- Test with the MrKite - he only sees his own session.
EXECUTE AS LOGIN = 'MrKite'
go
EXECUTE ShowSessions
go
REVERT
go
-- We need a new certificate. According to the recipe, we create it
-- first in PermTest.
CREATE CERTIFICATE DemoServerCert2
ENCRYPTION BY PASSWORD = 'Tomorrow Never Knows'
WITH SUBJECT = '"For signing of PermTest.dbo.ShowSessions"'
go
-- Sign the procedure.
ADD SIGNATURE TO ShowSessions BY CERTIFICATE DemoServerCert2
   WITH PASSWORD = 'Tomorrow Never Knows'
go
-- The private key has served its purpose, so we drop it to prevent
-- Mr. Kite from abusing it.
ALTER CERTIFICATE DemoServerCert2 REMOVE PRIVATE KEY
go


-- Now we need to copy the certificate to master. Here is the concept:
-- Get public key of the certificate with the function certencoded
-- into a variable.
DECLARE @public_key varbinary(MAX) =
            certencoded(cert_id('DemoServerCert2'))

-- Move to master
USE master
-- Create the certificate in this database, using the FROM BINARY option.
-- Alas, this syntax is not valid - the binary values must be literals.
CREATE CERTIFICATE DemoServerCert2
FROM BINARY = @public_key
go


-- We need to use dynamic SQL, sigh.
USE PermTest
go
DECLARE @public_key varbinary(MAX) =
            certencoded(cert_id('DemoServerCert2')),
        @sql nvarchar(MAX)

-- Code to create the certificates from the bytes we extracted.
SELECT @sql =
   'CREATE CERTIFICATE DemoServerCert2
    FROM BINARY = ' + convert(varchar(MAX), @public_key, 1)

PRINT  convert(varchar(MAX), @sql)

-- Move to master and run the SQL.
USE master
EXEC(@sql)
go

-- Create a login from the certificate and grant permissions.
CREATE LOGIN DemoServerCert2Login FROM CERTIFICATE DemoServerCert2
GRANT VIEW SERVER PERFORMANCE STATE TO DemoServerCert2Login

-- Move to PermTest again to test.
USE PermTest
go
-- The super user can run the procedure.
EXECUTE AS LOGIN = 'MrKite'
go
EXECUTE ShowSessions
go
REVERT

------------------------------------------------------------------------------------
-- On SQL 2005 and SQL 2008, you cannot use the above, but you can use
-- BACKUP CERTIFICATE which bounces the certificate over disk.

-- Make sure that the signature and the certificate is not in PermTest, in
-- case you ran the above.
USE PermTest
go
DROP SIGNATURE FROM ShowSessions BY CERTIFICATE DemoServerCert2
DROP CERTIFICATE DemoServerCert2

-- Verify that MrKite only can see his own session.
EXECUTE AS LOGIN = 'MrKite'
go
EXECUTE ShowSessions
go
REVERT

-- Create a new certificate for this test.
CREATE CERTIFICATE DemoServerCert3
ENCRYPTION BY PASSWORD = 'Lucy in the Sky with Diamonds'
WITH SUBJECT = '"For signing of PermTest.dbo.ShowSessions"'
go
-- Sign the procedure.
ADD SIGNATURE TO ShowSessions BY CERTIFICATE DemoServerCert3
   WITH PASSWORD = 'Lucy in the Sky with Diamonds'
go
-- The private key has served its purpose, so we drop it to prevent
-- Mr. Kite from abusing it.
ALTER CERTIFICATE DemoServerCert3 REMOVE PRIVATE KEY
go

-- Backup the certificate to disk. 
BACKUP CERTIFICATE DemoServerCert3
    TO FILE='C:\temp\DemoServerCert3.cer'

-- Move over to the master database.
USE master
go
-- Import the certificate from the files. 
CREATE CERTIFICATE DemoServerCert3
    FROM FILE='C:\temp\DemoServerCert3.cer'

-- Delete the certificate from disk, so that next export does not fail.
EXEC xp_cmdshell 'DEL C:\temp\DemoServerCert3.cer', 'no_output'
go

-- Create a login from the certificate and grant permissions.
CREATE LOGIN DemoServerCert3Login FROM CERTIFICATE DemoServerCert3
GRANT VIEW SERVER STATE TO DemoServerCert3Login

-- Move to PermTest again to test.
USE PermTest
go
-- The super user can run the procedure.
EXECUTE AS LOGIN = 'MrKite'
go
EXECUTE ShowSessions
go
REVERT



