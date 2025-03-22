if object_id('mfr_item_opers') is not null drop proc mfr_item_opers
go
-- exec mfr_item_opers 28688023
create proc mfr_item_opers
	@content_id int
as
begin

    set nocount on;

	SELECT 
    x.*,
		PLACE_NAME = pl.NAME,
		STATUS_ID = s.STATUS_ID,
		STATUS_CSS = s.CSS,
		STATUS_NAME = s.NAME,
		STATUS_STYLE = s.STYLE,
		RESOURCE_NAME = rs.NAME
	FROM SDOCS_MFR_OPERS AS x WITH(NOLOCK)
		LEFT JOIN MFR_RESOURCES AS rs ON x.RESOURCE_ID = rs.RESOURCE_ID
		LEFT JOIN MFR_ITEMS_STATUSES AS s ON x.STATUS_ID = s.STATUS_ID
		LEFT JOIN MFR_PLACES AS pl ON x.PLACE_ID = pl.PLACE_ID
	WHERE x.CONTENT_ID = @content_id

end
go
