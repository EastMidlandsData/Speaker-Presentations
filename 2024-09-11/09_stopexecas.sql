USE PermTest
go
-- Now we know that EXECUTE AS can cause problems, we decide that we don't
-- want it in our database.
CREATE TRIGGER stop_execute_as ON DATABASE
  FOR CREATE_PROCEDURE, ALTER_PROCEDURE,
      CREATE_FUNCTION, ALTER_FUNCTION,
      CREATE_TRIGGER, ALTER_TRIGGER AS
DECLARE @eventdata   xml,
        @schema      sysname,
        @object_name sysname,
        @object_id   int,
        @msg         nvarchar(255)

-- Get the schema and name for the object created/altered.
SELECT @eventdata = eventdata()
SELECT @schema = C.value(N'SchemaName[1]', 'nvarchar(128)'),
       @object_name = C.value(N'ObjectName[1]', 'nvarchar(128)')
FROM   @eventdata.nodes('/EVENT_INSTANCE') AS E(C)

-- Find its object id.
SELECT @object_id = o.object_id
FROM   sys.objects o
JOIN   sys.schemas s ON o.schema_id = s.schema_id
WHERE  o.name = @object_name
  AND  s.name = @schema

-- If we don't find it, it may be because the creator does not have
-- have permission on the object. (Yes, this can happen.)
IF @object_id IS NULL
BEGIN
   SELECT @msg = 'Could not retrieve object id for [%s].[%s], operation aborted'
   RAISERROR(@msg, 16, 1, @schema, @object_name)
   ROLLBACK TRANSACTION
   RETURN
END

-- Finally check that the catalog views whether the module has any
-- EXECUTE AS clause.
IF EXISTS (SELECT *
           FROM   sys.sql_modules
           WHERE  object_id = @object_id
             AND  execute_as_principal_id IS NOT NULL)
BEGIN
   ROLLBACK TRANSACTION
   SELECT @msg = 'Module [%s].[%s] has an EXECUTE AS clause. ' +
                 'This is not permitted in this database.'
   RAISERROR (@msg, 16, 1, @schema, @object_name)
   RETURN
END
go

-- Try now to recreate TestProc.
ALTER PROCEDURE TestProc @id int, @title varchar(40), @reset bit = 0 
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

-- Drop trigger for now.
DROP TRIGGER stop_execute_as ON DATABASE