-- This assumes that you have run 02_certsigndb.sql.
SET NOCOUNT ON
USE PermTest
go

-- Change TestSP to the version with TRUNCATE TABLE.
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

-- Here comes GrantPermsToSP. We put it in a separate schema.
CREATE SCHEMA Management
go
-- The interface uses this table type.
CREATE TYPE Management.Permission_list AS
       TABLE(perm nvarchar(400) PRIMARY KEY)
go
CREATE PROCEDURE Management.GrantPermsToSP
                 @spname       nvarchar(520),
                 @permissions  Management.Permission_list READONLY,
                 @debug        bit = 0 AS

   -- Make sure that we stop on errors.
   SET XACT_ABORT ON

   -- Set up variables. Names of the certificate and user, and the
   -- throw-away password.
   DECLARE @sql          nvarchar(MAX),   -- For our dynamic SQL.
           @certname     sysname,
           @certuser     sysname,
           @password     char(37) = convert(char(36), newid()) + 'a',
           @cert_subject sysname,
           @object_id    int = object_id(@spname)

   -- Check that the procedure exists.
   IF @object_id IS NULL
   BEGIN
      RAISERROR('Procedure %s does not exist', 16, 1, @spname)
      RETURN 1
   END

   -- Check that @spname is not in another database or server.
   IF parsename(@spname, 3) IS NOT NULL OR parsename(@spname, 4) IS NOT NULL
   BEGIN
      RAISERROR('Cannot sign procedures in a different database or server', 16, 1)
      RETURN 1
   END

   -- Normalise the procedure name and set the certificate from the 
   -- unquoted name. (With the latter names there is potentially a 
   -- risk for truncation, which we ignore.)
   SELECT @spname   = quotename(s.name) + '.' + quotename(o.name),
          @certname = CASE WHEN o.schema_id > 1
                           THEN s.name + '.'
                           ELSE ''
                      END + o.name + '$cert'
   FROM   sys.objects o
   JOIN   sys.schemas s ON o.schema_id = s.schema_id
   WHERE  o.object_id = @object_id

   -- And form the name of user.
   SELECT @certuser = @certname + 'user'

   -- If the certificate exists, clean it up.
   IF EXISTS(SELECT * FROM sys.certificates WHERE name = @certname)
   BEGIN
      -- If some other procedure is signed with the certificate, 
      -- this is wrong.
      IF EXISTS (SELECT *
                 FROM   sys.certificates c
                 JOIN   sys.crypt_properties cp ON c.thumbprint = cp.thumbprint
                 WHERE  c.name = @certname
                  AND   cp.major_id <> @object_id)
      BEGIN
         RAISERROR('Certificate %s has been used to sign another procedure than %s.',
                   16, 1, @certname, @spname)
         RETURN 1
      END

      -- If the given procedure is signed, drop the signature.
      IF EXISTS (SELECT *
                 FROM   sys.certificates c
                 JOIN   sys.crypt_properties cp ON c.thumbprint = cp.thumbprint
                 WHERE  c.name = @certname
                  AND   cp.major_id = @object_id)
      BEGIN
         SELECT @sql = 'DROP SIGNATURE FROM ' + @spname +
                       ' BY CERTIFICATE ' + quotename(@certname)
         IF @debug = 1 PRINT @sql
         EXEC(@sql)
      END

      -- Drop the certificate and any user tied to it, no matter the name.
      SELECT @sql = CASE WHEN u.name IS NOT NULL
                         THEN 'DROP USER ' + quotename(u.name) + char(13) + char(10)
                         ELSE ''
                     END + 'DROP CERTIFICATE ' + quotename(c.name)
      FROM   sys.certificates c
      LEFT   JOIN sys.database_principals u ON c.sid = u.sid
      WHERE  c.name = @certname
      IF @debug = 1 PRINT @sql
      EXEC (@sql)
   END

   -- If the user exists at this point, this is unexpected.
   IF user_id(@certuser) IS NOT NULL
   BEGIN
      RAISERROR('After dropping the certificate %s, user %s still exists.', 16, 1,
                @certname, @certuser)
      RETURN 1
   END

   -- Quit here, if no permissions were given.
   IF NOT EXISTS (SELECT * FROM @permissions)
   BEGIN
      PRINT 'Procedure not signed - no permissions were given'
      RETURN 0
   END

   -- Determine the subject from the permissions given. Again, we permit
   -- truncation.
   SELECT @cert_subject = '"GRANT ' +
       (SELECT CASE row_number() OVER (ORDER BY (SELECT NULL))
                    WHEN 1 THEN ''
                    ELSE ' - '
               END + replace(perm, '"', '""') + '"'
        FROM   @permissions
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(MAX)')

   -- Create the certificate.
   SELECT @sql =
      'CREATE CERTIFICATE ' + quotename(@certname) + '
       ENCRYPTION BY PASSWORD = ' + quotename(@password, '''') + '
       WITH SUBJECT = ' + quotename(@cert_subject, '''')
   IF @debug = 1 PRINT @sql
   EXEC(@sql)

   -- Sign the procedure. Recall that @spname was normalised above, 
   -- which is why there is no quotename.
   SELECT @sql =
      'ADD SIGNATURE TO ' + @spname + '
       BY CERTIFICATE ' + quotename(@certname) + '
       WITH PASSWORD = ' + quotename(@password, '''')
   IF @debug = 1 PRINT @sql
   EXEC(@sql)

   -- Create the user.
   SELECT @sql = 'CREATE USER ' + quotename(@certuser) + '
                  FROM CERTIFICATE ' + quotename(@certname)
   IF @debug = 1 PRINT @sql
   EXEC(@sql)

   -- Grant the permissions requested (or add to role). Need to force the
   -- collation, for the query to work in contained databases. If you
   -- are on SQL 2005/2008 use the commented call to sp_addrolemember in
   -- place of ALTER ROLE.
   SELECT @sql =
      (SELECT CASE WHEN EXISTS (SELECT *
                                FROM   sys.database_principals dp
                                WHERE  dp.name = p.perm COLLATE Latin1_General_100_CI_AS_KS_WS_SC
                                  AND  dp.type = 'R')
                   THEN 'ALTER ROLE ' + quotename(p.perm) + ' ADD MEMBER ' + quotename(@certuser)
                   --THEN 'EXEC sp_addrolemember ' + quotename(p.perm, '''') + ', ' + quotename(@certuser, '''')
                   ELSE 'GRANT ' + p.perm + ' TO ' + quotename(@certuser)
              END + char(13) + char(10)
       FROM   @permissions p
       FOR    XML PATH(''), TYPE).value('.', 'nvarchar(MAX)')
   IF @debug = 1 PRINT @sql
   EXEC(@sql)
go
------------------------------------------------------------------
-- Use the procedure to sign TestSP.
DECLARE @perms Management.Permission_list
INSERT @perms (perm) VALUES ('DELETE ON PermTable')
EXEC Management.GrantPermsToSP N'TestSP', @perms, @debug = 1

-- Run as Molly.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 13, 'Paperback Writer', @reset = 1
-- Oops, wrong permission
go
REVERT
go
-- Fix permission. Note that old signature, cert etc are dropped.
DECLARE @perms Management.Permission_list
INSERT @perms (perm) VALUES ('ALTER ON PermTable')
EXEC Management.GrantPermsToSP N'TestSP', @perms, @debug = 1

-- Try again.
EXECUTE AS USER = 'Molly'
go
EXEC TestSP 13, 'Paperback Writer', @reset = 1
-- Now it works.
go
REVERT
