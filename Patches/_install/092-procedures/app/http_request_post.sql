if object_id('http_request_post') is not null drop proc http_request_post
go
/***
  -- access
  grant exec on sp_OACreate to cisp
  grant exec on sp_OACreate to cisp
  grant exec on sp_OAMethod to cisp
  grant exec on sp_OAGetProperty to cisp
  grant exec on sp_OADestroy to cisp

  -- example
  exec dbo.http_Request_post
    @url = 'http://192.168.112.75:8091/api/rmq/send', @authHeader = null, @contentType = N'application/json',
    @data = N'{
      "ExchangeName": "crm",
      "RoutingKey": "crm.test",
      "Message": "{name: ''факел'', id: ''guid''}"
      }'
***/
create procedure [http_request_post]
  @url nvarchar(256),
  @authHeader nvarchar(64) = null,
  @contentType nvarchar(50) = null,
  @data nvarchar(max) = null
AS
begin

    declare
        @ret int,
        @token int,
        @contentLength int,
        @responseText nvarchar(2000),
        @responseXML nvarchar(2000),
        @status nvarchar(32),
        @statusText nvarchar(32)

    -- open the connection.
    exec @ret = sp_OACreate 'WinHttp.WinHttpRequest.5.1', @token out;
    if (@ret != 0) raiserror('Unable to open HTTP connection.', 10, 1);

    -- send the request
    exec @ret = sp_OAMethod @token, 'open', null, 'POST', @url, 'false'

    -- set header
    if (@authHeader is not null)
    exec @ret = sp_OAMethod @token, 'setRequestHeader', null, 'Authentication', @authHeader;
    --
    exec @ret = sp_OAMethod @token, 'setRequestHeader', null, 'Content-Type', @contentType
    --
    select @contentLength = len(@contentType)
    exec @ret = sp_OAMethod @token, 'setRequestHeader', null, 'Content-Length', @contentLength

    -- set data
    exec @ret = sp_OAMethod @token, 'send', null, @data

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

end
GO
