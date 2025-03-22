if object_id('mfr_docs_infos_view') is not null drop proc mfr_docs_infos_view
go
create proc mfr_docs_infos_view
	@mol_id int,
	@doc_id int
as
begin
	set nocount on;

    declare @info_id int = (select info_id from mfr_docs_infos where mfr_doc_id = @doc_id and is_last = 1)
        if @info_id is null exec mfr_docs_infos_calc @mol_id = @mol_id, @doc_id = @doc_id, @info_id = @info_id out
    
    select 
        Info = dbo.xml2json(
            (select * from mfr_docs_infos where info_id = @info_id for xml raw)
            ),
        MaterialsByDates = dbo.xml2json((
                SELECT X.ITEM_ID, ITEM_NAME = P.NAME, X.DURATION, X.D_TO_PLAN, X.D_TO_FACT
                FROM MFR_DOCS_INFOS_MATERIALS X
                    JOIN PRODUCTS P ON P.PRODUCT_ID = X.ITEM_ID
                WHERE INFO_ID = @INFO_ID
                    AND SLICE = 'dates'
                ORDER BY X.D_TO_PLAN, P.NAME
                FOR XML RAW
            )),
        MaterialsByDurations = dbo.xml2json((
                SELECT X.ITEM_ID, ITEM_NAME = P.NAME, X.DURATION, X.D_TO_PLAN, X.D_TO_FACT
                FROM MFR_DOCS_INFOS_MATERIALS X
                    JOIN PRODUCTS P ON P.PRODUCT_ID = X.ITEM_ID
                WHERE INFO_ID = @INFO_ID
                    AND SLICE = 'duration'
                ORDER BY X.DURATION DESC, P.NAME
                FOR XML RAW
            )),
        States = dbo.xml2json(
            (SELECT STATE_ID, NAME, D_PLAN, D_FACT FROM MFR_DOCS_INFOS_STATES WHERE INFO_ID = @INFO_ID FOR XML RAW)
            ),
        Syncs = dbo.xml2json((
            SELECT CONTENT_ID, NAME, DELAY FROM MFR_DOCS_INFOS_SYNCS WHERE INFO_ID = @INFO_ID
            ORDER BY DELAY DESC, NAME
            FOR XML RAW
            ))
    
end
go
-- exec mfr_docs_infos_view 1000, @doc_id = 644229
