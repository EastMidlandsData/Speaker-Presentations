-- This script assumes that you have run up to 05_certsignserver.sql
SET NOCOUNT ON
USE PermTest
go

-- The base procedure. We have seen this version before, but the name 
-- is new.
CREATE PROCEDURE TestProc @id int, @title varchar(40) AS
   SELECT * FROM tokeninfo
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
   PRINT 'The dynamic part'
   EXEC('SELECT id, title, enteredby 
         FROM   PermTable 
         WHERE  title = ''' + @title + '''')
go
GRANT EXECUTE ON TestProc TO RocknRole

-- As a repetition, this is what happens when Molly runs the procedure.
EXECUTE AS USER = 'Molly'
go
EXEC TestProc 14, 'Norwegian Wood'
go
REVERT
go
-- Create a proxy user for the procedure and grant permission on PermTable.
CREATE USER TestProc$Proxy WITHOUT LOGIN
GRANT SELECT ON PermTable TO TestProc$Proxy
go

-- Add EXECUTE AS clause to the procedure.
ALTER PROCEDURE TestProc @id int, @title varchar(40) 
  WITH EXECUTE AS 'TestProc$Proxy' AS
   SELECT * FROM tokeninfo
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
   PRINT 'The dynamic part'
   EXEC('SELECT id, title, enteredby 
         FROM   PermTable 
         WHERE  title = ''' + @title + '''')
go

-- Run as Molly again. Pay attention to the enteredby column
EXECUTE AS USER = 'Molly'
go
EXEC TestProc 15, 'Back in the USSR'
go
REVERT
go
-- Let's look more at how this works. Recreate the trigger and add call
-- to inner_sp and sp_helpindex.
CREATE TRIGGER PermTable_tri ON PermTable FOR INSERT AS
  SELECT 'PermTable_tri', * FROM tokeninfo
go

ALTER PROCEDURE TestProc @id int, @title varchar(40) 
  WITH EXECUTE AS 'TestProc$Proxy' AS
   SELECT * FROM tokeninfo
   EXEC sp_helpindex PermTable
   EXEC inner_sp
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
go

EXECUTE AS USER = 'Molly'
go
EXEC TestProc 16, 'Drive My Car'
-- EXECUTE AS propgates to trigger and inner_sp (and system procedure).
go
REVERT
go
-- What you have seen so far is the proper version of EXECUTE AS.
-- Here is the lazy version:
CREATE PROCEDURE TestProc2 @id int, @title varchar(40), @reset bit = 0 
 WITH EXECUTE AS OWNER AS
   SELECT * FROM tokeninfo
   IF @reset = 1
   BEGIN
      TRUNCATE TABLE PermTable
      PRINT 'Truncation done'
   END
   INSERT PermTable (id, title) VALUES (@id, @title)
   SELECT id, title, enteredby FROM PermTable
go
GRANT EXECUTE ON TestProc2 TO RocknRole
 
EXECUTE AS USER = 'Molly'
go
EXEC TestProc2 17, 'With a Little Help From My Friends', 1
go
REVERT


-- How to see which modules that have an EXECUTE AS clause:
SELECT object_name(object_id) AS Module, 
       CASE execute_as_principal_id WHEN -2 THEN 'OWNER'
            ELSE user_name(execute_as_principal_id)
       END AS [EXECUTE AS]
FROM   sys.sql_modules
WHERE  execute_as_principal_id IS NOT NULL
