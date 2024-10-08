if object_id('http_Request_get') is not null drop proc http_Request_get
go
--exec dbo.http_Request_get @url = 'http://192.168.112.75:8090/api/dadata/search?value=0104014449'
CREATE PROCEDURE [http_Request_get] (
  @url nvarchar(256),
  @authHeader nvarchar(64) = null
) AS

declare
  @ret int,
  @token int,
  @responseText nvarchar(2000),
  @responseXML nvarchar(2000),
  @status nvarchar(32),
  @statusText nvarchar(32)

-- open the connection.
--exec @ret = sp_OACreate 'MSXML2.ServerXMLHTTP', @token out;
exec @ret = sp_OACreate 'WinHttp.WinHttpRequest.5.1', @token out;
if (@ret != 0)
  raiserror('Unable to open HTTP connection.', 10, 1);

-- send the request
exec @ret = sp_OAMethod @token, 'open', null, 'GET', @url, 'false'

-- set header
if (@authHeader is not null)
  exec @ret = sp_OAMethod @token, 'setRequestHeader', null, 'Authentication', @authHeader;
--
--exec @ret = sp_OAMethod @token, 'setRequestHeader', null, 'Content-type', @contentType

-- set data
exec @ret = sp_OAMethod @token, 'send'
--exec @ret = sp_OAMethod @token, 'send', null, @data

-- handle the response.
exec @ret = sp_OAGetProperty @token, 'status', @status out;
exec @ret = sp_OAGetProperty @token, 'statusText', @statusText out;
exec @ret = sp_OAGetProperty @token, 'responseText', @responseText out;

-- show the response.
print 'Status: ' + isnull(@status, '') + ' (' + isnull(@statusText, '') + ')'
print 'Response text: ' + isnull(@responseText, '')

-- close the connection.
exec @ret = sp_OADestroy @token
if (@ret != 0)
  raiserror('Unable to close HTTP connection.', 10, 1);

/*
EXEC sp_OACREATE 'MSXML2.ServerXMLHttp', @Object OUT;
EXEC sp_OAMethod @Object, 'Open', NULL, 'POST', 'https://url.net/api/LoginUser', 'false'
EXEC sp_OAMethod @Object, 'SETRequestHeader', null, 'Content-Type', 'application/json'

DECLARE @len int
SET @len = len(@body)

EXEC sp_OAMethod @Object, 'SETRequestHeader', null, 'Ocp-Apim-Subscription-Key','4f82f9d067914287979884f920d86ffb'
EXEC sp_OAMethod @Object, 'SETRequestHeader', null, 'Ocp-Apim-Trace:true'
EXEC sp_OAMethod @Object, 'SETRequestHeader', null, 'Content-Length', @len
EXEC sp_OAMethod @Object, 'SETRequestBody', null, 'Body', @body
EXEC sp_OAMethod @Object, 'Send', null, @body
EXEC sp_OAMethod @Object, 'ResponseText', @ResponseText OUTPUT

SELECT @Token=@ResponseText

EXEC sp_OADestroy @Object

SET @Token='Bearer '+ REPLACE(@Token, '"', '')

PRINT @Token
*/

GO
