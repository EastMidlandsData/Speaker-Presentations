-- For this script, first log in as MrKite. Password is Benefit.
USE PermTest
go
-- Verify that he is MrKite - but not more than that.
SELECT is_srvrolemember('sysadmin') AS is_sysadmin, *
FROM   logintokeninfo

-- Mr. Kite impersonates dbo. Since he is db_owner, he can do anyting
-- in the database.
EXECUTE AS USER = 'dbo'
go
-- But look here:
SELECT is_srvrolemember('sysadmin') AS is_sysadmin, *
FROM   logintokeninfo

-- And it's not a joke.
EXEC sp_configure 'max server memory', 800
RECONFIGURE
go
REVERT

-----------------------------------------------------------------------
-- Change connection and login as ourselves and sysadmin.

-- We change to best practice and create an SQL login whose sole purpose
-- is to own PermTest
DECLARE @password char(37) = convert(char(36), newid()) + 'a'
EXEC('CREATE LOGIN PermTest$Owner WITH PASSWORD = ''' + @password + '''')
ALTER LOGIN PermTest$Owner DISABLE
go
ALTER AUTHORIZATION ON DATABASE::PermTest TO PermTest$Owner

-----------------------------------------------------------------------
-- Log in as MrKite again and try the same stunt again.
USE PermTest
go
EXECUTE AS USER = 'dbo'
go
-- No, not sysadmin.
SELECT is_srvrolemember('sysadmin') AS is_sysadmin, *
FROM   logintokeninfo
go
REVERT

-- Good, no sysadmin. However:
EXEC ShowSessions2

----------------------------------------------------------------------
-- Log in as sysadmin again and grant PermTest$Owner AUTHENTICATE SERVER.
USE master
go
GRANT AUTHENTICATE SERVER TO PermTest$Owner

-----------------------------------------------------------------------
-- Log in again as MrKite.
USE PermTest

-- ShowSessions2 works now.
EXEC ShowSessions2

-- What happens if he plays dbo?
EXECUTE AS USER = 'dbo'
go
-- No, not sysadmin.
SELECT is_srvrolemember('sysadmin') AS is_sysadmin, *
FROM   logintokeninfo
go
REVERT

-- Great, security hole tightened. Or? Look here, what the evil Mr Kite
-- does! He creates a user in the database for someone he knows is 
-- sysadmin. (Change to your username when you test this.)
CREATE USER [PRESENT11\sommar]
go

-- And then he impersonates that login.
EXECUTE AS USER = 'PRESENT11\sommar'
go
-- And he is sysadmin again!
SELECT is_srvrolemember('sysadmin') AS is_sysadmin, *
FROM   logintokeninfo
go
REVERT

-- CAN'T HAVE THE CAKE AND EAT IT!
