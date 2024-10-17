-- This script demonstrates granting server-level permissions with help of 
-- certificates. You should have run the scripts 01 to 04 prior to this one.

-- The scenario: give super users in a database the ability to see which 
-- users that are connected to their database, without seeing users in 
-- other databases.

-- We start in the master database.
USE master
go

-- First create a server role for super users.
CREATE SERVER ROLE SuperUsers
go
-- We will need a test login. This login will be made db_owner in PermTest.
CREATE LOGIN MrKite WITH PASSWORD = 'Benefit'
ALTER SERVER ROLE SuperUsers ADD MEMBER MrKite
go
-- Create a view to see login-token information. 
CREATE VIEW logintokeninfo AS
   SELECT name AS token_name, type, usage,
          original_login() AS original_login, 
          SYSTEM_USER AS [SYSTEM_USER], USER AS DBUSER 
   FROM   sys.login_token
go
-- Create a procedure - the aim is to show connections to the current
-- database. By calling the procedure sp_something, it is accesible 
-- from any database. Note! This is undocumented and may break in a 
-- future release!
CREATE PROCEDURE sp_showusersindb AS
   -- Add display of login token.
   SELECT * FROM logintokeninfo

   -- Only permit members in SuperUsers and sysadmin to use this procedure.
   IF is_srvrolemember('SuperUsers') = 1 OR
      has_perms_by_name(NULL, NULL, 'CONTROL SERVER') = 1
   BEGIN
      SELECT * FROM sys.dm_exec_sessions WHERE database_id = db_id()
   END
   ELSE
      RAISERROR('You don''t have permission do run this procedure.', 16, 1)
go
-- Grant rights to everyone - that's how do it in master.
GRANT EXECUTE ON sp_showusersindb TO public
go

-- Now move to PermTest.
USE PermTest
go
-- Run the procedure as ourselves.
EXEC sp_showusersindb
go

-- Add MrKite as a user in the database, and add him to db_owner.
CREATE USER MrKite
ALTER ROLE db_owner ADD MEMBER MrKite
go

-- Run it as MrKite. 
-- IMPORTANT: on server level, we need to impersonate the login!!!
EXECUTE AS LOGIN = 'MrKite'
go
EXEC sp_showusersindb
go
REVERT

-- Return to master.
USE master
go

-- 1. Create certificate.
CREATE CERTIFICATE DemoServerCert
ENCRYPTION BY PASSWORD = 'While My Guitar Gently Weeps'
WITH SUBJECT = '"For signing of the procedure sp_showuserindb"'
go 

-- 2. Sign the procedure.
ADD SIGNATURE TO sp_showusersindb BY CERTIFICATE DemoServerCert
    WITH PASSWORD = 'While My Guitar Gently Weeps'
go

-- 3. Create login.
CREATE LOGIN DemoServerCertLogin FROM CERTIFICATE DemoServerCert

-- Inspect this login
SELECT name, principal_id, type, type_desc 
FROM   sys.server_principals 
ORDER  BY principal_id DESC
go

-- 4. Grant the login VIEW SERVER PERFORMANCE STATE, the perssmission needed
-- for most dm_exec DMVs. (On SQL 2019 and earlier, use VIEW SERVER STATE.)
GRANT VIEW SERVER PERFORMANCE STATE TO DemoServerCertLogin
go

-- Back to PermTest for testing again.
USE PermTest
go
-- Run it as Mr. Kite. 
EXECUTE AS LOGIN = 'MrKite'
go
EXEC sp_showusersindb
go
REVERT  

