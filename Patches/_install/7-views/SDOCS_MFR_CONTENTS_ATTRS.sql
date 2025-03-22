--IF EXISTS(SELECT 1 FROM SYS.TABLES WHERE NAME = 'SDOCS_MFR_CONTENTS_ATTRS')
--	DROP TABLE SDOCS_MFR_CONTENTS_ATTRS
--GO

IF EXISTS(SELECT 1 FROM SYS.VIEWS WHERE NAME = 'SDOCS_MFR_CONTENTS_ATTRS')
	DROP VIEW SDOCS_MFR_CONTENTS_ATTRS
GO
CREATE VIEW SDOCS_MFR_CONTENTS_ATTRS
AS
SELECT 
	DA.ID,	
	X.CONTENT_ID,
	DA.DRAFT_ID,
	DA.ATTR_ID,
	DA.NOTE,
	DA.ADD_DATE,
	DA.ADD_MOL_ID,
	DA.UPDATE_DATE,
	DA.UPDATE_MOL_ID
FROM SDOCS_MFR_CONTENTS X
	JOIN SDOCS_MFR_DRAFTS_ATTRS DA ON DA.DRAFT_ID = X.DRAFT_ID
GO

create trigger tid_sdocs_mfr_contents_attrs on SDOCS_MFR_CONTENTS_ATTRS
instead of insert, delete
as
begin
	
	set nocount on ;

	-- instead of insert
	if not exists(select 1 from deleted)
	begin
		insert into sdocs_mfr_drafts_attrs(draft_id, attr_id, note)
		select distinct draft_id, attr_id, note
		from (
			-- use main_id
			select d.main_id as draft_id, i.attr_id, i.note
			from inserted i
				join sdocs_mfr_contents c on c.content_id = i.content_id
					join sdocs_mfr_drafts d on d.draft_id = c.draft_id
			where d.main_id is not null

			union all
			-- local draft_id
			select c.draft_id, i.attr_id, i.note
			from inserted i
				join sdocs_mfr_contents c on c.content_id = i.content_id

			union all
			-- synonyms with main_id
			select c2.draft_id, i.attr_id, i.note
			from inserted i
				join sdocs_mfr_contents c on c.content_id = i.content_id
					join sdocs_mfr_drafts d on d.draft_id = c.draft_id
					join sdocs_mfr_contents c2 on c2.plan_id = c.plan_id and c2.item_id = c.item_id
					join sdocs_mfr_drafts d2 on d2.draft_id = c2.draft_id and d2.main_id = d.main_id
		) u
		where not exists(select 1 from sdocs_mfr_drafts_attrs where draft_id = u.draft_id and attr_id = u.attr_id)
	end

	-- instead of delete
	if not exists(select 1 from inserted)
	begin
		-- delete by main_id
		delete x 
		from sdocs_mfr_drafts_attrs x
			join deleted d on d.attr_id = x.attr_id 
			join sdocs_mfr_drafts dd on dd.draft_id = d.draft_id and dd.main_id = x.draft_id				

		-- delete by local draft_id
		delete x 
		from sdocs_mfr_drafts_attrs x
			join deleted d on d.draft_id = x.draft_id and d.attr_id = x.attr_id 

		-- delete by synonyms with main_id
		delete x
		from deleted d
			join sdocs_mfr_contents c on c.content_id = d.content_id
				join sdocs_mfr_drafts dd on dd.draft_id = c.draft_id
				join sdocs_mfr_contents c2 on c2.plan_id = c.plan_id and c2.item_id = c.item_id
				join sdocs_mfr_drafts dd2 on dd2.draft_id = c2.draft_id and dd2.main_id = dd.main_id
			join sdocs_mfr_drafts_attrs x on x.draft_id = c2.draft_id and x.attr_id = d.attr_id
	end
end
GO
