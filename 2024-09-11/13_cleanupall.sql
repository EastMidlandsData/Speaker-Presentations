-- This script drops all databases, logins etc created by the other 
-- scripts.
USE master
go
-- Drop databases.
IF db_id('PermTest') IS NOT NULL
BEGIN
   ALTER DATABASE PermTest SET SINGLE_USER WITH ROLLBACK IMMEDIATE
   DROP DATABASE PermTest
END
go
-- Drop logins.
IF suser_sid('MrKite') IS NOT NULL
   DROP LOGIN MrKite

IF suser_sid('PermTest$Owner') IS NOT NULL
   DROP LOGIN PermTest$Owner

IF suser_sid('Molly') IS NOT NULL
   DROP LOGIN Molly

IF suser_sid('SuperUsers') IS NOT NULL
   DROP SERVER ROLE SuperUsers

IF suser_sid('SIGN [PermTest].[dbo].[ShowSessions]') IS NOT NULL
   DROP LOGIN [SIGN [PermTest]].[dbo]].[ShowSessions]]]

IF suser_sid('DemoServerCertLogin') IS NOT NULL
   DROP LOGIN DemoServerCertLogin

IF suser_sid('DemoServerCert2Login') IS NOT NULL
   DROP LOGIN DemoServerCert2Login

IF suser_sid('DemoServerCert3Login') IS NOT NULL
   DROP LOGIN DemoServerCert3Login

IF suser_sid('showusersindb$Proxy') IS NOT NULL
   DROP LOGIN showusersindb$Proxy

IF suser_sid('ShowSessions2$Proxy') IS NOT NULL
   DROP LOGIN ShowSessions2$Proxy

IF schema_id('ShowSessions2$Proxy') IS NOT NULL
   DROP SCHEMA ShowSessions2$Proxy

IF user_id('ShowSessions2$Proxy') IS NOT NULL
   DROP USER ShowSessions2$Proxy

-- Drop stored procedures.
IF object_id('sp_showusersindb') IS NOT NULL
   DROP PROCEDURE sp_showusersindb

-- Drop the view
IF object_id('logintokeninfo') IS NOT NULL
   DROP VIEW logintokeninfo

-- Drop certificates
IF cert_id('[SIGN [PermTest]].[dbo]].[ShowSessions]]]') IS NOT NULL
   DROP CERTIFICATE [SIGN [PermTest]].[dbo]].[ShowSessions]]]

IF cert_id('DemoServerCert') IS NOT NULL
   DROP CERTIFICATE DemoServerCert

IF cert_id('DemoServerCert2') IS NOT NULL
   DROP CERTIFICATE DemoServerCert2

IF cert_id('DemoServerCert3') IS NOT NULL
   DROP CERTIFICATE DemoServerCert3


