SET NOCOUNT ON
USE tempdb
go
-- Create a databases to work in.
CREATE DATABASE PermTest
ALTER AUTHORIZATION ON DATABASE::PermTest TO sa

-- Create a test user.
CREATE LOGIN Molly WITH PASSWORD = 'Ob-la-di Ob-la-da'
go

USE PermTest
go
-- Create a user for Molly and a role with Molly as a member.
CREATE USER Molly
CREATE ROLE RocknRole
ALTER ROLE RocknRole ADD MEMBER Molly
go
-- This is a helper view to view token and user information.
CREATE VIEW tokeninfo AS
   SELECT name AS token_name, type, usage,
          original_login() AS original_login, 
          SYSTEM_USER AS [SYSTEM_USER], USER AS DBUSER 
   FROM   sys.user_token
go
-- Create a table to play with.
CREATE TABLE PermTable 
    (id        int         NOT NULL PRIMARY KEY,
     title     varchar(40) NOT NULL,
     enteredby sysname     NOT NULL DEFAULT USER)
INSERT PermTable (id, title) 
   VALUES (1, 'Strawberry Fields Forever')
go
-- Create a stored procedure that accesses the table.
CREATE PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable ORDER BY id
go
-- Grant RocknRole permission to run the procedure.
GRANT EXECUTE ON TestSP TO RocknRole
go
-- Impersonate Molly to test permissions. This is a nice 
-- technique to test permissions that saves you from logging in 
-- separately as the other user.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 2, 'Fixing a Hole'
go
-- Be ourselves again.
REVERT
go

-- Change the ownership of the procedure to a loginless user. (It's
-- loginless because that easier to test with.)
CREATE USER Desmond WITHOUT LOGIN
ALTER AUTHORIZATION ON TestSP TO Desmond
GRANT EXECUTE ON TestSP TO RocknRole
go
-- Test again if Molly can run procedure.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 3, 'Come Together'  
-- Fails with three permisssion errors.
go
REVERT
go

-- Restore ownership to dbo and verify that Molly again has access.
ALTER AUTHORIZATION ON TestSP TO dbo
GRANT EXECUTE ON TestSP TO RocknRole
go
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 3, 'Come Together'
go
REVERT
go

-- Modify the procedure to use some (bad) dynamic SQL.
ALTER PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
   PRINT 'The dynamic part'
   EXEC('SELECT id, title, enteredby 
         FROM   PermTable 
         WHERE  title = ''' + @title + '''')
go
-- Can she still run the procedure?
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 4, 'Love Me Do'  
-- The dynamic SQL errors out, the rest successds.
go
REVERT
go

-- Add option to reset table.
ALTER PROCEDURE TestSP @id int, @title varchar(40), @reset bit = 0 AS
   SELECT * FROM tokeninfo
   IF @reset = 1
   BEGIN
      TRUNCATE TABLE PermTable
      PRINT 'Truncation done'
   END
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
go

-- Test this new version.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 5, 'Martha My Dear', @reset = 1
-- TRUNCATE TABLE Fails, and procedure is aborted.
go
REVERT
go

-- Test metadata access.
ALTER PROCEDURE TestSP @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   IF object_id('PermTable') IS NOT NULL
   BEGIN
      INSERT PermTable (id, title) VALUES (@id, @title)
      SELECT id, title, enteredby FROM PermTable
   END
   ELSE
      PRINT 'No table today'
go
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 6, 'The Fool on the Hill'  
-- According to object_id, table does not exist.
go
REVERT
go
