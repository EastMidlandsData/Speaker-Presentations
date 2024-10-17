-- This script tries to use EXECUTE AS for server-level permission.
USE master
go
-- Create a proxy login. We take precautions to prevent it from being 
-- able to log in.
CREATE LOGIN ShowSessions2$Proxy WITH PASSWORD = N'Magical Mystery Tour'
ALTER LOGIN ShowSessions2$Proxy DISABLE

-- Grant permissions needed.
GRANT VIEW SERVER PERFORMANCE STATE TO ShowSessions2$Proxy
go

-- Move to PermTest
USE PermTest
go
-- Create a user for ShowSessions2$Proxy.
CREATE USER ShowSessions2$Proxy
go
-- Create a version of ShowSessions with EXECUTE AS.
CREATE PROCEDURE ShowSessions2 WITH EXECUTE AS 'ShowSessions2$Proxy' AS

  -- Display login_token information.
  SELECT * FROM logintokeninfo

  -- Since we are the proxy login at this point, we need to revert back
  -- to the caller's context to see if that is a SuperUser.
  EXECUTE AS CALLER
  DECLARE @is_legit bit = is_srvrolemember('SuperUsers') |
                          has_perms_by_name(NULL, NULL, 'CONTROL SERVER')
  REVERT

  IF @is_legit = 1
     SELECT * FROM sys.dm_exec_sessions WHERE database_id = db_id()
  ELSE
     RAISERROR('You are not permitted to run this procedure.', 16, 1)
go

-- Try to run it ourselves.
EXEC ShowSessions2
-- But we only see our own session, and usage in sys.login_token is 
-- DENY ONLY!

