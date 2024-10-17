-- This script continues where 10_execasserver.sql ended.
SET NOCOUNT ON
USE master
go
-- We make the PermTest database trustworthy and move there.
ALTER DATABASE PermTest SET TRUSTWORTHY ON
go
USE PermTest
go

-- Try to run ShowSessions2 again.
EXEC ShowSessions2
-- Now it works!

-- Try also as MrKite. Success, but  ...to be continued.
EXECUTE AS LOGIN = 'MrKite'
go
EXEC ShowSessions2
go
REVERT
